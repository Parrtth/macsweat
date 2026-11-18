import AppKit
import ServiceManagement
import SwiftUI

/// Samples on a background queue and publishes snapshots on the main thread.
/// While the popover is closed only the cheap whole-Mac counters run often; the process list
/// is refreshed every few seconds while it's open and occasionally otherwise.
final class MonitorModel: ObservableObject {
    static let openInterval: TimeInterval = 3
    static let closedInterval: TimeInterval = 5
    static let closedScanInterval: TimeInterval = 30

    @Published private(set) var system: SystemReading?
    @Published private(set) var scan: ProcessScan?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var openAtLogin = SMAppService.mainApp.status == .enabled
    var onChange: (() -> Void)?

    private let monitor = SystemMonitor()
    private let queue = DispatchQueue(label: "MacPulse.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    // Only touched on `queue`.
    private var visible = false
    private var lastTick: TimeInterval = 0
    private var lastScan: TimeInterval = 0

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.schedule(deadline: .now() + 1.5, repeating: Self.closedInterval, leeway: .milliseconds(500))
        self.timer = timer
        queue.async { [weak self] in self?.tick() } // baseline for CPU deltas
        timer.resume()
    }

    func setVisible(_ isVisible: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.visible = isVisible
            let interval = isVisible ? Self.openInterval : Self.closedInterval
            let since = ProcessInfo.processInfo.systemUptime - self.lastTick
            let firstFire: TimeInterval
            if isVisible && since >= 1.5 {
                self.tick() // fresh numbers the moment the popover opens
                firstFire = interval
            } else if isVisible {
                firstFire = 1.5 - since // a CPU delta over less than ~1.5 s is too noisy to show
            } else {
                firstFire = interval - since // keep the cadence anchored to the last reading
            }
            self.timer?.schedule(deadline: .now() + max(0.5, firstFire), repeating: interval, leeway: .milliseconds(300))
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        lastTick = now
        let system = monitor.sampleSystem()
        var scan: ProcessScan?
        if lastScan == 0 || (visible && now - lastScan >= 0.9) || now - lastScan >= Self.closedScanInterval {
            scan = monitor.scanProcesses()
            lastScan = now
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.system = system
            if let cpu = system.cpu { self.cpuHistory = Array((self.cpuHistory + [cpu]).suffix(60)) }
            if let scan { self.scan = scan }
            self.onChange?()
        }
    }

    /// Re-read on every open: the setting can also be changed in System Settings ▸ Login Items.
    func refreshLoginStatus() {
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Actions.inform("Couldn’t change Open at Login", error.localizedDescription)
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum Severity {
    case calm, busy, strained

    var color: Color {
        switch self {
        case .calm: .green
        case .busy: .orange
        case .strained: .red
        }
    }
}

/// The one-glance verdict shown at the top of the popover and in the menu bar.
struct Summary {
    let severity: Severity
    let headline: String
    let detail: String
    let symbol: String

    static func make(system: SystemReading?, scan: ProcessScan?) -> Summary {
        guard let system else {
            return Summary(severity: .calm, headline: "Taking the first reading…", detail: "", symbol: "waveform.path.ecg")
        }
        let groups = scan?.groups ?? []
        let topCPU = scan?.cpuMeasured == true ? groups.max { $0.cpu < $1.cpu } : nil
        let topMemory = groups.max { $0.memory < $1.memory }
        let cpuNote = topCPU.flatMap { $0.cpu >= 20 ? "\($0.name) is using the most CPU (\(cpuLabel($0.cpu)))." : nil }
        let memoryNote = topMemory.map { "\($0.name) is using the most memory (\(memoryLabel($0.memory)))." }
        let cpu = system.cpu ?? 0
        func join(_ parts: String?...) -> String { parts.compactMap { $0 }.joined(separator: " ") }

        if system.thermal == .serious || system.thermal == .critical {
            return Summary(severity: .strained, headline: "Your Mac is running hot",
                           detail: join(cpuNote ?? "macOS is slowing things down to cool off.", memoryNote),
                           symbol: "thermometer.high")
        }
        if system.pressure == .high {
            return Summary(severity: .strained, headline: "Your Mac is short on memory",
                           detail: join(memoryNote, "Quitting apps you aren’t using frees it up."), symbol: "memorychip")
        }
        if cpu >= 75 {
            return Summary(severity: .strained, headline: "Your Mac is working hard", detail: join(cpuNote, memoryNote),
                           symbol: "flame")
        }
        if cpu >= 40 {
            return Summary(severity: .busy, headline: "Your Mac is fairly busy", detail: join(cpuNote, memoryNote),
                           symbol: "waveform.path.ecg")
        }
        if system.pressure == .elevated {
            return Summary(severity: .busy, headline: "Memory is getting full",
                           detail: join(memoryNote, "Quitting an app you aren’t using will help."), symbol: "memorychip")
        }
        if system.thermal == .fair {
            return Summary(severity: .busy, headline: "Your Mac is a little warm", detail: join(cpuNote, memoryNote),
                           symbol: "thermometer.medium")
        }
        return Summary(severity: .calm, headline: "Your Mac is taking it easy",
                       detail: join(cpuNote ?? "Nothing is using much CPU.", memoryNote), symbol: "waveform.path.ecg")
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        @unknown default: "Unknown"
        }
    }
}

func memoryLabel(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}

func cpuLabel(_ percent: Double) -> String {
    percent >= 9.95 ? String(format: "%.0f%%", percent) : String(format: "%.1f%%", percent)
}

func durationLabel(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 1 { return "<1m" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d \(hours % 24)h"
}

func abbreviatedPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home { return "~" }
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}
