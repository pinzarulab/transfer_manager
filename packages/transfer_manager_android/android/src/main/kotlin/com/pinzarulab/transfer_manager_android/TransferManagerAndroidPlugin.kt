package com.pinzarulab.transfer_manager_android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Observer
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

class TransferManagerAndroidPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var workManager: WorkManager
    private lateinit var registry: TaskRegistry
    private var eventSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null
    private val observers = mutableMapOf<UUID, Observer<WorkInfo?>>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        workManager = WorkManager.getInstance(context)
        registry = TaskRegistry(context)
        methods = MethodChannel(
            binding.binaryMessenger,
            "pinzarulab.com/transfer_manager/methods",
        )
        events = EventChannel(
            binding.binaryMessenger,
            "pinzarulab.com/transfer_manager/events",
        )
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        removeObservers()
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
        registry.entries().forEach { (taskId, workId) ->
            observe(taskId, workId)
            emitCurrent(taskId, workId)
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        removeObservers()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(
                mapOf(
                    "backgroundDownloads" to true,
                    "backgroundUploads" to false,
                    "pauseResume" to false,
                    "notifications" to true,
                    "notificationCancellation" to true,
                ),
            )
            "notificationsEnabled" -> result.success(
                NotificationManagerCompat.from(context).areNotificationsEnabled(),
            )
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "enqueueDownload" -> enqueueDownload(call, result)
            "task" -> queryTask(call.argument<String>("taskId"), result)
            "cancel" -> cancel(call.argument<String>("taskId"), result)
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false
        val result = permissionResult ?: return false
        permissionResult = null
        result.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        return true
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.error(
                "activity_unavailable",
                "Notification permission requires a foreground Activity",
                null,
            )
            return
        }
        if (permissionResult != null) {
            result.error(
                "permission_request_active",
                "A notification permission request is already active",
                null,
            )
            return
        }
        permissionResult = result
        currentActivity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        permissionResult?.error(
            "activity_detached",
            "Activity detached during notification permission request",
            null,
        )
        permissionResult = null
    }

    private fun enqueueDownload(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")
        val source = call.argument<String>("source")
        val destination = call.argument<String>("destinationPath")
        if (taskId.isNullOrBlank() || source.isNullOrBlank() || destination.isNullOrBlank()) {
            result.error("invalid_request", "taskId, source, and destinationPath are required", null)
            return
        }
        try {
            TransferFileNotifications.validateShareable(context, File(destination))
        } catch (_: IllegalArgumentException) {
            result.error(
                "unshareable_destination",
                "Destination must be in app storage or shared external storage",
                null,
            )
            return
        }
        val headers = call.argument<Map<String, String>>("headers").orEmpty()
        val sensitive = headers.keys.firstOrNull(TransferSecurity::isSensitiveHeader)
        if (sensitive != null) {
            result.error(
                "sensitive_header",
                "$sensitive cannot be persisted in WorkManager input",
                null,
            )
            return
        }
        val networkPolicy = call.argument<String>("networkPolicy") ?: "any"
        val networkType = when (networkPolicy) {
            "unmetered", "wifiOnly" -> NetworkType.UNMETERED
            else -> NetworkType.CONNECTED
        }
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(networkType)
            .build()
        val input = workDataOf(
            DownloadWorker.KEY_TASK_ID to taskId,
            DownloadWorker.KEY_SOURCE to source,
            DownloadWorker.KEY_DESTINATION to destination,
            DownloadWorker.KEY_HEADERS_JSON to JSONObject(headers).toString(),
            DownloadWorker.KEY_NOTIFICATION_TITLE to
                (call.argument<String>("notificationTitle") ?: "Downloading file"),
            DownloadWorker.KEY_MAX_ATTEMPTS to
                (call.argument<Int>("maxAttempts") ?: 5).coerceAtLeast(1),
        )
        val request = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setInputData(input)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .addTag(TAG_ALL)
            .addTag(tagFor(taskId))
            .build()
        workManager.enqueueUniqueWork(
            uniqueName(taskId),
            ExistingWorkPolicy.KEEP,
            request,
        )
        registry.put(taskId, request.id)
        observe(taskId, request.id)
        result.success(request.id.toString())
    }

    private fun queryTask(taskId: String?, result: MethodChannel.Result) {
        if (taskId == null) {
            result.error("invalid_task", "taskId is required", null)
            return
        }
        val workId = registry.get(taskId)
        if (workId == null) {
            result.success(null)
            return
        }
        val future = workManager.getWorkInfoById(workId)
        future.addListener(
            {
                runCatching { future.get() }
                    .onSuccess { result.success(it?.toSnapshot(taskId)) }
                    .onFailure {
                        result.error("query_failed", it.message, null)
                    }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun cancel(taskId: String?, result: MethodChannel.Result) {
        if (taskId == null) {
            result.error("invalid_task", "taskId is required", null)
            return
        }
        workManager.cancelUniqueWork(uniqueName(taskId))
        result.success(null)
    }

    private fun observe(taskId: String, workId: UUID) {
        if (observers.containsKey(workId)) return
        val liveData = workManager.getWorkInfoByIdLiveData(workId)
        val observer = Observer<WorkInfo?> { info ->
            if (info != null) {
                eventSink?.success(info.toSnapshot(taskId))
            }
        }
        observers[workId] = observer
        liveData.observeForever(observer)
    }

    private fun emitCurrent(taskId: String, workId: UUID) {
        val future = workManager.getWorkInfoById(workId)
        future.addListener(
            {
                runCatching { future.get() }
                    .getOrNull()
                    ?.let { eventSink?.success(it.toSnapshot(taskId)) }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun removeObservers() {
        observers.forEach { (workId, observer) ->
            workManager.getWorkInfoByIdLiveData(workId).removeObserver(observer)
        }
        observers.clear()
    }

    private fun WorkInfo.toSnapshot(taskId: String): Map<String, Any?> {
        val progressBytes = progress.getLong(DownloadWorker.KEY_BYTES, 0)
        val progressTotal = progress.getLong(DownloadWorker.KEY_TOTAL, -1)
        val outputBytes = outputData.getLong(DownloadWorker.KEY_BYTES, progressBytes)
        val outputTotal = outputData.getLong(DownloadWorker.KEY_TOTAL, progressTotal)
        return mapOf(
            "taskId" to taskId,
            "state" to state.name.lowercase().replace("enqueued", "enqueued"),
            "bytesTransferred" to outputBytes,
            "totalBytes" to outputTotal.takeIf { it >= 0 },
            "error" to outputData.getString(DownloadWorker.KEY_ERROR),
        )
    }

    companion object {
        private const val TAG_ALL = "transfer_manager"
        private const val NOTIFICATION_PERMISSION_REQUEST = 7319

        private fun tagFor(taskId: String) = "transfer_manager:task:$taskId"
        private fun uniqueName(taskId: String) = "transfer_manager:$taskId"
    }
}
