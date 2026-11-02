import XCTest
@testable import HappyMama

/// The String Catalog is compiled into the app; check Spanish is really there, plurals included.
final class LocalizationTests: XCTestCase {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj missing")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func text(_ key: String, _ language: String) throws -> String {
        try bundle(language).localizedString(forKey: key, value: "⚠️", table: nil)
    }

    func testSpanishIsBundled() throws {
        XCTAssertEqual(try text("Chores", "es"), "Tareas")
        XCTAssertEqual(try text("Who's using Happy Mama?", "es"), "¿Quién usa Happy Mama?")
        XCTAssertEqual(try text("Give the chore a title.", "es"), "Ponle un título a la tarea.")
        XCTAssertEqual(try text("Morning routine", "es"), "Rutina de la mañana")
    }

    func testPluralsInBothLanguages() throws {
        func points(_ n: Int, _ language: String) throws -> String {
            String(format: try text("%lld points", language), locale: Locale(identifier: language), n)
        }
        XCTAssertEqual(try points(1, "en"), "1 point")
        XCTAssertEqual(try points(5, "en"), "5 points")
        XCTAssertEqual(try points(1, "es"), "1 punto")
        XCTAssertEqual(try points(5, "es"), "5 puntos")
    }

    func testCountInsideASentence() throws {
        let format = try text("%@ is ready for you to check. Worth %d points.", "es")
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "es"), "Platos", 1),
                       "«Platos» está lista para que la revises. Vale 1 punto.")
    }
}
