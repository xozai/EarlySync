import AppKit
import Foundation

// MARK: - ShortcutRunning

/// Abstraction over invoking the `shortcuts` CLI, so tests can substitute a
/// mock without spawning a real process or depending on Shortcuts.app state.
protocol ShortcutRunning {
    func run(_ shortcutName: String, timeout: TimeInterval) async throws
    func list(timeout: TimeInterval) async throws -> [String]
}

// MARK: - ProcessShortcutRunner

/// Runs shortcuts via `/usr/bin/shortcuts`.
struct ProcessShortcutRunner: ShortcutRunning {

    func run(_ shortcutName: String, timeout: TimeInterval) async throws {
        _ = try await execute(arguments: ["run", shortcutName], timeout: timeout)
    }

    func list(timeout: TimeInterval) async throws -> [String] {
        let output = try await execute(arguments: ["list"], timeout: timeout)
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func execute(arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            let box = ResumeBox(continuation: continuation)

            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                box.resume(.failure(FocusManagerError.timedOut))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            process.terminationHandler = { proc in
                timeoutWorkItem.cancel()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    box.resume(.success(output))
                } else {
                    box.resume(.failure(FocusManagerError.shortcutFailed(proc.terminationStatus)))
                }
            }

            do {
                try process.run()
            } catch {
                timeoutWorkItem.cancel()
                box.resume(.failure(error))
            }
        }
    }
}

// MARK: - ResumeBox

/// Guards a `CheckedContinuation` so it resumes exactly once even though the
/// timeout and termination handler race on different queues.
private final class ResumeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

// MARK: - FocusManagerError

enum FocusManagerError: Error, Equatable {
    case shortcutFailed(Int32)
    case timedOut
}

// MARK: - FocusManager

/// Activates and deactivates macOS Focus profiles by running user-configured
/// Apple Shortcuts. There is no public API to set (or read) Focus mode
/// directly, so `shortcuts run "<name>"` via `Process` is the only reliable
/// cross-version approach.
public final class FocusManager {

    public static let focusOnShortcutName = "EarlySync: Focus On"
    public static let focusOffShortcutName = "EarlySync: Focus Off"

    private let runner: ShortcutRunning
    private let timeout: TimeInterval

    init(runner: ShortcutRunning = ProcessShortcutRunner(), timeout: TimeInterval = 5.0) {
        self.runner = runner
        self.timeout = timeout
    }

    // MARK: - Public Interface

    /// Activates a Focus profile. `profile` names a per-activity shortcut
    /// ("EarlySync: <profile>"); pass `nil` to run the default
    /// "EarlySync: Focus On" shortcut.
    ///
    /// Runs on a background task and never throws — a failed Shortcuts call
    /// is logged and ignored so the Luxafor light keeps working regardless.
    /// - Returns: `true` if the shortcut ran successfully.
    @discardableResult
    public func enableFocus(profile: String? = nil) async -> Bool {
        let name = profile.map { "EarlySync: \($0)" } ?? Self.focusOnShortcutName
        return await runShortcut(name)
    }

    /// Deactivates Focus by running "EarlySync: Focus Off".
    @discardableResult
    public func disableFocus() async -> Bool {
        await runShortcut(Self.focusOffShortcutName)
    }

    /// Best-effort check for whether a shortcut with the given name exists.
    /// Returns `false` (rather than throwing) if `shortcuts list` itself fails.
    public func isShortcutConfigured(_ name: String = FocusManager.focusOnShortcutName) async -> Bool {
        guard let names = try? await runner.list(timeout: timeout) else { return false }
        return names.contains(name)
    }

    /// Opens Shortcuts.app so the user can create the required shortcuts.
    public func openShortcutsSetupGuide() {
        if let url = URL(string: "shortcuts://") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    @discardableResult
    private func runShortcut(_ name: String) async -> Bool {
        do {
            try await runner.run(name, timeout: timeout)
            return true
        } catch {
            print("[FocusManager] Failed to run shortcut \"\(name)\": \(error) — Luxafor still works")
            return false
        }
    }
}
