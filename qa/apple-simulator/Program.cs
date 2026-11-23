using System.Text.Json;
using Wispel;

// Read operator diagnostics for a specific event and use the production payload builder.
// This fixture replaces the APNs transport only; the simulator runs the real receiver.
if (args.Length != 2)
    throw new ArgumentException("EVENT_ID OUTPUT.apns");
using var doc = JsonDocument.Parse(await Console.In.ReadToEndAsync());
var input = doc.RootElement;
var row = input
    .GetProperty("events")
    .EnumerateArray()
    .Single(r => r.GetProperty("eventId").GetString() == args[0]);
var source = row.GetProperty("sourceId").GetString()!;
var sender = input
    .GetProperty("devices")
    .EnumerateArray()
    .Single(d => d.GetProperty("id").GetString() == source);
var e = new Envelope(
    args[0],
    source,
    sender.GetProperty("name").GetString()!,
    row.GetProperty("kind").GetString()!,
    row.GetProperty("occurredAt").GetInt64()
);
await File.WriteAllBytesAsync(
    args[1],
    JsonSerializer.SerializeToUtf8Bytes(AppleDelivery.Payload(e), Wire.Json)
);
