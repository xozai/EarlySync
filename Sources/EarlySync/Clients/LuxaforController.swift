import Foundation

// MARK: - LuxaforColorSetting

/// Common interface for anything that can drive the Luxafor light, so
/// `LuxaforController` and tests can substitute the webhook client, the HID
/// client, or a mock without caring which.
protocol LuxaforColorSetting: Sendable {
    @discardableResult func setColor(_ color: LuxaforColor) async -> Bool
    @discardableResult func off() async -> Bool
}

extension LuxaforWebhookClient: LuxaforColorSetting {}
extension LuxaforHIDClient: LuxaforColorSetting {}

// MARK: - LuxaforController

/// Routes Luxafor color changes to USB/HID or the cloud webhook depending on
/// the configured `LuxaforTransport`, falling back to the webhook if USB is
/// selected but no device is found (or the write fails).
public actor LuxaforController: LuxaforColorSetting {

    private let hidClient: LuxaforColorSetting
    private let webhookClient: LuxaforColorSetting
    private let transportProvider: @Sendable () -> LuxaforTransport

    init(
        hidClient: LuxaforColorSetting = LuxaforHIDClient(),
        webhookClient: LuxaforColorSetting = LuxaforWebhookClient(),
        transportProvider: @escaping @Sendable () -> LuxaforTransport
    ) {
        self.hidClient = hidClient
        self.webhookClient = webhookClient
        self.transportProvider = transportProvider
    }

    @discardableResult
    public func setColor(_ color: LuxaforColor) async -> Bool {
        switch transportProvider() {
        case .webhook:
            return await webhookClient.setColor(color)
        case .usb:
            if await hidClient.setColor(color) { return true }
            return await webhookClient.setColor(color)
        }
    }

    @discardableResult
    public func off() async -> Bool {
        switch transportProvider() {
        case .webhook:
            return await webhookClient.off()
        case .usb:
            if await hidClient.off() { return true }
            return await webhookClient.off()
        }
    }
}
