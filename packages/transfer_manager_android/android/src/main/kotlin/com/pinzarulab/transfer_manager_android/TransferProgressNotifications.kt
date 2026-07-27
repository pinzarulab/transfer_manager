package com.pinzarulab.transfer_manager_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import androidx.work.WorkManager
import java.util.UUID

internal object TransferProgressNotifications {
    private const val PROGRESS_CHANNEL = "transfer_manager"

    fun foregroundInfo(
        context: Context,
        workerId: UUID,
        taskId: String,
        title: String,
        bytes: Long,
        total: Long?,
        uploading: Boolean,
        paused: Boolean = false,
    ): ForegroundInfo {
        createChannel(context)
        val cancelIntent = WorkManager.getInstance(context)
            .createCancelPendingIntent(workerId)
        val progress = when {
            total == null || total <= 0 -> null
            else -> ((bytes * 100) / total).toInt().coerceIn(0, 100)
        }
        val notification = NotificationCompat.Builder(context, PROGRESS_CHANNEL)
            .setSmallIcon(
                if (uploading) {
                    android.R.drawable.stat_sys_upload
                } else {
                    android.R.drawable.stat_sys_download
                },
            )
            .setContentTitle(title)
            .setContentText(
                if (paused) {
                    "Paused"
                } else if (total == null) {
                    "$bytes bytes"
                } else {
                    "$bytes of $total bytes"
                },
            )
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, progress ?: 0, progress == null)
            .addAction(
                if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                if (paused) "Resume" else "Pause",
                controlIntent(context, workerId, taskId, title, bytes, total, uploading, paused),
            )
            .addAction(
                android.R.drawable.ic_delete,
                "Cancel",
                cancelIntent,
            )
            .build()
        val notificationId = taskId.hashCode().and(Int.MAX_VALUE).coerceAtLeast(1)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(notificationId, notification)
        }
    }

    private fun controlIntent(
        context: Context,
        workerId: UUID,
        taskId: String,
        title: String,
        bytes: Long,
        total: Long?,
        uploading: Boolean,
        paused: Boolean,
    ): PendingIntent {
        val action = if (paused) {
            TransferNotificationActionReceiver.ACTION_RESUME
        } else {
            TransferNotificationActionReceiver.ACTION_PAUSE
        }
        val intent = Intent(context, TransferNotificationActionReceiver::class.java)
            .setAction(action)
            .putExtra(TransferNotificationActionReceiver.EXTRA_TASK_ID, taskId)
            .putExtra(TransferNotificationActionReceiver.EXTRA_WORKER_ID, workerId.toString())
            .putExtra(TransferNotificationActionReceiver.EXTRA_TITLE, title)
            .putExtra(TransferNotificationActionReceiver.EXTRA_BYTES, bytes)
            .putExtra(TransferNotificationActionReceiver.EXTRA_TOTAL, total ?: -1)
            .putExtra(TransferNotificationActionReceiver.EXTRA_UPLOADING, uploading)
        return PendingIntent.getBroadcast(
            context,
            taskId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(
            Service.NOTIFICATION_SERVICE,
        ) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                PROGRESS_CHANNEL,
                "File transfers",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Progress for background uploads and downloads"
            },
        )
    }
}
