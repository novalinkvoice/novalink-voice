package com.novalinkfiber.novalink_voice

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Thin Flutter host. The Linphone Core lives in [Phone] (process-scoped, owned by
 * the Application) so it survives the Activity being gone. This Activity just wires
 * the method/event channels to it and renders the call screen — including over the
 * lock screen when launched by an incoming-call full-screen intent.
 */
class MainActivity : FlutterActivity() {
    private val methodCh = "novalink/linphone"
    private val eventCh = "novalink/linphone/events"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun onResume() {
        super.onResume()
        Phone.refreshRegistration()   // re-register promptly when the user opens the app
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Phone.ensureCore(applicationContext)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventCh)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    Phone.onEvent = { m -> runOnUiThread { sink?.success(m) } }
                    Phone.pushCurrentState()   // catch an already-ringing/woken call
                }
                override fun onCancel(args: Any?) { Phone.onEvent = null }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodCh)
            .setMethodCallHandler { call, result ->
                fun s(k: String) = call.argument<String>(k)
                try {
                    when (call.method) {
                        "login" -> {
                            Phone.login(applicationContext, s("domain")!!, s("username")!!,
                                s("password")!!, s("proxy")!!, s("displayName"))
                            result.success(true)
                        }
                        "logout" -> { Phone.logout(applicationContext); result.success(true) }
                        "status" -> result.success(Phone.savedIdentity(applicationContext))
                        "call" -> result.success(Phone.placeCall(s("target")!!))
                        "answer" -> { Phone.answer(); result.success(true) }
                        "decline" -> { Phone.decline(); result.success(true) }
                        "hangup" -> { Phone.hangup(); result.success(true) }
                        "mute" -> { Phone.setMuted(call.argument<Boolean>("on") == true); result.success(true) }
                        "speaker" -> { Phone.setSpeaker(call.argument<Boolean>("on") == true); result.success(true) }
                        "hold" -> { Phone.setHold(call.argument<Boolean>("on") == true); result.success(true) }
                        "dtmf" -> { Phone.sendDtmf(s("digit") ?: ""); result.success(true) }
                        "transfer" -> { Phone.transfer(s("target")!!); result.success(true) }
                        "callLogs" -> result.success(Phone.callLogs())
                        "clearCallLogs" -> { Phone.clearCallLogs(); result.success(true) }
                        "refresh" -> { Phone.refreshRegistration(); result.success(true) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("phone", e.message, null)
                }
            }
    }
}
