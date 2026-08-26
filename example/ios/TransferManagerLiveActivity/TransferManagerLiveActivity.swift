import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

#if canImport(TransferManagerLiveActivitySupport)
import TransferManagerLiveActivitySupport
#elseif canImport(transfer_manager_ios)
import transfer_manager_ios
#endif

@main
struct TransferManagerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TransferManagerLiveActivityWidget()
    }
}

struct TransferManagerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransferLiveActivityAttributes.self) { context in
            TransferLockScreenView(context: context)
                .activityBackgroundTint(background(for: context.attributes.style))
                .activitySystemActionForegroundColor(foreground(for: context.attributes.style))
                .widgetURL(completedURL(context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: statusSymbol(context.state.state))
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percent(context.state))
                        .font(.headline.monospacedDigit())
                        .accessibilityLabel("Progress \(percent(context.state))")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.fileName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.fraction)
                            .tint(accent(for: context.attributes.style))
                        TransferActions(context: context)
                    }
                }
            } compactLeading: {
                Image(systemName: statusSymbol(context.state.state))
                    .foregroundStyle(accent(for: context.attributes.style))
            } compactTrailing: {
                Text(percent(context.state))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.35), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: context.state.fraction)
                        .stroke(accent(for: context.attributes.style), lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                }
                .padding(3)
                .accessibilityLabel("Transfer progress \(percent(context.state))")
            }
            .widgetURL(completedURL(context))
            .keylineTint(accent(for: context.attributes.style))
        }
    }
}

private struct TransferLockScreenView: View {
    let context: ActivityViewContext<TransferLiveActivityAttributes>

    var body: some View {
        switch context.attributes.style {
        case "compact": compact
        case "detailed": detailed
        case "prominent": prominent
        default: system
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ProgressView(value: context.state.fraction)
                .tint(accent(for: context.attributes.style))
            TransferActions(context: context)
        }
        .padding(16)
    }

    private var compact: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol(context.state.state))
                .font(.title2)
                .foregroundStyle(accent(for: context.attributes.style))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(context.attributes.fileName).lineLimit(1)
                    Spacer()
                    Text(percent(context.state)).monospacedDigit()
                }
                ProgressView(value: context.state.fraction)
                    .tint(accent(for: context.attributes.style))
            }
            TransferActions(context: context, labels: false)
        }
        .padding(14)
    }

    private var detailed: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            HStack {
                Text(byteProgress(context.state))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percent(context.state))
                    .font(.headline.monospacedDigit())
            }
            ProgressView(value: context.state.fraction)
                .tint(accent(for: context.attributes.style))
            TransferActions(context: context)
        }
        .padding(16)
    }

    private var prominent: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: context.state.fraction)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percent(context.state))
                    .font(.caption.bold().monospacedDigit())
            }
            .frame(width: 72, height: 72)
            .accessibilityLabel("Transfer progress \(percent(context.state))")
            VStack(alignment: .leading, spacing: 7) {
                Text(context.attributes.title).font(.headline)
                Text(context.attributes.fileName).lineLimit(1)
                TransferActions(context: context)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol(context.state.state))
                .foregroundStyle(accent(for: context.attributes.style))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title).font(.headline)
                Text(context.attributes.fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(stateLabel(context.state.state))
                .font(.caption.weight(.semibold))
        }
    }
}

private struct TransferActions: View {
    let context: ActivityViewContext<TransferLiveActivityAttributes>
    var labels = true

    var body: some View {
        HStack(spacing: 8) {
            if context.state.state == "succeeded" {
                Link(destination: actionURL("open", taskId: context.attributes.taskId)) {
                    actionLabel("Open", symbol: "doc", showText: labels)
                }
                Link(destination: actionURL("reveal", taskId: context.attributes.taskId)) {
                    actionLabel("Reveal", symbol: "folder", showText: labels)
                }
            } else if !["failed", "cancelled"].contains(context.state.state) {
                if #available(iOSApplicationExtension 17.0, *) {
                    if context.attributes.allowPause {
                        Button(intent: TransferLiveActivityControlIntent(
                            taskId: context.attributes.taskId,
                            action: "togglePause"
                        )) {
                            actionLabel(
                                context.state.state == "paused" ? "Resume" : "Pause",
                                symbol: context.state.state == "paused" ? "play.fill" : "pause.fill",
                                showText: labels
                            )
                        }
                    }
                    if context.attributes.allowCancel {
                        Button(intent: TransferLiveActivityControlIntent(
                            taskId: context.attributes.taskId,
                            action: "cancel"
                        )) {
                            actionLabel("Cancel", symbol: "xmark", showText: labels)
                        }
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func actionLabel(_ text: String, symbol: String, showText: Bool) -> some View {
        Group {
            if showText {
                Label(text, systemImage: symbol)
            } else {
                Image(systemName: symbol)
            }
        }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(text)
    }
}

private func actionURL(_ action: String, taskId: String) -> URL {
    var components = URLComponents()
    components.scheme = "transfer-manager"
    components.host = action
    components.queryItems = [URLQueryItem(name: "taskId", value: taskId)]
    return components.url!
}

private func completedURL(
    _ context: ActivityViewContext<TransferLiveActivityAttributes>
) -> URL? {
    context.state.state == "succeeded"
        ? actionURL("open", taskId: context.attributes.taskId)
        : nil
}

private func percent(_ state: TransferLiveActivityAttributes.ContentState) -> String {
    state.totalBytes == nil ? "—" : "\(Int((state.fraction * 100).rounded()))%"
}

private func byteProgress(_ state: TransferLiveActivityAttributes.ContentState) -> String {
    let sent = ByteCountFormatter.string(fromByteCount: state.bytesTransferred, countStyle: .file)
    guard let total = state.totalBytes else { return sent }
    return "\(sent) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
}

private func stateLabel(_ state: String) -> String {
    switch state {
    case "paused": return "Paused"
    case "succeeded": return "Complete"
    case "failed": return "Failed"
    case "cancelled": return "Cancelled"
    default: return "Downloading"
    }
}

private func statusSymbol(_ state: String) -> String {
    switch state {
    case "paused": return "pause.circle.fill"
    case "succeeded": return "checkmark.circle.fill"
    case "failed": return "exclamationmark.triangle.fill"
    case "cancelled": return "xmark.circle.fill"
    default: return "arrow.down.circle.fill"
    }
}

private func accent(for style: String) -> Color {
    switch style {
    case "compact": return .teal
    case "detailed": return .indigo
    case "prominent": return .white
    default: return .blue
    }
}

private func background(for style: String) -> Color {
    style == "prominent" ? .indigo : Color(uiColor: .secondarySystemBackground)
}

private func foreground(for style: String) -> Color {
    style == "prominent" ? .white : .primary
}
