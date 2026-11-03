import SwiftUI

/// Shows a kid's uncelebrated wins one at a time, with confetti and a happy buzz.
struct CelebrationOverlay: ViewModifier {
    @ObservedObject var me: Member
    @EnvironmentObject private var celebrations: Celebrations
    @State private var queue: [Celebration] = []

    /// Changes whenever something celebration-worthy could have happened.
    private var trigger: String {
        "\(me.balance)-\(me.available)-\(me.entryList.count)-\(me.goalRewardID?.uuidString ?? "")"
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let current = queue.first {
                    CelebrationCard(celebration: current) {
                        celebrations.markSeen(current, for: me)
                        withAnimation(.spring) { queue.removeFirst() }
                    }
                    .id(current.id)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .sensoryFeedback(.success, trigger: queue.first?.id) { _, new in new != nil }
            .task(id: trigger) {
                guard !me.isParent else { return }
                let fresh = celebrations.pending(for: me).filter { item in !queue.contains { $0.id == item.id } }
                withAnimation(.spring) { queue.append(contentsOf: fresh) }
            }
    }
}

extension View {
    func celebrations(for me: Member) -> some View {
        modifier(CelebrationOverlay(me: me))
    }
}

private struct CelebrationCard: View {
    let celebration: Celebration
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture(perform: onDone)
            if !reduceMotion { Confetti().ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: 14) {
                Goat(mood: celebration.id.hasPrefix("badge-") ? .party : .cheer, size: 140)
                    .overlay(alignment: .bottomTrailing) {
                        Text(celebration.emoji)
                            .font(.system(size: 34))
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                            .offset(x: 8, y: 4)
                    }
                Text(celebration.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(celebration.message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Yay!", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// Falling coloured pieces, drawn with a Canvas so it stays cheap.
private struct Confetti: View {
    private struct Piece {
        let x: Double, delay: Double, speed: Double, spin: Double, size: Double, color: Color
    }
    private let pieces: [Piece] = (0..<70).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.8), speed: .random(in: 0.35...0.7),
              spin: .random(in: 1...4), size: .random(in: 6...11),
              color: Theme.palette.randomElement() ?? Theme.accent)
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let progress = (t - piece.delay) * piece.speed
                    guard progress > 0, progress < 1.3 else { continue }
                    let y = progress * (size.height + 40) - 20
                    let x = piece.x * size.width + sin(progress * 8 + piece.spin) * 18
                    var copy = context
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(progress * piece.spin * 6))
                    copy.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)),
                              with: .color(piece.color))
                }
            }
        }
    }
}

/// A row of badges: earned ones in colour, the rest waiting.
struct BadgeShelf: View {
    let badges: [Badge]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(badges) { badge in
                    VStack(spacing: 4) {
                        Text(badge.emoji)
                            .font(.title)
                            .frame(width: 54, height: 54)
                            .background(badge.earned ? Theme.gold.opacity(0.2) : Color.secondary.opacity(0.1), in: Circle())
                            .grayscale(badge.earned ? 0 : 1)
                            .opacity(badge.earned ? 1 : 0.45)
                        Text(badge.title).font(.caption2).lineLimit(1)
                    }
                    .frame(width: 72)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(badge.title), \(badge.earned ? "earned" : "not yet: \(badge.detail)")")
                }
            }
            .padding(.vertical, 4)
        }
    }
}
