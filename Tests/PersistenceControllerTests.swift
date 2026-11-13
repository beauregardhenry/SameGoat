import XCTest
import CoreData
@testable import SameGoat

@MainActor
final class PersistenceControllerTests: XCTestCase {
    func testTheContainerIDDefaultsToTheAppsICloudContainer() {
        XCTAssertTrue(AppConfig.containerID.hasPrefix("iCloud."))
    }

    func testAnInMemoryStackLoadsOneStoreAndNothingIsShared() throws {
        let persistence = PersistenceController(mode: .inMemory)
        XCTAssertNil(persistence.loadError)
        XCTAssertNotNil(persistence.privateStore)
        XCTAssertNil(persistence.sharedStore, "only the iCloud setup has a second, shared store")
        XCTAssertEqual(persistence.container.persistentStoreCoordinator.persistentStores.count, 1)
        XCTAssertEqual(persistence.privateStore?.type, NSInMemoryStoreType)
    }

    func testTheViewContextMergesSyncedChangesAndLetsTheNewestEditWin() {
        let context = PersistenceController(mode: .inMemory).viewContext
        XCTAssertTrue(context.automaticallyMergesChangesFromParent)
        XCTAssertTrue((context.mergePolicy as AnyObject) === NSMergeByPropertyObjectTrumpMergePolicy as AnyObject)
        XCTAssertEqual(context.name, "view")
    }

    func testYouOwnEveryHouseholdOutsideICloud() throws {
        let service = HouseholdService(persistence: PersistenceController(mode: .inMemory))
        let household = try service.createHousehold(name: "Home", yourName: "Mama", emoji: "🌻", userID: "u")
        XCTAssertTrue(service.persistence.isOwner(of: household))
    }

    func testDataSavedInTheStackComesBackOut() throws {
        let service = HouseholdService(persistence: PersistenceController(mode: .inMemory))
        _ = try service.createHousehold(name: "Home", yourName: "Mama", emoji: "🌻", userID: "u")
        service.context.reset()

        let households = try service.context.fetch(NSFetchRequest<Household>(entityName: "Household"))
        XCTAssertEqual(households.map(\.name), ["Home"])
    }

    func testTheSameModelIsSharedByEveryStack() {
        let first = PersistenceController(mode: .inMemory).container.managedObjectModel
        let second = PersistenceController(mode: .inMemory).container.managedObjectModel
        XCTAssertTrue(first === second)
        XCTAssertEqual(Set(first.entities.compactMap(\.name)),
                       ["Household", "Member", "Chore", "Reward", "Redemption", "Project", "MoodCheckIn", "PointEntry"])
    }

    func testTheOnDiskLocalStackOpensItsOwnFile() throws {
        let persistence = PersistenceController(mode: .local)
        XCTAssertNil(persistence.loadError)
        XCTAssertEqual(persistence.privateStore?.url?.lastPathComponent, "SameGoat-local.sqlite")
        XCTAssertNil(persistence.sharedStore)
    }

    func testInvitingPeopleExplainsItNeedsICloudWhenThereIsNone() async throws {
        let service = HouseholdService(persistence: PersistenceController(mode: .inMemory))
        let household = try service.createHousehold(name: "Home", yourName: "Mama", emoji: "🌻", userID: "u")
        do {
            _ = try await service.persistence.share(household)
            XCTFail("sharing should need iCloud")
        } catch let error as ServiceError {
            XCTAssertTrue(error.localizedDescription.contains("iCloud"))
        }
    }
}
