package com.pinzarulab.transfer_manager_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import java.util.UUID

internal class TransferNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
        val paused = when (intent.action) {
            ACTION_PAUSE -> true
            ACTION_RESUME -> false
            else -> return
        }
        TransferPauseStore(context).setPaused(taskId, paused)
        val workerId = intent.getStringExtra(EXTRA_WORKER_ID)
            ?.let { value -> runCatching { UUID.fromString(value) }.getOrNull() }
            ?: return
        val info = TransferProgressNotifications.foregroundInfo(
            context = context,
            workerId = workerId,
            taskId = taskId,
            title = intent.getStringExtra(EXTRA_TITLE) ?: "File transfer",
            bytes = intent.getLongExtra(EXTRA_BYTES, 0),
            total = intent.getLongExtra(EXTRA_TOTAL, -1).takeIf { it >= 0 },
            uploading = intent.getBooleanExtra(EXTRA_UPLOADING, false),
            paused = paused,
        )
        runCatching {
            NotificationManagerCompat.from(context).notify(info.notificationId, info.notification)
        }
    }

    companion object {
        const val ACTION_PAUSE =
            "com.pinzarulab.transfer_manager_android.action.PAUSE"
        const val ACTION_RESUME =
            "com.pinzarulab.transfer_manager_android.action.RESUME"
        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_WORKER_ID = "workerId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BYTES = "bytes"
        const val EXTRA_TOTAL = "total"
        const val EXTRA_UPLOADING = "uploading"
    }
}
