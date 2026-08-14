import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import CalendarPlugin

final class CalendarHolidayProviderTests: XCTestCase {
    func testDecodesSupportedHolidayKindsAndIgnoresUnknownDates() throws {
        let calendar = Self.makeCalendar()
        let provider = try CalendarHolidayProvider(
            data: #"{"2026":{"0101":2,"0104":1,"0201":9}}"#.data(using: .utf8)!
        )

        XCTAssertEqual(
            provider.kind(for: try Self.date(year: 2026, month: 1, day: 1, calendar: calendar), calendar: calendar),
            .holiday
        )
        XCTAssertEqual(
            provider.kind(for: try Self.date(year: 2026, month: 1, day: 4, calendar: calendar), calendar: calendar),
            .workday
        )
        XCTAssertNil(provider.kind(for: try Self.date(year: 2026, month: 2, day: 1, calendar: calendar), calendar: calendar))
        XCTAssertNil(provider.kind(for: try Self.date(year: 2027, month: 1, day: 1, calendar: calendar), calendar: calendar))
    }

    @MainActor
    func testBundledProviderReadsFromPluginResourceContext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let resourcesDirectory = directory.appendingPathComponent("CalendarPluginResources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
        try #"{"2026":{"0501":2}}"#.write(
            to: resourcesDirectory.appendingPathComponent("ChinaHolidayOverrides.json"),
            atomically: true,
            encoding: .utf8
        )
        let bundle = try XCTUnwrap(Bundle(url: directory))
        let provider = CalendarHolidayProvider.bundled(
            context: PluginRuntimeContext(
                pluginID: "calendar",
                resourceBundle: bundle,
                resourceSubdirectory: "CalendarPluginResources"
            )
        )
        let calendar = Self.makeCalendar()

        XCTAssertEqual(
            provider.kind(for: try Self.date(year: 2026, month: 5, day: 1, calendar: calendar), calendar: calendar),
            .holiday
        )
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
