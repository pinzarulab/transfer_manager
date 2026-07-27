package com.pinzarulab.transfer_manager_android

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

internal class TusUploadWorker(
    context: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(context, parameters) {
    private val sessions = TusUploadMetadataStore(context)

    override suspend fun doWork(): Result {
        val taskId = inputData.getString(KEY_TASK_ID)
            ?: return failure("Missing task identifier")
        val sourcePath = inputData.getString(KEY_SOURCE_PATH)
            ?: return failure("Missing source path")
        val endpoint = inputData.getString(KEY_ENDPOINT)
            ?: return failure("Missing TUS endpoint")
        val source = File(sourcePath)
        if (!source.isFile) return failure("Upload source is missing")
        val title = inputData.getString(KEY_NOTIFICATION_TITLE) ?: "Uploading file"
        val sourceLength = source.length()

        setForeground(
            TransferProgressNotifications.foregroundInfo(
                applicationContext,
                id,
                taskId,
                title,
                sessions.get(taskId)?.offset ?: 0,
                sourceLength,
                true,
            ),
        )

        return try {
            upload(taskId, source, endpoint, title)
        } catch (error: RetryableTusException) {
            retryOrFailure(error.message ?: error.javaClass.simpleName)
        } catch (error: IOException) {
            retryOrFailure(error.javaClass.simpleName)
        } catch (error: SecurityException) {
            failure(error.javaClass.simpleName)
        } catch (error: IllegalArgumentException) {
            failure(error.message ?: error.javaClass.simpleName)
        }
    }

    private suspend fun upload(
        taskId: String,
        source: File,
        endpoint: String,
        title: String,
    ): Result {
        val sourceLength = source.length()
        val sourceModified = source.lastModified()
        var session = sessions.get(taskId)
        if (
            session != null &&
            (session.sourceLength != sourceLength || session.sourceModified != sourceModified)
        ) {
            throw IllegalArgumentException(
                "Upload source changed after the TUS session was created",
            )
        }
        val firstSession = session
            ?: create(taskId, source, sourceLength, sourceModified, endpoint)
        val firstOffset = reconcileOffset(firstSession)
        val activeSession: TusUploadSession
        var offset: Long
        if (firstOffset == null) {
            sessions.clear(taskId)
            activeSession = create(taskId, source, sourceLength, sourceModified, endpoint)
            offset = reconcileOffset(activeSession)
                ?: throw IOException("New TUS upload was not found")
        } else {
            activeSession = firstSession
            offset = firstOffset
        }
        if (offset > sourceLength) {
            throw IllegalArgumentException("Server offset exceeds source length")
        }
        sessions.put(taskId, activeSession.copy(offset = offset))
        publishProgress(taskId, title, offset, sourceLength, true)

        val chunkSize = inputData.getInt(KEY_CHUNK_SIZE, DEFAULT_CHUNK_SIZE)
            .coerceAtLeast(1)
        RandomAccessFile(source, "r").use { file ->
            file.seek(offset)
            while (offset < sourceLength) {
                currentCoroutineContext().ensureActive()
                if (isStopped) throw IOException("Worker stopped")
                val count = minOf(chunkSize.toLong(), sourceLength - offset).toInt()
                offset = patchChunk(
                    taskId = taskId,
                    title = title,
                    uploadUrl = activeSession.uploadUrl,
                    file = file,
                    offset = offset,
                    count = count,
                    total = sourceLength,
                )
                sessions.put(taskId, activeSession.copy(offset = offset))
            }
        }

        sessions.clear(taskId)
        TransferFileNotifications.showUploadCompleted(
            applicationContext,
            taskId,
            title,
            source,
        )
        return Result.success(progressData(sourceLength, sourceLength))
    }

    private fun create(
        taskId: String,
        source: File,
        sourceLength: Long,
        sourceModified: Long,
        endpoint: String,
    ): TusUploadSession {
        val connection = open(endpoint).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Tus-Resumable", TusProtocol.VERSION)
            setRequestProperty("Upload-Length", sourceLength.toString())
            val metadata = jsonMap(KEY_METADATA_JSON).toMutableMap()
            metadata.putIfAbsent("filename", source.name)
            if (metadata.isNotEmpty()) {
                setRequestProperty("Upload-Metadata", TusProtocol.encodeMetadata(metadata))
            }
            setFixedLengthStreamingMode(0)
        }
        try {
            connection.outputStream.use { }
            val status = connection.responseCode
            drain(connection, status)
            if (TusProtocol.isRetryableStatus(status)) {
                throw RetryableTusException("TUS creation failed with HTTP $status")
            }
            if (status != HttpURLConnection.HTTP_CREATED) {
                throw IllegalArgumentException("TUS creation failed with HTTP $status")
            }
            val location = connection.getHeaderField("Location")
                ?: throw IllegalArgumentException("TUS creation response has no Location")
            val uploadUrl = URI(endpoint).resolve(location).toString()
            return TusUploadSession(uploadUrl, 0, sourceLength, sourceModified).also {
                sessions.put(taskId, it)
            }
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Returns null when the server says the persisted upload resource is gone.
     */
    private fun reconcileOffset(session: TusUploadSession): Long? {
        val connection = open(session.uploadUrl).apply {
            requestMethod = "HEAD"
            setRequestProperty("Tus-Resumable", TusProtocol.VERSION)
        }
        try {
            val status = connection.responseCode
            drain(connection, status)
            if (status == 404 || status == 410) return null
            if (TusProtocol.isRetryableStatus(status)) {
                throw RetryableTusException("TUS offset check failed with HTTP $status")
            }
            if (
                status != HttpURLConnection.HTTP_OK &&
                status != HttpURLConnection.HTTP_NO_CONTENT
            ) {
                throw IllegalArgumentException("TUS offset check failed with HTTP $status")
            }
            return connection.getHeaderField("Upload-Offset")?.toLongOrNull()
                ?: throw IllegalArgumentException("TUS response has no valid Upload-Offset")
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun patchChunk(
        taskId: String,
        title: String,
        uploadUrl: String,
        file: RandomAccessFile,
        offset: Long,
        count: Int,
        total: Long,
    ): Long {
        val connection = open(uploadUrl).apply {
            requestMethod = "PATCH"
            doOutput = true
            setRequestProperty("Tus-Resumable", TusProtocol.VERSION)
            setRequestProperty("Upload-Offset", offset.toString())
            setRequestProperty("Content-Type", "application/offset+octet-stream")
            setFixedLengthStreamingMode(count)
        }
        try {
            var written = 0
            var lastNotificationAt = 0L
            connection.outputStream.buffered().use { output ->
                val buffer = ByteArray(minOf(DEFAULT_BUFFER_SIZE, count))
                while (written < count) {
                    currentCoroutineContext().ensureActive()
                    if (isStopped) throw IOException("Worker stopped")
                    val read = file.read(buffer, 0, minOf(buffer.size, count - written))
                    if (read < 0) throw IOException("Upload source ended unexpectedly")
                    output.write(buffer, 0, read)
                    written += read
                    val current = offset + written
                    setProgress(progressData(current, total))
                    val now = System.currentTimeMillis()
                    if (now - lastNotificationAt >= NOTIFICATION_INTERVAL_MS) {
                        publishProgress(taskId, title, current, total, true)
                        lastNotificationAt = now
                    }
                }
            }
            val status = connection.responseCode
            drain(connection, status)
            if (TusProtocol.isRetryableStatus(status)) {
                throw RetryableTusException("TUS chunk failed with HTTP $status")
            }
            if (status != HttpURLConnection.HTTP_NO_CONTENT) {
                throw IllegalArgumentException("TUS chunk failed with HTTP $status")
            }
            val acknowledged = connection.getHeaderField("Upload-Offset")?.toLongOrNull()
                ?: throw IllegalArgumentException("TUS response has no valid Upload-Offset")
            if (acknowledged != offset + count) {
                throw RetryableTusException(
                    "TUS server acknowledged offset $acknowledged instead of ${offset + count}",
                )
            }
            setProgress(progressData(acknowledged, total))
            return acknowledged
        } finally {
            connection.disconnect()
        }
    }

    private fun open(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            jsonMap(KEY_HEADERS_JSON).forEach { (name, value) ->
                if (!TransferSecurity.isSensitiveHeader(name)) {
                    setRequestProperty(name, value)
                }
            }
        }

    private fun jsonMap(key: String): Map<String, String> {
        val json = JSONObject(inputData.getString(key) ?: "{}")
        return buildMap {
            json.keys().forEach { name -> put(name, json.getString(name)) }
        }
    }

    private suspend fun publishProgress(
        taskId: String,
        title: String,
        bytes: Long,
        total: Long,
        uploading: Boolean,
    ) {
        setProgress(progressData(bytes, total))
        setForeground(
            TransferProgressNotifications.foregroundInfo(
                applicationContext,
                id,
                taskId,
                title,
                bytes,
                total,
                uploading,
            ),
        )
    }

    private fun drain(connection: HttpURLConnection, status: Int) {
        val response = if (status >= 400) connection.errorStream else connection.inputStream
        response?.use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (input.read(buffer) >= 0) {
                // Drain the response so the connection can be reused.
            }
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

    private class RetryableTusException(message: String) : IOException(message)

    companion object {
        const val KEY_TASK_ID = "taskId"
        const val KEY_SOURCE_PATH = "sourcePath"
        const val KEY_ENDPOINT = "endpoint"
        const val KEY_CHUNK_SIZE = "chunkSize"
        const val KEY_METADATA_JSON = "metadataJson"
        const val KEY_HEADERS_JSON = "headersJson"
        const val KEY_NOTIFICATION_TITLE = "notificationTitle"
        const val KEY_MAX_ATTEMPTS = "maxAttempts"
        const val KEY_ERROR = DownloadWorker.KEY_ERROR

        private const val DEFAULT_CHUNK_SIZE = 5 * 1024 * 1024
        private const val NOTIFICATION_INTERVAL_MS = 500L
    }
}
