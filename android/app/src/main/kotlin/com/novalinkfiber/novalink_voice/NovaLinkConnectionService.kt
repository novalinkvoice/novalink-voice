package com.novalinkfiber.novalink_voice

import android.os.Build
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.annotation.RequiresApi

/**
 * Self-managed Telecom ConnectionService. Handing the incoming call to Telecom is
 * what grants the app microphone + audio focus when it was woken from a killed
 * state by a push (a plain background service can't get the mic). Telecom does NOT
 * post UI or ring for self-managed calls — the app does that (see Phone.showIncomingCallUi).
 */
@RequiresApi(Build.VERSION_CODES.O)
class NovaLinkConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val caller = request?.extras?.getString(KEY_CALLER) ?: "NovaLink Voice"
        val conn = NovaLinkConnection().apply {
            setCallerDisplayName(caller, TelecomManager.PRESENTATION_ALLOWED)
            setRinging()
        }
        NovaLinkConnection.current = conn
        return conn
    }

    companion object { const val KEY_CALLER = "caller" }
}

@RequiresApi(Build.VERSION_CODES.O)
class NovaLinkConnection : Connection() {
    init {
        connectionProperties = PROPERTY_SELF_MANAGED
        audioModeIsVoip = true
    }

    /** Telecom tells us we may show our incoming-call UI now. */
    override fun onShowIncomingCallUi() { Phone.showIncomingCallUi() }

    override fun onAnswer() { Phone.answer() }            // setActive() follows on StreamsRunning
    override fun onReject() { Phone.decline(); finish(DisconnectCause.REJECTED) }
    override fun onDisconnect() { Phone.hangup(); finish(DisconnectCause.LOCAL) }
    override fun onAbort() { Phone.hangup(); finish(DisconnectCause.CANCELED) }

    fun finish(cause: Int) {
        setDisconnected(DisconnectCause(cause))
        destroy()
        if (current === this) current = null
    }

    companion object {
        @Volatile var current: NovaLinkConnection? = null
    }
}
