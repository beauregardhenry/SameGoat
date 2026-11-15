import Foundation
import LocalAuthentication

/// Something that can ask the person holding the device to unlock it. The real one uses the system's
/// Face ID, Touch ID or passcode prompt; tests use a stand-in so they never pop that up.
protocol DeviceUnlocking {
    func canUnlock() -> Bool
    func unlock(reason: String) async -> Bool
}

struct SystemUnlock: DeviceUnlocking {
    func canUnlock() -> Bool {
        var unavailable: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &unavailable)
    }

    func unlock(reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Proves the person holding the device can unlock it, with Face ID, Touch ID or the device passcode.
/// Resetting the parent code asks for this, so a child who picks up an unlocked iPad still can't do it.
enum DeviceOwner {
    /// Throws a `ServiceError` that explains what to do if the device can't confirm it's you.
    /// Simulators often have no passcode, so they skip the check (`allowWithoutPasscode`).
    static func verify(reason: String, using device: DeviceUnlocking = SystemUnlock(),
                       allowWithoutPasscode: Bool = Self.isSimulator) async throws {
        guard device.canUnlock() else {
            if allowWithoutPasscode { return }
            throw ServiceError.notAllowed(String(localized: "Set a passcode on this device first, then try again."))
        }
        guard await device.unlock(reason: reason) else {
            throw ServiceError.notAllowed(String(localized: "That didn't unlock the device. Try again."))
        }
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
