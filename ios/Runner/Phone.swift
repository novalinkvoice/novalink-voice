import AVFoundation
import CallKit
import Flutter
import Foundation
import PushKit
import UIKit
import linphonesw

/// Process-wide Linphone Core for iOS — the counterpart of Android's Phone.kt, speaking
/// the same method/event channel protocol so the Flutter UI is shared unchanged.
///
/// Signalling: registers to the Flexisip push gateway on voice-01 (TLS 5062). Flexisip
/// passes REGISTER/INVITE to FusionPBX, which authenticates with the extension's SIP
/// password, and wakes us with an APNs VoIP push when a call arrives while we're asleep.
///
/// iOS rules this file is built around:
///  - Every VoIP push MUST be reported to CallKit before the PushKit handler returns,
///    or iOS kills the app and eventually stops delivering VoIP pushes to it. So we own
///    the PKPushRegistry (core.pushNotificationEnabled = false) and report immediately,
///    then let the Core fetch the INVITE (processPushNotification).
///  - With CallKit the system owns the audio session: core.callkitEnabled = true, and the
///    provider's didActivate/didDeactivate drive core.activateAudioSession.
final class Phone: NSObject {
    static let shared = Phone()

    private(set) var core: Core?
    /// Set while a Flutter engine is listening on the event channel.
    var onEvent: (([String: Any?]) -> Void)?

    private var delegate: CoreDelegateStub?
    private var logDelegate: LoggingServiceDelegateStub?
    private var lastRegState = "None"
    private var lastRegMessage = ""
    private var voipToken: String?

    // CallKit
    private let provider: CXProvider
    private let callController = CXCallController()
    /// Call-ID (SIP) -> CallKit UUID, for calls announced by push before the INVITE lands.
    private var pushUUIDs: [String: UUID] = [:]
    /// CallKit UUID -> Linphone call, once the INVITE has arrived (or we dialled out).
    private var calls: [UUID: Call] = [:]
    /// The user answered on the CallKit screen before the INVITE reached us.
    private var answerWhenArrives: Set<UUID> = []
    private var pushRegistry: PKPushRegistry?

    private static let emergency: Set<String> = ["911", "112", "9911"]

    private override init() {
        let cfg = CXProviderConfiguration()
        cfg.supportsVideo = false
        cfg.maximumCallGroups = 2
        cfg.maximumCallsPerCallGroup = 1
        cfg.supportedHandleTypes = [.phoneNumber, .generic]
        cfg.includesCallsInRecents = true
        if let icon = UIImage(named: "CallKitIcon") { cfg.iconTemplateImageData = icon.pngData() }
        provider = CXProvider(configuration: cfg)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - startup

    /// Called from didFinishLaunching — also when iOS launches us in the background for a
    /// VoIP push — so the Core, the push registry and the saved login are always up.
    func start() {
        ensureCore()
        let reg = PKPushRegistry(queue: .main)
        reg.delegate = self
        reg.desiredPushTypes = [.voIP]
        pushRegistry = reg
        autoLoginIfSaved()
    }

    @discardableResult
    func ensureCore() -> Core? {
        if let c = core { return c }
        do {
            #if DEBUG
            // Debug builds: full SIP trace into the device log (subsystem "NLVoice").
            LoggingService.Instance.logLevel = .Message
            let logD = LoggingServiceDelegateStub(onLogMessageWritten: { _, domain, _, msg in
                NSLog("NLVoice [%@] %@", domain, msg)
            })
            LoggingService.Instance.addDelegate(delegate: logD)
            logDelegate = logD
            #else
            LoggingService.Instance.logLevel = .Warning
            #endif
            let c = try Factory.Instance.createCore(configPath: nil, factoryConfigPath: nil, systemContext: nil)
            let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            c.setUserAgent(name: "NovaLink Voice iOS", version: ver)
            // Verify the server against the Let's Encrypt roots shipped with the app
            // (same bundle the Android build uses).
            if let pem = Phone.leRoots() { c.rootCaData = pem }
            c.verifyServerCertificates(yesno: true)
            c.verifyServerCn(yesno: true)
            // Audio profile matched to the Android build.
            c.echoCancellationEnabled = true
            c.echoLimiterEnabled = true
            c.genericComfortNoiseEnabled = false
            c.agcEnabled = false
            c.adaptiveRateControlEnabled = true
            c.micGainDb = -1.0
            c.playbackGainDb = 1.0
            // No ICE/STUN/TURN: FreeSWITCH latches to our real RTP source.
            let nat = try c.createNatPolicy()
            nat.stunEnabled = false
            nat.turnEnabled = false
            nat.iceEnabled = false
            nat.upnpEnabled = false
            c.natPolicy = nat
            // Plain RTP/AVP, no AVPF — matches FusionPBX/Flowroute.
            try? c.setMediaencryption(newValue: .None)
            c.avpfMode = .Disabled
            // We own PushKit (see the class comment) and CallKit owns the audio session.
            c.pushNotificationEnabled = false
            #if targetEnvironment(simulator)
            // The simulator's CallKit never activates the audio session (callservicesd
            // logs "not supported"), so the audio unit can't start and every call dies.
            // Simulator builds let the Core run the session itself; devices use CallKit.
            c.callkitEnabled = false
            #else
            c.callkitEnabled = true
            #endif
            let d = CoreDelegateStub(
                onCallStateChanged: { [weak self] core, call, state, message in
                    self?.callStateChanged(core: core, call: call, state: state, message: message)
                },
                onAccountRegistrationStateChanged: { [weak self] _, _, state, message in
                    guard let self = self else { return }
                    self.lastRegState = "\(state)"
                    self.lastRegMessage = message
                    self.emit(["type": "registration", "state": self.lastRegState, "message": message])
                })
            c.addDelegate(delegate: d)
            delegate = d
            try c.start()
            core = c
            return c
        } catch {
            NSLog("NovaLink: core start failed: \(error)")
            return nil
        }
    }

    private static func leRoots() -> String? {
        // Flutter packs assets into App.framework/flutter_assets.
        let key = FlutterDartProject.lookupKey(forAsset: "assets/le-roots.pem")
        let candidates = [
            Bundle.main.bundlePath + "/Frameworks/App.framework/" + key,
            Bundle.main.path(forResource: key, ofType: nil),
        ]
        for case let p? in candidates {
            if let s = try? String(contentsOfFile: p, encoding: .utf8) { return s }
        }
        return nil
    }

    // MARK: - events to Flutter

    private func emit(_ m: [String: Any?]) {
        if Thread.isMainThread { onEvent?(m) } else { DispatchQueue.main.async { self.onEvent?(m) } }
    }

    private static func userPart(_ uri: String) -> String {
        var s = uri
        if let r = s.range(of: "^sips?:", options: .regularExpression) { s.removeSubrange(r) }
        return String(s.split(separator: "@", maxSplits: 1).first ?? "")
    }

    private func callEvent(_ call: Call, _ state: Call.State, _ message: String = "") -> [String: Any?] {
        let remote = call.remoteAddress
        return [
            "type": "call",
            "state": "\(state)",
            "message": message,
            "incoming": call.dir == .Incoming,
            "remote": Phone.userPart(remote?.asStringUriOnly() ?? ""),
            "name": remote?.displayName ?? "",
            "duration": call.duration,
            "muted": !(core?.micEnabled ?? true),
            "speaker": call.outputAudioDevice?.type == .Speaker,
            "paused": state == .Paused || state == .Pausing,
        ]
    }

    func pushCurrentState() {
        emit(["type": "registration", "state": lastRegState, "message": lastRegMessage])
        if let c = core?.currentCall ?? core?.calls.first { emit(callEvent(c, c.state)) }
    }

    // MARK: - credentials (Keychain, readable after first unlock so a push can log in)

    private func saved() -> [String: String]? {
        guard let d = Keychain.get("login"),
              let m = try? JSONSerialization.jsonObject(with: d) as? [String: String],
              m["domain"] != nil, m["user"] != nil else { return nil }
        return m
    }

    func login(domain: String, username: String, password: String, proxy: String,
               displayName: String?, persist: Bool = true) throws {
        guard let c = ensureCore() else { throw PhoneError.noCore }
        c.clearAccounts(); c.clearAllAuthInfo()
        let auth = try Factory.Instance.createAuthInfo(username: username, userid: nil, passwd: password,
                                                       ha1: nil, realm: nil, domain: domain)
        c.addAuthInfo(info: auth)
        let params = try c.createAccountParams()
        let identity = try Factory.Instance.createAddress(addr: "sip:\(username)@\(domain)")
        if let n = displayName, !n.isEmpty { try? identity.setDisplayname(newValue: n) }
        try params.setIdentityaddress(newValue: identity)
        let server = try Factory.Instance.createAddress(addr: proxy)
        try? server.setTransport(newValue: .Tls)
        try params.setServeraddress(newValue: server)
        params.registerEnabled = true
        applyPush(to: params)
        let account = try c.createAccount(params: params)
        try c.addAccount(account: account)
        c.defaultAccount = account
        if persist {
            let m = ["domain": domain, "user": username, "pass": password, "proxy": proxy,
                     "name": displayName ?? ""]
            if let d = try? JSONSerialization.data(withJSONObject: m) { Keychain.set("login", d) }
        }
    }

    /// Stamp our APNs VoIP token into the account so Flexisip can wake us.
    /// Contact params (RFC 8599, as Flexisip expects): pn-provider=apns|apns.dev,
    /// pn-param=TEAMID.bundle.voip, pn-prid=<token>:voip.
    private func applyPush(to params: AccountParams) {
        guard let token = voipToken else { params.pushNotificationAllowed = false; return }
        params.pushNotificationAllowed = true
        params.remotePushNotificationAllowed = false
        guard let cfg = params.pushNotificationConfig else { return }
        let bundle = Bundle.main.bundleIdentifier ?? "com.novalinkfiber.novalinkvoice"
        let team = Bundle.main.infoDictionary?["NLTeamID"] as? String ?? ""
        #if DEBUG
        cfg.provider = "apns.dev"
        #else
        cfg.provider = "apns"
        #endif
        cfg.param = "\(team).\(bundle).voip"
        cfg.prid = "\(token):voip"
        cfg.bundleIdentifier = bundle
        cfg.teamId = team
        cfg.voipToken = "\(token):voip"
    }

    private func refreshPushParams() {
        guard let c = core else { return }
        for a in c.accountList {
            guard let p = a.params?.clone() else { continue }
            applyPush(to: p)
            a.params = p
        }
        c.refreshRegisters()
    }

    func logout() {
        guard let c = ensureCore() else { return }
        try? c.terminateAllCalls()
        // Unregister so FusionPBX stops routing (and Flexisip stops pushing) to this phone.
        for a in c.accountList {
            if let p = a.params?.clone() { p.registerEnabled = false; a.params = p }
        }
        c.clearAccounts(); c.clearAllAuthInfo()
        c.clearCallLogs()
        Keychain.delete("login")
        lastRegState = "None"
        emit(["type": "registration", "state": "None", "message": ""])
    }

    func savedIdentity() -> [String: Any?] {
        ensureCore()
        let m = saved()
        return ["loggedIn": m != nil, "user": m?["user"], "domain": m?["domain"],
                "name": m?["name"] ?? "", "registration": lastRegState]
    }

    private func autoLoginIfSaved() {
        guard let m = saved(), let d = m["domain"], let u = m["user"], let pw = m["pass"],
              let proxy = m["proxy"] else { return }
        try? login(domain: d, username: u, password: pw, proxy: proxy, displayName: m["name"], persist: false)
    }

    func refreshRegistration() { core?.refreshRegisters() }

    // MARK: - placing calls

    static func isEmergency(_ target: String) -> Bool {
        let t = target.trimmingCharacters(in: .whitespaces)
        return !t.hasPrefix("sip:") && emergency.contains(t.filter(\.isNumber))
    }

    /// 911 must not go out as VoIP: the 911 centre would get the registered business
    /// address, not where the phone is. Hand it to the phone app (cellular E911 sends the
    /// real location). iOS shows its own "Call 911?" confirmation. False on a device with
    /// no cellular calling (e.g. a Wi-Fi iPad) — then we fall back to the VoIP path.
    private func openEmergencyDialer() -> Bool {
        guard let url = URL(string: "tel://911"), UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    /// @return "emergency_native" if handed to the phone app, else "voip".
    func placeCall(_ target: String) -> String {
        if Phone.isEmergency(target) && openEmergencyDialer() { return "emergency_native" }
        #if targetEnvironment(simulator)
        if let c = ensureCore(), let addr = sipAddress(target), let cp = try? c.createCallParams(call: nil) {
            cp.videoEnabled = false
            _ = c.inviteAddressWithParams(addr: addr, params: cp)
        }
        return "voip"
        #endif
        let uuid = UUID()
        let handle = CXHandle(type: .phoneNumber, value: target)
        let start = CXStartCallAction(call: uuid, handle: handle)
        callController.request(CXTransaction(action: start)) { err in
            if let err = err { NSLog("NovaLink: CallKit start refused: \(err)") }
        }
        return "voip"
    }

    private func sipAddress(_ target: String) -> Address? {
        guard let c = core, let domain = saved()?["domain"] else { return nil }
        let clean = target.trimmingCharacters(in: .whitespaces)
        let uri = clean.hasPrefix("sip:") ? clean
            : "sip:\(clean.filter { $0.isNumber || "*#+".contains($0) })@\(domain)"
        return c.interpretUrl(url: uri, applyInternationalPrefix: false)
    }

    // MARK: - in-call controls (from Flutter)

    private var active: Call? { core?.currentCall ?? core?.calls.first }
    private func uuid(for call: Call) -> UUID? { calls.first(where: { $0.value === call })?.key }

    func answer() {
        guard let call = active, let id = uuid(for: call) else { return }
        callController.request(CXTransaction(action: CXAnswerCallAction(call: id))) { _ in }
    }

    func decline() { hangup() }

    func hangup() {
        if let call = active, let id = uuid(for: call) {
            callController.request(CXTransaction(action: CXEndCallAction(call: id))) { _ in }
        } else {
            try? active?.terminate()
        }
    }

    func setMuted(_ muted: Bool) {
        if let call = active, let id = uuid(for: call) {
            callController.request(CXTransaction(action: CXSetMutedCallAction(call: id, muted: muted))) { _ in }
        } else {
            core?.micEnabled = !muted
        }
    }

    func setSpeaker(_ on: Bool) {
        guard let call = active else { return }
        let want: AudioDevice.Kind = on ? .Speaker : .Earpiece
        let devs = core?.audioDevices ?? []
        let wired: [AudioDevice.Kind] = [.Bluetooth, .Headset, .Headphones]
        let dev = devs.first(where: { $0.type == want })
            ?? (on ? nil : devs.first(where: { wired.contains($0.type) }))
        if let dev = dev { call.outputAudioDevice = dev }
        emit(callEvent(call, call.state))
    }

    func setHold(_ hold: Bool) {
        if let call = active, let id = uuid(for: call) {
            callController.request(CXTransaction(action: CXSetHeldCallAction(call: id, onHold: hold))) { _ in }
        }
    }

    func sendDtmf(_ digit: String) {
        guard let ch = digit.utf8.first else { return }
        try? active?.sendDtmf(dtmf: CChar(bitPattern: ch))
    }

    /// Blind transfer the current call to an extension or number.
    func transfer(_ target: String) {
        guard let call = active, let addr = sipAddress(target) else { return }
        try? call.transferTo(referTo: addr)
    }

    func callLogs() -> [[String: Any?]] {
        guard let c = core else { return [] }
        return c.callLogs.prefix(200).map { l in
            [
                "remote": Phone.userPart(l.remoteAddress?.asStringUriOnly() ?? ""),
                "name": l.remoteAddress?.displayName ?? "",
                "incoming": l.dir == .Incoming,
                "status": "\(l.status)",     // Success | Missed | Declined | Aborted | ...
                "start": l.startDate,        // epoch seconds
                "duration": l.duration,
            ]
        }
    }

    func clearCallLogs() { core?.clearCallLogs() }

    // MARK: - Core call state -> CallKit + Flutter

    private func callStateChanged(core: Core, call: Call, state: Call.State, message: String) {
        switch state {
        case .IncomingReceived:
            let callId = call.callLog?.callId ?? ""
            if let id = pushUUIDs.removeValue(forKey: callId) {
                // Already on the CallKit screen from the push.
                calls[id] = call
                if answerWhenArrives.remove(id) != nil {
                    core.configureAudioSession()
                    try? call.accept()
                }
            } else {
                // App was awake and registered: no push, announce it ourselves.
                let id = UUID()
                calls[id] = call
                reportIncoming(id, caller: call.remoteAddress)
            }
        case .Connected:
            if call.dir == .Outgoing, let id = uuid(for: call) {
                provider.reportOutgoingCall(with: id, connectedAt: Date())
            }
        case .OutgoingRinging, .OutgoingEarlyMedia:
            if let id = uuid(for: call) { provider.reportOutgoingCall(with: id, startedConnectingAt: Date()) }
        case .End, .Error, .Released:
            if let id = uuid(for: call) {
                if state != .Released {
                    let reason: CXCallEndedReason =
                        state == .Error ? .failed :
                        (call.callLog?.status == .Missed ? .unanswered : .remoteEnded)
                    provider.reportCall(with: id, endedAt: Date(), reason: reason)
                }
                if state == .Released { calls.removeValue(forKey: id) }
            }
        default:
            break
        }
        emit(callEvent(call, state, message))
    }

    private func reportIncoming(_ id: UUID, caller: Address?, fallback: String = "NovaLink Voice") {
        let update = CXCallUpdate()
        let number = Phone.userPart(caller?.asStringUriOnly() ?? "")
        update.remoteHandle = CXHandle(type: .phoneNumber, value: number.isEmpty ? fallback : number)
        update.localizedCallerName = caller?.displayName ?? (number.isEmpty ? fallback : number)
        update.hasVideo = false
        update.supportsDTMF = true
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        provider.reportNewIncomingCall(with: id, update: update) { err in
            if let err = err { NSLog("NovaLink: CallKit refused incoming: \(err)") }
        }
    }

    enum PhoneError: Error { case noCore }
}

// MARK: - PushKit

extension Phone: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        voipToken = credentials.token.map { String(format: "%02x", $0) }.joined()
        refreshPushParams()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        voipToken = nil
        refreshPushParams()
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let p = payload.dictionaryPayload
        let aps = p["aps"] as? [String: Any] ?? [:]
        let callId = (p["call-id"] as? String) ?? (aps["call-id"] as? String) ?? ""
        let from = (p["from-uri"] as? String) ?? ""
        let name = (p["display-name"] as? String) ?? (aps["loc-args"] as? [String])?.first

        // iOS requirement: report to CallKit before returning, every time.
        let id = UUID()
        if !callId.isEmpty { pushUUIDs[callId] = id }
        let update = CXCallUpdate()
        let number = from.isEmpty ? "NovaLink Voice" : Phone.userPart(from)
        update.remoteHandle = CXHandle(type: .phoneNumber, value: number)
        update.localizedCallerName = (name?.isEmpty == false) ? name : number
        update.hasVideo = false
        update.supportsDTMF = true
        update.supportsHolding = true
        provider.reportNewIncomingCall(with: id, update: update) { _ in completion() }

        // Then make sure the Core is registered and pulls the INVITE in.
        ensureCore()
        if core?.accountList.isEmpty ?? true { autoLoginIfSaved() }
        core?.processPushNotification(callId: callId.isEmpty ? nil : callId)

        // If the INVITE never shows (caller hung up first), don't leave a ghost ringing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, self.calls[id] == nil else { return }
            self.pushUUIDs = self.pushUUIDs.filter { $0.value != id }
            self.answerWhenArrives.remove(id)
            self.provider.reportCall(with: id, endedAt: Date(), reason: .remoteEnded)
        }
    }
}

// MARK: - CallKit

extension Phone: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        try? core?.terminateAllCalls()
        calls.removeAll(); pushUUIDs.removeAll(); answerWhenArrives.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let c = ensureCore(), let addr = sipAddress(action.handle.value),
              let cp = try? c.createCallParams(call: nil) else { action.fail(); return }
        cp.videoEnabled = false
        c.configureAudioSession()
        guard let call = c.inviteAddressWithParams(addr: addr, params: cp) else { action.fail(); return }
        calls[action.callUUID] = call
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if let call = calls[action.callUUID] {
            core?.configureAudioSession()
            try? call.accept()
        } else {
            // Answered on the lock screen before the INVITE arrived — accept when it lands.
            answerWhenArrives.insert(action.callUUID)
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if let call = calls[action.callUUID] {
            if call.state == .IncomingReceived || call.state == .IncomingEarlyMedia {
                try? call.decline(reason: .Declined)
            } else {
                try? call.terminate()
            }
        } else {
            // Declined before the INVITE arrived: forget it; the 20 s timer clears the rest.
            pushUUIDs = pushUUIDs.filter { $0.value != action.callUUID }
            answerWhenArrives.remove(action.callUUID)
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        core?.micEnabled = !action.isMuted
        if let call = calls[action.callUUID] { emit(callEvent(call, call.state)) }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        if let call = calls[action.callUUID] {
            if action.isOnHold { try? call.pause() } else { try? call.resume() }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        if let call = calls[action.callUUID] {
            for ch in action.digits.utf8 { try? call.sendDtmf(dtmf: CChar(bitPattern: ch)) }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        core?.activateAudioSession(activated: true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        core?.activateAudioSession(activated: false)
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.novalinkfiber.novalinkvoice"

    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func set(_ key: String, _ data: Data) {
        SecItemDelete(base(key) as CFDictionary)
        var q = base(key)
        q[kSecValueData as String] = data
        // Readable after the first unlock since boot, so a VoIP push can sign in while
        // the phone is locked; never synced off the device.
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func delete(_ key: String) { SecItemDelete(base(key) as CFDictionary) }
}
