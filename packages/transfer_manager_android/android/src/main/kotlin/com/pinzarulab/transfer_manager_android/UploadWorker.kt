package com.pinzarulab.transfer_manager_android

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

internal class UploadWorker(
    context: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val taskId = inputData.getString(KEY_TASK_ID)
            ?: return failure("Missing task identifier")
        val sourcePath = inputData.getString(KEY_SOURCE_PATH)
            ?: return failure("Missing source path")
        val destination = inputData.getString(KEY_DESTINATION)
            ?: return failure("Missing destination URL")
        val source = File(sourcePath)
        if (!source.isFile) return failure("Upload source is missing")
        val title = inputData.getString(KEY_NOTIFICATION_TITLE) ?: "Uploading file"
        val maxAttempts = inputData.getInt(KEY_MAX_ATTEMPTS, 5).coerceAtLeast(1)

        setForeground(
            TransferProgressNotifications.foregroundInfo(
                applicationContext,
                id,
                taskId,
                title,
                0,
                source.length(),
                true,
            ),
        )

        return try {
            waitWhilePaused(taskId, title, 0, source.length())
            upload(taskId, source, destination, title)
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

    private suspend fun upload(
        taskId: String,
        source: File,
        destination: String,
        title: String,
    ): Result {
        val boundary = "transfer-manager-${UUID.randomUUID()}"
        val fieldName = inputData.getString(KEY_FIELD_NAME) ?: "file"
        val fileName = source.name.replace("\"", "_").replace("\r", "_").replace("\n", "_")
        val prefix = (
            "--$boundary\r\n" +
                "Content-Disposition: form-data; name=\"$fieldName\"; " +
                "filename=\"$fileName\"\r\n" +
                "Content-Type: application/octet-stream\r\n\r\n"
            ).encodeToByteArray()
        val suffix = "\r\n--$boundary--\r\n".encodeToByteArray()
        val sourceLength = source.length()
        val bodyLength = prefix.size.toLong() + sourceLength + suffix.size
        val connection = (URL(destination).openConnection() as HttpURLConnection).apply {
            requestMethod = inputData.getString(KEY_METHOD) ?: "POST"
            connectTimeout = 30_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            doOutput = true
            val headersJson = inputData.getString(KEY_HEADERS_JSON) ?: "{}"
            val headers = JSONObject(headersJson)
            headers.keys().forEach { name ->
                if (!TransferSecurity.isSensitiveHeader(name)) {
                    setRequestProperty(name, headers.getString(name))
                }
            }
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            setFixedLengthStreamingMode(bodyLength)
        }
        try {
            var transferred = 0L
            var lastNotificationAt = 0L
            connection.outputStream.buffered().use { output ->
                output.write(prefix)
                source.inputStream().buffered().use { input ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        waitWhilePaused(taskId, title, transferred, sourceLength)
                        currentCoroutineContext().ensureActive()
                        if (isStopped) throw IOException("Worker stopped")
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        transferred += count
                        setProgress(progressData(transferred, sourceLength))
                        val now = System.currentTimeMillis()
                        if (now - lastNotificationAt >= NOTIFICATION_INTERVAL_MS) {
                            setForeground(
                                TransferProgressNotifications.foregroundInfo(
                                    applicationContext,
                                    id,
                                    taskId,
                                    title,
                                    transferred,
                                    sourceLength,
                                    true,
                                ),
                            )
                            lastNotificationAt = now
                        }
                    }
                }
                output.write(suffix)
                output.flush()
            }

            val status = connection.responseCode
            val response = if (status >= 400) connection.errorStream else connection.inputStream
            response?.use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (input.read(buffer) >= 0) {
                    // Drain the response so the connection can be reused.
                }
            }
            if (DownloadWorker.isRetryableStatus(status)) {
                return retryOrFailure("HTTP $status")
            }
            if (status !in 200..299) {
                return failure("HTTP $status")
            }
            TransferFileNotifications.showUploadCompleted(
                applicationContext,
                taskId,
                title,
                source,
            )
            return Result.success(progressData(sourceLength, sourceLength))
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun waitWhilePaused(
        taskId: String,
        title: String,
        bytes: Long,
        total: Long,
    ) {
        val pauses = TransferPauseStore(applicationContext)
        var announced = false
        while (pauses.isPaused(taskId)) {
            currentCoroutineContext().ensureActive()
            if (isStopped) throw IOException("Worker stopped")
            if (!announced) {
                setProgress(
                    workDataOf(
                        DownloadWorker.KEY_BYTES to bytes,
                        DownloadWorker.KEY_TOTAL to total,
                        DownloadWorker.KEY_PAUSED to true,
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
                        true,
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
                    DownloadWorker.KEY_BYTES to bytes,
                    DownloadWorker.KEY_TOTAL to total,
                    DownloadWorker.KEY_PAUSED to false,
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

    private fun progressData(bytes: Long, total: Long): Data =
        workDataOf(
            DownloadWorker.KEY_BYTES to bytes,
            DownloadWorker.KEY_TOTAL to total,
        )

    companion object {
        const val KEY_TASK_ID = "taskId"
        const val KEY_SOURCE_PATH = "sourcePath"
        const val KEY_DESTINATION = "destination"
        const val KEY_METHOD = "method"
        const val KEY_FIELD_NAME = "fieldName"
        const val KEY_HEADERS_JSON = "headersJson"
        const val KEY_NOTIFICATION_TITLE = "notificationTitle"
        const val KEY_MAX_ATTEMPTS = "maxAttempts"
        const val KEY_ERROR = DownloadWorker.KEY_ERROR

        private const val NOTIFICATION_INTERVAL_MS = 500L
        private const val PAUSE_POLL_INTERVAL_MS = 500L
    }
}
