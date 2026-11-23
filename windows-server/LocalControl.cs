using System.IO.Pipes;
using System.Net;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using QRCoder;

namespace Wispel;

public class LocalControl(Settings cfg, Store store) : BackgroundService
{
    static readonly PipeAccessRights Access = PipeAccessRights.ReadWrite;

    protected override async Task ExecuteAsync(CancellationToken stop)
    {
        while (!stop.IsCancellationRequested)
        {
            var acl = new PipeSecurity();
            foreach (
                var sid in new[]
                {
                    new SecurityIdentifier(cfg.Owner),
                    WindowsIdentity.GetCurrent().User!,
                    new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                }
            )
                acl.AddAccessRule(
                    new PipeAccessRule(
                        sid,
                        Access | PipeAccessRights.CreateNewInstance,
                        AccessControlType.Allow
                    )
                );
            using var pipe = NamedPipeServerStreamAcl.Create(
                cfg.Pipe,
                PipeDirection.InOut,
                1,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous,
                4096,
                4096,
                acl
            );
            await pipe.WaitForConnectionAsync(stop);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stop);
            timeout.CancelAfter(5000);
            try
            {
                using var read = new StreamReader(pipe, leaveOpen: true);
                using var write = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
                var line = await read.ReadLineAsync(timeout.Token);
                var args = (line ?? "").Split(' ', 2);
                var result = args[0] switch
                {
                    "status" => JsonSerializer.Serialize(store.Stats(), Wire.Json),
                    "pair" when args.Length == 2 => PairUri(args[1]),
                    "remove" when args.Length == 2 => Remove(args[1]),
                    "test" when args.Length == 2 => Test(args[1]),
                    _ => "error:unknown_command",
                };
                await write.WriteLineAsync(result.AsMemory(), timeout.Token);
            }
            catch (Exception e) when (e is IOException or OperationCanceledException or ApiError)
            { }
        }
    }

    string PairUri(string role) =>
        $"wispel://pair?server={Uri.EscapeDataString(cfg.Url)}&pin={cfg.Pin}&role={role}&code={store.Issue(role)}";

    string Remove(string id)
    {
        store.Remove(id);
        return "ok";
    }

    string Test(string source)
    {
        var d = store.Devices().SingleOrDefault(x => x.Id == source)
            ?? throw new ApiError(404, "unknown_device");
        return store.Accept(d, new Notice(Guid.NewGuid().ToString(), d.Id, "kakao", store.Now));
    }

    static async Task<string> Request(Settings cfg, string line)
    {
        using var pipe = new NamedPipeClientStream(
            ".",
            cfg.Pipe,
            PipeDirection.InOut,
            PipeOptions.Asynchronous
        );
        await pipe.ConnectAsync(2500);
        using var w = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
        using var r = new StreamReader(pipe, leaveOpen: true);
        await w.WriteLineAsync(line);
        return await r.ReadLineAsync() ?? throw new IOException("Service unavailable");
    }

    public static async Task Client(string cmd, string[] args, Settings cfg)
    {
        if (cmd == "diag")
        {
            var builder = WebApplication.CreateBuilder();
            builder.Logging.ClearProviders();
            builder.WebHost.ConfigureKestrel(o =>
                o.Listen(IPAddress.Loopback, args.Length == 1 ? int.Parse(args[0]) : 7444)
            );
            var web = builder.Build();
            // A browser-local capability also protects diagnostics on multi-user hosts.
            var ticket = Convert.ToHexString(
                System.Security.Cryptography.RandomNumberGenerator.GetBytes(24)
            );
            web.Use(
                async (c, next) =>
                {
                    if (c.Request.Host.Host != "127.0.0.1")
                    {
                        c.Response.StatusCode = 404;
                        return;
                    }
                    c.Response.Headers.CacheControl = "no-store";
                    await next();
                }
            );
            var pages = web.MapGroup("/" + ticket);
            pages.MapGet("/", () =>
                Results.Stream(
                    typeof(LocalControl).Assembly.GetManifestResourceStream(
                        "Wispel.Diagnostics.html"
                    )!,
                    "text/html; charset=utf-8"
                )
            );
            pages.MapGet("/board.css", () =>
                Results.Stream(
                    typeof(LocalControl).Assembly.GetManifestResourceStream("Wispel.Board.css")!,
                    "text/css"
                )
            );
            pages.MapGet("/diagnostics.css", () =>
                Results.Stream(
                    typeof(LocalControl).Assembly.GetManifestResourceStream(
                        "Wispel.Diagnostics.css"
                    )!,
                    "text/css"
                )
            );
            pages.MapGet("/icon", () =>
                Results.Stream(
                    typeof(LocalControl).Assembly.GetManifestResourceStream("Wispel.Icon.png")!,
                    "image/png"
                )
            );
            pages.MapGet("/status", async () =>
            {
                try
                {
                    return Results.Text(await Request(cfg, "status"), "application/json");
                }
                catch (Exception e) when (e is IOException or TimeoutException)
                {
                    return Results.StatusCode(503);
                }
            });
            Console.WriteLine($"http://127.0.0.1:{(args.FirstOrDefault() ?? "7444")}/{ticket}/");
            await web.RunAsync();
            return;
        }
        if (cmd is not ("pair" or "remove" or "status" or "test"))
            throw new ArgumentException(
                "init | serve | pair send/receive [qr.png] | status | test SOURCE | remove ID | diag"
            );
        var result = await Request(cfg, cmd + (args.Length > 0 ? " " + args[0] : ""));
        if (cmd == "pair" && args.Length > 1)
        {
            using var generator = new QRCodeGenerator();
            using var code = generator.CreateQrCode(result, QRCodeGenerator.ECCLevel.M);
            using var qr = new PngByteQRCode(code);
            File.WriteAllBytes(args[1], qr.GetGraphic(8));
        }
        Console.WriteLine(result);
    }
}
