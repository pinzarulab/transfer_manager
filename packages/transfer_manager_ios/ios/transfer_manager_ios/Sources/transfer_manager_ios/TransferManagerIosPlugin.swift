import Flutter
import Foundation
import UIKit
import UserNotifications

#if SWIFT_PACKAGE
import TransferManagerLiveActivitySupport
#endif

private struct TransferDescriptor: Codable {
    let taskId: String
    let kind: String
    let destinationPath: String?
    let sourcePath: String?
    let bodyPath: String?
    let notificationTitle: String
    let showNotification: Bool?
    let notificationOpenType: String?
    let showProgress: Bool?
    let allowPause: Bool?
    let allowCancel: Bool?
    let showLiveActivity: Bool?
    let liveActivityStyle: String?
    let maxAttempts: Int
    let attempt: Int
}

private struct TransferSnapshot: Codable {
    let taskId: String
    var state: String
    var bytesTransferred: Int64
    var totalBytes: Int64?
    var error: String?
    var nativeTaskId: Int
    var destinationPath: String? = nil

    var dictionary: [String: Any?] {
        [
            "taskId": taskId,
            "state": state,
            "bytesTransferred": bytesTransferred,
            "totalBytes": totalBytes,
            "error": error,
        ]
    }
}

private final class TransferRegistry {
    private let defaults = UserDefaults.standard
    private let key = "transfer_manager_ios.snapshots"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func all() -> [TransferSnapshot] {
        guard let data = defaults.data(forKey: key),
              let values = try? decoder.decode([TransferSnapshot].self, from: data)
        else {
            return []
        }
        return values
    }

    func get(_ taskId: String) -> TransferSnapshot? {
        all().first { $0.taskId == taskId }
    }

    func put(_ snapshot: TransferSnapshot) {
        var values = all().filter { $0.taskId != snapshot.taskId }
        values.append(snapshot)
        if let data = try? encoder.encode(values) {
            defaults.set(data, forKey: key)
        }
    }
}

public final class TransferManagerIosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
    FlutterSceneLifeCycleDelegate {
    private static let methodChannelName = "pinzarulab.com/transfer_manager_ios/methods"
    private static let eventChannelName = "pinzarulab.com/transfer_manager_ios/events"
    private static let sensitiveHeaders = Set([
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
    ])

    private let registry = TransferRegistry()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var eventSink: FlutterEventSink?
    private var backgroundCompletionHandler: (() -> Void)?
    private weak var previousNotificationDelegate: UNUserNotificationCenterDelegate?
    private var methodChannel: FlutterMethodChannel?
    private var pendingNotificationResponse: [String: Any]?
    private var documentInteractionController: UIDocumentInteractionController?
    private let liveActivities = TransferLiveActivityCoordinator()
    private var liveActivityActionObserver: NSObjectProtocol?
    private var pendingArtifactAction: (taskId: String, reveal: Bool)?

    private lazy var sessionIdentifier: String = {
        let bundle = Bundle.main.bundleIdentifier ?? "com.pinzarulab.transfer_manager"
        return "\(bundle).transfer_manager.background"
    }()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: OperationQueue.main
        )
    }()

    deinit {
        if let liveActivityActionObserver {
            NotificationCenter.default.removeObserver(liveActivityActionObserver)
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TransferManagerIosPlugin()
        let methods = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        let events = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = methods
        registrar.addMethodCallDelegate(instance, channel: methods)
        registrar.addApplicationDelegate(instance)
        registrar.addSceneDelegate(instance)
        events.setStreamHandler(instance)
        let notifications = UNUserNotificationCenter.current()
        if notifications.delegate !== instance {
            instance.previousNotificationDelegate = notifications.delegate
            notifications.delegate = instance
        }
        _ = instance.session
        instance.installLiveActivityActions()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "capabilities":
            result([
                "backgroundDownloads": true,
                "backgroundUploads": true,
                "backgroundTusUploads": false,
                "pauseResume": true,
                "notifications": true,
                "notificationCancellation": false,
                "notificationTaps": true,
                "openArtifacts": true,
                "revealArtifacts": true,
                "liveActivities": liveActivities.isAvailable,
            ])
        case "notificationsEnabled":
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    result(settings.authorizationStatus == .authorized ||
                           settings.authorizationStatus == .provisional)
                }
            }
        case "requestNotificationPermission":
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            ) { granted, _ in
                DispatchQueue.main.async { result(granted) }
            }
        case "takeInitialNotificationResponse":
            let response = pendingNotificationResponse
            pendingNotificationResponse = nil
            result(response)
        case "enqueueDownload":
            enqueueDownload(arguments(call), result: result)
        case "enqueueUpload":
            enqueueUpload(arguments(call), result: result)
        case "task":
            guard let taskId = arguments(call)["taskId"] as? String else {
                result(error("invalid_task", "taskId is required"))
                return
            }
            result(registry.get(taskId)?.dictionary)
        case "pause":
            control(arguments(call), action: .suspend, result: result)
        case "resume":
            control(arguments(call), action: .resume, result: result)
        case "cancel":
            control(arguments(call), action: .cancel, result: result)
        case "open":
            artifactAction(arguments(call), reveal: false, result: result)
        case "reveal":
            artifactAction(arguments(call), reveal: true, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        registry.all().forEach { events($0.dictionary) }
        reconcile()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    public func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        guard identifier == sessionIdentifier else { return false }
        backgroundCompletionHandler = completionHandler
        _ = session
        return true
    }

    public func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        handleArtifactURL(url)
    }

    public func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) -> Bool {
        URLContexts.contains { handleArtifactURL($0.url) }
    }

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions?
    ) -> Bool {
        connectionOptions?.urlContexts.contains {
            handleArtifactURL($0.url)
        } ?? false
    }

    public func sceneDidBecomeActive(_ scene: UIScene) {
        presentPendingArtifactAction()
    }

    private func handleArtifactURL(_ url: URL) -> Bool {
        guard url.scheme == "transfer-manager",
              let action = url.host,
              ["open", "reveal"].contains(action),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let taskId = components.queryItems?.first(where: {
                  $0.name == "taskId"
              })?.value,
              !taskId.isEmpty
        else { return false }
        pendingArtifactAction = (taskId: taskId, reveal: action == "reveal")
        presentPendingArtifactAction()
        return true
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        presentPendingArtifactAction()
    }

    private func enqueueDownload(
        _ arguments: [String: Any],
        result: @escaping FlutterResult
    ) {
        guard let taskId = arguments["taskId"] as? String,
              let sourceValue = arguments["source"] as? String,
              let source = URL(string: sourceValue),
              let destination = destinationURL(arguments)?.path
        else {
            result(error("invalid_request", "taskId, source, and destination are required"))
            return
        }
        guard let headers = safeHeaders(arguments, result: result) else { return }
        var request = URLRequest(url: source)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        applyNetworkPolicy(arguments["networkPolicy"] as? String, to: &request)
        let title = arguments["notificationTitle"] as? String ?? "Download complete"
        let descriptor = TransferDescriptor(
            taskId: taskId,
            kind: "download",
            destinationPath: destination,
            sourcePath: nil,
            bodyPath: nil,
            notificationTitle: title,
            showNotification: arguments["showNotification"] as? Bool ?? true,
            notificationOpenType: arguments["notificationOpenType"] as? String,
            showProgress: arguments["showProgress"] as? Bool,
            allowPause: arguments["allowPause"] as? Bool,
            allowCancel: arguments["allowCancel"] as? Bool,
            showLiveActivity: arguments["showLiveActivity"] as? Bool,
            liveActivityStyle: arguments["liveActivityStyle"] as? String,
            maxAttempts: max(arguments["maxAttempts"] as? Int ?? 5, 1),
            attempt: 0
        )
        let task = session.downloadTask(with: request)
        task.taskDescription = encode(descriptor)
        store(taskId, task: task, state: "enqueued", bytes: 0, total: nil)
        if descriptor.showLiveActivity == true {
            liveActivities.start(
                taskId: taskId,
                title: title,
                fileName: URL(fileURLWithPath: destination).lastPathComponent,
                style: descriptor.liveActivityStyle ?? "system",
                allowPause: descriptor.allowPause ?? false,
                allowCancel: descriptor.allowCancel ?? true
            )
        }
        task.resume()
        result(String(task.taskIdentifier))
    }

    private func destinationURL(_ arguments: [String: Any]) -> URL? {
        guard let destination = arguments["destination"] as? [String: Any],
              let kind = destination["kind"] as? String,
              let value = destination["value"] as? String,
              !value.isEmpty
        else {
            return nil
        }
        if kind == "file" {
            return URL(fileURLWithPath: value)
        }
        guard kind == "downloads",
              URL(fileURLWithPath: value).lastPathComponent == value,
              let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first
        else {
            return nil
        }
        return documents
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(value, isDirectory: false)
    }

    private func artifactAction(
        _ arguments: [String: Any],
        reveal: Bool,
        result: @escaping FlutterResult
    ) {
        guard let url = destinationURL(arguments),
              FileManager.default.fileExists(atPath: url.path)
        else {
            result(error("artifact_missing", "Downloaded file is unavailable"))
            return
        }
        guard presentArtifact(url, reveal: reveal) else {
            result(error("artifact_open_failed", "No application can open this file"))
            return
        }
        result(nil)
    }

    @discardableResult
    private func presentArtifact(_ url: URL, reveal: Bool) -> Bool {
        guard let presenter = topViewController() else { return false }
        let controller = UIDocumentInteractionController(url: url)
        controller.delegate = self
        documentInteractionController = controller
        let presented = reveal
            ? controller.presentOptionsMenu(
                from: presenter.view.bounds,
                in: presenter.view,
                animated: true
              )
            : controller.presentPreview(animated: true)
        if !presented {
            documentInteractionController = nil
        }
        return presented
    }

    private func presentPendingArtifactAction() {
        guard UIApplication.shared.applicationState == .active,
              let pending = pendingArtifactAction,
              let path = registry.get(pending.taskId)?.destinationPath,
              FileManager.default.fileExists(atPath: path)
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.presentArtifact(
                URL(fileURLWithPath: path),
                reveal: pending.reveal
            ) else { return }
            self.pendingArtifactAction = nil
        }
    }

    private func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }

    private func enqueueUpload(
        _ arguments: [String: Any],
        result: @escaping FlutterResult
    ) {
        guard let taskId = arguments["taskId"] as? String,
              let sourcePath = arguments["sourcePath"] as? String,
              let destinationValue = arguments["destination"] as? String,
              let destination = URL(string: destinationValue)
        else {
            result(error("invalid_request", "taskId, sourcePath, and destination are required"))
            return
        }
        let source = URL(fileURLWithPath: sourcePath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            result(error("source_missing", "Upload source does not exist"))
            return
        }
        guard let headers = safeHeaders(arguments, result: result) else { return }
        let method = (arguments["method"] as? String ?? "POST").uppercased()
        guard ["POST", "PUT", "PATCH"].contains(method) else {
            result(error("invalid_method", "Upload method must be POST, PUT, or PATCH"))
            return
        }
        let fieldName = arguments["fieldName"] as? String ?? "file"
        guard fieldName.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            result(error("invalid_field", "Multipart field name is invalid"))
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                let boundary = "transfer-manager-\(UUID().uuidString)"
                let body = try self.makeMultipartBody(
                    taskId: taskId,
                    source: source,
                    fieldName: fieldName,
                    boundary: boundary
                )
                var request = URLRequest(url: destination)
                request.httpMethod = method
                headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                request.setValue(
                    "multipart/form-data; boundary=\(boundary)",
                    forHTTPHeaderField: "Content-Type"
                )
                self.applyNetworkPolicy(
                    arguments["networkPolicy"] as? String,
                    to: &request
                )
                let title = arguments["notificationTitle"] as? String ?? "Upload complete"
                let descriptor = TransferDescriptor(
                    taskId: taskId,
                    kind: "upload",
                    destinationPath: nil,
                    sourcePath: source.path,
                    bodyPath: body.path,
                    notificationTitle: title,
                    showNotification: true,
                    notificationOpenType: nil,
                    showProgress: nil,
                    allowPause: nil,
                    allowCancel: nil,
                    showLiveActivity: false,
                    liveActivityStyle: nil,
                    maxAttempts: max(arguments["maxAttempts"] as? Int ?? 5, 1),
                    attempt: 0
                )
                DispatchQueue.main.async {
                    let task = self.session.uploadTask(with: request, fromFile: body)
                    task.taskDescription = self.encode(descriptor)
                    let total = (try? body.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                        .map(Int64.init)
                    self.store(taskId, task: task, state: "enqueued", bytes: 0, total: total)
                    task.resume()
                    result(String(task.taskIdentifier))
                }
            } catch {
                DispatchQueue.main.async {
                    result(self.error("body_creation_failed", error.localizedDescription))
                }
            }
        }
    }

    private enum ControlAction { case suspend, resume, cancel }

    private func control(
        _ arguments: [String: Any],
        action: ControlAction,
        result: @escaping FlutterResult
    ) {
        guard let taskId = arguments["taskId"] as? String else {
            result(error("invalid_task", "taskId is required"))
            return
        }
        session.getAllTasks { tasks in
            guard let task = tasks.first(where: {
                self.descriptor($0)?.taskId == taskId
            }) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            switch action {
            case .suspend:
                task.suspend()
                self.update(taskId, task: task, state: "paused")
            case .resume:
                task.resume()
                self.update(taskId, task: task, state: "running")
            case .cancel:
                task.cancel()
                self.update(taskId, task: task, state: "cancelled")
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func installLiveActivityActions() {
        liveActivityActionObserver = NotificationCenter.default.addObserver(
            forName: TransferLiveActivityActionStore.notification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.consumeLiveActivityActions()
        }
        consumeLiveActivityActions()
    }

    private func consumeLiveActivityActions() {
        for action in TransferLiveActivityActionStore.takeAll() {
            switch action.action {
            case "togglePause":
                controlFromLiveActivity(taskId: action.taskId, togglePause: true)
            case "cancel":
                controlFromLiveActivity(taskId: action.taskId, togglePause: false)
            default:
                continue
            }
        }
    }

    private func controlFromLiveActivity(taskId: String, togglePause: Bool) {
        session.getAllTasks { tasks in
            guard let task = tasks.first(where: {
                self.descriptor($0)?.taskId == taskId
            }) else { return }
            if togglePause {
                if task.state == .suspended {
                    task.resume()
                    self.update(taskId, task: task, state: "running")
                } else {
                    task.suspend()
                    self.update(taskId, task: task, state: "paused")
                }
            } else {
                task.cancel()
                self.update(taskId, task: task, state: "cancelled")
            }
        }
    }

    private func reconcile() {
        session.getAllTasks { tasks in
            let activeIds = Set(tasks.compactMap { self.descriptor($0)?.taskId })
            for task in tasks {
                guard let value = self.descriptor(task) else { continue }
                self.update(
                    value.taskId,
                    task: task,
                    state: self.stateName(task.state)
                )
            }
            for snapshot in self.registry.all()
            where !activeIds.contains(snapshot.taskId) &&
                  !["succeeded", "failed", "cancelled"].contains(snapshot.state) {
                var failed = snapshot
                failed.state = "failed"
                failed.error = "Background URLSession task was not restored"
                self.saveAndEmit(failed)
            }
        }
    }

    private func makeMultipartBody(
        taskId: String,
        source: URL,
        fieldName: String,
        boundary: String
    ) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("transfer_manager/uploads", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let body = directory.appendingPathComponent("\(taskId).multipart")
        if FileManager.default.fileExists(atPath: body.path) {
            try FileManager.default.removeItem(at: body)
        }
        FileManager.default.createFile(atPath: body.path, contents: nil)
        let output = try FileHandle(forWritingTo: body)
        defer { try? output.close() }
        let safeName = source.lastPathComponent
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
        let prefix = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(safeName)\"\r\n" +
            "Content-Type: application/octet-stream\r\n\r\n"
        output.write(Data(prefix.utf8))
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while true {
            let data = input.readData(ofLength: 64 * 1024)
            if data.isEmpty { break }
            output.write(data)
        }
        output.write(Data("\r\n--\(boundary)--\r\n".utf8))
        try output.synchronize()
        return body
    }

    private func applyNetworkPolicy(_ policy: String?, to request: inout URLRequest) {
        if policy == "unmetered" || policy == "wifiOnly" {
            request.allowsExpensiveNetworkAccess = false
            request.allowsConstrainedNetworkAccess = false
        }
    }

    private func safeHeaders(
        _ arguments: [String: Any],
        result: @escaping FlutterResult
    ) -> [String: String]? {
        let headers = arguments["headers"] as? [String: String] ?? [:]
        if let name = headers.keys.first(where: {
            Self.sensitiveHeaders.contains($0.lowercased())
        }) {
            result(error(
                "sensitive_header",
                "\(name) cannot be persisted in a background URLSession task"
            ))
            return nil
        }
        return headers
    }

    private func descriptor(_ task: URLSessionTask) -> TransferDescriptor? {
        guard let value = task.taskDescription,
              let data = value.data(using: .utf8)
        else {
            return nil
        }
        return try? decoder.decode(TransferDescriptor.self, from: data)
    }

    private func encode(_ value: TransferDescriptor) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func arguments(_ call: FlutterMethodCall) -> [String: Any] {
        call.arguments as? [String: Any] ?? [:]
    }

    private func error(_ code: String, _ message: String) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }

    private func stateName(_ state: URLSessionTask.State) -> String {
        switch state {
        case .running: return "running"
        case .suspended: return "paused"
        case .canceling: return "cancelled"
        case .completed: return "succeeded"
        @unknown default: return "unknown"
        }
    }

    private func store(
        _ taskId: String,
        task: URLSessionTask,
        state: String,
        bytes: Int64,
        total: Int64?
    ) {
        saveAndEmit(TransferSnapshot(
            taskId: taskId,
            state: state,
            bytesTransferred: bytes,
            totalBytes: total,
            error: nil,
            nativeTaskId: task.taskIdentifier,
            destinationPath: descriptor(task)?.destinationPath
        ))
        updateLiveActivity(
            task: task,
            taskId: taskId,
            state: state,
            bytes: bytes,
            total: total
        )
    }

    private func update(
        _ taskId: String,
        task: URLSessionTask,
        state: String,
        error: String? = nil
    ) {
        var snapshot = registry.get(taskId) ?? TransferSnapshot(
            taskId: taskId,
            state: state,
            bytesTransferred: task.countOfBytesReceived > 0
                ? task.countOfBytesReceived
                : task.countOfBytesSent,
            totalBytes: nil,
            error: nil,
            nativeTaskId: task.taskIdentifier,
            destinationPath: descriptor(task)?.destinationPath
        )
        snapshot.state = state
        snapshot.bytesTransferred = task.countOfBytesReceived > 0
            ? task.countOfBytesReceived
            : task.countOfBytesSent
        let expected = task.countOfBytesExpectedToReceive > 0
            ? task.countOfBytesExpectedToReceive
            : task.countOfBytesExpectedToSend
        snapshot.totalBytes = expected > 0 ? expected : snapshot.totalBytes
        snapshot.error = error
        snapshot.destinationPath = snapshot.destinationPath ?? descriptor(task)?.destinationPath
        saveAndEmit(snapshot)
        updateLiveActivity(
            task: task,
            taskId: taskId,
            state: state,
            bytes: snapshot.bytesTransferred,
            total: snapshot.totalBytes
        )
    }

    private func updateLiveActivity(
        task: URLSessionTask,
        taskId: String,
        state: String,
        bytes: Int64,
        total: Int64?
    ) {
        guard descriptor(task)?.showLiveActivity == true else { return }
        liveActivities.update(
            taskId: taskId,
            state: state,
            bytesTransferred: bytes,
            totalBytes: total
        )
    }

    private func saveAndEmit(_ snapshot: TransferSnapshot) {
        registry.put(snapshot)
        DispatchQueue.main.async {
            self.eventSink?(snapshot.dictionary)
        }
    }

    private func notify(_ descriptor: TransferDescriptor) {
        let content = UNMutableNotificationContent()
        content.title = descriptor.notificationTitle
        content.body = descriptor.kind == "download"
            ? "Download completed"
            : "Upload completed"
        content.sound = .default
        if let path = descriptor.destinationPath {
            content.userInfo = ["taskId": descriptor.taskId, "filePath": path]
        } else {
            content.userInfo = ["taskId": descriptor.taskId]
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "transfer-manager-\(descriptor.taskId)",
                content: content,
                trigger: nil
            )
        )
    }

    private func retry(
        _ task: URLSessionTask,
        descriptor value: TransferDescriptor,
        status: Int?,
        error: Error?
    ) -> Bool {
        guard value.attempt + 1 < value.maxAttempts else { return false }
        let retryableStatus = status.map {
            $0 == 408 || $0 == 429 || (500...599).contains($0)
        } ?? false
        let retryableError: Bool
        if let urlError = error as? URLError {
            retryableError = urlError.code != .cancelled &&
                urlError.code != .unsupportedURL &&
                urlError.code != .badURL &&
                urlError.code != .userAuthenticationRequired
        } else {
            retryableError = error != nil
        }
        guard retryableStatus || retryableError else { return false }
        guard let request = task.originalRequest else { return false }
        let next = TransferDescriptor(
            taskId: value.taskId,
            kind: value.kind,
            destinationPath: value.destinationPath,
            sourcePath: value.sourcePath,
            bodyPath: value.bodyPath,
            notificationTitle: value.notificationTitle,
            showNotification: value.showNotification,
            notificationOpenType: value.notificationOpenType,
            showProgress: value.showProgress,
            allowPause: value.allowPause,
            allowCancel: value.allowCancel,
            showLiveActivity: value.showLiveActivity,
            liveActivityStyle: value.liveActivityStyle,
            maxAttempts: value.maxAttempts,
            attempt: value.attempt + 1
        )
        let replacement: URLSessionTask
        if value.kind == "download" {
            replacement = session.downloadTask(with: request)
        } else if let bodyPath = value.bodyPath,
                  FileManager.default.fileExists(atPath: bodyPath) {
            replacement = session.uploadTask(
                with: request,
                fromFile: URL(fileURLWithPath: bodyPath)
            )
        } else {
            return false
        }
        replacement.taskDescription = encode(next)
        store(
            value.taskId,
            task: replacement,
            state: "enqueued",
            bytes: 0,
            total: registry.get(value.taskId)?.totalBytes
        )
        replacement.resume()
        return true
    }
}

extension TransferManagerIosPlugin: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let value = descriptor(downloadTask) else { return }
        update(value.taskId, task: downloadTask, state: "running")
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let value = descriptor(downloadTask),
              let destinationPath = value.destinationPath
        else {
            return
        }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            update(value.taskId, task: downloadTask, state: "failed", error: "HTTP \(status)")
            return
        }
        do {
            let destination = URL(fileURLWithPath: destinationPath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            update(value.taskId, task: downloadTask, state: "succeeded")
            if value.showNotification != false {
                notify(value)
            }
        } catch {
            update(
                value.taskId,
                task: downloadTask,
                state: "failed",
                error: error.localizedDescription
            )
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let value = descriptor(task) else { return }
        update(value.taskId, task: task, state: "running")
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let value = descriptor(task) else { return }
        if registry.get(value.taskId)?.state == "succeeded" { return }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            update(value.taskId, task: task, state: "cancelled")
            if let bodyPath = value.bodyPath {
                try? FileManager.default.removeItem(atPath: bodyPath)
            }
            return
        }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        if retry(task, descriptor: value, status: status, error: error) {
            return
        }
        defer {
            if let bodyPath = value.bodyPath {
                try? FileManager.default.removeItem(atPath: bodyPath)
            }
        }
        if let error {
            update(
                value.taskId,
                task: task,
                state: "failed",
                error: error.localizedDescription
            )
            return
        }
        let resolvedStatus = status ?? 0
        if (200...299).contains(resolvedStatus) {
            update(value.taskId, task: task, state: "succeeded")
            notify(value)
        } else {
            update(
                value.taskId,
                task: task,
                state: "failed",
                error: "HTTP \(resolvedStatus)"
            )
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            let handler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            handler?()
        }
    }
}

extension TransferManagerIosPlugin: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        if notification.request.identifier.hasPrefix("transfer-manager-") {
            completionHandler([.alert, .sound])
            return
        }
        if let delegate = previousNotificationDelegate,
           delegate.responds(to: #selector(
               UNUserNotificationCenterDelegate.userNotificationCenter(
                   _:willPresent:withCompletionHandler:
               )
           )) {
            delegate.userNotificationCenter?(
                center,
                willPresent: notification,
                withCompletionHandler: completionHandler
            )
        } else {
            completionHandler([])
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier.hasPrefix("transfer-manager-") {
            let userInfo = response.notification.request.content.userInfo
            guard let taskId = userInfo["taskId"] as? String else {
                completionHandler()
                return
            }
            var payload: [String: Any] = ["taskId": taskId]
            if let filePath = userInfo["filePath"] as? String {
                payload["filePath"] = filePath
            }
            pendingNotificationResponse = payload
            methodChannel?.invokeMethod(
                "notificationTapped",
                arguments: payload,
                result: { [weak self] result in
                    guard result as? Bool == true,
                          self?.pendingNotificationResponse?["taskId"] as? String == taskId
                    else {
                        return
                    }
                    self?.pendingNotificationResponse = nil
                }
            )
            completionHandler()
            return
        }
        if let delegate = previousNotificationDelegate,
           delegate.responds(to: #selector(
               UNUserNotificationCenterDelegate.userNotificationCenter(
                   _:didReceive:withCompletionHandler:
               )
           )) {
            delegate.userNotificationCenter?(
                center,
                didReceive: response,
                withCompletionHandler: completionHandler
            )
        } else {
            completionHandler()
        }
    }
}

extension TransferManagerIosPlugin: UIDocumentInteractionControllerDelegate {
    public func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController
    ) -> UIViewController {
        topViewController() ?? UIViewController()
    }

    public func documentInteractionControllerDidEndPreview(
        _ controller: UIDocumentInteractionController
    ) {
        documentInteractionController = nil
    }
}
