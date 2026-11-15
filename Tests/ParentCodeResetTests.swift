import XCTest
@testable import SameGoat

/// A parent who has forgotten the code and can't sign in to look it up can still get back in.
@MainActor
final class ParentCodeResetTests: ServiceTestCase {
    func testTheFamilysCreatorCanResetTheCodeWithoutSigningInAsAParent() throws {
        let old = try XCTUnwrap(household.parentCode)
        try service.resetParentCode(to: "482916", for: household)
        XCTAssertEqual(household.parentCode, "482916")
        XCTAssertNotEqual(old, "482916")
    }

    func testTheNewCodeOpensAParentProfileAndTheOldOneNoLongerDoes() throws {
        let old = try XCTUnwrap(household.parentCode)
        try service.resetParentCode(to: "1357", for: household)

        let sharedDevice = SharedDevice(defaults: UserDefaults(suiteName: "ParentCodeResetTests-\(UUID().uuidString)")!)
        assertThrowsServiceError(try sharedDevice.signIn(parent, code: old))
        try sharedDevice.signIn(parent, code: "1357")
        XCTAssertEqual(sharedDevice.activeMemberID, parent.id)
    }

    func testTheNewCodeNeedsFourToEightDigits() throws {
        let original = household.parentCode
        for bad in ["", "123", "123456789", "12ab", "12 34", "١٢٣٤"] {
            assertThrowsServiceError(try service.resetParentCode(to: bad, for: household))
        }
        XCTAssertEqual(household.parentCode, original, "a bad code changes nothing")
        try service.resetParentCode(to: " 2468 ", for: household)
        XCTAssertEqual(household.parentCode, "2468", "spaces around it are ignored")
    }

    func testParentsChangingTheCodeStillWorksTheSameWay() throws {
        try service.setParentCode("9999", for: household, by: parent)
        XCTAssertEqual(household.parentCode, "9999")
        assertThrowsServiceError(try service.setParentCode("9999", for: household, by: kid))
        assertThrowsServiceError(try service.setParentCode("12", for: household, by: parent))
    }
}

private struct FakeDevice: DeviceUnlocking {
    var hasPasscode = true
    var unlocks = true
    func canUnlock() -> Bool { hasPasscode }
    func unlock(reason: String) async -> Bool { unlocks }
}

/// The unlock step in front of the reset, with a stand-in for the system prompt.
final class DeviceOwnerTests: XCTestCase {
    func testAnUnlockedDeviceLetsYouThrough() async throws {
        try await DeviceOwner.verify(reason: "Reset", using: FakeDevice(), allowWithoutPasscode: false)
    }

    func testAFailedUnlockStopsYou() async {
        do {
            try await DeviceOwner.verify(reason: "Reset", using: FakeDevice(unlocks: false), allowWithoutPasscode: false)
            XCTFail("should have refused")
        } catch let error as ServiceError {
            XCTAssertTrue(error.localizedDescription.contains("unlock"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testADeviceWithoutAPasscodeIsRefusedUnlessItIsASimulator() async throws {
        do {
            try await DeviceOwner.verify(reason: "Reset", using: FakeDevice(hasPasscode: false), allowWithoutPasscode: false)
            XCTFail("should have refused")
        } catch let error as ServiceError {
            XCTAssertTrue(error.localizedDescription.contains("passcode"))
        }
        try await DeviceOwner.verify(reason: "Reset", using: FakeDevice(hasPasscode: false), allowWithoutPasscode: true)
    }
}

final class SystemUnlockTests: XCTestCase {
    /// Only asks whether a passcode or biometrics exist; it never shows the unlock prompt.
    func testTheSystemCheckAnswersWithoutPrompting() {
        _ = SystemUnlock().canUnlock()
        XCTAssertFalse(DeviceOwner.isSimulator, "unit tests run on the Mac, which has no simulator exemption")
    }
}
