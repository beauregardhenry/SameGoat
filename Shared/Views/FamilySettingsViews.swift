import SwiftUI

/// Parents turn allowance mode on and choose how many points make one unit of money.
struct AllowanceSettingsView: View {
    @ObservedObject var household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @State private var rate: Int
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _rate = State(initialValue: household.allowanceOn ? Int(household.allowanceRate) : 10)
    }

    /// The currency already chosen, or this device's.
    private var currency: String {
        household.currencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }

    private var oneUnit: String {
        Decimal(1).formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Allowance mode", isOn: Binding(
                    get: { household.allowanceOn },
                    set: { save(on: $0) }))
            } footer: {
                Text("Points are worth real money. Kids see what their points are worth, and you record it when you pay them.")
            }
            if household.allowanceOn {
                Section {
                    Stepper(value: $rate, in: HouseholdService.allowanceRates, step: rate < 10 ? 1 : 5) {
                        LabeledContent("\(rate) points", value: oneUnit)
                    }
                    .onChange(of: rate) { _, _ in save(on: true) }
                    LabeledContent("50 points", value: household.moneyText(for: 50) ?? "")
                    LabeledContent("Currency", value: currency)
                } header: {
                    Text("Exchange rate")
                } footer: {
                    Text("Changing the rate changes what everyone's current points are worth.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Allowance")
        .errorAlert($error)
    }

    private func save(on: Bool) {
        do { try service.setAllowance(rate: on ? rate : nil, currencyCode: currency, for: household, by: me) }
        catch { self.error = error.localizedDescription }
    }
}

/// A parent records handing a kid money for some of their points.
struct PayoutSheet: View {
    @ObservedObject var kid: Member
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var points: Int
    @State private var error: String?

    init(kid: Member, me: Member) {
        self.kid = kid
        self.me = me
        _points = State(initialValue: max(0, kid.available))
    }

    private var rate: Int { max(1, Int(kid.household?.allowanceRate ?? 1)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Available", value: String(localized: "\(kid.available) points"))
                    Stepper(value: $points, in: 0...max(0, kid.available), step: rate) {
                        LabeledContent("Pay out", value: String(localized: "\(points) points"))
                    }
                    LabeledContent("Amount") {
                        Text(kid.household?.moneyText(for: points) ?? "").font(.title3.bold()).foregroundStyle(Theme.accent)
                    }
                } footer: {
                    Text("Record this when you hand \(kid.displayName) the money. The points are spent.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pay \(kid.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Paid") {
                        do {
                            try service.payOut(points, to: kid, by: me)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(points == 0)
                }
            }
            .errorAlert($error)
        }
        .sheetFrame(height: 340)
        .presentationDetents([.medium])
    }
}

/// Parents pause chores for a trip: nothing goes overdue and streaks wait.
struct PauseSettingsView: View {
    @ObservedObject var household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @State private var from: Date
    @State private var until: Date
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        let today = Calendar.current.startOfDay(for: Date())
        _from = State(initialValue: household.upcomingPause()?.lowerBound ?? today)
        _until = State(initialValue: household.upcomingPause()?.upperBound
                       ?? Calendar.current.date(byAdding: .day, value: 6, to: today) ?? today)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Pause chores", isOn: Binding(
                    get: { household.upcomingPause() != nil },
                    set: { save(on: $0) }))
            } footer: {
                Text("For a trip or a sick week. Chores due during the pause don't go overdue or send reminders, repeating chores skip ahead to after it, and nobody's streak breaks.")
            }
            if household.upcomingPause() != nil {
                Section("Dates") {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("Until", selection: $until, in: from..., displayedComponents: .date)
                }
                .onChange(of: from) { _, _ in save(on: true) }
                .onChange(of: until) { _, _ in save(on: true) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vacation Pause")
        .errorAlert($error)
    }

    private func save(on: Bool) {
        do {
            try service.setPause(from: on ? from : nil, until: on ? max(from, until) : nil, for: household, by: me)
        } catch { self.error = error.localizedDescription }
    }
}

/// "On vacation until Sun, Nov 9" at the top of the chore list.
struct PauseBanner: View {
    @ObservedObject var household: Household

    var body: some View {
        if let pause = household.upcomingPause() {
            let started = pause.lowerBound <= Date()
            Label(started
                  ? "On vacation until \(pause.upperBound.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())). Chores are paused."
                  : "Vacation from \(pause.lowerBound.formatted(.dateTime.month(.abbreviated).day())) to \(pause.upperBound.formatted(.dateTime.month(.abbreviated).day())).",
                  systemImage: "beach.umbrella")
                .font(.subheadline)
                .foregroundStyle(.teal)
        }
    }
}

/// Parents choose how many points each 5 minutes of a chore is worth before difficulty.
struct EffortSettingsView: View {
    @ObservedObject var household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @State private var rate: Int
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _rate = State(initialValue: max(1, Int(household.effortRate)))
    }

    private func example(_ minutes: Int, _ difficulty: Difficulty) -> some View {
        LabeledContent(Effort.label(minutes: minutes, difficulty: difficulty) ?? "",
                       value: String(localized: "\(Effort.suggestedPoints(minutes: minutes, difficulty: difficulty, rate: rate) ?? 0) points"))
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: $rate, in: Effort.rateRange) {
                    LabeledContent("Every 5 minutes", value: String(localized: "\(rate) points"))
                }
                .onChange(of: rate) { _, rate in
                    do { try service.setEffortRate(rate, for: household, by: me) } catch { self.error = error.localizedDescription }
                }
            } footer: {
                Text("Then times 1 for easy, 1.5 for medium and 2 for hard. It only suggests points in the chore editor; you can always change them.")
            }
            Section("Examples") {
                example(5, .easy)
                example(15, .medium)
                example(30, .hard)
                example(60, .hard)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Points for Effort")
        .errorAlert($error)
    }
}

/// Parents switch the optional parts of the app on and off, so it only shows what the family uses.
struct FeaturesView: View {
    @ObservedObject var household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(Feature.allCases) { feature in
                    Toggle(isOn: Binding(
                        get: { household.has(feature) },
                        set: { on in
                            do { try service.setFeature(feature, on: on, for: household, by: me) }
                            catch { self.error = error.localizedDescription }
                        })) {
                        FeatureLabel(feature: feature)
                    }
                }
            } footer: {
                Text("Turn on only what your family wants; everything else stays out of the way. Allowance mode has its own switch under Family.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Features")
        .errorAlert($error)
    }
}

struct FeatureLabel: View {
    let feature: Feature

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                Text(feature.detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: feature.icon)
        }
    }
}
