package app.wispel.phone

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray

private val forest = Color(0xFF043D2B)
private val canvas = Color(0xFFFFFCF4)
private val tileColors =
    mapOf(
        "call" to 0xFFE8C6B5,
        "missedCall" to 0xFFE8C6B5,
        "sms" to 0xFFE4DBEB,
        "kakao" to 0xFFF4D67B,
        "slack" to 0xFFCFD9F3,
        "mail" to 0xFFD2DFD0,
    )

class Home : ComponentActivity() {
    private var incoming by mutableStateOf("")

    override fun onStart() {
        super.onStart()
        val r = Relay(this)
        if (r.role == "receive" && r.prefs.getBoolean("enabled", false))
            startForegroundService(Intent(this, Reception::class.java))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        incoming = intent.dataString.orEmpty()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.view.WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        incoming = intent.dataString.orEmpty()
        setContent {
            MaterialTheme(
                colorScheme =
                    lightColorScheme(primary = forest, background = canvas, surface = canvas)
            ) {
                Screen()
            }
        }
    }

    @Composable
    private fun Screen() {
        val relay = remember { Relay(this) }
        val prefs = relay.prefs
        val events = remember { Events.get(this) }
        var revision by remember { mutableIntStateOf(0) }
        DisposableEffect(Unit) {
            val l =
                android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
                    revision++
                }
            prefs.registerOnSharedPreferenceChangeListener(l)
            onDispose { prefs.unregisterOnSharedPreferenceChangeListener(l) }
        }
        val scope = rememberCoroutineScope()
        var settings by remember { mutableStateOf(false) }
        var message by remember { mutableStateOf("") }
        var devices by remember { mutableStateOf(listOf<Pair<String, String>>()) }
        var chosen by remember { mutableStateOf("") }
        var section by remember { mutableStateOf("") }
        var invite by remember(incoming) { mutableStateOf(incoming) }
        var name by
            remember(relay.id) { mutableStateOf(prefs.getString("name", "안드로이드 폰").orEmpty()) }
        val scan =
            rememberLauncherForActivityResult(ScanContract()) {
                if (it.contents != null) invite = it.contents
            }
        val permission =
            rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
        fun task(action: () -> String) {
            scope.launch {
                message =
                    try {
                        withContext(Dispatchers.IO) { action() }
                    } catch (e: Exception) {
                        e.localizedMessage ?: "연결 실패"
                    }
                revision++
            }
        }
        fun startReceiving() {
            prefs.edit().putBoolean("enabled", true).apply()
            if (Build.VERSION.SDK_INT >= 33)
                permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            startForegroundService(Intent(this, Reception::class.java))
        }
        LaunchedEffect(settings, relay.id) {
            if (relay.id.isNotEmpty()) {
                runCatching { withContext(Dispatchers.IO) { JSONArray(relay.api("/v1/devices")) } }
                    .onSuccess { arr ->
                        devices =
                            (0 until arr.length()).mapNotNull {
                                val o = arr.getJSONObject(it)
                                if (
                                    o.getString("role") != relay.role ||
                                        o.getString("id") == relay.id
                                )
                                    o.getString("id") to o.getString("name")
                                else null
                            }
                    }
            }
        }
        val version = revision
        val enrolled = relay.id.isNotEmpty() && !(invite.isNotEmpty() && incoming.isNotEmpty())
        androidx.activity.compose.BackHandler(settings) {
            if (section.isNotEmpty()) section = "" else settings = false
        }
        Column(Modifier.fillMaxSize().background(canvas).systemBarsPadding()) {
            val scroll = rememberScrollState()
            LaunchedEffect(settings, section) { scroll.scrollTo(0) }
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(scroll).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(painterResource(R.drawable.brand), "접은 쪽지", Modifier.size(30.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Wispel",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                        color = forest,
                    )
                    if (enrolled && !settings && relay.role == "receive") {
                        Spacer(Modifier.weight(1f))
                        TextButton({
                            settings = true
                            section = "잠시 쉬기"
                        }) {
                            Text(
                                if (prefs.getLong("pause", 0) > System.currentTimeMillis()) "일시정지 중"
                                else "잠시 쉬기"
                            )
                        }
                    }
                }
                if (relay.id.isEmpty() || (invite.isNotEmpty() && incoming.isNotEmpty())) {
                    Text("기기 등록", style = MaterialTheme.typography.headlineMedium)
                    OutlinedTextField(name, { name = it }, label = { Text("이 폰 이름") })
                    OutlinedTextField(invite, { invite = it }, label = { Text("등록 QR 주소") })
                    Button({ scan.launch(ScanOptions().setPrompt("Windows에 표시한 등록 QR을 스캔하세요")) }) {
                        Text("QR 스캔")
                    }
                    val parsed = runCatching { Invite.parse(invite) }.getOrNull()
                    if (parsed != null)
                        Text(
                            if (parsed.role == "send") "이 폰 → 본폰 · 보내기 전용" else "서브폰 → 이 폰 · 받기 전용"
                        )
                    Button(
                        onClick = {
                            val input = parsed!!
                            task {
                                relay.pair(input, name)
                                runOnUiThread {
                                    invite = ""
                                    incoming = ""
                                    intent.data = null
                                }
                                "등록 완료"
                            }
                        },
                        enabled = parsed != null && name.isNotBlank(),
                    ) {
                        Text("이 역할로 등록")
                    }
                } else {
                    Text(
                        if (settings) section.ifEmpty { "설정" } else "최근 알림",
                        style = MaterialTheme.typography.headlineMedium,
                    )
                    Text(name + " · " + if (relay.role == "send") "보내기 전용" else "받기 전용")
                    if (!settings) {
                        if (relay.role == "receive") {
                            Text(
                                prefs.getString("state", "수신 중지").orEmpty(),
                                style = MaterialTheme.typography.labelMedium,
                            )
                            if (prefs.getString("state", "") != "연결됨")
                                Button({ startReceiving() }) { Text("직접 수신 켜기") }
                            val tiles = remember(version, relay.id) { events.tiles(relay.id) }
                            if (tiles.isEmpty()) Text("첫 알림 대기 중")
                            tiles.firstOrNull()?.let {
                                Text(
                                    it.name +
                                        " · 마지막 수신 " +
                                        DateFormat.getTimeInstance(DateFormat.SHORT)
                                            .format(Date(it.at)),
                                    style = MaterialTheme.typography.bodySmall,
                                )
                                Text("앱별로 보기", style = MaterialTheme.typography.titleSmall)
                            }
                            tiles.firstOrNull()?.let {
                                EventTile(it, Modifier.fillMaxWidth()) {
                                    chosen = it.source + "." + it.kind
                                }
                            }
                            tiles.drop(1).chunked(2).forEach { pair ->
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    pair.forEach {
                                        EventTile(it, Modifier.weight(1f)) {
                                            chosen = it.source + "." + it.kind
                                        }
                                    }
                                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                                }
                            }
                            tiles.firstOrNull()?.let { latest ->
                                Text("마지막 수신", style = MaterialTheme.typography.titleSmall)
                                Text(
                                    Rules.labels[latest.kind].orEmpty() + " · " + latest.name,
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            }
                            tiles
                                .firstOrNull { it.source + "." + it.kind == chosen }
                                ?.let {
                                    Text(
                                        it.name +
                                            " · " +
                                            Rules.labels[it.kind] +
                                            " · " +
                                            it.count +
                                            "건"
                                    )
                                }
                        } else {
                            Button({
                                startActivity(
                                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                )
                            }) {
                                Text("알림 접근 설정")
                            }
                            Button({
                                task {
                                    events.add(relay.id, "kakao")
                                    DeliveryWorker.schedule(this@Home)
                                    "발송 대기열에 저장했습니다."
                                }
                            }) {
                                Text("시험 알림 보내기")
                            }
                        }
                    } else if (section.isEmpty()) {
                        Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFE0E8D7))) {
                            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                                Text(
                                    "이 폰 · " + if (relay.role == "receive") "받기 전용" else "보내기 전용",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                                Text(name, style = MaterialTheme.typography.titleLarge)
                                devices
                                    .filter { it.first != relay.id }
                                    .forEach {
                                        Text(
                                            if (relay.role == "receive")
                                                "← " + it.second + " · 보내기 전용"
                                            else "→ " + it.second + " · 받기 전용"
                                        )
                                    }
                            }
                        }
                        val pages =
                            if (relay.role == "receive")
                                listOf("기기 관리", "받을 알림", "소리와 진동", "워치에 표시", "잠시 쉬기", "기록 보관")
                            else listOf("기기 관리", "보낼 알림")
                        pages.forEach { page ->
                            TextButton(
                                onClick = { section = page },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(page, Modifier.weight(1f))
                                Text("›")
                            }
                            HorizontalDivider()
                        }
                    } else {
                        TextButton({ section = "" }) { Text("‹ 설정") }
                        if (section == "기기 관리") {
                            if (relay.role == "receive") {
                                TextButton({
                                    if (
                                        !getSystemService(NotificationManager::class.java)
                                            .areNotificationsEnabled()
                                    ) {
                                        message = "Android 설정에서 위스펠 알림을 허용하세요."
                                    } else if (
                                        prefs.getLong("pause", 0) > System.currentTimeMillis() ||
                                            !prefs.getBoolean("allow.kakao", true)
                                    ) {
                                        message = "잠시 쉬기와 카카오톡 수신 설정을 확인하세요."
                                    } else {
                                        postNotice(
                                            json(
                                                "sourceId" to "local-test",
                                                "sourceName" to "이 폰 · 표시 시험",
                                                "kind" to "kakao",
                                                "occurredAt" to System.currentTimeMillis(),
                                            ),
                                            1,
                                            prefs.getBoolean("watch.kakao", true),
                                        )
                                        message = "본폰에 시험 알림을 게시했습니다."
                                    }
                                }) {
                                    Text("본폰 표시 시험")
                                }
                            }
                            OutlinedTextField(name, { name = it }, label = { Text("기기 이름") })
                            Button({
                                task {
                                    relay.api(
                                        "/v1/devices/" + relay.id,
                                        "PUT",
                                        json("name" to name),
                                    )
                                    prefs.edit().putString("name", name).apply()
                                    "이름 저장됨"
                                }
                            }) {
                                Text("이름 저장")
                            }
                            devices.forEach {
                                val (peerId, peerName) = it
                                if (relay.role == "receive" && peerId != relay.id) {
                                    var edit by
                                        remember(peerId, peerName) { mutableStateOf(peerName) }
                                    var removing by remember(peerId) { mutableStateOf(false) }
                                    OutlinedTextField(
                                        edit,
                                        { edit = it },
                                        label = { Text("서브폰 이름 · 보내기 전용") },
                                    )
                                    Row {
                                        TextButton({
                                            task {
                                                relay.api(
                                                    "/v1/devices/" + peerId,
                                                    "PUT",
                                                    json("name" to edit),
                                                )
                                                runOnUiThread {
                                                    devices =
                                                        devices.map {
                                                            if (it.first == peerId) peerId to edit
                                                            else it
                                                        }
                                                }
                                                "이름 저장됨"
                                            }
                                        }) {
                                            Text("서브폰 이름 저장")
                                        }
                                        TextButton({ removing = true }) { Text("서브폰 연결 해제") }
                                    }
                                    if (removing)
                                        AlertDialog(
                                            onDismissRequest = { removing = false },
                                            title = { Text(peerName + " 연결 해제") },
                                            text = { Text("이 기기에서 보내는 알림 전달이 중단됩니다.") },
                                            confirmButton = {
                                                TextButton({
                                                    removing = false
                                                    task {
                                                        relay.api("/v1/devices/" + peerId, "DELETE")
                                                        runOnUiThread {
                                                            devices =
                                                                devices.filter {
                                                                    it.first != peerId
                                                                }
                                                        }
                                                        "해제됨"
                                                    }
                                                }) {
                                                    Text("해제")
                                                }
                                            },
                                            dismissButton = {
                                                TextButton({ removing = false }) { Text("취소") }
                                            },
                                        )
                                } else Text(peerName + if (peerId == relay.id) " · 이 폰" else "")
                            }
                            if (relay.role == "receive")
                                Button({
                                    prefs.edit().putBoolean("enabled", false).apply()
                                    stopService(Intent(this@Home, Reception::class.java))
                                }) {
                                    Text("직접 수신 중지")
                                }
                            TextButton({
                                task {
                                    try {
                                        relay.api("/v1/devices/" + relay.id, "DELETE")
                                    } catch (failure: NetworkError) {
                                        if (failure.status != 401) throw failure
                                    }
                                    stopService(Intent(this@Home, Reception::class.java))
                                    prefs.edit().clear().commit()
                                    "연결 해제됨"
                                }
                            }) {
                                Text("이 폰 연결 해제")
                            }
                        }
                        if (section == "잠시 쉬기") {
                            Row {
                                TextButton({
                                    prefs
                                        .edit()
                                        .putLong("pause", System.currentTimeMillis() + 3600000)
                                        .apply()
                                }) {
                                    Text("1시간 쉬기")
                                }
                                TextButton({
                                    prefs.edit().putLong("pause", Long.MAX_VALUE).apply()
                                }) {
                                    Text("계속 쉬기")
                                }
                                TextButton({ prefs.edit().remove("pause").apply() }) { Text("재개") }
                            }
                            if (prefs.getLong("pause", 0) > System.currentTimeMillis())
                                Text("알림 일시정지 중")
                        }
                        if (section == "기록 보관") {
                            Toggle("최근 기록 7일", prefs.getBoolean("history", true)) {
                                prefs.edit().putBoolean("history", it).apply()
                            }
                            TextButton({
                                events.clearHistory(relay.id)
                                revision++
                            }) {
                                Text("기록 전체 삭제")
                            }
                        }
                        if (section == "보낼 알림") {
                            var mail by remember {
                                mutableStateOf(
                                    prefs.getString("mailPackage", "com.mailplug.aeolos2").orEmpty()
                                )
                            }
                            OutlinedTextField(mail, { mail = it }, label = { Text("메일플러그 앱 패키지") })
                            TextButton({
                                prefs.edit().putString("mailPackage", mail.trim()).apply()
                            }) {
                                Text("메일 앱 저장")
                            }
                        }
                        Rules.labels.forEach { (kind, label) ->
                            if (section == "보낼 알림" || section == "받을 알림")
                                Toggle(label, prefs.getBoolean("allow." + kind, true)) {
                                    prefs.edit().putBoolean("allow." + kind, it).apply()
                                }
                            if (section == "워치에 표시") {
                                Toggle(label + " · 워치", prefs.getBoolean("watch." + kind, true)) {
                                    prefs.edit().putBoolean("watch." + kind, it).apply()
                                }
                            }
                            if (section == "소리와 진동") {
                                TextButton({
                                    val id = "kind." + kind
                                    val nm = getSystemService(NotificationManager::class.java)
                                    if (nm.getNotificationChannel(id) == null)
                                        nm.createNotificationChannel(
                                            android.app
                                                .NotificationChannel(
                                                    id,
                                                    label,
                                                    NotificationManager.IMPORTANCE_DEFAULT,
                                                )
                                                .apply {
                                                    setSound(null, null)
                                                    enableVibration(false)
                                                }
                                        )
                                    startActivity(
                                        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                            .putExtra(Settings.EXTRA_CHANNEL_ID, id)
                                    )
                                }) {
                                    Text(label + " 소리와 진동")
                                }
                            }
                        }
                        if (section == "받을 알림")
                            devices
                                .filter { it.first != relay.id }
                                .forEach { (id, device) ->
                                    Text(device)
                                    Rules.labels.forEach { (kind, label) ->
                                        val k = "allow." + id + "." + kind
                                        Toggle(device + " · " + label, prefs.getBoolean(k, true)) {
                                            prefs.edit().putBoolean(k, it).apply()
                                        }
                                    }
                                }
                    }
                }
                if (message.isNotBlank()) Text(message)
            }
            if (enrolled)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    TextButton({
                        settings = false
                        section = ""
                    }) {
                        Text("최근 알림")
                    }
                    TextButton({
                        settings = true
                        section = ""
                    }) {
                        Text("기기 설정")
                    }
                }
        }
    }
}

@Composable
private fun EventTile(t: Tile, modifier: Modifier, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = Color(tileColors[t.kind] ?: 0xFFD2DFD0)),
    ) {
        Column(Modifier.fillMaxWidth().padding(14.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val icon =
                    when (t.kind) {
                        "call" -> R.drawable.kind_call
                        "missedCall" -> R.drawable.kind_missed_call
                        "sms" -> R.drawable.kind_sms
                        "slack" -> R.drawable.kind_slack
                        "mail" -> R.drawable.kind_mail
                        else -> R.drawable.kind_kakao
                    }
                Image(painterResource(icon), null, Modifier.size(22.dp))
                Text(
                    t.count.toString() + "건",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                )
            }
            Text(Rules.labels[t.kind].orEmpty(), style = MaterialTheme.typography.titleSmall)
            Text(t.name, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun Toggle(label: String, value: Boolean, change: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .toggleable(value = value, role = Role.Switch, onValueChange = change)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, Modifier.weight(1f))
        Switch(checked = value, onCheckedChange = null)
    }
}
