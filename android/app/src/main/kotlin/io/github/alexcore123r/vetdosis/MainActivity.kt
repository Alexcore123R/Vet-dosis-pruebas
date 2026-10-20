package io.github.alexcore123r.vetdosis

import android.content.Intent
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vetdosis/contact_actions")
            .setMethodCallHandler { call, result ->
                val intent = when (call.method) {
                    "insertContact" -> Intent(Intent.ACTION_INSERT).apply {
                        type = ContactsContract.RawContacts.CONTENT_TYPE
                        putExtra(ContactsContract.Intents.Insert.NAME, call.argument<String>("name"))
                        putExtra(ContactsContract.Intents.Insert.PHONE, call.argument<String>("phone"))
                    }
                    "openContacts" -> Intent(Intent.ACTION_VIEW, ContactsContract.Contacts.CONTENT_URI)
                    else -> null
                }
                if (intent == null) {
                    result.notImplemented()
                } else {
                    try {
                        startActivity(intent)
                        // The contacts app owns confirmation; this does not certify a saved contact.
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("contacts_unavailable", "No se pudo abrir la agenda del teléfono.", null)
                    }
                }
            }
    }
}
