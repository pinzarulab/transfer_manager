package com.pinzarulab.transfer_manager_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

internal object TransferNotificationTapStore {
    private const val PREFERENCES = "transfer_manager_notification_tap"
    private const val KEY_TASK_ID = "taskId"
    private const val KEY_KIND = "kind"
    private const val KEY_VALUE = "value"

    var listener: ((Map<String, Any>, (Boolean) -> Unit) -> Unit)? = null

    fun put(context: Context, taskId: String, kind: String, value: String) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TASK_ID, taskId)
            .putString(KEY_KIND, kind)
            .putString(KEY_VALUE, value)
            .commit()
        listener?.invoke(payload(taskId, kind, value)) { delivered ->
            if (delivered) clear(context, taskId)
        }
    }

    fun take(context: Context): Map<String, Any>? {
        val preferences = context.getSharedPreferences(
            PREFERENCES,
            Context.MODE_PRIVATE,
        )
        val taskId = preferences.getString(KEY_TASK_ID, null) ?: return null
        val kind = preferences.getString(KEY_KIND, null) ?: return null
        val value = preferences.getString(KEY_VALUE, null) ?: return null
        preferences.edit().clear().apply()
        return payload(taskId, kind, value)
    }

    private fun clear(context: Context, taskId: String) {
        val preferences = context.getSharedPreferences(
            PREFERENCES,
            Context.MODE_PRIVATE,
        )
        if (preferences.getString(KEY_TASK_ID, null) == taskId) {
            preferences.edit().clear().apply()
        }
    }

    private fun payload(taskId: String, kind: String, value: String) = mapOf(
        "taskId" to taskId,
        "destination" to mapOf("kind" to kind, "value" to value),
    )
}

class TransferNotificationTapReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
        val kind = intent.getStringExtra(EXTRA_DESTINATION_KIND) ?: return
        val value = intent.getStringExtra(EXTRA_DESTINATION_VALUE) ?: return
        TransferNotificationTapStore.put(context, taskId, kind, value)
        context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            ?.let(context::startActivity)
    }

    companion object {
        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_DESTINATION_KIND = "destinationKind"
        const val EXTRA_DESTINATION_VALUE = "destinationValue"
    }
}
