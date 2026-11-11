import AppKit
import ConversionCore
import Foundation
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let registry: EngineRegistry
    private let dragMonitor: DragMonitor
    private var loginItem: NSMenuItem?
    private var celebrationItem: NSMenuItem?

    override init() {
        let registry = EngineRegistry.local()
        self.registry = registry
        dragMonitor = DragMonitor(registry: registry)
        super.init()
    }

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
            button.toolTip = "OpenLorikeet"
        }

        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "OpenLorikeet", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let status = NSMenuItem(title: "Shift-drag to convert · Command-drag for PDF tools", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let convert = NSMenuItem(title: "Convert Files…", action: #selector(pickFiles), keyEquivalent: "")
        convert.target = self
        menu.addItem(convert)
        let engines = NSMenuItem(title: "Conversion engines", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu()
        for engine in registry.engineStatuses {
            let name: String
            switch engine.availability {
            case .ready: name = "\(engine.name) · Available"
            case .unavailable(let reason): name = "\(engine.name) · \(reason)"
            }
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.isEnabled = false
            engineMenu.addItem(item)
        }
        engines.submenu = engineMenu
        menu.addItem(engines)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginItem = login
        let celebration = NSMenuItem(title: "Feather celebrations", action: #selector(toggleCelebrations), keyEquivalent: "")
        celebration.target = self
        menu.addItem(celebration)
        celebrationItem = celebration
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit OpenLorikeet", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let status = SMAppService.mainApp.status
        loginItem?.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginItem?.title = status == .requiresApproval ? "Launch at login (approval pending)" : "Launch at login"
        celebrationItem?.state = UserDefaults.standard.object(forKey: "FeatherCelebrations") as? Bool != false ? .on : .off
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func toggleCelebrations() {
        let enabled = UserDefaults.standard.object(forKey: "FeatherCelebrations") as? Bool != false
        UserDefaults.standard.set(!enabled, forKey: "FeatherCelebrations")
    }

    @objc private func pickFiles() {
        NSApp.activate()
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.prompt = "Choose"
        guard picker.runModal() == .OK else { return }
        let choices = (registry.choices(for: picker.urls) + registry.pdfTools(for: picker.urls))
            .reduce(into: [ConversionChoice]()) { list, choice in
                if !list.contains(choice) { list.append(choice) }
            }
        let alert = NSAlert()
        guard !choices.isEmpty else {
            alert.messageText = "No shared conversion is available"
            alert.informativeText = "Choose supported files with a common output or check Conversion engines in the menu bar."
            alert.runModal()
            return
        }
        alert.messageText = "Choose a conversion or tool"
        alert.informativeText = picker.urls.count == 1 ? picker.urls[0].lastPathComponent : "\(picker.urls.count) files selected"
        let formats = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        formats.addItems(withTitles: choices.map(\.label))
        formats.setAccessibilityLabel("Output format or tool")
        alert.accessoryView = formats
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, choices.indices.contains(formats.indexOfSelectedItem) else { return }
        var session = PickerSession(sources: picker.urls, choices: choices)
        do {
            if let requests = try session.select(choices[formats.indexOfSelectedItem], droppedURLs: picker.urls) {
                dragMonitor.submit(requests)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
