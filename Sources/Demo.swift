import Foundation

/// Made-up readings for `--demo`, used for website screenshots so no real apps or folders appear.
enum DemoData {
    private static func gb(_ value: Double) -> UInt64 { UInt64(value * 1_073_741_824) }
    private static func mb(_ value: Double) -> UInt64 { UInt64(value * 1_048_576) }

    static let system = SystemReading(cpu: 78, usedMemory: gb(14.2), totalMemory: gb(16), swapUsed: gb(1.3),
                                      pressure: .elevated, thermal: .fair, timestamp: Date())

    static let history: [Double] = [12, 14, 11, 13, 18, 22, 19, 25, 31, 28, 36, 44, 41, 52, 58, 55, 63, 69, 66, 72, 75, 71, 78, 80, 76, 78]

    static var scan: ProcessScan {
        ProcessScan(groups: [
            task("Next.js dev server", folder: "storefront", by: "Terminal", up: 3 * 3600 + 12 * 60, cpu: 386, memory: gb(4.1), count: 7),
            task("Python", folder: "price-scraper", by: nil, up: 2 * 86_400 + 4 * 3600, cpu: 0.4, memory: mb(212), count: 1),
            app("Google Chrome", "/Applications/Google Chrome.app", id: "com.google.Chrome", cpu: 64, memory: gb(3.4), count: 27),
            system("Spotlight indexing", hint: "Indexing files for search. Settles down on its own.", cpu: 48, memory: mb(96)),
            system("WindowServer", hint: "Draws the screen. Busier with many windows, displays or animations.", cpu: 31, memory: mb(412)),
            app("Mail", "/System/Applications/Mail.app", id: "com.apple.mail", cpu: 12, memory: gb(1.2), count: 9),
            app("Music", "/System/Applications/Music.app", id: "com.apple.Music", cpu: 6.2, memory: mb(420), count: 3),
            app("Messages", "/System/Applications/Messages.app", id: "com.apple.MobileSMS", cpu: 1.4, memory: mb(310), count: 4),
            system("iCloud sync", hint: "Syncing with iCloud. Settles once syncing finishes.", cpu: 3.1, memory: mb(38)),
            app("Terminal", "/System/Applications/Utilities/Terminal.app", id: "com.apple.Terminal", cpu: 2.2, memory: mb(128), count: 2),
        ], cpuMeasured: true, timestamp: Date(), error: nil)
    }

    private static func task(_ name: String, folder: String, by app: String?, up: TimeInterval, cpu: Double,
                             memory: UInt64, count: Int) -> AppUsage {
        AppUsage(id: "demo|" + name, name: name, kind: .task, bundlePath: nil, bundleID: nil,
                 folder: "/Users/you/Projects/" + folder, launchedBy: app, runningFor: up, hint: nil,
                 pids: Array(1...Int32(count)), cpu: cpu, memory: memory, memoryEstimated: false,
                 processes: [ProcessLine(pid: 1, name: "node", cpu: cpu, memory: memory)], canQuit: false, canStop: true,
                 startTimes: [:])
    }

    private static func app(_ name: String, _ path: String, id: String, cpu: Double, memory: UInt64, count: Int) -> AppUsage {
        AppUsage(id: "demo|" + name, name: name, kind: .app, bundlePath: path, bundleID: id, folder: nil, launchedBy: nil,
                 runningFor: nil, hint: nil, pids: Array(1...Int32(count)), cpu: cpu, memory: memory, memoryEstimated: false,
                 processes: [], canQuit: true, canStop: false, startTimes: [:])
    }

    private static func system(_ name: String, hint: String, cpu: Double, memory: UInt64) -> AppUsage {
        AppUsage(id: "demo|" + name, name: name, kind: .system, bundlePath: nil, bundleID: nil, folder: nil, launchedBy: nil,
                 runningFor: nil, hint: hint, pids: [1], cpu: cpu, memory: memory, memoryEstimated: true, processes: [],
                 canQuit: false, canStop: false, startTimes: [:])
    }
}
