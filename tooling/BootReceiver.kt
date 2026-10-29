package ir.apadanasleep.customer_callbook

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Manifest PHONE_STATE receiver is enough; boot just ensures app data is warm.
    }
}
