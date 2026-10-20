import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Bring the phone up first: iOS may have launched us in the background purely to
    // deliver a VoIP push, and the PushKit registry has to exist before that is handed over.
    Phone.shared.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    Phone.shared.refreshRegistration()   // re-register promptly when the user opens the app
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // flutter_contacts force-unwraps UIApplication.delegate.window at registration (a
    // pre-UIScene assumption; iOS 27 SDK apps must use scenes, so that window is nil).
    // Lend it a window only while plugins register (it keeps the root controller, which
    // forwards present/dismiss to the real scene), then take it back so the scene's own
    // window stays the one on screen.
    let lent = window == nil
    if lent {
      let w = UIWindow(frame: UIScreen.main.bounds)
      w.rootViewController = ScenePresenter()
      window = w
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if lent { window = nil }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NovaLinkPhone") else { return }
    PhoneChannels.register(messenger: registrar.messenger())
  }
}

/// Stand-in root controller for plugins that present UI from AppDelegate.window: it is
/// never shown, it hands every present/dismiss to the top controller of the active scene.
final class ScenePresenter: UIViewController {
  private var top: UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    let win = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    var vc = win?.rootViewController
    while let next = vc?.presentedViewController { vc = next }
    return vc
  }

  override func present(_ vc: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
    top?.present(vc, animated: animated, completion: completion)
  }

  override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
    top?.dismiss(animated: animated, completion: completion)
  }
}

/// Same channel names and methods as Android's MainActivity, so the Dart side is shared.
enum PhoneChannels {
  static func register(messenger: FlutterBinaryMessenger) {
    let phone = Phone.shared

    FlutterEventChannel(name: "novalink/linphone/events", binaryMessenger: messenger)
      .setStreamHandler(EventHandler())

    FlutterMethodChannel(name: "novalink/linphone", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        let a = call.arguments as? [String: Any] ?? [:]
        func s(_ k: String) -> String? { a[k] as? String }
        func b(_ k: String) -> Bool { a[k] as? Bool ?? false }
        switch call.method {
        case "login":
          guard let d = s("domain"), let u = s("username"), let p = s("password"), let px = s("proxy") else {
            return result(FlutterError(code: "phone", message: "missing login fields", details: nil))
          }
          do {
            try phone.login(domain: d, username: u, password: p, proxy: px, displayName: s("displayName"))
            result(true)
          } catch {
            result(FlutterError(code: "phone", message: "\(error)", details: nil))
          }
        case "logout": phone.logout(); result(true)
        case "status": result(phone.savedIdentity())
        case "call": result(phone.placeCall(s("target") ?? ""))
        case "answer": phone.answer(); result(true)
        case "decline": phone.decline(); result(true)
        case "hangup": phone.hangup(); result(true)
        case "mute": phone.setMuted(b("on")); result(true)
        case "speaker": phone.setSpeaker(b("on")); result(true)
        case "hold": phone.setHold(b("on")); result(true)
        case "dtmf": phone.sendDtmf(s("digit") ?? ""); result(true)
        case "transfer": phone.transfer(s("target") ?? ""); result(true)
        case "callLogs": result(phone.callLogs())
        case "clearCallLogs": phone.clearCallLogs(); result(true)
        case "refresh": phone.refreshRegistration(); result(true)
        default: result(FlutterMethodNotImplemented)
        }
      }
  }

  final class EventHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
      Phone.shared.onEvent = { m in events(m) }
      Phone.shared.pushCurrentState()   // catch an already-ringing/woken call
      return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
      Phone.shared.onEvent = nil
      return nil
    }
  }
}
