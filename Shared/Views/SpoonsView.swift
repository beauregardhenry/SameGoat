import SwiftUI

/// "How much energy do you have?" Pick 1 to 3 spoons and see what fits right now.
struct SpoonsView: View {
    let me: Member
    let household: Household
    @Environment(\.dismiss) private var dismiss
    @State private var spoons = 2

    var body: some View {
        let plan = Spoons.plan(for: me, spoons: spoons)
        NavigationStack {
            List {
                Section {
                    Picker("Energy", selection: $spoons) {
                        ForEach(Spoons.range, id: \.self) { n in
                            Text(String(repeating: "🥄", count: n)).tag(n)
                                .accessibilityLabel(String(localized: "\(n) spoons"))
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How much energy do you have right now?")
                } footer: {
                    Text(spoons == 1 ? "Low energy is OK. Here's what's easy." :
                         spoons == 2 ? "A medium moment. Here's what fits." : "Lots of energy! A good time for the big ones.")
                }
                section(String(localized: "Due today"), plan.mustDo, icon: "exclamationmark.circle",
                        footer: String(localized: "These can't wait, so they're here whatever your energy."))
                section(String(localized: "Good for right now"), plan.fits, icon: "checkmark.circle", footer: nil)
                section(String(localized: "Save for a better moment"), plan.later, icon: "moon.zzz", footer: nil)
            }
            .overlay {
                if plan.mustDo.isEmpty && plan.fits.isEmpty && plan.later.isEmpty {
                    GoatEmptyView(title: "Nothing to do!", mood: .sleep,
                                  description: Text("Rest up. You've earned it."))
                }
            }
            .navigationTitle("Energy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheetFrame(height: 600)
    }

    @ViewBuilder
    private func section(_ title: String, _ chores: [Chore], icon: String, footer: String?) -> some View {
        if !chores.isEmpty {
            Section {
                ForEach(chores) { chore in
                    HStack {
                        ChoreRow(chore: chore, showAssignee: false)
                        Text(String(repeating: "🥄", count: chore.spoons)).font(.caption)
                            .accessibilityLabel("\(chore.spoons) spoons")
                    }
                }
            } header: {
                Label(title, systemImage: icon)
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }
}
