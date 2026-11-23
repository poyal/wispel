import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken data: Data
  ) {
    let token = data.map { String(format: "%02x", $0) }.joined()
    Task {
      guard await Relay.shared.identity()?.device.role == "receive" else { return }
      do {
        _ = try await Relay.shared.api("v1/apns", "PUT", ["value": token])
        UserDefaults.standard.set("서버에 수신 토큰 등록됨", forKey: "pushState")
      } catch { UserDefaults.standard.set("수신 토큰 등록 대기", forKey: "pushState") }
    }
  }
  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    UserDefaults.standard.set("Apple 푸시 등록 확인 필요", forKey: "pushState")
  }
  func acknowledge(_ n: UNNotification) async {
    guard let e = n.request.content.userInfo["wispel"] as? [String: Any],
      let id = e["eventId"] as? String, let src = e["sourceId"] as? String
    else { return }
    await Relay.shared.acknowledge(source: src, event: id)
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification)
    async -> UNNotificationPresentationOptions
  {
    Task { await acknowledge(n) }
    return [.banner, .list]
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive r: UNNotificationResponse
  ) async { await acknowledge(r.notification) }
}
@main struct WispelApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene { WindowGroup { Content() } }
}
private let forest = Color(red: 0.016, green: 0.239, blue: 0.169)
struct Content: View {
  @Environment(\.scenePhase) var phase
  @State var c: Connection?
  @State var devices: [Device] = []
  @State var name = "업무용 아이폰"
  @State var raw = ""
  @State var status = ""
  @State var scanner = false
  @State var help: Kind?
  @AppStorage("lastAccepted") var last: Double = 0
  @AppStorage("pushState") var pushState = "수신 토큰 등록 대기"
  var invite: Invite? { try? Invite(raw) }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack {
            Image("Brand").resizable().frame(width: 30, height: 30).clipShape(
              RoundedRectangle(cornerRadius: 7))
            Text("Wispel").font(.title2.bold())
          }.foregroundStyle(forest)
          if c == nil || !raw.isEmpty {
            Text("기기 등록").font(.largeTitle.bold())
            TextField("이 폰 이름", text: $name).textFieldStyle(.roundedBorder)
            Button("QR 스캔") { scanner = true }
            TextField("등록 QR 주소", text: $raw).textInputAutocapitalization(.never)
              .autocorrectionDisabled().textFieldStyle(.roundedBorder)
            if let i = invite { Text(i.role == "send" ? "이 폰 → 본폰 · 보내기 전용" : "서브폰 → 이 폰 · 받기 전용") }
            Button("이 역할로 등록") {
              run {
                try await Relay.shared.pair(raw, name: name)
                raw = ""
                await refresh()
                status = "등록 완료"
              }
            }.buttonStyle(.borderedProminent).disabled(invite == nil || name.isEmpty)
          } else if let c {
            Text(c.device.role == "send" ? "단축어 받기" : "받은 알림").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 5) {
              Text("이 폰 · " + (c.device.role == "send" ? "보내기 전용" : "받기 전용")).font(.caption)
              Text(c.device.name).font(.headline)
              ForEach(devices.filter { $0.role != c.device.role }) {
                Text($0.role == "receive" ? "→ " + $0.name + " · 받기 전용" : "← " + $0.name + " · 보내기 전용")
                  .font(.subheadline)
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(
              Color(red: 0.88, green: 0.91, blue: 0.83), in: RoundedRectangle(cornerRadius: 14))
            if c.device.role == "send" {
              group("기본 앱 알림", [.call, .sms])
              group("일반 앱 알림", [.kakao, .slack, .mail])
              Button("시험 알림 보내기") {
                run {
                  let done = try await Relay.shared.capture(.kakao)
                  status = done ? "서버 접수 완료" : "발송 대기"
                }
              }.buttonStyle(.borderedProminent)
              if last > 0 {
                Text("마지막 서버 접수 " + Date(timeIntervalSince1970: last).formatted()).font(.caption)
              }
            } else {
              Button("수신 알림 허용") {
                run {
                  let allowed = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound])
                  if allowed { UIApplication.shared.registerForRemoteNotifications() }
                  status = allowed ? "수신 권한 허용" : "수신 권한 꺼짐"
                }
              }
              Text("이 폰으로 전달된 알림은 알림 센터에 표시됩니다.")
              Text(pushState).font(.caption)
            }
            DisclosureGroup("기기 설정") {
              TextField("기기 이름", text: $name).textFieldStyle(.roundedBorder)
              Button("이름 저장") {
                run {
                  try await Relay.shared.rename(name)
                  await refresh()
                }
              }
              if c.device.role == "receive" {
                ForEach(devices.filter { $0.role == "send" }) { device in
                  PeerEditor(device: device) { method, name in
                    run {
                      _ = try await Relay.shared.api(
                        "v1/devices/" + device.id, method, name.map { ["name": $0] })
                      await refresh()
                    }
                  }
                }
              }
              Button("이 폰 연결 해제", role: .destructive) {
                run {
                  try await Relay.shared.unlink()
                  await refresh()
                }
              }
            }
          }
          if !status.isEmpty { Text(status).accessibilityIdentifier("status").font(.callout) }
        }.padding(22).frame(maxWidth: 540, alignment: .leading).frame(maxWidth: .infinity)
      }.background(Color(red: 1, green: 0.988, blue: 0.957)).tint(forest)
    }.task {
      await refresh()
      try? await Relay.shared.flush()
    }
    .onChange(of: phase) { _, p in
      if p == .active {
        Task {
          await refresh()
          try? await Relay.shared.flush()
        }
      }
    }
    .onOpenURL { url in
      if (try? Invite(url.absoluteString)) != nil {
        raw = url.absoluteString
        status = ""
      }
    }
    .sheet(isPresented: $scanner) {
      Scanner { v in
        scanner = false
        if let v { raw = v } else { status = "카메라 또는 사진 권한을 확인하거나 QR 주소를 붙여넣으세요." }
      }
    }
    .sheet(isPresented: Binding(get: { help != nil }, set: { if !$0 { help = nil } })) {
      if let kind = help { ShortcutHelp(kind: kind) }
    }
  }
  func group(_ title: String, _ list: [Kind]) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.caption.bold())
      ForEach(list, id: \.self) { kind in
        HStack {
          Text(kind == .call ? "전화" : kind == .sms ? "문자" : kind.label)
          Spacer()
          Button("받기") { help = kind }.buttonStyle(.bordered).accessibilityLabel(
            kind.label + " 단축어 받기")
        }
        Divider()
      }
    }
  }
  @MainActor func refresh() async {
    c = await Relay.shared.identity()
    if let c {
      name = c.device.name
      devices = (try? await Relay.shared.devices()) ?? []
      if c.device.role == "receive" {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }
  }
  func run(_ body: @escaping @MainActor () async throws -> Void) {
    Task { @MainActor in do { try await body() } catch { status = error.localizedDescription } }
  }
}
private struct PeerEditor: View {
  let device: Device
  let update: (String, String?) -> Void
  @State private var draft = ""
  @State private var removing = false
  var body: some View {
    DisclosureGroup(device.name + " · 보내기 전용") {
      TextField("서브폰 이름", text: $draft).textFieldStyle(.roundedBorder)
      Button("서브폰 이름 저장") { update("PUT", draft) }.disabled(draft.isEmpty)
      Button("서브폰 연결 해제", role: .destructive) { removing = true }
    }.onAppear { draft = device.name }
      .confirmationDialog(device.name + " 연결 해제", isPresented: $removing) {
        Button("해제", role: .destructive) { update("DELETE", nil) }
        Button("취소", role: .cancel) {}
      }
  }
}
struct ShortcutHelp: View {
  let kind: Kind
  @Environment(\.dismiss) var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section("단축어 받기") {
          if let path = Bundle.main.url(
            forResource: kind.rawValue, withExtension: "shortcut", subdirectory: "Shortcuts")
          {
            ShareLink(item: path) { Label("서명된 단축어 파일 받기", systemImage: "square.and.arrow.up") }
            Text("파일을 저장해 단축어에서 연 뒤, 해당 앱의 알림 자동화에 추가하세요.").font(.caption)
          }
          if let s =
            (Bundle.main.object(forInfoDictionaryKey: "WispelShortcuts") as? [String: String])?[
              kind.rawValue], let url = URL(string: s), url.host == "www.icloud.com"
          {
            Link("공유 단축어 열기", destination: url)
          }
          Link("단축어 앱 열기", destination: URL(string: "shortcuts://")!)
        }
        Section("기존 자동화에 연결하기") {
          Text("1. 단축어에서 알림 자동화를 열고 대상 앱을 선택하세요.")
          Text("2. ‘위스펠로 알림 전달’을 추가하고 종류를 " + kind.label + "로 지정하세요.")
          if kind == .call { Text("전화 알림 텍스트에 자동화의 알림 입력을 연결하세요.") }
          Text("3. 즉시 실행과 잠금 중 실행을 허용한 뒤 실제 알림 한 건으로 확인하세요.")
        }
      }.navigationTitle(kind.label).toolbar { Button("닫기") { dismiss() } }
    }
  }
}
struct Scanner: UIViewControllerRepresentable {
  let result: (String?) -> Void
  func makeUIViewController(context: Context) -> Camera {
    let c = Camera()
    c.complete = result
    return c
  }
  func updateUIViewController(_ vc: Camera, context: Context) {}
}
final class Camera: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  let session = AVCaptureSession()
  var complete: ((String?) -> Void)?
  private var layer: AVCaptureVideoPreviewLayer?
  override func viewDidLoad() {
    super.viewDidLoad()
    AVCaptureDevice.requestAccess(for: .video) { ok in
      DispatchQueue.main.async {
        guard ok, let cam = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: cam), self.session.canAddInput(input)
        else {
          self.complete?(nil)
          return
        }
        self.session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard self.session.canAddOutput(out) else {
          self.complete?(nil)
          return
        }
        self.session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: self.session)
        preview.videoGravity = .resizeAspectFill
        self.view.layer.addSublayer(preview)
        self.layer = preview
        preview.frame = self.view.bounds
        DispatchQueue.global().async { self.session.startRunning() }
      }
    }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layer?.frame = view.bounds
  }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    let s = session
    DispatchQueue.global().async { s.stopRunning() }
  }
  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    if let value = (objs.first as? AVMetadataMachineReadableCodeObject)?.stringValue {
      let callback = complete
      complete = nil
      callback?(value)
    }
  }
}
