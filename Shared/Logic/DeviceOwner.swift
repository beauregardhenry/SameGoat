import Foundation
import LocalAuthentication

/// Proves the person holding the device can unlock it, with Face ID, Touch ID or the device passcode.
/// Resetting the parent code asks for this, so a child who picks up an unlocked iPad still can't do it.
enum DeviceOwner {
    /// Throws a `ServiceError` that explains what to do if the device can't confirm it's you.
    @MainActor
    static func verify(reason: String) async throws {
        let context = LAContext()
        var unavailable: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &unavailable) else {
            #if targetEnvironment(simulator)
            return // Simulators often have no passcode.
            #else
            throw ServiceError.notAllowed(String(localized: "Set a passcode on this device first, then try again."))
            #endif
        }
        let unlocked = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        guard unlocked else { throw ServiceError.notAllowed(String(localized: "That didn't unlock the device. Try again.")) }
    }
}
