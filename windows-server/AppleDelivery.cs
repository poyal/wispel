using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Wispel;

public record AppleSettings(
    string? KeyFile,
    string? KeyId,
    string? Team,
    string? Topic,
    bool Production
)
{
    public static AppleSettings FromEnvironment()
    {
        string? Read(string name) => Environment.GetEnvironmentVariable("WISPEL_APNS_" + name);
        return new(
            Read("KEY"),
            Read("KEY_ID"),
            Read("TEAM"),
            Read("TOPIC"),
            Read("PRODUCTION") == "1"
        );
    }
}

public sealed class AppleDelivery(Store store, HttpClient http, AppleSettings provider)
    : BackgroundService
{
    string? jwt;
    long signedAt;

    static string Enc(byte[] data) =>
        Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    string Token(string key, string kid, string team)
    {
        if (jwt != null && store.Now - signedAt < 50 * 60000)
            return jwt;
        var header = Enc(JsonSerializer.SerializeToUtf8Bytes(new { alg = "ES256", kid }));
        var claims = Enc(
            JsonSerializer.SerializeToUtf8Bytes(new { iss = team, iat = store.Now / 1000 })
        );
        using var ec = ECDsa.Create();
        ec.ImportFromPem(File.ReadAllText(key));
        var body = header + "." + claims;
        jwt =
            body
            + "."
            + Enc(
                ec.SignData(
                    Encoding.ASCII.GetBytes(body),
                    HashAlgorithmName.SHA256,
                    DSASignatureFormat.IeeeP1363FixedFieldConcatenation
                )
            );
        signedAt = store.Now;
        return jwt;
    }

    public static object Payload(Envelope n) =>
        new
        {
            aps = new Dictionary<string, object>
            {
                ["alert"] = new { title = Labels[n.Kind], body = n.SourceName },
                ["thread-id"] = n.SourceId + "." + n.Kind,
            },
            wispel = n,
        };

    static readonly Dictionary<string, string> Labels = new()
    {
        { "call", "전화 알림" },
        { "missedCall", "부재중 전화" },
        { "sms", "새 문자" },
        { "kakao", "카카오톡" },
        { "slack", "Slack" },
        { "mail", "메일플러그" },
    };

    protected override async Task ExecuteAsync(CancellationToken stop)
    {
        while (!stop.IsCancellationRequested)
        {
            store.Sweep();
            foreach (
                var d in store.Devices().Where(d => d.Platform == "ios" && d.Role == "receive")
            )
            {
                var registration = store.Apns(d.Id);
                foreach (var n in store.Pending(d.Id))
                {
                    var (key, kid, team, topic, production) = provider;
                    if (
                        registration == null
                        || key == null
                        || kid == null
                        || team == null
                        || topic == null
                    )
                    {
                        store.Mark(
                            d.Id,
                            n,
                            "queued",
                            5000,
                            registration == null ? "ios_token_missing" : "apns_setup_required"
                        );
                        continue;
                    }
                    try
                    {
                        var host = production ? "api.push.apple.com" : "api.sandbox.push.apple.com";
                        using var req = new HttpRequestMessage(
                            HttpMethod.Post,
                            $"https://{host}/3/device/{registration}"
                        )
                        {
                            Version = HttpVersion.Version20,
                            VersionPolicy = HttpVersionPolicy.RequestVersionExact,
                            Content = JsonContent.Create(Payload(n), options: Wire.Json),
                        };
                        req.Headers.Authorization = new AuthenticationHeaderValue(
                            "bearer",
                            Token(key, kid, team)
                        );
                        req.Headers.Add("apns-topic", topic);
                        req.Headers.Add("apns-push-type", "alert");
                        req.Headers.Add(
                            "apns-expiration",
                            ((n.OccurredAt + Store.Day) / 1000).ToString()
                        );
                        req.Headers.Add("apns-collapse-id", n.EventId);
                        using var res = await http.SendAsync(req, stop);
                        if (res.IsSuccessStatusCode)
                        {
                            store.Mark(d.Id, n, "apns", 0);
                            continue;
                        }
                        string? reason = null;
                        if (res.StatusCode == HttpStatusCode.BadRequest)
                        {
                            var json = await res.Content.ReadFromJsonAsync<JsonElement>(stop);
                            if (json.TryGetProperty("reason", out var why))
                                reason = why.GetString();
                        }
                        if (res.StatusCode == HttpStatusCode.Gone || reason == "BadDeviceToken")
                        {
                            store.InvalidToken(d.Id, registration);
                            store.Mark(d.Id, n, "queued", 30000, "ios_token_invalid");
                        }
                        else
                        {
                            if (res.StatusCode == HttpStatusCode.Forbidden)
                                jwt = null;
                            var retry = res.Headers.RetryAfter?.Delta?.TotalMilliseconds ?? 60000;
                            store.Mark(
                                d.Id,
                                n,
                                "queued",
                                (long)Math.Clamp(retry, 1000, Store.Day),
                                "apns_" + (int)res.StatusCode
                            );
                        }
                    }
                    catch (Exception ex)
                        when (ex
                                is IOException
                                    or UnauthorizedAccessException
                                    or HttpRequestException
                                    or JsonException
                                    or CryptographicException
                                    or ArgumentException
                                    or TaskCanceledException
                        )
                    {
                        store.Mark(d.Id, n, "queued", 60000, "apns_unavailable");
                    }
                }
            }
            await Task.Delay(1000, stop);
        }
    }
}
