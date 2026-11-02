import SwiftUI

/// A countdown ring for a chore, from its estimated time, so kids can see how long is left.
struct ChoreTimerView: View {
    let title: String
    let emoji: String?
    let minutes: Int
    @Environment(\.dismiss) private var dismiss
    @State private var endsAt: Date?
    @State private var pausedRemaining: TimeInterval?
    @State private var finished = false

    private var total: TimeInterval { TimeInterval(max(1, minutes) * 60) }

    private func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endsAt else { return total }
        return max(0, endsAt.timeIntervalSince(now))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let left = remaining(at: context.date)
                VStack(spacing: 28) {
                    if let emoji { Text(emoji).font(.system(size: 56)).accessibilityHidden(true) }
                    ZStack {
                        Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 22)
                        Circle()
                            .trim(from: 0, to: left / total)
                            .stroke(left > 0 ? Theme.accent : Color.green, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: left)
                        VStack(spacing: 4) {
                            Text(Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                            Text(left > 0 ? LocalizedStringKey("left") : LocalizedStringKey("Time's up!"))
                                .font(.headline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 260, height: 260)
                    .accessibilityElement(children: .combine)
                    controls(left: left)
                }
                .padding()
                .onChange(of: left <= 0) { _, done in if done && endsAt != nil { finished = true } }
            }
            .sensoryFeedback(.success, trigger: finished)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheetFrame(height: 520)
    }

    @ViewBuilder
    private func controls(left: TimeInterval) -> some View {
        HStack(spacing: 16) {
            if endsAt == nil && pausedRemaining == nil {
                Button { endsAt = Date().addingTimeInterval(total) } label: {
                    Label("Start", systemImage: "play.fill").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
            } else if let paused = pausedRemaining {
                Button { endsAt = Date().addingTimeInterval(paused); pausedRemaining = nil } label: {
                    Label("Keep going", systemImage: "play.fill").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
            } else if left > 0 {
                Button { pausedRemaining = left } label: {
                    Label("Pause", systemImage: "pause.fill").frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
            }
            if endsAt != nil || pausedRemaining != nil {
                Button { endsAt = nil; pausedRemaining = nil; finished = false } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }
}
