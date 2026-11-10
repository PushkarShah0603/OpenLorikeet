import AppKit
import ConversionCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let dragMonitor = DragMonitor(registry: .local())

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        // Exercise the real launch path without opening a window or touching files.
        if CommandLine.arguments.contains("--smoke-test") {
            let passed = NSApp.activationPolicy() == .accessory
                && NSApp.windows.isEmpty
                && statusItem != nil
            print(passed ? "PASS: background launch; no windows; status item ready"
                         : "FAIL: background launch requirements not met")
            fflush(stdout)
            if !passed { exit(EXIT_FAILURE) }
            NSApp.terminate(nil)
        } else {
            dragMonitor.start()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        dragMonitor.stop()
        Task {
            await dragMonitor.cancelJobsAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragMonitor.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "OpenLorikeet")
            image?.isTemplate = true
            button.image = image
            if image == nil { button.title = "OL" }
            button.toolTip = "OpenLorikeet — conversion engine foundation"
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: "OpenLorikeet", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let status = NSMenuItem(title: "Shift-drag a file to convert", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit OpenLorikeet", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
