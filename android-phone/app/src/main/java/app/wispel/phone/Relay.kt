package app.wispel.phone

import android.content.Context
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.net.URI
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

data class Invite(val url: String, val pin: String, val role: String, val code: String) {
    companion object {
        fun parse(raw: String): Invite {
            val u = Uri.parse(raw.trim())
            require(u.scheme == "wispel" && u.host == "pair")
            fun field(k: String) = requireNotNull(u.getQueryParameter(k))
            val url = URI(field("server"))
            val pin = field("pin")
            val role = field("role")
            val code = field("code")
            require(
                url.scheme == "https" &&
                    url.host != null &&
                    url.rawUserInfo == null &&
                    url.rawPath.orEmpty().isEmpty() &&
                    url.rawQuery == null &&
                    url.fragment == null
            )
            require(
                pin.matches(Regex("[a-fA-F0-9]{64}")) &&
                    role in setOf("send", "receive") &&
                    code.matches(Regex("[a-fA-F0-9]{64}"))
            )
            return Invite(url.toString(), pin.lowercase(), role, code)
        }
    }
}

class NetworkError(val status: Int) : Exception("서버 응답 " + status)

class Relay(private val context: Context) {
    val prefs = context.getSharedPreferences("relay", Context.MODE_PRIVATE)
    val id
        get() = prefs.getString("id", "").orEmpty()

    val role
        get() = prefs.getString("role", "").orEmpty()

    private val secretKey
        get() =
            synchronized(Relay::class.java) {
                val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                (ks.getKey("wispel-device", null) as? javax.crypto.SecretKey)
                    ?: KeyGenerator.getInstance("AES", "AndroidKeyStore")
                        .apply {
                            init(
                                KeyGenParameterSpec.Builder(
                                        "wispel-device",
                                        KeyProperties.PURPOSE_DECRYPT or
                                            KeyProperties.PURPOSE_ENCRYPT,
                                    )
                                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                                    .build()
                            )
                        }
                        .generateKey()
            }

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)

    private fun storeToken(token: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, secretKey)
        return b64(c.iv) + "." + b64(c.doFinal(token.toByteArray()))
    }

    private fun token(): String {
        val pieces = prefs.getString("credential", null)!!.split(".")
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, Base64.decode(pieces[0], 0)))
        return String(c.doFinal(Base64.decode(pieces[1], 0)))
    }

    companion object {
        private val clients = mutableMapOf<String, OkHttpClient>()

        @Synchronized
        fun client(pin: String): OkHttpClient =
            clients.getOrPut(pin) {
                val trust =
                    object : X509TrustManager {
                        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

                        override fun checkClientTrusted(
                            chain: Array<X509Certificate>,
                            type: String,
                        ) {
                            throw CertificateException()
                        }

                        override fun checkServerTrusted(
                            chain: Array<X509Certificate>,
                            type: String,
                        ) {
                            val cert = chain.firstOrNull() ?: throw CertificateException()
                            cert.checkValidity()
                            val hashed =
                                MessageDigest.getInstance("SHA-256")
                                    .digest(cert.encoded)
                                    .joinToString("") { "%02x".format(it) }
                            if (hashed != pin)
                                throw CertificateException("Unrecognized Wispel server")
                        }
                    }
                val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
                OkHttpClient.Builder()
                    .sslSocketFactory(tls.socketFactory, trust)
                    .followRedirects(false)
                    .followSslRedirects(false)
                    .pingInterval(20, TimeUnit.SECONDS)
                    .callTimeout(12, TimeUnit.SECONDS)
                    .build()
            }
    }

    fun pair(inv: Invite, name: String) {
        val previous =
            if (
                id.isNotEmpty() &&
                    prefs.getString("url", null) == inv.url &&
                    prefs.getString("pin", null) == inv.pin &&
                    (role == "send" || inv.role == "send")
            )
                request("/v1/devices/" + id).delete().build()
            else null
        val req =
            Request.Builder()
                .url(inv.url + "/v1/pair")
                .post(
                    json("code" to inv.code, "name" to name, "platform" to "android")
                        .toString()
                        .toRequestBody("application/json".toMediaType())
                )
                .build()
        client(inv.pin).newCall(req).execute().use {
            if (!it.isSuccessful) throw NetworkError(it.code)
            val r = JSONObject(it.body!!.string())
            require(r.getString("role") == inv.role)
            check(
                prefs
                    .edit()
                    .clear()
                    .putString("url", inv.url)
                    .putString("pin", inv.pin)
                    .putString("id", r.getString("id"))
                    .putLong("pairedAt", System.currentTimeMillis())
                    .putString("role", inv.role)
                    .putString("name", name)
                    .putString("credential", storeToken(r.getString("token")))
                    .commit()
            ) {
                "기기 등록 정보를 저장할 수 없습니다."
            }
        }
        if (previous != null) runCatching { client(inv.pin).newCall(previous).execute().use {} }
    }

    fun request(path: String) =
        Request.Builder()
            .url(prefs.getString("url", "") + path)
            .header("Authorization", "Bearer " + token())

    fun transport() = client(requireNotNull(prefs.getString("pin", null)))

    fun api(path: String, method: String = "GET", body: JSONObject? = null): String {
        val req =
            request(path)
                .method(method, body?.toString()?.toRequestBody("application/json".toMediaType()))
                .build()
        transport().newCall(req).execute().use {
            if (!it.isSuccessful) throw NetworkError(it.code)
            return it.body?.string().orEmpty()
        }
    }
}

fun json(vararg fields: Pair<String, Any>) =
    JSONObject().apply { fields.forEach { put(it.first, it.second) } }
