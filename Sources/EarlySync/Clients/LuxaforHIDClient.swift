import Foundation
import IOKit
import IOKit.hid

// MARK: - LuxaforHIDClient

/// Controls a Luxafor light directly over USB HID, for offline use when the
/// cloud webhook API is unavailable. Falls back silently (returns `false`) if
/// no matching device is plugged in — `LuxaforController` handles the actual
/// fallback to the webhook client.
///
/// IMPORTANT — unverified against real hardware: this repo/CI has no
/// physical Luxafor device attached. The report byte layout below follows
/// the format documented by pyluxa4 and used by LuxaforPresence (both linked
/// from issue #5); `reportBytes(for:)` is unit-tested for correctness of the
/// *encoding*, but the actual `IOHIDDeviceSetReport` write path has only been
/// exercised in code review, not against a device. Treat as needing a manual
/// hardware smoke test before relying on it.
public actor LuxaforHIDClient {

    /// Luxafor Flag vendor/product ID, per issue #5.
    static let vendorID: Int32 = 0x04D8
    static let productID: Int32 = 0xF372

    public init() {}

    // MARK: - Public Interface

    @discardableResult
    public func setColor(_ color: LuxaforColor) async -> Bool {
        Self.performWrite(Self.reportBytes(for: color))
    }

    @discardableResult
    public func off() async -> Bool {
        await setColor(.off)
    }

    // MARK: - Report Encoding (pure, unit-testable)

    /// Solid-color output report: `[reportId, mode=1 (static color), R, G, B, 0, 0, 0]`.
    static func reportBytes(for color: LuxaforColor) -> [UInt8] {
        let (r, g, b) = rgbComponents(fromHex: color.hexColor)
        return [0x00, 0x01, r, g, b, 0x00, 0x00, 0x00]
    }

    static func rgbComponents(fromHex hex: String) -> (UInt8, UInt8, UInt8) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = UInt8((value & 0xFF0000) >> 16)
        let g = UInt8((value & 0x00FF00) >> 8)
        let b = UInt8(value & 0x0000FF)
        return (r, g, b)
    }

    // MARK: - IOKit (not unit-testable without hardware)

    private static func performWrite(_ bytes: [UInt8]) -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return false
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first
        else {
            return false
        }

        let reportId = CFIndex(bytes[0])
        let result = bytes.withUnsafeBufferPointer { buffer -> IOReturn in
            guard let baseAddress = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportId, baseAddress, buffer.count)
        }
        return result == kIOReturnSuccess
    }
}
