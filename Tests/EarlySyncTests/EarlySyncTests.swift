import XCTest
@testable import EarlySync

// MARK: - EarlyModels Tests

final class EarlyModelsTests: XCTestCase {

    // MARK: - TrackingEntry Decoding

    func testDecodeTrackingEntry_withFractionalSeconds() throws {
        let json = """
        {
            "id": 42,
            "activityId": 7,
            "activityName": "Deep Work",
            "startedAt": "2026-08-26T10:00:00.000",
            "note": {
                "text": "Working on EarlySync",
                "tags": [
                    {"id": 1, "key": "dev", "label": "Development", "color": "#FF0000"}
                ]
            }
        }
        """
        let entry = try decodeEntry(from: json)

        XCTAssertEqual(entry.id, 42)
        XCTAssertEqual(entry.activityId, 7)
        XCTAssertEqual(entry.activityName, "Deep Work")
        XCTAssertEqual(entry.note?.text, "Working on EarlySync")
        XCTAssertEqual(entry.note?.tags.count, 1)
        XCTAssertEqual(entry.note?.tags.first?.key, "dev")
        XCTAssertEqual(entry.note?.tags.first?.label, "Development")
    }

    func testDecodeTrackingEntry_noNote() throws {
        let json = """
        {
            "id": 1,
            "activityId": 2,
            "activityName": "Planning",
            "startedAt": "2026-08-26T09:00:00.000",
            "note": null
        }
        """
        let entry = try decodeEntry(from: json)
        XCTAssertNil(entry.note)
        XCTAssertEqual(entry.tagLabels, "")
    }

    // MARK: - Helper: matches Early's date format (no timezone suffix)
    private func decodeEntry(from json: String) throws -> TrackingEntry {
        let decoder = JSONDecoder()
        // Early API omits timezone: "2026-08-26T10:00:00.000" — no 'Z' or offset.
        // Use DateFormatter directly rather than ISO8601DateFormatter which requires a timezone.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        let fmtNoFrac = DateFormatter()
        fmtNoFrac.locale = Locale(identifier: "en_US_POSIX")
        fmtNoFrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fmt.date(from: string) { return date }
            if let date = fmtNoFrac.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(string)")
        }
        return try decoder.decode(TrackingEntry.self, from: Data(json.utf8))
    }

    // MARK: - TrackingState Equality

    func testTrackingStateEquality_bothIdle() {
        XCTAssertEqual(TrackingState.idle, TrackingState.idle)
    }

    func testTrackingStateEquality_differentActivities() {
        let entry1 = makeEntry(activityName: "Deep Work")
        let entry2 = makeEntry(activityName: "Meeting")
        XCTAssertNotEqual(TrackingState.tracking(entry: entry1), TrackingState.tracking(entry: entry2))
    }

    func testTrackingStateEquality_idleVsTracking() {
        let entry = makeEntry(activityName: "Deep Work")
        XCTAssertNotEqual(TrackingState.idle, TrackingState.tracking(entry: entry))
    }
}

// MARK: - ActivityMappingConfig Tests

final class ActivityMappingConfigTests: XCTestCase {

    func testMatchDeepWork() {
        let config = ActivityMappingConfig.defaults
        let entry = makeEntry(activityName: "Deep Work Session")

        let match = config.match(for: entry)

        XCTAssertNotNil(match)
        XCTAssertEqual(match?.luxaforColor, .red)
        XCTAssertEqual(match?.enableFocus, true)
        XCTAssertEqual(match?.focusProfileName, "Work")
    }

    func testMatchMeeting() {
        let config = ActivityMappingConfig.defaults
        let entry = makeEntry(activityName: "1:1 with Manager")

        let match = config.match(for: entry)

        XCTAssertNotNil(match)
        XCTAssertEqual(match?.luxaforColor, .blue)
    }

    func testMatchBreak() {
        let config = ActivityMappingConfig.defaults
        let entry = makeEntry(activityName: "Lunch break")

        let match = config.match(for: entry)

        XCTAssertNotNil(match)
        XCTAssertEqual(match?.luxaforColor, .green)
        XCTAssertEqual(match?.enableFocus, false)
    }

    func testNoMatchReturnsNil() {
        let config = ActivityMappingConfig.defaults
        let entry = makeEntry(activityName: "Some random uncategorized thing")

        let match = config.match(for: entry)

        XCTAssertNil(match)
    }

    func testMatchIsCaseInsensitive() {
        let config = ActivityMappingConfig.defaults
        let entry = makeEntry(activityName: "DEEP WORK")

        let match = config.match(for: entry)

        XCTAssertNotNil(match)
        XCTAssertEqual(match?.luxaforColor, .red)
    }

    func testMatchCoding_roundTrip() throws {
        let config = ActivityMappingConfig.defaults
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(ActivityMappingConfig.self, from: data)

        XCTAssertEqual(decoded.mappings.count, config.mappings.count)
        XCTAssertEqual(decoded.mappings.first?.label, config.mappings.first?.label)
    }
}

// MARK: - LuxaforColor Tests

final class LuxaforColorTests: XCTestCase {

    func testHexColorValues() {
        XCTAssertEqual(LuxaforColor.red.hexColor, "FF0000")
        XCTAssertEqual(LuxaforColor.green.hexColor, "00FF00")
        XCTAssertEqual(LuxaforColor.off.hexColor, "000000")
    }

    func testAllCasesHaveDisplayName() {
        for color in LuxaforColor.allCases {
            XCTAssertFalse(color.displayName.isEmpty)
        }
    }

    func testCodingRoundTrip() throws {
        for color in LuxaforColor.allCases {
            let data = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(LuxaforColor.self, from: data)
            XCTAssertEqual(decoded, color)
        }
    }
}

// MARK: - EarlyAPIError Tests

final class EarlyAPIErrorTests: XCTestCase {

    func testErrorDescriptions_notEmpty() {
        let errors: [EarlyAPIError] = [
            .invalidCredentials, .unauthorized, .notTracking,
            .networkError("timeout"), .decodingError("bad json"), .unknown(500)
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty: \(error)")
        }
    }

    func testEquality() {
        XCTAssertEqual(EarlyAPIError.unauthorized, EarlyAPIError.unauthorized)
        XCTAssertEqual(EarlyAPIError.networkError("x"), EarlyAPIError.networkError("x"))
        XCTAssertNotEqual(EarlyAPIError.networkError("x"), EarlyAPIError.networkError("y"))
        XCTAssertNotEqual(EarlyAPIError.unauthorized, EarlyAPIError.invalidCredentials)
    }
}

// MARK: - TrackingEntry Display Helpers Tests

final class TrackingEntryDisplayTests: XCTestCase {

    func testDurationString_minutes() {
        // Entry started 45 minutes ago
        let entry = makeEntry(startedAt: Date().addingTimeInterval(-45 * 60))
        XCTAssertEqual(entry.durationString, "45m")
    }

    func testDurationString_hoursAndMinutes() {
        // Entry started 1h 23m ago
        let entry = makeEntry(startedAt: Date().addingTimeInterval(-(3600 + 23 * 60)))
        XCTAssertEqual(entry.durationString, "1h 23m")
    }

    func testTagLabels_withTags() {
        let entry = makeEntry(tags: [
            TrackingTag(id: 1, key: "dev", label: "Development"),
            TrackingTag(id: 2, key: "pm", label: "Project Management"),
        ])
        XCTAssertEqual(entry.tagLabels, "Development, Project Management")
    }

    func testTagLabels_noTags() {
        let entry = makeEntry()
        XCTAssertEqual(entry.tagLabels, "")
    }
}

// MARK: - Helpers

func makeEntry(
    id: Int = 1,
    activityId: Int = 1,
    activityName: String = "Deep Work",
    startedAt: Date = Date(),
    tags: [TrackingTag] = []
) -> TrackingEntry {
    TrackingEntry(
        id: id,
        activityId: activityId,
        activityName: activityName,
        startedAt: startedAt,
        note: tags.isEmpty ? nil : TrackingNote(text: nil, tags: tags)
    )
}
