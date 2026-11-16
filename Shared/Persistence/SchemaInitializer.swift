import CloudKit
import CoreData
import Foundation

#if DEBUG && !LOCAL_ONLY
/// A one-off developer step that makes CloudKit create every record type and field in the
/// Development environment, so the schema can be deployed to Production complete.
///
/// CloudKit normally builds its schema lazily as records are written, so a field nobody has used
/// yet is missing, and Production can't add it on the fly. The same goes for `cloudkit.share`, the
/// record type behind every invitation: it only appears once a share has been saved, and without
/// it in Production "Invite Someone" fails. Launch a Debug build with
/// `-initializeCloudKitSchema` (for example `xcrun devicectl device process launch --console ...`)
/// and the app runs this, reports the outcome on standard error and exits.
///
/// It uses its own store file and a private-database-only container, so it never touches a
/// family's data, and the temporary store is deleted afterwards. Release builds, including the
/// App Store and TestFlight ones, don't contain this code.
enum SchemaInitializer {
    static let launchArgument = "-initializeCloudKitSchema"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    /// Runs the step if the launch argument is present, then exits the app.
    static func runIfRequested() {
        guard isRequested else { return }
        let code: Int32
        do {
            let types = try initialize()
            report("SCHEMA OK: created the schema for \(types.count) record types: \(types.joined(separator: ", ")). Check Schema > Record Types in the CloudKit Console.")
            code = 0
        } catch {
            report("SCHEMA FAILED: \(error)")
            code = 1
        }
        exit(code)
    }

    /// Creates the schema and returns the record type names it covers.
    static func initialize() throws -> [String] {
        let model = SameGoatModel.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SchemaInit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = NSPersistentCloudKitContainer(name: "SameGoatSchema", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("schema.sqlite"))
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: AppConfig.containerID)
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema(options: [])
        try createShareRecordType()
        return (model.entities.compactMap(\.name).map { "CD_" + $0 } + [CKRecord.SystemType.share]).sorted()
    }

    /// Saves a share in a throwaway zone, which makes CloudKit create the `cloudkit.share`
    /// record type, then deletes the zone again.
    private static func createShareRecordType() throws {
        let database = CKContainer(identifier: AppConfig.containerID).privateCloudDatabase
        let zone = CKRecordZone(zoneName: "SchemaInit-\(UUID().uuidString)")
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
                let share = CKShare(recordZoneID: zone.zoneID)
                let saved = try await database.modifyRecords(saving: [share], deleting: [])
                for result in saved.saveResults.values { _ = try result.get() }
            } catch {
                outcome.error = error
            }
            _ = try? await database.modifyRecordZones(saving: [], deleting: [zone.zoneID])
            done.signal()
        }
        done.wait()
        if let error = outcome.error { throw error }
    }

    private final class Outcome: @unchecked Sendable {
        var error: Error?
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
#endif
