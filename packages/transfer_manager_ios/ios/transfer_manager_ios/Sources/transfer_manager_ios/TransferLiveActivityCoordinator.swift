import ActivityKit
import Foundation

#if SWIFT_PACKAGE
import TransferManagerLiveActivitySupport
#endif

final class TransferLiveActivityCoordinator {
    private var lastUpdates: [String: Date] = [:]

    var isAvailable: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    func start(
        taskId: String,
        title: String,
        fileName: String,
        style: String,
        allowPause: Bool,
        allowCancel: Bool
    ) {
        guard #available(iOS 16.1, *),
              ActivityAuthorizationInfo().areActivitiesEnabled,
              activity(taskId) == nil
        else { return }
        let attributes = TransferLiveActivityAttributes(
            taskId: taskId,
            title: title,
            fileName: fileName,
            style: style,
            allowPause: allowPause,
            allowCancel: allowCancel
        )
        let state = TransferLiveActivityAttributes.ContentState(
            state: "running",
            bytesTransferred: 0,
            totalBytes: nil
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                contentState: state,
                pushType: nil
            )
            lastUpdates[taskId] = Date()
        } catch {
            // Live Activity setup must never make the transfer fail.
        }
    }

    func update(
        taskId: String,
        state: String,
        bytesTransferred: Int64,
        totalBytes: Int64?
    ) {
        guard #available(iOS 16.1, *), let activity = activity(taskId) else {
            return
        }
        let terminal = ["succeeded", "failed", "cancelled"].contains(state)
        let last = lastUpdates[taskId] ?? .distantPast
        guard terminal || Date().timeIntervalSince(last) >= 0.5 else { return }
        lastUpdates[taskId] = Date()
        let content = TransferLiveActivityAttributes.ContentState(
            state: state,
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes
        )
        Task {
            if terminal {
                let policy: ActivityUIDismissalPolicy = state == "succeeded"
                    ? .default
                    : .immediate
                await activity.end(using: content, dismissalPolicy: policy)
                self.lastUpdates.removeValue(forKey: taskId)
            } else {
                await activity.update(using: content)
            }
        }
    }

    @available(iOS 16.1, *)
    private func activity(
        _ taskId: String
    ) -> Activity<TransferLiveActivityAttributes>? {
        Activity<TransferLiveActivityAttributes>.activities.first {
            $0.attributes.taskId == taskId
        }
    }
}
