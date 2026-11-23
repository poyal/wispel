package app.wispel.phone

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.UUID
import org.json.JSONObject

data class Tile(
    val source: String,
    val name: String,
    val kind: String,
    val at: Long,
    val count: Int,
)

class Events private constructor(context: Context) :
    SQLiteOpenHelper(context, "events.db", null, 1) {
    companion object {
        @Volatile private var instance: Events? = null

        fun get(c: Context): Events =
            instance
                ?: synchronized(this) {
                    instance ?: Events(c.applicationContext).also { instance = it }
                }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE inbound(owner TEXT,source TEXT,eid TEXT,name TEXT,kind TEXT,at INTEGER,seen INTEGER,history INTEGER,done INTEGER,PRIMARY KEY(owner,source,eid))"
        )
        db.execSQL(
            "CREATE TABLE outbound(owner TEXT,eid TEXT,kind TEXT,at INTEGER,PRIMARY KEY(owner,eid))"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) = Unit

    fun remember(owner: String, n: JSONObject, history: Boolean, show: Boolean): Boolean {
        val db = writableDatabase
        val now = System.currentTimeMillis()
        val key = arrayOf(owner, n.getString("sourceId"), n.getString("eventId"))
        db.execSQL("DELETE FROM inbound WHERE seen<=?", arrayOf(now - 7 * Rules.DAY))
        db.execSQL(
            "INSERT OR IGNORE INTO inbound VALUES(?,?,?,?,?,?,?,?,?)",
            arrayOf(
                key[0],
                key[1],
                key[2],
                n.getString("sourceName"),
                n.getString("kind"),
                n.getLong("occurredAt"),
                now,
                if (history) 1 else 0,
                if (show) 0 else 1,
            ),
        )
        return db.rawQuery("SELECT done FROM inbound WHERE owner=? AND source=? AND eid=?", key)
            .use { it.moveToFirst() && it.getInt(0) == 0 }
    }

    fun done(owner: String, n: JSONObject) {
        writableDatabase.execSQL(
            "UPDATE inbound SET done=1,name=CASE WHEN history=0 THEN '' ELSE name END,kind=CASE WHEN history=0 THEN '' ELSE kind END,at=CASE WHEN history=0 THEN 0 ELSE at END WHERE owner=? AND source=? AND eid=?",
            arrayOf(owner, n.getString("sourceId"), n.getString("eventId")),
        )
    }

    fun clearHistory(owner: String) {
        writableDatabase.execSQL(
            "UPDATE inbound SET history=0,name='',kind='',at=0 WHERE owner=? AND done=1",
            arrayOf(owner),
        )
    }

    fun tiles(owner: String): List<Tile> {
        val since = (System.currentTimeMillis() - 7 * Rules.DAY).toString()
        return readableDatabase
            .rawQuery(
                "SELECT source,name,kind,MAX(at),COUNT(*) FROM inbound WHERE owner=? AND history=1 AND seen>? GROUP BY source,kind ORDER BY MAX(at) DESC",
                arrayOf(owner, since),
            )
            .use {
                buildList {
                    while (it.moveToNext()) add(
                        Tile(
                            it.getString(0),
                            it.getString(1),
                            it.getString(2),
                            it.getLong(3),
                            it.getInt(4),
                        )
                    )
                }
            }
    }

    fun add(
        owner: String,
        kind: String,
        at: Long = System.currentTimeMillis(),
        eid: String = UUID.randomUUID().toString(),
    ) {
        writableDatabase.execSQL(
            "INSERT OR IGNORE INTO outbound VALUES(?,?,?,?)",
            arrayOf<Any>(owner, eid, kind, at),
        )
    }

    fun flush(relay: Relay) {
        val owner = relay.id
        if (owner.isEmpty() || relay.role != "send") return
        val db = writableDatabase
        db.execSQL(
            "DELETE FROM outbound WHERE at<=?",
            arrayOf(System.currentTimeMillis() - Rules.DAY),
        )
        db.rawQuery("SELECT eid,kind,at FROM outbound WHERE owner=? ORDER BY at", arrayOf(owner))
            .use {
                while (it.moveToNext()) {
                    val eid = it.getString(0)
                    relay.api(
                        "/v1/events",
                        "POST",
                        json(
                            "eventId" to eid,
                            "sourceId" to owner,
                            "kind" to it.getString(1),
                            "occurredAt" to it.getLong(2),
                        ),
                    )
                    db.delete("outbound", "owner=? AND eid=?", arrayOf(owner, eid))
                }
            }
    }
}
