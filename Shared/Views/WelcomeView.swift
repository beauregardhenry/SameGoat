import SwiftUI

/// First launch: a few short steps to set up the family.
struct WelcomeView: View {
    let userID: String
    @EnvironmentObject private var service: HouseholdService
    @State private var step = Step.hello
    @State private var householdName = ""
    @State private var yourName = ""
    @State private var emoji = Theme.parentEmojis[0]
    @State private var kids: [NewKid] = []
    @State private var kidName = ""
    @State private var kidEmoji = Theme.kidEmojis[0]
    @State private var features: Set<Feature> = []
    @State private var error: String?

    private enum Step: Int, CaseIterable { case hello, family, kids, extras }

    private struct NewKid: Identifiable {
        let id = UUID()
        let name: String
        let emoji: String
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .hello: hello
                case .family: family
                case .kids: kidsStep
                case .extras: extras
                }
            }
            .formStyle(.grouped)
            .readableWidth()
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(title)
        }
        .errorAlert($error)
    }

    private var title: LocalizedStringKey {
        switch step {
        case .hello: "Same Goat"
        case .family: "Your family"
        case .kids: "Your kids"
        case .extras: "Extras"
        }
    }

    // MARK: Steps

    private var hello: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image("Mascot")
                        .resizable()
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Welcome to Same Goat").font(.title2.bold())
                    Text("We're all in the same goat.").font(.subheadline.italic()).foregroundStyle(.secondary)
                    Text("Assign chores, check them off, and cheer everyone on with points.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            #if LOCAL_ONLY
            Section("Testing") {
                Button("Load demo family") { loadDemo() }
            }
            #endif
            Section("Joining a household?") {
                Text("Open the invitation you were sent on this device. Your household appears here once it syncs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var family: some View {
        Form {
            intro(.cheer, "What should we call your household, and you?")
            Section {
                TextField("Household name", text: $householdName)
                TextField("Your name", text: $yourName)
                EmojiPicker(selection: $emoji, options: Theme.parentEmojis)
            }
        }
    }

    private var kidsStep: some View {
        Form {
            intro(.curious, "Add the kids who'll be doing chores. You can add more, and other grown-ups, later under Family.")
            if !kids.isEmpty {
                Section {
                    ForEach(kids) { kid in
                        HStack(spacing: 12) {
                            Text(kid.emoji).font(.title2).accessibilityHidden(true)
                            Text(kid.name).font(.headline)
                        }
                    }
                    .onDelete { kids.remove(atOffsets: $0) }
                }
            }
            Section {
                HStack {
                    TextField("Kid's name", text: $kidName)
                        .onSubmit(addKid)
                    Button("Add", action: addKid)
                        .buttonStyle(.bordered)
                        .disabled(kidName.trimmed.isEmpty)
                }
                EmojiPicker(selection: $kidEmoji, options: Theme.kidEmojis)
            }
        }
    }

    private var extras: some View {
        Form {
            intro(.party, "Start simple: chores, points and rewards are always on. You can change these anytime under Family → Features.")
            Section {
                ForEach(Feature.allCases) { feature in
                    Toggle(isOn: Binding(
                        get: { features.contains(feature) },
                        set: { on in if on { features.insert(feature) } else { features.remove(feature) } })) {
                        FeatureLabel(feature: feature)
                    }
                }
            }
        }
    }

    /// The goat and a line about what this step is for.
    private func intro(_ mood: GoatMood, _ text: LocalizedStringKey) -> some View {
        Section {
            HStack(spacing: 14) {
                Goat(mood: mood, size: 76)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Moving between steps

    private var controls: some View {
        VStack(spacing: 12) {
            if step != .hello {
                // Three dots for the three setup steps after the welcome.
                HStack(spacing: 8) {
                    ForEach(Step.allCases.dropFirst(), id: \.self) { dot in
                        Capsule()
                            .fill(dot.rawValue <= step.rawValue ? Theme.accent : Color.secondary.opacity(0.3))
                            .frame(width: dot == step ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Step \(step.rawValue) of \(Step.allCases.count - 1)"))
            }
            HStack(spacing: 12) {
                if step != .hello {
                    Button("Back") { move(-1) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button(action: next) {
                    Text(nextTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)
            }
        }
        .padding()
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .animation(.spring(duration: 0.3), value: step)
    }

    private var nextTitle: LocalizedStringKey {
        switch step {
        case .hello: "Get started"
        case .family: "Next"
        case .kids: kids.isEmpty && kidName.trimmed.isEmpty ? "Skip for now" : "Next"
        case .extras: "Create Household"
        }
    }

    private var canContinue: Bool {
        step != .family || !(householdName.trimmed.isEmpty || yourName.trimmed.isEmpty)
    }

    private func next() {
        switch step {
        case .kids:
            addKid()
            move(1)
        case .extras:
            create()
        default:
            move(1)
        }
    }

    private func move(_ by: Int) {
        guard let target = Step(rawValue: step.rawValue + by) else { return }
        withAnimation { step = target }
    }

    private func addKid() {
        let name = kidName.trimmed
        guard !name.isEmpty else { return }
        kids.append(NewKid(name: name, emoji: kidEmoji))
        kidName = ""
        // Offer a different animal for the next one.
        let used = Set(kids.map(\.emoji))
        kidEmoji = Theme.kidEmojis.first { !used.contains($0) } ?? kidEmoji
    }

    private func create() {
        do {
            try service.createHousehold(name: householdName, yourName: yourName, emoji: emoji, userID: userID,
                                        features: features, kids: kids.map { ($0.name, $0.emoji) })
        } catch {
            self.error = error.localizedDescription
        }
    }

    #if LOCAL_ONLY
    private func loadDemo() {
        do { try service.loadDemoHousehold(userID: userID) } catch { self.error = error.localizedDescription }
    }
    #endif
}
