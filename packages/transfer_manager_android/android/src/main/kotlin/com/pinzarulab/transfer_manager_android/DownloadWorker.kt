package com.pinzarulab.transfer_manager_android

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption

internal class DownloadWorker(
    context: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val taskId = inputData.getString(KEY_TASK_ID)
            ?: return failure("Missing task identifier")
        val source = inputData.getString(KEY_SOURCE)
            ?: return failure("Missing source URL")
        val destinationPath = inputData.getString(KEY_DESTINATION)
            ?: return failure("Missing destination path")
        val title = inputData.getString(KEY_NOTIFICATION_TITLE) ?: "Downloading file"
        val showNotification = inputData.getBoolean(KEY_SHOW_NOTIFICATION, true)
        val notificationOpenType = inputData.getString(KEY_NOTIFICATION_OPEN_TYPE) ?: "open"
        val maxAttempts = inputData.getInt(KEY_MAX_ATTEMPTS, 5).coerceAtLeast(1)
        val publicFileName = publicDownloadFileName(destinationPath)
        if (publicFileName != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return failure("Public Downloads requires Android 10 or newer")
        }
        val destination: File? = if (publicFileName == null) {
            File(destinationPath)
        } else {
            null
        }
        val partial = if (publicFileName == null) {
            File("$destinationPath.part")
        } else {
            val stagingRoot = applicationContext.externalCacheDir
                ?: applicationContext.cacheDir
            File(stagingRoot, "transfer_manager/downloads/$taskId.part")
        }
        destination?.parentFile?.mkdirs()
        partial.parentFile?.mkdirs()

        setForeground(
            TransferProgressNotifications.foregroundInfo(
                applicationContext,
                id,
                taskId,
                title,
                0,
                null,
                false,
            ),
        )

        return try {
            waitWhilePaused(taskId, title, partial.length(), null, false)
            download(
                source,
                destination,
                publicFileName,
                partial,
                taskId,
                title,
                showNotification,
                notificationOpenType,
            )
        } catch (error: IOException) {
            if (runAttemptCount + 1 < maxAttempts) {
                Result.retry()
            } else {
                failure(error.javaClass.simpleName)
            }
        } catch (error: SecurityException) {
            failure(error.javaClass.simpleName)
        } catch (error: IllegalArgumentException) {
            failure(error.javaClass.simpleName)
        }
    }

    private suspend fun download(
        source: String,
        destination: File?,
        publicFileName: String?,
        partial: File,
        taskId: String,
        title: String,
        showNotification: Boolean,
        notificationOpenType: String,
    ): Result {
        var offset = partial.takeIf(File::exists)?.length() ?: 0
        val metadata = DownloadMetadataStore(applicationContext)
        val connection = (URL(source).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 30_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            if (offset > 0) {
                setRequestProperty("Range", "bytes=$offset-")
                metadata.validator(taskId)?.let {
                    setRequestProperty("If-Range", it)
                }
            }
            val headersJson = inputData.getString(KEY_HEADERS_JSON) ?: "{}"
            val headers = JSONObject(headersJson)
            headers.keys().forEach { name ->
                if (!TransferSecurity.isSensitiveHeader(name)) {
                    setRequestProperty(name, headers.getString(name))
                }
            }
        }
        try {
            val status = connection.responseCode
            if (isRetryableStatus(status)) {
                return retryOrFailure("HTTP $status")
            }
            if (status !in 200..299) {
                return failure("HTTP $status")
            }
            val resumed = status == HttpURLConnection.HTTP_PARTIAL
            if (offset > 0 && !resumed) {
                offset = 0
            }
            metadata.putValidator(
                taskId,
                connection.getHeaderField("ETag")
                    ?: connection.getHeaderField("Last-Modified"),
            )
            val responseLength = connection.contentLengthLong
            val total = responseLength.takeIf { it >= 0 }?.plus(offset)
            var transferred = offset
            total?.let {
                TransferStorageGuard.requireDownloadCapacity(
                    destination ?: partial,
                    it - transferred,
                )
            }
            var lastNotificationAt = 0L

            FileOutputStream(partial, resumed).buffered().use { sink ->
                connection.inputStream.buffered().use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        waitWhilePaused(taskId, title, transferred, total, false)
                        currentCoroutineContext().ensureActive()
                        if (isStopped) throw IOException("Worker stopped")
                        val count = input.read(buffer)
                        if (count < 0) break
                        sink.write(buffer, 0, count)
                        transferred += count
                        setProgress(progressData(transferred, total))
                        val now = System.currentTimeMillis()
                        if (now - lastNotificationAt >= NOTIFICATION_INTERVAL_MS) {
                            setForeground(
                                TransferProgressNotifications.foregroundInfo(
                                    applicationContext,
                                    id,
                                    taskId,
                                    title,
                                    transferred,
                                    total,
                                    false,
                                ),
                            )
                            lastNotificationAt = now
                        }
                    }
                    sink.flush()
                }
            }
            if (total != null && transferred != total) {
                throw IOException("Incomplete response")
            }
            val publicUri = if (publicFileName == null) {
                completeAtomically(partial, checkNotNull(destination))
                null
            } else {
                publishToDownloads(partial, publicFileName)
            }
            metadata.clear(taskId)
            if (showNotification) {
                if (publicUri == null) {
                    TransferFileNotifications.showCompleted(
                        applicationContext,
                        taskId,
                        title,
                        checkNotNull(destination),
                        notificationOpenType,
                    )
                } else {
                    TransferFileNotifications.showCompleted(
                        applicationContext,
                        taskId,
                        title,
                        publicUri,
                        checkNotNull(publicFileName),
                        notificationOpenType = notificationOpenType,
                    )
                }
            }
            val output = progressData(transferred, total)
            return Result.success(output)
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun waitWhilePaused(
        taskId: String,
        title: String,
        bytes: Long,
        total: Long?,
        uploading: Boolean,
    ) {
        val pauses = TransferPauseStore(applicationContext)
        var announced = false
        while (pauses.isPaused(taskId)) {
            currentCoroutineContext().ensureActive()
            if (isStopped) throw IOException("Worker stopped")
            if (!announced) {
                setProgress(
                    workDataOf(
                        KEY_BYTES to bytes,
                        KEY_TOTAL to (total ?: -1),
                        KEY_PAUSED to true,
                    ),
                )
                setForeground(
                    TransferProgressNotifications.foregroundInfo(
                        applicationContext,
                        id,
                        taskId,
                        title,
                        bytes,
                        total,
                        uploading,
                        paused = true,
                    ),
                )
                announced = true
            }
            delay(PAUSE_POLL_INTERVAL_MS)
        }
        if (announced) {
            setProgress(
                workDataOf(
                    KEY_BYTES to bytes,
                    KEY_TOTAL to (total ?: -1),
                    KEY_PAUSED to false,
                ),
            )
        }
    }

    private fun retryOrFailure(message: String): Result {
        val maxAttempts = inputData.getInt(KEY_MAX_ATTEMPTS, 5).coerceAtLeast(1)
        return if (runAttemptCount + 1 < maxAttempts) {
            Result.retry()
        } else {
            failure(message)
        }
    }

    private fun failure(message: String): Result =
        Result.failure(workDataOf(KEY_ERROR to message))

    private fun progressData(bytes: Long, total: Long?): Data =
        workDataOf(
            KEY_BYTES to bytes,
            KEY_TOTAL to (total ?: -1),
        )

    private fun completeAtomically(partial: File, destination: File) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Files.move(
                partial.toPath(),
                destination.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } else {
            if (destination.exists() && !destination.delete()) {
                throw IOException("Could not replace destination")
            }
            if (!partial.renameTo(destination)) {
                throw IOException("Could not finalize download")
            }
        }
    }

    private fun publishToDownloads(partial: File, fileName: String): Uri {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IOException("Public Downloads requires Android 10 or newer")
        }
        val resolver = applicationContext.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/"

        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(fileName, relativePath),
            null,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                resolver.delete(
                    Uri.withAppendedPath(collection, cursor.getLong(idColumn).toString()),
                    null,
                    null,
                )
            }
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(
                MediaStore.MediaColumns.MIME_TYPE,
                MimeTypeMap.getSingleton()
                    .getMimeTypeFromExtension(File(fileName).extension.lowercase())
                    ?: "application/octet-stream",
            )
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("Could not create Downloads entry")
        try {
            resolver.openOutputStream(uri, "w")?.use { output ->
                partial.inputStream().buffered().use { input ->
                    input.copyTo(output)
                }
            } ?: throw IOException("Could not open Downloads entry")
            resolver.update(
                uri,
                ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                },
                null,
                null,
            )
            if (!partial.delete()) {
                throw IOException("Could not remove staged download")
            }
            return uri
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    companion object {
        private const val DOWNLOADS_SCHEME = "transfer-manager-downloads"
        const val KEY_TASK_ID = "taskId"
        const val KEY_SOURCE = "source"
        const val KEY_DESTINATION = "destination"
        const val KEY_HEADERS_JSON = "headersJson"
        const val KEY_NOTIFICATION_TITLE = "notificationTitle"
        const val KEY_SHOW_NOTIFICATION = "showNotification"
        const val KEY_NOTIFICATION_OPEN_TYPE = "notificationOpenType"
        const val KEY_MAX_ATTEMPTS = "maxAttempts"
        const val KEY_BYTES = "bytesTransferred"
        const val KEY_TOTAL = "totalBytes"
        const val KEY_ERROR = "error"
        const val KEY_PAUSED = "paused"

        private const val NOTIFICATION_INTERVAL_MS = 500L
        private const val PAUSE_POLL_INTERVAL_MS = 500L

        internal fun isRetryableStatus(status: Int): Boolean =
            status == HttpURLConnection.HTTP_CLIENT_TIMEOUT ||
                status == 429 ||
                status in 500..599

        internal fun isPublicDownloadsDestination(destination: String): Boolean =
            try {
                URI(destination).scheme == DOWNLOADS_SCHEME
            } catch (_: Exception) {
                false
            }

        internal fun publicDownloadsDestination(fileName: String): String =
            "$DOWNLOADS_SCHEME:/${Uri.encode(fileName)}"

        internal fun publicDownloadFileName(destination: String): String? {
            if (!isPublicDownloadsDestination(destination)) return null
            val uri = URI(destination)
            val rawName = uri.rawPath
                ?.substringAfterLast('/')
                ?.takeIf(String::isNotEmpty)
                ?: uri.rawSchemeSpecificPart
                    ?.removePrefix("//")
                    ?.substringAfterLast('/')
                    ?.takeIf(String::isNotEmpty)
                ?: return null
            val decodedName = URI("file:/$rawName").path.substringAfterLast('/')
            return decodedName.takeIf {
                    it.isNotBlank() &&
                        it != "." &&
                        it != ".." &&
                        !it.contains('/') &&
                        !it.contains('\\')
                }
        }
    }
}
