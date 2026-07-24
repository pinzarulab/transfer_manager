package com.pinzarulab.transfer_manager_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import java.io.File

internal object TransferFileNotifications {
    private const val COMPLETION_CHANNEL = "transfer_manager_complete"

    fun validateShareable(context: Context, file: File) {
        contentUri(context, file)
    }

    fun showCompleted(
        context: Context,
        taskId: String,
        title: String,
        file: File,
    ) {
        val notifications = NotificationManagerCompat.from(context)
        if (!notifications.areNotificationsEnabled()) return
        createCompletionChannel(context)
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri(context, file), mimeType(file))
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val openFile = PendingIntent.getActivity(
            context,
            completionNotificationId(taskId),
            viewIntent,
            flags,
        )
        val notification = NotificationCompat.Builder(context, COMPLETION_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("$title complete")
            .setContentText(file.name)
            .setContentIntent(openFile)
            .setAutoCancel(true)
            .setOngoing(false)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .build()
        notifications.notify(completionNotificationId(taskId), notification)
    }

    private fun contentUri(context: Context, file: File) =
        FileProvider.getUriForFile(
            context,
            "${context.packageName}.transfer_manager.fileprovider",
            file,
        )

    private fun mimeType(file: File): String {
        val extension = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }

    private fun createCompletionChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(
            Context.NOTIFICATION_SERVICE,
        ) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                COMPLETION_CHANNEL,
                "Completed transfers",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Completed download notifications"
            },
        )
    }

    private fun completionNotificationId(taskId: String): Int =
        taskId.hashCode().xor(0x5f3759df).and(Int.MAX_VALUE).coerceAtLeast(1)
}

