using System.Security.Cryptography;
using System.Text;
using Dapper;
using Microsoft.Data.Sqlite;

namespace Wispel;

public record Device(string Id, string Name, string Platform, string Role);

public record Notice(string EventId, string SourceId, string Kind, long OccurredAt);

public record Envelope(
    string EventId,
    string SourceId,
    string SourceName,
    string Kind,
    long OccurredAt
);

public record PairRequest(string Code, string Platform, string Name);

public record Registration(string Id, string Name, string Platform, string Role, string Token);

public sealed class ApiError(int status, string code) : Exception(code)
{
    public int Status => status;
}

public sealed class Store
{
    public static readonly string[] Kinds = ["call", "missedCall", "sms", "slack", "mail", "kakao"];
    public const long Day = 86_400_000;
    private readonly string connection;
    private readonly TimeProvider clock;
    public long Now => clock.GetUtcNow().ToUnixTimeMilliseconds();

    public Store(string path, TimeProvider? clock = null)
    {
        this.clock = clock ?? TimeProvider.System;
        connection = new SqliteConnectionStringBuilder
        {
            DataSource = path,
            DefaultTimeout = 10,
        }.ToString();
        using var db = Open();
        db.Execute(
            """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY,name TEXT NOT NULL,platform TEXT NOT NULL,role TEXT NOT NULL,secret TEXT UNIQUE,active INTEGER NOT NULL,apns TEXT,lastSeen INTEGER);
            CREATE UNIQUE INDEX IF NOT EXISTS one_receiver ON devices(role) WHERE role='receive' AND active=1;
            CREATE TABLE IF NOT EXISTS codes(secret TEXT PRIMARY KEY,role TEXT NOT NULL,expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS events(sourceId TEXT NOT NULL,eventId TEXT NOT NULL,kind TEXT NOT NULL,occurredAt INTEGER NOT NULL,created INTEGER NOT NULL,target TEXT,status TEXT NOT NULL,attempts INTEGER DEFAULT 0,nextTry INTEGER DEFAULT 0,error TEXT,PRIMARY KEY(sourceId,eventId));
            CREATE INDEX IF NOT EXISTS pending ON events(target,status,nextTry);
            """
        );
        using var migration = db.BeginTransaction(deferred: false);
        if (db.ExecuteScalar<long>("PRAGMA user_version", transaction: migration) == 0)
        {
            db.Execute(
                "ALTER TABLE events ADD COLUMN sentAt INTEGER; ALTER TABLE events ADD COLUMN ackAt INTEGER; ALTER TABLE events ADD COLUMN errorAt INTEGER; PRAGMA user_version=1",
                transaction: migration
            );
        }
        migration.Commit();
    }

    private SqliteConnection Open()
    {
        var db = new SqliteConnection(connection);
        db.Open();
        return db;
    }

    private T Write<T>(Func<SqliteConnection, SqliteTransaction, T> action)
    {
        using var db = Open();
        using var tx = db.BeginTransaction(deferred: false);
        var result = action(db, tx);
        tx.Commit();
        return result;
    }

    static string Secret() => Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));

    static string Hash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    public static string Name(string name) =>
        !string.IsNullOrWhiteSpace(name) && name.Trim().Length <= 48 && !name.Any(char.IsControl)
            ? name.Trim()
            : throw new ApiError(400, "invalid_name");

    public string Issue(string role)
    {
        if (role is not ("send" or "receive"))
            throw new ApiError(400, "invalid_role");
        var code = Secret();
        using var db = Open();
        db.Execute(
            "INSERT INTO codes VALUES(@secret,@role,@expires)",
            new
            {
                secret = Hash(code),
                role,
                expires = Now + 300000,
            }
        );
        return code;
    }

    public Registration Pair(PairRequest p) =>
        Write(
            (db, tx) =>
            {
                var name = Name(p.Name);
                if (p.Platform is not ("ios" or "android") || string.IsNullOrEmpty(p.Code))
                    throw new ApiError(400, "invalid_registration");
                var role = db.QuerySingleOrDefault<string>(
                    "DELETE FROM codes WHERE secret=@hash AND expires>@now RETURNING role",
                    new { hash = Hash(p.Code), now = Now },
                    tx
                ) ?? throw new ApiError(403, "invalid_code");
                // Keep the current receiver active while its replacement establishes its transport.
                var replacing =
                    role == "receive"
                    && db.ExecuteScalar<long>(
                        "SELECT COUNT(*) FROM devices WHERE active=1 AND role='receive'",
                        transaction: tx
                    ) > 0;
                if (role == "receive")
                    db.Execute(
                        "UPDATE devices SET active=0,secret=NULL,apns=NULL WHERE active=2 AND role='receive'",
                        transaction: tx
                    );
                var id = Guid.NewGuid().ToString();
                var token = Secret();
                db.Execute(
                    "INSERT INTO devices(id,name,platform,role,active,secret) VALUES(@id,@name,@platform,@role,@state,@hash)",
                    new
                    {
                        id,
                        name,
                        platform = p.Platform,
                        role,
                        state = replacing ? 2 : 1,
                        hash = Hash(token),
                    },
                    tx
                );
                return new Registration(id, name, p.Platform, role, token);
            }
        );

    static void Revoke(SqliteConnection db, SqliteTransaction tx, string id)
    {
        db.Execute(
            "UPDATE devices SET active=0,secret=NULL,apns=NULL WHERE id=@id; UPDATE events SET status='cancelled' WHERE (sourceId=@id OR target=@id) AND status IN ('queued','sent','apns')",
            new { id },
            tx
        );
    }

    public void Remove(string id) =>
        Write(
            (db, tx) =>
            {
                Revoke(db, tx, id);
                return true;
            }
        );

    public Device Authenticate(string token)
    {
        using var db = Open();
        return db.QuerySingleOrDefault<Device>(
            "SELECT id,name,platform,role FROM devices WHERE secret=@hash AND active IN (1,2)",
            new { hash = Hash(token) }
        ) ?? throw new ApiError(401, "unauthorized");
    }

    public bool IsCurrentReceiver(string id)
    {
        using var db = Open();
        return db.ExecuteScalar<long>(
                "SELECT COUNT(*) FROM devices WHERE id=@id AND role='receive' AND active=1",
                new { id }
            ) == 1;
    }

    public void Activate(string id) =>
        Write(
            (db, tx) =>
            {
                Activate(db, tx, id);
                return true;
            }
        );

    static void Activate(SqliteConnection db, SqliteTransaction tx, string id)
    {
        var state = db.QuerySingleOrDefault<long>(
            "SELECT active FROM devices WHERE id=@id AND role='receive'",
            new { id },
            tx
        );
        if (state == 1)
            return;
        if (state != 2)
            throw new ApiError(403, "not_registered");
        foreach (
            var old in db.Query<string>(
                    "SELECT id FROM devices WHERE role='receive' AND active=1",
                    transaction: tx
                )
                .ToList()
        )
            Revoke(db, tx, old);
        db.Execute("UPDATE devices SET active=1 WHERE id=@id", new { id }, tx);
    }

    public void Rename(string id, string name)
    {
        using var db = Open();
        db.Execute(
            "UPDATE devices SET name=@name WHERE active=1 AND id=@id",
            new { id, name = Name(name) }
        );
    }

    public Device[] Devices()
    {
        using var db = Open();
        return db.Query<Device>(
                "SELECT id,name,platform,role FROM devices WHERE active=1 ORDER BY role,name"
            )
            .ToArray();
    }

    public string Accept(Device sender, Notice n) =>
        Write(
            (db, tx) =>
            {
                if (sender.Role != "send" || n.SourceId != sender.Id || !Active(db, tx, sender.Id))
                    throw new ApiError(403, "wrong_sender");
                if (
                    !Guid.TryParseExact(n.EventId, "D", out _)
                    || !Kinds.Contains(n.Kind)
                    || n.OccurredAt <= 0
                    || n.OccurredAt > Now + 300000
                )
                    throw new ApiError(400, "invalid_event");
                var prev = db.QuerySingleOrDefault<Notice>(
                    "SELECT eventId,sourceId,kind,occurredAt FROM events WHERE sourceId=@SourceId AND eventId=@EventId",
                    n,
                    tx
                );
                if (prev != null)
                    return prev == n ? "duplicate" : throw new ApiError(409, "conflict");
                var target = db.QuerySingleOrDefault<string>(
                    "SELECT id FROM devices WHERE active=1 AND role='receive'",
                    transaction: tx
                ) ?? throw new ApiError(503, "no_receiver");
                var status = n.OccurredAt <= Now - Day ? "expired" : "queued";
                db.Execute(
                    "INSERT INTO events(sourceId,eventId,kind,occurredAt,created,target,status) VALUES(@SourceId,@EventId,@Kind,@OccurredAt,@created,@target,@status)",
                    new
                    {
                        n.SourceId,
                        n.EventId,
                        n.Kind,
                        n.OccurredAt,
                        created = Now,
                        target,
                        status,
                    },
                    tx
                );
                db.Execute(
                    "UPDATE devices SET lastSeen=@now WHERE id=@id",
                    new { now = Now, id = sender.Id },
                    tx
                );
                return status;
            }
        );

    static bool Active(SqliteConnection db, SqliteTransaction tx, string id) =>
        db.ExecuteScalar<long>(
            "SELECT COUNT(*) FROM devices WHERE id=@id AND active=1",
            new { id },
            tx
        ) == 1;

    public Envelope[] Pending(string id)
    {
        using var db = Open();
        return db.Query<Envelope>(
                """
                SELECT e.eventId,e.sourceId,s.name AS sourceName,e.kind,e.occurredAt FROM events e
                JOIN devices s ON s.id=e.sourceId AND s.active=1 JOIN devices t ON t.id=e.target AND t.active=1
                WHERE e.target=@id AND e.status IN ('queued','sent') AND e.occurredAt>@cut AND e.nextTry<=@now
                ORDER BY e.created,e.rowid LIMIT 64
                """,
                new
                {
                    id,
                    cut = Now - Day,
                    now = Now,
                }
            )
            .ToArray();
    }

    public void Mark(string id, Envelope n, string status, long delay, string? error = null)
    {
        using var db = Open();
        db.Execute(
            "UPDATE events SET status=@status,nextTry=@next,attempts=attempts+1,error=@error,sentAt=CASE WHEN @status IN ('sent','apns') THEN COALESCE(sentAt,@now) ELSE sentAt END,errorAt=CASE WHEN @error IS NULL THEN errorAt ELSE @now END WHERE target=@id AND eventId=@EventId AND sourceId=@SourceId AND status IN ('queued','sent')",
            new
            {
                id,
                n.EventId,
                n.SourceId,
                status,
                next = Now + delay,
                now = Now,
                error,
            }
        );
    }

    public void Ack(string id, string sourceId, string eventId) =>
        Write(
            (db, tx) =>
            {
                if (!Active(db, tx, id))
                    throw new ApiError(401, "unauthorized");
                var changed = db.Execute(
                    "UPDATE events SET status='ack',error=NULL,ackAt=COALESCE(ackAt,@now) WHERE target=@id AND eventId=@eventId AND sourceId=@sourceId AND status IN ('queued','sent','apns','ack')",
                    new
                    {
                        id,
                        eventId,
                        sourceId,
                        now = Now,
                    },
                    tx
                );
                if (changed == 0)
                    throw new ApiError(404, "unknown_event");
                db.Execute(
                    "UPDATE devices SET lastSeen=@now WHERE id=@id",
                    new { id, now = Now },
                    tx
                );
                return true;
            }
        );

    public void SetApns(string id, string token) =>
        Write(
            (db, tx) =>
            {
                if (
                    string.IsNullOrEmpty(token)
                    || token.Length is < 32 or > 512
                    || token.Length % 2 != 0
                    || !token.All(Uri.IsHexDigit)
                )
                    throw new ApiError(400, "invalid_token");
                Activate(db, tx, id);
                db.Execute(
                    "UPDATE devices SET apns=@token WHERE id=@id AND active=1",
                    new { id, token },
                    tx
                );
                return true;
            }
        );

    public string? Apns(string id)
    {
        using var db = Open();
        return db.QuerySingleOrDefault<string>(
            "SELECT apns FROM devices WHERE id=@id AND active=1",
            new { id }
        );
    }

    public void InvalidToken(string id, string token)
    {
        using var db = Open();
        db.Execute("UPDATE devices SET apns=NULL WHERE id=@id AND apns=@token", new { id, token });
    }

    public void Sweep()
    {
        using var db = Open();
        db.Execute(
            "UPDATE events SET status='expired' WHERE status IN ('queued','sent') AND occurredAt<=@cut; DELETE FROM events WHERE created<=@old; DELETE FROM codes WHERE expires<=@now",
            new
            {
                now = Now,
                cut = Now - Day,
                old = Now - 7 * Day,
            }
        );
    }

    public object Stats()
    {
        using var db = Open();
        var rows = db.Query(
                "SELECT eventId,sourceId,kind,status,occurredAt,created,sentAt,ackAt,attempts,error FROM events ORDER BY created DESC,rowid DESC LIMIT 100"
            )
            .Select(x => (IDictionary<string, object>)x);
        return new
        {
            checkedAt = Now,
            recentErrors = db.ExecuteScalar<long>(
                "SELECT COUNT(*) FROM events WHERE errorAt>=@cut",
                new { cut = Now - 3600000 }
            ),
            devices = db.Query("SELECT id,name,role,platform,lastSeen FROM devices WHERE active=1")
                .Select(x => (IDictionary<string, object>)x),
            pending = db.ExecuteScalar<long>(
                "SELECT COUNT(*) FROM events WHERE status IN ('queued','sent')"
            ),
            oldest = db.ExecuteScalar<long?>(
                "SELECT MIN(created) FROM events WHERE status IN ('queued','sent')"
            ),
            events = rows,
        };
    }
}
