import SwiftUI

/// For a parent who forgot the code and is locked out. The person who created the family unlocks
/// the device, then picks a new code. Anyone else is pointed to the person who can.
struct ResetParentCodeView: View {
    let household: Household
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false
    @State private var code = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var done = false

    private var canReset: Bool { service.persistence.isOwner(of: household) }

    var body: some View {
        NavigationStack {
            Form {
                if done {
                    Section {
                        Label("Your parent code is changed.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                        Text("Use the new code to open a parent profile.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if !canReset {
                    Section {
                        Text("Only the person who created the family can reset the parent code. Ask them to read it to you under Family, or to reset it here on their own device.")
                    }
                } else if !unlocked {
                    Section {
                        Text("To make sure it's you, unlock this device first. Then you can choose a new parent code.")
                        Button("Unlock to continue") { unlock() }
                    }
                } else {
                    Section("Choose a new code") {
                        SecureField("4 to 8 digits", text: $code)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            #endif
                        SecureField("Type it again", text: $confirmation)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            #endif
                        Button("Save new code") { save() }
                            .disabled(code.isEmpty || confirmation.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .readableWidth()
            .navigationTitle("Forgot the code?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(done ? "Close" : "Cancel") { dismiss() }
                }
            }
            .errorAlert($error)
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }

    private func unlock() {
        Task {
            do {
                try await DeviceOwner.verify(reason: String(localized: "Reset the Same Goat parent code"))
                unlocked = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        guard code.trimmed == confirmation.trimmed else {
            error = String(localized: "The two codes don't match.")
            return
        }
        do {
            try service.resetParentCode(to: code, for: household)
            code = ""
            confirmation = ""
            done = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
