package com.novalinkfiber.novalink_voice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.linphone.core.Account
import org.linphone.core.AudioDevice
import org.linphone.core.AVPFMode
import org.linphone.core.Call
import org.linphone.core.Core
import org.linphone.core.CoreListenerStub
import org.linphone.core.Factory
import org.linphone.core.MediaEncryption
import org.linphone.core.Reason
import org.linphone.core.RegistrationState
import org.linphone.core.TransportType

/**
 * Process-wide Linphone Core. Lives in the Application (not the Activity) so the
 * Core can come up when FCM wakes a killed app in the background. Holds the call
 * engine, drives the incoming-call notification, and bridges state to Flutter
 * (when the UI is attached) via [onEvent].
 *
 * Signalling: the app registers to the Flexisip push gateway on voice-01
 * (TLS 5062). Flexisip passes REGISTER/INVITE to FusionPBX, which authenticates
 * with the extension's own SIP password, and wakes us with an FCM push when a
 * call arrives while we're asleep. Media goes straight to FreeSWITCH (no relay).
 */
object Phone {
    private const val SECURE_PREFS = "novalink_secure"
    private const val LEGACY_PREFS = "novalink"            // phase-1 plaintext prefs, wiped on upgrade
    private const val CH_INCOMING = "nl_incoming_call_v2"   // channel carries a ringtone sound
    private const val NOTIF_INCOMING = 42
    private const val TELECOM_ACCOUNT_ID = "novalink_voice"

    @Volatile var core: Core? = null; private set
    @Volatile var currentCall: Call? = null
    /** Set by MainActivity while its Flutter engine is alive; null when detached. */
    @Volatile var onEvent: ((Map<String, Any?>) -> Unit)? = null

    private lateinit var appCtx: Context
    private var lastRegState: String = "None"
    private var lastRegMessage: String = ""
    private var incomingCaller: String = ""
    private var incomingName: String = ""
    private var phoneAccountHandle: PhoneAccountHandle? = null

    private val listener = object : CoreListenerStub() {
        override fun onAccountRegistrationStateChanged(
            core: Core, account: Account, state: RegistrationState?, message: String
        ) {
            lastRegState = state?.name ?: "None"
            lastRegMessage = message
            emit(mapOf("type" to "registration", "state" to lastRegState, "message" to message))
        }

        override fun onCallStateChanged(
            core: Core, call: Call, state: Call.State?, message: String
        ) {
            val ended = state == Call.State.End || state == Call.State.Released ||
                state == Call.State.Error
            currentCall = if (ended) core.currentCall ?: core.calls.firstOrNull { it != call } else call
            when (state) {
                Call.State.IncomingReceived -> {
                    incomingCaller = userPart(call.remoteAddress.asStringUriOnly())
                    incomingName = call.remoteAddress.displayName ?: ""
                    // Hand the call to Telecom so the OS grants mic/audio when we answer
                    // even from a push-woken background state. Telecom calls back into
                    // onShowIncomingCallUi() -> we post the ringing notification.
                    if (!startTelecomIncoming()) showIncomingCallUi()   // fallback if Telecom unavailable
                }
                Call.State.OutgoingInit -> CallService.start(appCtx)
                Call.State.Connected, Call.State.StreamsRunning -> {
                    cancelIncomingNotification()
                    CallService.start(appCtx)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        NovaLinkConnection.current?.setActive()
                }
                Call.State.End, Call.State.Released, Call.State.Error -> {
                    cancelIncomingNotification()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        NovaLinkConnection.current?.finish(android.telecom.DisconnectCause.REMOTE)
                    if (core.callsNb == 0) CallService.stop(appCtx)
                }
                else -> {}
            }
            emit(callEvent(call, state, message))
        }
    }

    private fun userPart(uri: String) = uri.replaceFirst(Regex("^sips?:"), "").substringBefore('@')

    private fun callEvent(call: Call, state: Call.State?, message: String = "") = mapOf(
        "type" to "call",
        "state" to (state?.name ?: ""),
        "message" to message,
        "incoming" to (call.dir == Call.Dir.Incoming),
        "remote" to userPart(call.remoteAddress.asStringUriOnly()),
        "name" to (call.remoteAddress.displayName ?: ""),
        "duration" to call.duration,
        "muted" to !(core?.isMicEnabled ?: true),
        "speaker" to (call.outputAudioDevice?.type == AudioDevice.Type.Speaker),
        "paused" to (state == Call.State.Paused || state == Call.State.Pausing),
    )

    private fun emit(m: Map<String, Any?>) { onEvent?.invoke(m) }

    /** Re-send current state so a freshly-attached UI catches an in-flight call. */
    fun pushCurrentState() {
        emit(mapOf("type" to "registration", "state" to lastRegState, "message" to lastRegMessage))
        currentCall?.let { emit(callEvent(it, it.state)) }
    }

    // ---- credentials (Android Keystore-backed) ----

    private fun prefs(ctx: Context): SharedPreferences {
        val key = MasterKey.Builder(ctx).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        return EncryptedSharedPreferences.create(
            ctx, SECURE_PREFS, key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun ensureCore(context: Context): Core {
        core?.let { return it }
        appCtx = context.applicationContext
        // The May prototype kept a test SIP password in plain prefs; drop it.
        appCtx.deleteSharedPreferences(LEGACY_PREFS)
        Factory.instance().enableLogcatLogs(true)
        val c = Factory.instance().createCore(null, null, appCtx)
        c.setUserAgent("NovaLink Voice Android", BuildConfig.VERSION_NAME)
        // Verify the server: Let's Encrypt roots shipped in assets (the SDK's own
        // CA bundle predates the current LE chain).
        appCtx.assets.open("le-roots.pem").bufferedReader().use { c.setRootCaData(it.readText()) }
        c.verifyServerCertificates(true)
        c.verifyServerCn(true)
        // Audio profile tuned live (echo limiter + balanced gains).
        c.isEchoCancellationEnabled = true
        c.isEchoLimiterEnabled = true
        c.isGenericComfortNoiseEnabled = false
        c.isAgcEnabled = false
        c.isAdaptiveRateControlEnabled = true
        c.micGainDb = -1.0f
        c.playbackGainDb = 1.0f
        // No ICE/STUN/TURN: FreeSWITCH latches to our real RTP source (symmetric
        // RTP / auto-adjust), which handles CG-NAT and 464XLAT mobile networks.
        val nat = c.createNatPolicy()
        nat.isStunEnabled = false
        nat.isTurnEnabled = false
        nat.isIceEnabled = false
        nat.isUpnpEnabled = false
        c.natPolicy = nat
        // Plain RTP/AVP, no AVPF — matches FusionPBX/Flowroute.
        c.setMediaEncryption(MediaEncryption.None)
        c.avpfMode = AVPFMode.Disabled
        // Push: SDK fetches the FCM token and stamps push params into REGISTER.
        c.isPushNotificationEnabled = true
        c.addListener(listener)
        c.start()
        c.isAutoIterateEnabled = true
        core = c
        createIncomingChannel()
        registerPhoneAccount()
        return c
    }

    // ---- Telecom (self-managed) so a push-woken call gets mic/audio ----

    private fun registerPhoneAccount() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val tm = appCtx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val handle = PhoneAccountHandle(
                ComponentName(appCtx, NovaLinkConnectionService::class.java), TELECOM_ACCOUNT_ID
            )
            val account = PhoneAccount.builder(handle, "NovaLink Voice")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
            tm.registerPhoneAccount(account)
            phoneAccountHandle = handle
        } catch (e: Exception) {
            phoneAccountHandle = null   // fall back to plain notification path
        }
    }

    /** @return true if Telecom accepted the incoming call (it will call back onShowIncomingCallUi). */
    private fun startTelecomIncoming(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val handle = phoneAccountHandle ?: return false
        return try {
            val tm = appCtx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val callExtras = Bundle().apply {
                putString(NovaLinkConnectionService.KEY_CALLER, incomingName.ifEmpty { incomingCaller })
            }
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, Uri.fromParts("sip", incomingCaller, null))
                putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, callExtras)
            }
            tm.addNewIncomingCall(handle, extras)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ---- account ----

    /**
     * Register [username]@[domain] through [proxy] (the Flexisip push gateway),
     * authenticating to FusionPBX with the extension's SIP password.
     */
    fun login(context: Context, domain: String, username: String, password: String,
              proxy: String, displayName: String?, persist: Boolean = true) {
        val c = ensureCore(context)
        c.clearAccounts(); c.clearAllAuthInfo()
        val auth = Factory.instance().createAuthInfo(username, null, password, null, null, domain, null)
        c.addAuthInfo(auth)
        val params = c.createAccountParams()
        val identity = Factory.instance().createAddress("sip:$username@$domain")
        if (!displayName.isNullOrBlank()) identity?.setDisplayName(displayName)
        params.identityAddress = identity
        val server = Factory.instance().createAddress(proxy)
        server?.transport = TransportType.Tls
        params.serverAddress = server
        params.isRegisterEnabled = true
        params.pushNotificationAllowed = true
        params.remotePushNotificationAllowed = true
        val account = c.createAccount(params)
        c.addAccount(account)
        c.defaultAccount = account
        if (persist) {
            prefs(appCtx).edit()
                .putString("domain", domain).putString("user", username).putString("pass", password)
                .putString("proxy", proxy).putString("name", displayName ?: "")
                .apply()
        }
    }

    fun logout(context: Context) {
        val c = ensureCore(context)
        c.terminateAllCalls()
        // Unregister so FusionPBX stops routing (and Flexisip stops pushing) to this phone.
        c.accountList.forEach { a ->
            val p = a.params.clone(); p.isRegisterEnabled = false; a.params = p
        }
        c.clearAccounts(); c.clearAllAuthInfo()
        c.clearCallLogs()
        prefs(appCtx).edit().clear().apply()
        lastRegState = "None"
        emit(mapOf("type" to "registration", "state" to "None", "message" to ""))
    }

    /** What the UI uses on startup to decide login screen vs app. */
    fun savedIdentity(context: Context): Map<String, Any?> {
        ensureCore(context)
        val p = prefs(appCtx)
        val u = p.getString("user", null)
        val d = p.getString("domain", null)
        return mapOf("loggedIn" to (u != null && d != null), "user" to u, "domain" to d,
            "name" to p.getString("name", ""), "registration" to lastRegState)
    }

    /** Called from Application.onCreate so any process start brings up + registers the Core. */
    fun autoLoginIfSaved(context: Context) {
        ensureCore(context)
        val p = prefs(appCtx)
        val d = p.getString("domain", null) ?: return
        val u = p.getString("user", null) ?: return
        val pw = p.getString("pass", null) ?: return
        val proxy = p.getString("proxy", null) ?: return
        login(context, d, u, pw, proxy, p.getString("name", null), persist = false)
    }

    fun refreshRegistration() { core?.refreshRegisters() }

    // ---- calls ----

    // ---- emergency calls ----
    // 911 from a cell phone must NOT go out as VoIP: the 911 centre would get the
    // registered business address, not where the phone is. Hand it to the phone's own
    // dialer so it goes over the cellular network, which delivers the real location
    // (carrier E911 + Android Emergency Location Service). 9911 = "dial 9 first" habit.
    private val EMERGENCY = setOf("911", "112", "9911")

    fun isEmergency(target: String): Boolean =
        !target.trim().startsWith("sip:") && target.filter { it.isDigit() } in EMERGENCY

    /** Opens the system dialer pre-filled with 911. False if the device has no cellular
     *  radio (Wi-Fi tablet) — the caller then falls back to the VoIP 911 path. */
    fun openEmergencyDialer(): Boolean {
        if (!appCtx.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) return false
        return try {
            appCtx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:911"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) { false }
    }

    /** @return "emergency_native" if handed to the phone's dialer, else "voip". */
    fun placeCall(target: String): String {
        if (isEmergency(target) && openEmergencyDialer()) return "emergency_native"
        placeVoipCall(target)
        return "voip"
    }

    private fun placeVoipCall(target: String) {
        val c = ensureCore(appCtx)
        val domain = prefs(appCtx).getString("domain", null) ?: return
        val clean = target.trim()
        val uri = if (clean.startsWith("sip:")) clean else "sip:${clean.filter { it.isDigit() || it in "*#+" }}@$domain"
        val addr = c.interpretUrl(uri, false) ?: return
        val cp = c.createCallParams(null) ?: return
        cp.isVideoEnabled = false
        currentCall = c.inviteAddressWithParams(addr, cp)
    }

    fun answer() {
        // Activate the Telecom call first so the OS grants mic/audio before
        // mediastreamer opens the microphone.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) NovaLinkConnection.current?.setActive()
        currentCall?.accept()
    }

    fun decline() {
        val call = currentCall ?: return
        if (call.state == Call.State.IncomingReceived || call.state == Call.State.IncomingEarlyMedia)
            call.decline(Reason.Declined) else call.terminate()
    }

    fun hangup() { currentCall?.terminate() }   // connection.finish() follows on the End callback

    fun setMuted(muted: Boolean) {
        core?.isMicEnabled = !muted
        currentCall?.let { emit(callEvent(it, it.state)) }
    }

    fun setSpeaker(on: Boolean) {
        val call = currentCall ?: return
        val want = if (on) AudioDevice.Type.Speaker else AudioDevice.Type.Earpiece
        val dev = core?.audioDevices?.firstOrNull { it.type == want }
            ?: if (!on) core?.audioDevices?.firstOrNull { it.type == AudioDevice.Type.Bluetooth || it.type == AudioDevice.Type.Headset || it.type == AudioDevice.Type.Headphones } else null
        if (dev != null) call.outputAudioDevice = dev
        emit(callEvent(call, call.state))
    }

    fun setHold(hold: Boolean) {
        val call = currentCall ?: return
        if (hold) call.pause() else call.resume()
    }

    fun sendDtmf(digit: String) { digit.firstOrNull()?.let { currentCall?.sendDtmf(it) } }

    /** Blind transfer the current call to an extension or number. */
    fun transfer(target: String) {
        val c = core ?: return
        val call = currentCall ?: return
        val domain = prefs(appCtx).getString("domain", null) ?: return
        val addr = c.interpretUrl("sip:${target.filter { it.isDigit() || it in "*#+" }}@$domain", false) ?: return
        call.transferTo(addr)
    }

    fun callLogs(): List<Map<String, Any?>> {
        val c = core ?: return emptyList()
        return c.callLogs.take(200).map { l ->
            mapOf(
                "remote" to userPart(l.remoteAddress.asStringUriOnly()),
                "name" to (l.remoteAddress.displayName ?: ""),
                "incoming" to (l.dir == Call.Dir.Incoming),
                "status" to l.status.name,      // Success | Missed | Declined | Aborted | ...
                "start" to l.startDate,         // epoch seconds
                "duration" to l.duration,
            )
        }
    }

    fun clearCallLogs() { core?.clearCallLogs() }

    // ---- incoming-call notification (rings/wakes a killed or locked phone) ----

    private fun nm() = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createIncomingChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CH_INCOMING, "Incoming calls", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "NovaLink Voice incoming calls"
            ch.enableVibration(true)
            ch.setBypassDnd(true)
            // Ring with the system ringtone — the NotificationManager plays this even
            // when the app was woken from the background (immune to the audio-playback
            // restriction that silenced the SDK's own ringer).
            val ring = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ch.setSound(ring, attrs)
            nm().createNotificationChannel(ch)
        }
    }

    /** Posts the ringing full-screen notification. Public: Telecom calls this via the connection. */
    fun showIncomingCallUi() {
        val caller = incomingName.ifEmpty { incomingCaller }.ifEmpty { "NovaLink Voice" }
        val fullScreen = Intent(appCtx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("incoming_call", true)
        }
        val pi = PendingIntent.getActivity(
            appCtx, 0, fullScreen,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(appCtx, CH_INCOMING) else
            @Suppress("DEPRECATION") Notification.Builder(appCtx)
        val n = builder
            .setContentTitle("Incoming call")
            .setContentText(caller)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setColor(0xFF7200BC.toInt())
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(true)
            .setFullScreenIntent(pi, true)   // pops the call screen over the lock screen
            .setContentIntent(pi)
            .build()
        nm().notify(NOTIF_INCOMING, n)
    }

    private fun cancelIncomingNotification() { nm().cancel(NOTIF_INCOMING) }
}
