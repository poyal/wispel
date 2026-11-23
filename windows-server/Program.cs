using System.Net;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Http.Json;
using Wispel;

var argsList = args.ToList();
var data = Environment.GetEnvironmentVariable("WISPEL_HOME")
    ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Wispel"
    );
if (argsList.IndexOf("--home") is var ix && ix >= 0)
{
    data = argsList[ix + 1];
    argsList.RemoveRange(ix, 2);
}
data = Path.GetFullPath(data);
var command = argsList.FirstOrDefault() ?? "serve";
var cfgPath = Path.Combine(data, "server.json");
if (command == "init")
{
    var ip = IPAddress.Parse(argsList.ElementAtOrDefault(1) ?? "127.0.0.1");
    var port = int.Parse(argsList.ElementAtOrDefault(2) ?? "7443");
    var advertised = argsList.ElementAtOrDefault(3) is string external
        ? IPAddress.Parse(external)
        : ip;
    Directory.CreateDirectory(data);
    if (File.Exists(cfgPath) || File.Exists(Path.Combine(data, "server.pfx")))
        throw new InvalidOperationException("Already initialized");
    using var key = RSA.Create(3072);
    var req = new CertificateRequest(
        "CN=Wispel",
        key,
        HashAlgorithmName.SHA256,
        RSASignaturePadding.Pkcs1
    );
    var san = new SubjectAlternativeNameBuilder();
    san.AddIpAddress(ip);
    if (!ip.Equals(advertised))
        san.AddIpAddress(advertised);
    req.CertificateExtensions.Add(san.Build());
    req.CertificateExtensions.Add(
        new X509KeyUsageExtension(
            X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment,
            true
        )
    );
    req.CertificateExtensions.Add(
        new X509EnhancedKeyUsageExtension(new OidCollection { new Oid("1.3.6.1.5.5.7.3.1") }, false)
    );
    using var cert = req.CreateSelfSigned(
        DateTimeOffset.UtcNow.AddMinutes(-5),
        DateTimeOffset.UtcNow.AddYears(2)
    );
    File.WriteAllBytes(Path.Combine(data, "server.pfx"), cert.Export(X509ContentType.Pfx));
    File.WriteAllText(
        cfgPath,
        JsonSerializer.Serialize(
            new Settings(
                $"https://{new IPEndPoint(advertised, port)}",
                cert.GetCertHashString(HashAlgorithmName.SHA256).ToLowerInvariant(),
                "Wispel-" + Guid.NewGuid().ToString("N"),
                System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value,
                ip.ToString()
            )
        )
    );
    return;
}
var cfg = JsonSerializer.Deserialize<Settings>(File.ReadAllText(cfgPath))!;
if (command != "serve")
{
    await LocalControl.Client(command, argsList.Skip(1).ToArray(), cfg);
    return;
}
var builder = WebApplication.CreateBuilder(
    new WebApplicationOptions { Args = [], ContentRootPath = AppContext.BaseDirectory }
);
builder.Logging.ClearProviders();
builder.Services.AddWindowsService();
var serverUri = new Uri(cfg.Url);
using var tls = X509CertificateLoader.LoadPkcs12FromFile(Path.Combine(data, "server.pfx"), null);
builder.WebHost.ConfigureKestrel(o =>
{
    o.Limits.MaxRequestBodySize = 4096;
    o.Listen(IPAddress.Parse(cfg.ListenAddress ?? serverUri.Host), serverUri.Port, l =>
        l.UseHttps(tls)
    );
});
builder.Services.Configure<JsonOptions>(o =>
    o.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
);
var store = new Store(Path.Combine(data, "wispel.db"));
builder.Services.AddSingleton(cfg);
builder.Services.AddSingleton(store);
builder.Services.AddSingleton(AppleSettings.FromEnvironment());
builder.Services.AddSingleton<HttpClient>(_ => new HttpClient
{
    Timeout = TimeSpan.FromSeconds(12),
});
builder.Services.AddHostedService<LocalControl>();
builder.Services.AddHostedService<AppleDelivery>();
var app = builder.Build();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(15) });
app.Use(
    async (ctx, next) =>
    {
        try
        {
            if (ctx.Request.Path != "/v1/pair")
            {
                var header = ctx.Request.Headers.Authorization.ToString();
                if (!header.StartsWith("Bearer ", StringComparison.Ordinal))
                    throw new ApiError(401, "unauthorized");
                ctx.Items["device"] = store.Authenticate(header[7..]);
            }
            await next();
        }
        catch (ApiError ex) when (!ctx.Response.HasStarted)
        {
            ctx.Response.StatusCode = ex.Status;
            await ctx.Response.WriteAsJsonAsync(new { error = ex.Message });
        }
        catch (BadHttpRequestException ex) when (!ctx.Response.HasStarted)
        {
            ctx.Response.StatusCode = ex.StatusCode;
        }
    }
);
static Device Current(HttpContext c) => (Device)c.Items["device"]!;
app.MapPost("/v1/pair", (PairRequest p) => store.Pair(p));
app.MapGet("/v1/devices", () => store.Devices());
app.MapPut("/v1/devices/{id}", (HttpContext c, string id, Rename r) =>
{
    Control(c, id);
    store.Rename(id, r.Name);
    return Results.NoContent();
});
app.MapDelete("/v1/devices/{id}", (HttpContext c, string id) =>
{
    Control(c, id);
    store.Remove(id);
    return Results.NoContent();
});
void Control(HttpContext c, string id)
{
    var d = Current(c);
    if (d.Id != id && !store.IsCurrentReceiver(d.Id))
        throw new ApiError(403, "wrong_role");
}
app.MapPost("/v1/events", (HttpContext c, Notice e) =>
    new { status = store.Accept(Current(c), e) }
);
app.MapPost("/v1/ack", (HttpContext c, Acknowledgment a) =>
{
    var d = Current(c);
    if (d.Role != "receive")
        throw new ApiError(403, "wrong_role");
    store.Ack(d.Id, a.SourceId, a.EventId);
    return Results.NoContent();
});
app.MapPut("/v1/apns", (HttpContext c, Token t) =>
{
    var d = Current(c);
    if (d.Platform != "ios" || d.Role != "receive")
        throw new ApiError(403, "wrong_role");
    store.SetApns(d.Id, t.Value);
    return Results.NoContent();
});
app.MapGet("/v1/stream", async (HttpContext c) =>
{
    var d = Current(c);
    if (d.Platform != "android" || d.Role != "receive")
        throw new ApiError(403, "wrong_role");
    if (!c.WebSockets.IsWebSocketRequest)
        throw new ApiError(400, "websocket_required");
    using var ws = await c.WebSockets.AcceptWebSocketAsync();
    store.Activate(d.Id);
    using var stop = CancellationTokenSource.CreateLinkedTokenSource(
        c.RequestAborted,
        app.Lifetime.ApplicationStopping
    );
    var token = stop.Token;
    var reader = Task.Run(async () =>
    {
        try
        {
            var buffer = new byte[256];
            while (!token.IsCancellationRequested)
            {
                var m = await ws.ReceiveAsync(buffer, token);
                if (m.MessageType == WebSocketMessageType.Close)
                    break;
            }
        }
        catch (WebSocketException) { }
        catch (OperationCanceledException) { }
        finally
        {
            await stop.CancelAsync();
        }
    });
    try
    {
        while (!token.IsCancellationRequested)
        {
            store.Authenticate(c.Request.Headers.Authorization.ToString()[7..]);
            foreach (var n in store.Pending(d.Id))
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(n, Wire.Json);
                await ws.SendAsync(bytes, WebSocketMessageType.Text, true, token);
                store.Mark(d.Id, n, "sent", 5000);
            }
            await Task.Delay(250, token);
        }
    }
    catch (OperationCanceledException) { }
    catch (WebSocketException) { }
    catch (ApiError) { }
    finally
    {
        await stop.CancelAsync();
        ws.Abort();
        await reader;
    }
});
await app.RunAsync();

namespace Wispel
{
    public record Settings(
        string Url,
        string Pin,
        string Pipe,
        string Owner,
        string? ListenAddress = null
    );

    public record Acknowledgment(string SourceId, string EventId);

    public record Token(string Value);

    public record Rename(string Name);

    public static class Wire
    {
        public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    }
}
