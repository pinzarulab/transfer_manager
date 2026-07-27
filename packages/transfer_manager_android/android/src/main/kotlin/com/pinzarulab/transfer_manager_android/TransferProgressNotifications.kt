package com.pinzarulab.transfer_manager_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
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
                if (total == null) "$bytes bytes" else "$bytes of $total bytes",
            )
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, progress ?: 0, progress == null)
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
