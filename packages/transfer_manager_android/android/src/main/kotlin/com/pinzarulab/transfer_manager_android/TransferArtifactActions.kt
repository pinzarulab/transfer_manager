package com.pinzarulab.transfer_manager_android

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileNotFoundException

internal object TransferArtifactActions {
    fun open(context: Context, kind: String, value: String) {
        when (kind) {
            "downloads" -> {
                val uri = findDownload(context, value)
                    ?: throw FileNotFoundException(value)
                TransferFileNotifications.open(context, uri, value)
            }
            "file" -> {
                val file = File(value)
                if (!file.isFile) throw FileNotFoundException(value)
                TransferFileNotifications.open(context, file)
            }
            else -> throw IllegalArgumentException("Unknown destination kind")
        }
    }

    fun reveal(context: Context, kind: String, value: String) {
        if (kind == "downloads") {
            context.startActivity(
                Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            return
        }
        open(context, kind, value)
    }

    private fun findDownload(context: Context, fileName: String): Uri? {
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/"
        return context.contentResolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(fileName, relativePath),
            "${MediaStore.MediaColumns.DATE_ADDED} DESC",
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val id = cursor.getLong(
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID),
            )
            Uri.withAppendedPath(collection, id.toString())
        }
    }
}
