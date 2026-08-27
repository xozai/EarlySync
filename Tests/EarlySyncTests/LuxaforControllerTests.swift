import XCTest
@testable import EarlySync

// MARK: - MockColorSetting

private actor MockColorSetting: LuxaforColorSetting {
    private(set) var setColorCalls: [LuxaforColor] = []
    private(set) var offCallCount = 0
    var setColorResult = true
    var offResult = true

    func setColor(_ color: LuxaforColor) async -> Bool {
        setColorCalls.append(color)
        return setColorResult
    }

    func off() async -> Bool {
        offCallCount += 1
        return offResult
    }
}

// MARK: - LuxaforControllerTests

final class LuxaforControllerTests: XCTestCase {

    func testWebhookTransport_goesStraightToWebhook_neverTouchesHID() async {
        let hid = MockColorSetting()
        let webhook = MockColorSetting()
        let controller = LuxaforController(hidClient: hid, webhookClient: webhook, transportProvider: { .webhook })

        let result = await controller.setColor(.red)

        XCTAssertTrue(result)
        let hidCalls = await hid.setColorCalls
        let webhookCalls = await webhook.setColorCalls
        XCTAssertEqual(hidCalls, [])
        XCTAssertEqual(webhookCalls, [.red])
    }

    func testUsbTransport_hidSucceeds_neverFallsBackToWebhook() async {
        let hid = MockColorSetting()
        let webhook = MockColorSetting()
        let controller = LuxaforController(hidClient: hid, webhookClient: webhook, transportProvider: { .usb })

        let result = await controller.setColor(.blue)

        XCTAssertTrue(result)
        let hidCalls = await hid.setColorCalls
        let webhookCalls = await webhook.setColorCalls
        XCTAssertEqual(hidCalls, [.blue])
        XCTAssertEqual(webhookCalls, [])
    }

    func testUsbTransport_hidFails_fallsBackToWebhook() async {
        let hid = MockColorSetting()
        await hid.setSetColorResult(false)
        let webhook = MockColorSetting()
        let controller = LuxaforController(hidClient: hid, webhookClient: webhook, transportProvider: { .usb })

        let result = await controller.setColor(.green)

        XCTAssertTrue(result)
        let hidCalls = await hid.setColorCalls
        let webhookCalls = await webhook.setColorCalls
        XCTAssertEqual(hidCalls, [.green])
        XCTAssertEqual(webhookCalls, [.green])
    }

    func testUsbTransport_bothFail_reportsFailure() async {
        let hid = MockColorSetting()
        await hid.setSetColorResult(false)
        let webhook = MockColorSetting()
        await webhook.setSetColorResult(false)
        let controller = LuxaforController(hidClient: hid, webhookClient: webhook, transportProvider: { .usb })

        let result = await controller.setColor(.yellow)

        XCTAssertFalse(result)
    }

    func testOff_usbTransport_fallsBackLikeSetColor() async {
        let hid = MockColorSetting()
        await hid.setOffResult(false)
        let webhook = MockColorSetting()
        let controller = LuxaforController(hidClient: hid, webhookClient: webhook, transportProvider: { .usb })

        let result = await controller.off()

        XCTAssertTrue(result)
        let hidOffCount = await hid.offCallCount
        let webhookOffCount = await webhook.offCallCount
        XCTAssertEqual(hidOffCount, 1)
        XCTAssertEqual(webhookOffCount, 1)
    }
}

private extension MockColorSetting {
    func setSetColorResult(_ value: Bool) { setColorResult = value }
    func setOffResult(_ value: Bool) { offResult = value }
}
