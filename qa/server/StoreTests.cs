using System.Text.Json;
using Wispel;
using Xunit;

public sealed class StoreTests : IDisposable
{
    sealed class Clock : TimeProvider
    {
        public long Ms = 1_800_000_000_000;

        public override DateTimeOffset GetUtcNow() => DateTimeOffset.FromUnixTimeMilliseconds(Ms);
    }

    readonly string dir = Directory.CreateTempSubdirectory("wispel-qa-").FullName;
    readonly Clock clock = new();
    readonly Store db;

    public StoreTests()
    {
        db = new Store(Path.Combine(dir, "data.db"), clock);
    }

    Device Pair(string role, string platform = "android")
    {
        var r = db.Pair(new(db.Issue(role), platform, role));
        return db.Authenticate(r.Token);
    }

    Notice Event(Device d, string kind = "kakao") =>
        new(Guid.NewGuid().ToString(), d.Id, kind, clock.Ms);

    public void Dispose()
    {
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        Directory.Delete(dir, true);
    }

    [Fact]
    public void ConcurrentCodeIsUsedOnce()
    {
        var code = db.Issue("send");
        var results = Enumerable
            .Range(0, 8)
            .AsParallel()
            .Select(i =>
            {
                try
                {
                    db.Pair(new(code, "ios", "iPhone"));
                    return true;
                }
                catch (ApiError)
                {
                    return false;
                }
            })
            .ToArray();
        Assert.Single(results, x => x);
        clock.Ms += 300000;
        var expired = db.Issue("send");
        clock.Ms += 300000;
        Assert.Throws<ApiError>(() => db.Pair(new(expired, "ios", "test")));
    }

    [Theory]
    [InlineData("call")]
    [InlineData("missedCall")]
    [InlineData("sms")]
    [InlineData("kakao")]
    [InlineData("slack")]
    [InlineData("mail")]
    public void RoundTripAndAck(string kind)
    {
        var tx = Pair("send", "ios");
        var rx = Pair("receive");
        var n = Event(tx, kind);
        Assert.Equal("queued", db.Accept(tx, n));
        var e = Assert.Single(db.Pending(rx.Id));
        Assert.Equal(tx.Name, e.SourceName);
        Assert.Equal(kind, e.Kind);
        db.Mark(rx.Id, e, "sent", 5000);
        Assert.Empty(db.Pending(rx.Id));
        clock.Ms += 5000;
        Assert.Equal(e, Assert.Single(db.Pending(rx.Id)));
        db.Ack(rx.Id, e.SourceId, e.EventId);
        db.Ack(rx.Id, e.SourceId, e.EventId);
        db.Mark(rx.Id, e, "sent", 0);
        Assert.Empty(db.Pending(rx.Id));
    }

    [Fact]
    public void RetryAndTwoDistinctEvents()
    {
        var s = Pair("send");
        var r = Pair("receive");
        var n = Event(s);
        var first = Enumerable.Range(0, 12).AsParallel().Select(i => db.Accept(s, n)).ToList();
        Assert.Single(first, x => x == "queued");
        db.Accept(s, Event(s));
        Assert.Equal(2, db.Pending(r.Id).Length);
        Assert.Equal(
            409,
            Assert.Throws<ApiError>(() => db.Accept(s, n with { Kind = "sms" })).Status
        );
    }

    [Fact]
    public void RejectUnauthorizedAndSpoof()
    {
        var s = Pair("send");
        var other = Pair("send");
        var r = Pair("receive");
        Assert.Throws<ApiError>(() => db.Authenticate("bad"));
        Assert.Throws<ApiError>(() => db.Accept(r, Event(r)));
        Assert.Throws<ApiError>(() => db.Accept(s, Event(other)));
        Assert.Throws<ApiError>(() => db.Accept(s, Event(s, "not-an-app")));
        db.Remove(s.Id);
        Assert.Throws<ApiError>(() => db.Accept(s, Event(s)));
    }

    [Fact]
    public void ReplacementAndRevocation()
    {
        var s = Pair("send");
        var old = Pair("receive");
        db.Accept(s, Event(s));
        var next = Pair("receive");
        Assert.Single(db.Pending(old.Id));
        db.Activate(next.Id);
        Assert.Empty(db.Pending(old.Id));
        Assert.Empty(db.Pending(next.Id));
        db.Accept(s, Event(s));
        Assert.Single(db.Pending(next.Id));
        db.Remove(s.Id);
        Assert.Empty(db.Pending(next.Id));
    }

    [Fact]
    public void AppleReplacementWaitsForToken()
    {
        var old = Pair("receive");
        var apple = Pair("receive", "ios");
        Assert.True(db.IsCurrentReceiver(old.Id));
        Assert.Throws<ApiError>(() => db.SetApns(apple.Id, "bad"));
        Assert.True(db.IsCurrentReceiver(old.Id));
        db.SetApns(apple.Id, new string('c', 64));
        Assert.True(db.IsCurrentReceiver(apple.Id));
        Assert.False(db.IsCurrentReceiver(old.Id));
    }

    [Fact]
    public void TimeBoundariesAndPersistence()
    {
        var s = Pair("send");
        var r = Pair("receive");
        var n = Event(s);
        db.Accept(s, n);
        var restarted = new Store(Path.Combine(dir, "data.db"), clock);
        Assert.Single(restarted.Pending(r.Id));
        clock.Ms += Store.Day - 1;
        Assert.Single(db.Pending(r.Id));
        clock.Ms++;
        db.Sweep();
        Assert.Empty(db.Pending(r.Id));
        Assert.Contains("expired", JsonSerializer.Serialize(db.Stats(), Wire.Json));
        clock.Ms += 6 * Store.Day;
        db.Sweep();
        Assert.DoesNotContain(n.EventId, JsonSerializer.Serialize(db.Stats(), Wire.Json));
    }

    [Fact]
    public void IndependentSourcesAndMissingReceiver()
    {
        var a = Pair("send");
        var b = Pair("send");
        var e = Event(a);
        Assert.Equal(503, Assert.Throws<ApiError>(() => db.Accept(a, e)).Status);
        var r = Pair("receive");
        db.Accept(a, e);
        db.Accept(b, e with { SourceId = b.Id });
        Assert.Equal(2, db.Pending(r.Id).Length);
    }

    [Fact]
    public void PrivateApplePayloadAndTokenRotation()
    {
        var s = Pair("send");
        var r = Pair("receive", "ios");
        db.SetApns(r.Id, new string('a', 64));
        db.SetApns(r.Id, new string('b', 64));
        db.InvalidToken(r.Id, new string('a', 64));
        Assert.Equal(new string('b', 64), db.Apns(r.Id));
        db.Accept(s, Event(s));
        var e = Assert.Single(db.Pending(r.Id));
        var json = JsonSerializer.Serialize(AppleDelivery.Payload(e), Wire.Json);
        Assert.Contains("카카오톡", System.Text.RegularExpressions.Regex.Unescape(json));
        Assert.DoesNotContain("token", json);
        Assert.DoesNotContain(new string('b', 64), JsonSerializer.Serialize(db.Stats()));
    }
}
