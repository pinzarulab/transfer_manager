import ActivityKit
import Foundation

/// ActivityKit data shared by the transfer manager and the host application's
/// Live Activity Widget Extension.
@available(iOS 16.1, *)
public struct TransferLiveActivityAttributes: ActivityAttributes {
    /// Values that change while a transfer runs.
    public struct ContentState: Codable, Hashable {
        public let state: String
        public let bytesTransferred: Int64
        public let totalBytes: Int64?

        public init(
            state: String,
            bytesTransferred: Int64,
            totalBytes: Int64?
        ) {
            self.state = state
            self.bytesTransferred = bytesTransferred
            self.totalBytes = totalBytes
        }

        public var fraction: Double {
            guard let totalBytes, totalBytes > 0 else { return 0 }
            return min(max(Double(bytesTransferred) / Double(totalBytes), 0), 1)
        }
    }

    public let taskId: String
    public let title: String
    public let fileName: String
    public let style: String
    public let allowPause: Bool
    public let allowCancel: Bool

    public init(
        taskId: String,
        title: String,
        fileName: String,
        style: String,
        allowPause: Bool,
        allowCancel: Bool
    ) {
        self.taskId = taskId
        self.title = title
        self.fileName = fileName
        self.style = style
        self.allowPause = allowPause
        self.allowCancel = allowCancel
    }
}

/// Native action sent by a Live Activity control.
public struct TransferLiveActivityAction: Codable, Hashable {
    public let taskId: String
    public let action: String

    public init(taskId: String, action: String) {
        self.taskId = taskId
        self.action = action
    }
}

/// Small process-local inbox used by `LiveActivityIntent` actions.
///
/// Apple runs `LiveActivityIntent` in the application process. Persisting the
/// action also covers the short interval before Flutter registers the plugin.
public enum TransferLiveActivityActionStore {
    public static let notification = Notification.Name(
        "com.pinzarulab.transfer_manager.live_activity_action"
    )

    private static let key = "transfer_manager_ios.live_activity_actions"
    private static let lock = NSLock()

    public static func append(_ action: TransferLiveActivityAction) {
        lock.lock()
        defer { lock.unlock() }
        var actions = load()
        actions.append(action)
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func takeAll() -> [TransferLiveActivityAction] {
        lock.lock()
        defer { lock.unlock() }
        let actions = load()
        UserDefaults.standard.removeObject(forKey: key)
        return actions
    }

    private static func load() -> [TransferLiveActivityAction] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode(
            [TransferLiveActivityAction].self,
            from: data
        )) ?? []
    }
}

#if canImport(AppIntents)
import AppIntents

/// Pause, resume, or cancel a transfer directly from a Live Activity.
@available(iOS 17.0, *)
public struct TransferLiveActivityControlIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Control transfer"
    public static var description = IntentDescription(
        "Pauses, resumes, or cancels a background transfer."
    )
    public static var isDiscoverable: Bool = false

    @Parameter(title: "Task identifier")
    public var taskId: String

    @Parameter(title: "Action")
    public var action: String

    public init() {
        taskId = ""
        action = ""
    }

    public init(taskId: String, action: String) {
        self.taskId = taskId
        self.action = action
    }

    public func perform() async throws -> some IntentResult {
        guard !taskId.isEmpty,
              ["togglePause", "cancel"].contains(action)
        else {
            return .result()
        }
        TransferLiveActivityActionStore.append(
            TransferLiveActivityAction(taskId: taskId, action: action)
        )
        NotificationCenter.default.post(
            name: TransferLiveActivityActionStore.notification,
            object: nil
        )
        return .result()
    }
}

/// Opens the host app and asks it to open or reveal a completed download.
///
/// Unlike a custom URL, this intent is persisted before the host app becomes
/// active. The plugin can therefore finish the action after a cold launch.
@available(iOS 17.0, *)
public struct TransferLiveActivityArtifactIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Open downloaded file"
    public static var description = IntentDescription(
        "Opens or reveals a completed background download."
    )
    public static var isDiscoverable: Bool = false
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "Task identifier")
    public var taskId: String

    @Parameter(title: "Action")
    public var action: String

    public init() {
        taskId = ""
        action = ""
    }

    public init(taskId: String, action: String) {
        self.taskId = taskId
        self.action = action
    }

    public func perform() async throws -> some IntentResult {
        guard !taskId.isEmpty,
              ["open", "reveal"].contains(action)
        else {
            return .result()
        }
        TransferLiveActivityActionStore.append(
            TransferLiveActivityAction(taskId: taskId, action: action)
        )
        NotificationCenter.default.post(
            name: TransferLiveActivityActionStore.notification,
            object: nil
        )
        return .result()
    }
}
#endif
