import XCTest
@testable import EarlySync

// MARK: - ActivityMappingStoreTests

final class ActivityMappingStoreTests: XCTestCase {

    private var tempURL: URL!
    private var store: ActivityMappingStore!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EarlySyncTests-\(UUID().uuidString).json")
        store = ActivityMappingStore(fileURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testLoad_missingFile_returnsDefaults() {
        XCTAssertEqual(store.load().mappings.count, ActivityMappingConfig.defaults.mappings.count)
    }

    func testSaveThenLoad_roundTrips() {
        var config = ActivityMappingConfig.defaults
        config.transport = .usb
        store.save(config)

        XCTAssertEqual(store.load().transport, .usb)
    }

    /// Regression test for issue #17: HoneyX found that the transport picker's
    /// binding called `appState.saveMapping()`, which round-trips the entire
    /// in-memory `mappingConfig` — silently persisting any unsaved draft edits
    /// held elsewhere (e.g. added-but-not-yet-saved rows on the Activity
    /// Mapping tab). `updateTransport(_:)` fixes this by reading fresh from
    /// disk and touching only the `transport` field, ignoring whatever's
    /// sitting unsaved in memory.
    func testUpdateTransport_doesNotPersistUnrelatedInMemoryDraftEdits() {
        // Disk starts with one saved mapping.
        let savedMapping = ActivityMapping(
            activityNameContains: ["saved"],
            luxaforColor: .red,
            focusProfileName: nil,
            enableFocus: false,
            label: "Saved Row"
        )
        store.save(ActivityMappingConfig(mappings: [savedMapping], transport: .webhook))

        // Simulate an in-progress, unsaved edit elsewhere in the app: load a
        // config into memory and append a draft row, but never call save().
        var inMemory = store.load()
        inMemory.mappings.append(
            ActivityMapping(
                activityNameContains: ["draft"],
                luxaforColor: .blue,
                focusProfileName: nil,
                enableFocus: false,
                label: "Unsaved Draft Row"
            )
        )
        // (inMemory is intentionally never saved here — exactly what
        // AppState.setTransport must not do.)

        store.updateTransport(.usb)

        let onDisk = store.load()
        XCTAssertEqual(onDisk.transport, .usb, "transport change should persist")
        XCTAssertEqual(onDisk.mappings.count, 1, "the unsaved draft row must not have been written to disk")
        XCTAssertEqual(onDisk.mappings.first?.label, "Saved Row")
    }
}
