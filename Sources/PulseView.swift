import AppKit
import SwiftUI

struct PulseView: View {
    @ObservedObject var model: MonitorModel
    @AppStorage("sortByMemory") private var sortByMemory = false
    @State private var showAllTasks = false

    private var groups: [AppUsage] { model.scan?.groups ?? [] }
    private var measured: Bool { model.scan?.cpuMeasured == true }
    private let cores = ProcessInfo.processInfo.activeProcessorCount

    private var tasks: [AppUsage] {
        groups.filter { $0.kind == .task }.sorted { $0.cpu == $1.cpu ? $0.memory > $1.memory : $0.cpu > $1.cpu }
    }

    private var others: [AppUsage] {
        groups.filter { $0.kind != .task }.sorted { a, b in
            if sortByMemory || !measured { return a.memory == b.memory ? a.name < b.name : a.memory > b.memory }
            return a.cpu == b.cpu ? a.memory > b.memory : a.cpu > b.cpu
        }
    }

    var body: some View {
        let summary = Summary.make(system: model.system, scan: model.scan)
        VStack(alignment: .leading, spacing: 14) {
            header(summary)
            tiles
            if let error = model.scan?.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
            }
            tasksSection
            appsSection
            footer
        }
        .padding(18)
        .frame(width: 500, height: 700)
    }

    private func header(_ summary: Summary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(summary.severity.color).frame(width: 10, height: 10).padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.headline).font(.title3.weight(.semibold))
                if !summary.detail.isEmpty {
                    Text(summary.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            moreMenu
        }
    }

    private var tiles: some View {
        let system = model.system
        let cpu = system?.cpu
        let swap = system?.swapUsed.map(memoryLabel) ?? "—"
        return HStack(spacing: 8) {
            Tile(title: "CPU", value: cpu.map { String(format: "%.0f%%", $0) } ?? "…", detail: "of \(cores) cores",
                 tone: (cpu ?? 0) >= 75 ? .critical : (cpu ?? 0) >= 40 ? .warning : .normal) {
                Sparkline(values: model.cpuHistory)
            }
            .help("Whole-Mac CPU use. The line shows the last few minutes.")
            Tile(title: "Memory", value: system.map { memoryLabel($0.usedMemory) } ?? "…",
                 detail: system.map { "of \(memoryLabel($0.totalMemory))" } ?? " ", tone: .normal)
                .help("Memory in use by apps, macOS and compression — the same figure as Activity Monitor.")
            Tile(title: "Pressure", value: system?.pressure.label ?? "…", detail: "swap \(swap)",
                 tone: system?.pressure == .high ? .critical : system?.pressure == .elevated ? .warning : .normal)
                .help("How hard macOS is working to fit everything in memory. High pressure makes everything slower.")
            Tile(title: "Heat", value: system?.thermal.label ?? "…", detail: "thermal state",
                 tone: thermalTone(system?.thermal))
                .help("macOS’s thermal state. When it’s Hot, macOS slows the processor down to cool off.")
        }
    }

    private func thermalTone(_ state: ProcessInfo.ThermalState?) -> Tone {
        switch state {
        case .serious?, .critical?: .critical
        case .fair?: .warning
        default: .normal
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Background tasks").font(.headline)
                Text("dev servers & scripts").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)
            if model.scan == nil {
                Text("Looking…").font(.callout).foregroundStyle(.secondary)
            } else if tasks.isEmpty {
                Text("None running.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                ForEach(tasks.prefix(showAllTasks ? tasks.count : 3)) { UsageRow(app: $0, measured: measured) }
                if tasks.count > 3 {
                    Button(showAllTasks ? "Show fewer" : "Show \(tasks.count - 3) more") { showAllTasks.toggle() }
                        .buttonStyle(.link).font(.caption).padding(.leading, 40)
                }
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Apps & processes").font(.headline)
                Spacer()
                Picker("Sort by", selection: $sortByMemory) {
                    Text("CPU").tag(false)
                    Text("Memory").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }
            HStack(spacing: 10) {
                Text("Helpers are grouped with their app")
                Spacer()
                Text("CPU").frame(width: 52, alignment: .trailing)
                    .help("100% = one full CPU core. This Mac has \(cores) cores.")
                Text("Memory").frame(width: 70, alignment: .trailing)
                Color.clear.frame(width: 46, height: 1)
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(others.prefix(30)) { UsageRow(app: $0, measured: measured) }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.shield").accessibilityHidden(true)
            Text("Stays on this Mac")
            if let time = model.system?.timestamp {
                Text("· Updated \(time.formatted(date: .omitted, time: .standard))").monospacedDigit()
            }
            Spacer()
            Button("Open Activity Monitor") { Actions.openActivityMonitor() }.buttonStyle(.link)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var moreMenu: some View {
        Menu {
            Button("Open Activity Monitor") { Actions.openActivityMonitor() }
            Button("Find Heavy Browser Tabs…") { Actions.showBrowserTabsHelp() }
            Divider()
            Toggle("Open at Login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
            Divider()
            Button("Quit Mac Pulse") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 16))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More options")
        .accessibilityLabel("More options")
    }
}

struct UsageRow: View {
    let app: AppUsage
    let measured: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(measured ? cpuLabel(app.cpu) : "—")
                .foregroundStyle(app.cpu >= 300 ? Color.red : app.cpu >= 100 ? Color.orange : Color.primary)
                .frame(width: 52, alignment: .trailing)
            Text((app.memoryEstimated && app.kind != .app ? "≈" : "") + memoryLabel(app.memory))
                .frame(width: 70, alignment: .trailing)
            action.frame(width: 46, alignment: .trailing)
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(tooltip)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        if let path = app.bundlePath {
            Image(nsImage: IconCache.shared.icon(for: path)).resizable().interpolation(.high)
        } else {
            let symbol = switch app.kind {
            case .task: "terminal"
            case .system: "gearshape"
            default: "app.dashed"
            }
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }

    private var action: some View {
        ZStack(alignment: .trailing) {
            Color.clear.frame(height: 1) // keeps the columns aligned on rows without a button
            if app.canQuit || app.canStop {
                Button(app.canQuit ? "Quit" : "Stop") { app.canQuit ? Actions.quit(app) : Actions.stop(app) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if app.canQuit { Button("Quit \(app.name)…") { Actions.quit(app) } }
        if app.canStop { Button("Stop \(app.name)…") { Actions.stop(app) } }
        if app.isBrowser { Button("Find Heavy Tabs…") { Actions.showBrowserTabsHelp() } }
        if let path = app.bundlePath { Button("Show in Finder") { Actions.reveal(path) } }
        if let folder = app.folder { Button("Show Project Folder") { Actions.reveal(folder) } }
        Button("Copy Process IDs") { Actions.copy(app.pids.map(String.init).joined(separator: " ")) }
        Divider()
        Button("Open Activity Monitor") { Actions.openActivityMonitor() }
    }

    private var processCount: String { "\(app.pids.count) process\(app.pids.count == 1 ? "" : "es")" }

    private var subtitle: String {
        switch app.kind {
        case .task:
            var parts: [String] = []
            if let folder = app.folder { parts.append((folder as NSString).lastPathComponent) }
            if let time = app.runningFor { parts.append("up \(durationLabel(time))") }
            parts.append(app.launchedBy.map { "started by \($0)" } ?? "running on its own")
            return parts.joined(separator: " · ")
        case .app:
            if app.isSelf { return "This app" }
            if app.isBrowser { return "Browser · \(processCount) · right-click for tabs" }
            return app.canQuit ? "App · \(processCount)" : "Runs in the background · \(processCount)"
        case .system:
            return app.hint ?? "Part of macOS"
        case .other:
            return app.hint ?? "Background process · \(processCount)"
        }
    }

    private var tooltip: String {
        var lines: [String] = []
        switch app.kind {
        case .app where app.isSelf:
            lines.append("Mac Pulse itself.")
        case .app:
            lines.append(app.canQuit ? "You can quit this app if you aren’t using it — hover and click Quit, or right-click."
                                     : "This app doesn’t have a normal Quit.")
            if app.isBrowser { lines.append("To see which tab is heavy: right-click → Find Heavy Tabs.") }
        case .task:
            if let folder = app.folder { lines.append("Folder: \(abbreviatedPath(folder))") }
            lines.append("A developer task left running. Stop it if you aren’t using it — usually from its terminal with Control-C, or with Stop here.")
        case .system:
            lines.append((app.hint.map { $0 + " " } ?? "") + "Part of macOS — usually best left alone.")
        case .other:
            lines.append("A background process that isn’t part of macOS. Check which app installed it before stopping it.")
        }
        let busiest = app.processes.prefix(5).map {
            "• \($0.name) (\($0.pid)) — \(measured ? cpuLabel($0.cpu) : "—") CPU, \(memoryLabel($0.memory))"
        }
        if !busiest.isEmpty { lines.append("\nBusiest processes:\n" + busiest.joined(separator: "\n")) }
        if app.memoryEstimated { lines.append("Memory for system processes is estimated from resident size.") }
        return lines.joined(separator: "\n")
    }
}

enum Tone {
    case normal, warning, critical

    var color: Color {
        switch self {
        case .normal: .primary
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct Tile<Accessory: View>: View {
    let title: String
    let value: String
    let detail: String
    let tone: Tone
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tone.color).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            accessory
        }
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

extension Tile where Accessory == EmptyView {
    init(title: String, value: String, detail: String, tone: Tone) {
        self.init(title: title, value: value, detail: detail, tone: tone) { EmptyView() }
    }
}

/// Whole-Mac CPU on a fixed 0–100% scale, so a flat line really means calm.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard values.count > 1 else { return }
                let step = geometry.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let y = geometry.size.height * (1 - CGFloat(min(max(value, 0), 100)) / 100)
                    let point = CGPoint(x: CGFloat(index) * step, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}

/// Everything here acts only after the person confirms, and only in ways they could do themselves.
enum Actions {
    static func quit(_ app: AppUsage) {
        guard let bundleID = app.bundleID else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty, confirm(
            title: "Quit \(app.name)?",
            message: "\(app.name) will quit normally, just like choosing Quit from its menu. If it has unsaved work, it will ask first.",
            button: "Quit \(app.name)") else { return }
        running.forEach { $0.terminate() }
    }

    static func stop(_ task: AppUsage) {
        let place = task.folder.map { " in \(abbreviatedPath($0))" } ?? ""
        let count = task.pids.count == 1 ? "its process" : "its \(task.pids.count) processes"
        guard confirm(title: "Stop \(task.name)\(place)?",
                      message: "Mac Pulse will send \(count) a normal stop signal, like pressing Control-C in its terminal.",
                      button: "Stop") else { return }
        // The row can be seconds old and the dialog may sit open, so only signal processes that are
        // still the same ones (same start time) — never a reused process ID.
        for (pid, started) in task.startTimes where SystemMonitor.startTime(of: pid) == started {
            kill(pid, SIGTERM)
        }
    }

    static func showBrowserTabsHelp() {
        inform("Find heavy browser tabs",
               "A browser shows up as one entry because it decides which tab runs in which process.\n\nChrome, Edge and Brave: choose Window ▸ Task Manager, then click “Memory footprint” to put the largest tabs first.\n\nSafari: open Activity Monitor — Safari’s tabs are listed by their web address.")
    }

    static func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func inform(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        activate()
        alert.runModal()
    }

    private static func confirm(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}
