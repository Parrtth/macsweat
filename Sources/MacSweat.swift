import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var snapshotDirectory: URL?
    private let model = MonitorModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var currentSymbol = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedAtLogin = Self.launchedAsLoginItem()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("MacSweat")
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        popover.contentSize = NSSize(width: 500, height: 700)
        model.onChange = { [weak self] in self?.refreshStatusItem() }
        refreshStatusItem()
        model.start()

        if !launchedAtLogin || snapshotDirectory != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showPopover() }
        }
        if let directory = snapshotDirectory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                self.writeSnapshots(to: directory)
                NSApp.terminate(nil)
            }
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it's running shows the popover.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func popoverDidShow(_ notification: Notification) {
        model.setVisible(true)
        model.refreshLoginStatus()
    }
    func popoverDidClose(_ notification: Notification) { model.setVisible(false) }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showStatusMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    @objc private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        Actions.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show MacSweat", action: #selector(showPopover), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacSweat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func openActivityMonitor() { Actions.openActivityMonitor() }
    @objc private func checkForUpdates() { Actions.checkForUpdates() }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let summary = Summary.make(system: model.system, scan: model.scan)
        let symbol = summary.severity == .strained ? summary.symbol : Brand.symbol
        if symbol != currentSymbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MacSweat")
                ?? NSImage(systemSymbolName: Brand.symbol, accessibilityDescription: "MacSweat")
            image?.isTemplate = true
            button.image = image
            currentSymbol = symbol
        }
        button.contentTintColor = summary.severity == .strained ? .systemRed : nil
        // Pad with figure spaces so the menu bar doesn't shift as the number changes.
        let digits = model.system?.cpu.map { String(format: "%.0f", $0) } ?? "–"
        button.title = " " + String(repeating: "\u{2007}", count: max(0, 3 - digits.count)) + digits + "%"
        if let system = model.system {
            button.toolTip = "\(summary.headline)\nCPU \(digits)% · Memory \(memoryLabel(system.usedMemory)) of \(memoryLabel(system.totalMemory)) · Pressure \(system.pressure.label) · Heat \(system.thermal.label)"
        }
    }

    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// `--snapshot DIR` renders the live popover and menu bar item to PNGs for checking the UI.
    private func writeSnapshots(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func write(_ view: NSView, _ name: String) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
        }
        // The popover itself is translucent, so render the same view on an opaque window background.
        let host = NSHostingView(rootView: PanelView(model: model).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        write(host, "popover.png")
        if let button = statusItem.button { write(button, "statusitem.png") }
        let popoverWindow = popover.contentViewController?.view.window
        let info = [
            "statusItemWindow=\(statusItem.button?.window?.windowNumber ?? -1)",
            "statusItemFrame=\(NSStringFromRect(statusItem.button?.window?.frame ?? .zero))",
            "popoverWindow=\(popoverWindow?.windowNumber ?? -1)",
            "popoverFrame=\(NSStringFromRect(popoverWindow?.frame ?? .zero))",
            "popoverShown=\(popover.isShown)",
            "statusTitle=\(statusItem.button?.title ?? "")",
        ]
        try? info.joined(separator: "\n").write(to: directory.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)
    }
}

/// `--check` prints a plain-text reading for comparing against Activity Monitor or `top`.
enum Diagnostics {
    static func check() -> Int32 {
        let monitor = SystemMonitor()
        _ = monitor.sampleSystem()
        _ = monitor.scanProcesses()
        Thread.sleep(forTimeInterval: 3)
        let system = monitor.sampleSystem()
        let scan = monitor.scanProcesses()
        guard let cpu = system.cpu, (0...100).contains(cpu), scan.error == nil, scan.cpuMeasured, !scan.groups.isEmpty,
              system.usedMemory > 0, system.usedMemory <= system.totalMemory else {
            fputs("FAIL: \(scan.error ?? "unable to collect valid system counters")\n", stderr)
            return 1
        }
        let summary = Summary.make(system: system, scan: scan)
        print("PASS: CPU \(String(format: "%.1f", cpu))% · memory \(memoryLabel(system.usedMemory)) of \(memoryLabel(system.totalMemory)) · pressure \(system.pressure.label) · swap \(system.swapUsed.map(memoryLabel) ?? "?") · heat \(system.thermal.label) · \(scan.groups.count) groups")
        print("Verdict: \(summary.headline) — \(summary.detail)")
        func line(_ app: AppUsage) -> String {
            let pad = app.name.padding(toLength: 34, withPad: " ", startingAt: 0)
            var extra = "\(app.kind) ×\(app.pids.count)"
            if let folder = app.folder { extra += " \(abbreviatedPath(folder))" }
            if let by = app.launchedBy { extra += " by \(by)" }
            if let time = app.runningFor, app.kind == .task { extra += " up \(durationLabel(time))" }
            if app.canQuit { extra += " [quit]" }
            if app.canStop { extra += " [stop]" }
            return "  \(pad) \(String(format: "%7.1f%%", app.cpu))  \(memoryLabel(app.memory).padding(toLength: 10, withPad: " ", startingAt: 0)) \(extra)"
        }
        print("Top CPU:")
        scan.groups.sorted { $0.cpu > $1.cpu }.prefix(10).forEach { print(line($0)) }
        print("Top memory:")
        scan.groups.sorted { $0.memory > $1.memory }.prefix(10).forEach { print(line($0)) }
        print("Background tasks:")
        scan.groups.filter { $0.kind == .task }.sorted { $0.memory > $1.memory }.forEach { print(line($0)) }
        if CommandLine.arguments.contains("--pids") {
            print("PIDS:")
            for app in scan.groups { for p in app.processes { print("\(p.pid)\t\(String(format: "%.1f", p.cpu))\t\(p.memory)\t\(app.name)") } }
        }
        return 0
    }
}

/// `--login-item on|off|status`: the same switch as "Open at Login" in the ⋯ menu, for scripts.
/// macOS registers the app that runs this, so run it from the copy in /Applications.
enum LoginItem {
    static func run(_ command: String) -> Int32 {
        let service = SMAppService.mainApp
        do {
            switch command {
            case "on": try service.register()
            case "off": try service.unregister()
            case "status": break
            default:
                fputs("usage: MacSweat --login-item on|off|status\n", stderr)
                return 2
            }
        } catch {
            fputs("Couldn’t change Open at Login: \(error.localizedDescription)\n", stderr)
            return 1
        }
        let status = switch service.status {
        case .enabled: "on"
        case .notRegistered: "off"
        case .requiresApproval: "needs approval in System Settings ▸ General ▸ Login Items"
        case .notFound: "not found"
        @unknown default: "unknown"
        }
        print("Open at Login: \(status) (\(Bundle.main.bundlePath))")
        return 0
    }
}

@main
struct MacSweatMain {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--check") { exit(Diagnostics.check()) }
        if let index = arguments.firstIndex(of: "--login-item") {
            exit(LoginItem.run(index + 1 < arguments.count ? arguments[index + 1] : "status"))
        }
        Actions.demoMode = arguments.contains("--demo")
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            delegate.snapshotDirectory = URL(fileURLWithPath: arguments[index + 1])
        }
        if arguments.contains("--dark") { application.appearance = NSAppearance(named: .darkAqua) }
        if arguments.contains("--light") { application.appearance = NSAppearance(named: .aqua) }
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
