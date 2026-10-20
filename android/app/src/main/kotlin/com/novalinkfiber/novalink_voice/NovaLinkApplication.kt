package com.novalinkfiber.novalink_voice

import android.app.Application

/**
 * Custom Application so the Linphone Core comes up on EVERY process start — including
 * when FCM starts the process in the background to deliver a push. That lets the
 * woken Core re-register (Flexisip holds the INVITE via fork-late) and ring.
 */
class NovaLinkApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Phone.autoLoginIfSaved(this)
    }
}
