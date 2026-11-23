using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Wispel;
using Xunit;

public sealed class AppleTests
{
    sealed class Provider(HttpStatusCode status) : HttpMessageHandler
    {
        public TaskCompletionSource<(string Token, string Payload)> Request { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage req,
            CancellationToken stop
        )
        {
            Assert.Equal(HttpVersion.Version20, req.Version);
            Assert.Equal(HttpVersionPolicy.RequestVersionExact, req.VersionPolicy);
            Assert.Equal("api.sandbox.push.apple.com", req.RequestUri!.Host);
            Assert.Equal("app.wispel.phone", Assert.Single(req.Headers.GetValues("apns-topic")));
            Assert.Equal("alert", Assert.Single(req.Headers.GetValues("apns-push-type")));
            Assert.True(
                long.Parse(Assert.Single(req.Headers.GetValues("apns-expiration")))
                    > DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            );
            Request.TrySetResult(
                (req.Headers.Authorization!.Parameter!, await req.Content!.ReadAsStringAsync(stop))
            );
            return new HttpResponseMessage(status)
            {
                Content = new StringContent(
                    "{\"reason\":\"BadDeviceToken\"}",
                    Encoding.UTF8,
                    "application/json"
                ),
            };
        }
    }

    static byte[] Decode(string part) =>
        Convert.FromBase64String(
            part.Replace('-', '+').Replace('_', '/').PadRight((part.Length + 3) / 4 * 4, '=')
        );

    [Theory]
    [InlineData(200, "apns")]
    [InlineData(400, "ios_token_invalid")]
    [InlineData(410, "ios_token_invalid")]
    [InlineData(503, "apns_503")]
    public async Task SignedRequestAndProviderResponse(int code, string expected)
    {
        var dir = Directory.CreateTempSubdirectory("wispel-apns-");
        try
        {
            var db = new Store(Path.Combine(dir.FullName, "data.db"));
            var sender = db.Pair(new(db.Issue("send"), "android", "안드로이드"));
            var receiver = db.Pair(new(db.Issue("receive"), "ios", "아이폰"));
            db.SetApns(receiver.Id, new string('a', 64));
            var eid = Guid.NewGuid().ToString();
            db.Accept(db.Authenticate(sender.Token), new(eid, sender.Id, "mail", db.Now));
            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var file = Path.Combine(dir.FullName, "test.p8");
            await File.WriteAllTextAsync(file, key.ExportPkcs8PrivateKeyPem());
            using var handler = new Provider((HttpStatusCode)code);
            using var client = new HttpClient(handler);
            using var worker = new AppleDelivery(
                db,
                client,
                new(file, "TESTKEY", "TESTTEAM", "app.wispel.phone", false)
            );
            await worker.StartAsync(CancellationToken.None);
            try
            {
                var (jwt, json) = await handler.Request.Task.WaitAsync(TimeSpan.FromSeconds(7));
                var parts = jwt.Split('.');
                Assert.Equal(3, parts.Length);
                Assert.True(
                    key.VerifyData(
                        Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]),
                        Decode(parts[2]),
                        HashAlgorithmName.SHA256,
                        DSASignatureFormat.IeeeP1363FixedFieldConcatenation
                    )
                );
                using var payload = JsonDocument.Parse(json);
                Assert.Equal(
                    eid,
                    payload.RootElement.GetProperty("wispel").GetProperty("eventId").GetString()
                );
                Assert.Equal(
                    "메일플러그",
                    payload
                        .RootElement.GetProperty("aps")
                        .GetProperty("alert")
                        .GetProperty("title")
                        .GetString()
                );
                bool observed = false;
                for (int i = 0; i < 50 && !observed; i++)
                {
                    await Task.Delay(25);
                    observed = JsonSerializer
                        .Serialize(db.Stats(), Wire.Json)
                        .Contains("\"" + expected + "\"");
                }
                Assert.True(observed);
                if (code is 400 or 410)
                    Assert.Null(db.Apns(receiver.Id));
            }
            finally
            {
                await worker.StopAsync(CancellationToken.None);
            }
        }
        finally
        {
            Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
            dir.Delete(true);
        }
    }
}
