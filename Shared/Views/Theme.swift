import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum Theme {
    /// Same Goat teal: buttons, selection and anything the family taps. Lighter in dark mode.
    static let accent = Color("AccentColor")
    /// Points, wherever they're counted.
    static let coral = Color("Coral")
    /// Rewards, goals, badges and streaks.
    static let gold = Color("Gold")
    /// A brighter gold for bars and backgrounds, where the text shade would look muddy.
    static let goldFill = Color(red: 0.96, green: 0.72, blue: 0.18)
    /// Cards on a grouped background: white in light mode, a raised gray in dark mode.
    #if os(iOS)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    #else
    static let card = Color(nsColor: .controlBackgroundColor)
    #endif

    static let palette: [Color] = [
        Color(red: 0.91, green: 0.35, blue: 0.32),
        Color(red: 0.20, green: 0.55, blue: 0.85),
        Color(red: 0.25, green: 0.65, blue: 0.45),
        Color(red: 0.95, green: 0.62, blue: 0.15),
        Color(red: 0.58, green: 0.38, blue: 0.80),
        Color(red: 0.12, green: 0.65, blue: 0.70),
        Color(red: 0.85, green: 0.38, blue: 0.62),
        Color(red: 0.45, green: 0.48, blue: 0.55),
    ]
    static func color(_ index: Int) -> Color { palette[abs(index) % palette.count] }

    static let kidEmojis = ["🦊", "🐼", "🐯", "🦁", "🐸", "🐵", "🐰", "🐻", "🦄", "🐙", "🐢", "🦉"]
    static let parentEmojis = ["🌻", "🌷", "🍀", "⭐️", "🌈", "☕️"]
    static let rewardEmojis = ["🎬", "🍦", "🎮", "📱", "🍕", "🎁", "🛍️", "⚽️"]
    static let choreEmojis = ["🛏️", "🧸", "🍽️", "🧺", "🗑️", "🐶", "🐱", "🪴", "🧹", "🧽", "🦷", "🎒", "📚", "🚿", "👕", "🧦", "🍳", "🚗"]
}

struct Avatar: View {
    let member: Member
    var size: CGFloat = 40

    var body: some View {
        Text(member.displayEmoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Theme.color(Int(member.colorIndex)).opacity(0.22), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The Same Goat goat in one of its moods, for celebrations and empty screens.
enum GoatMood: String {
    case cheer, party, sleep, curious
    var imageName: String { "Goat" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct Goat: View {
    let mood: GoatMood
    var size: CGFloat = 120

    var body: some View {
        Image(mood.imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size)
            .accessibilityHidden(true)
    }
}

/// An empty screen with the goat in place of a symbol.
struct GoatEmptyView<Actions: View>: View {
    let title: LocalizedStringKey
    let mood: GoatMood
    let description: Text
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                Goat(mood: mood)
                Text(title).font(.title2.bold())
            }
        } description: {
            description
        } actions: {
            actions()
        }
    }
}

extension GoatEmptyView where Actions == EmptyView {
    init(title: LocalizedStringKey, mood: GoatMood, description: Text) {
        self.init(title: title, mood: mood, description: description, actions: { EmptyView() })
    }
}

struct PointsBadge: View {
    let points: Int
    var body: some View {
        Text("\(points) pts")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.coral.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.coral)
            .accessibilityLabel("\(points) points")
    }
}

struct StatusChip: View {
    let text: LocalizedStringKey
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

func dueText(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return String(localized: "Today") }
    if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
    if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
    return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
}

/// "Today" or "Today, 5:00 PM" when the chore has a due time.
func dueText(for chore: Chore) -> String? {
    guard let due = chore.dueDate else { return nil }
    if chore.dueWithinWeek {
        let calendar = Calendar.current
        if calendar.isDate(due, equalTo: Date(), toGranularity: .weekOfYear) { return String(localized: "This week") }
        let start = calendar.dateInterval(of: .weekOfYear, for: due)?.start ?? due
        return String(localized: "Week of \(start.formatted(.dateTime.month(.abbreviated).day()))")
    }
    guard chore.dueTime != nil, let at = chore.dueAt() else { return dueText(due) }
    return dueText(due) + ", " + at.formatted(date: .omitted, time: .shortened)
}

// MARK: Photos

enum ImageProcessing {
    /// Shrinks a picked photo so it syncs quickly, and returns JPEG data.
    static func jpegData(from data: Data, maxDimension: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        guard let image = cgImage(from: data, maxDimension: maxDimension) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    static func cgImage(from data: Data, maxDimension: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

struct PhotoView: View {
    let data: Data
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: data) {
            image = ImageProcessing.cgImage(from: data, maxDimension: 1200)
        }
    }
}

// MARK: Shared modifiers

extension View {
    /// Presents a thrown error to the user. The message says what to fix; the title
    /// stays neutral because most of these are rules ("Give the chore a title.").
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Couldn't do that", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// Gives sheets a sensible size on the Mac, where they otherwise collapse.
    /// The height is capped so the sheet (and its Cancel/Save buttons) always fits
    /// inside the smallest window; taller forms scroll.
    func sheetFrame(width: CGFloat = 460, height: CGFloat = 560) -> some View {
        #if os(macOS)
        frame(minWidth: width, minHeight: 400, idealHeight: min(height, 500))
        #else
        self
        #endif
    }

    /// Keeps a full-screen form to a comfortable reading width on iPad and the Mac,
    /// while its background still fills the window.
    func readableWidth(_ maxWidth: CGFloat = 640) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

private struct ReadableWidth: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content.contentMargins(.horizontal, max(0, (proxy.size.width - maxWidth) / 2), for: .scrollContent)
        }
    }
}
