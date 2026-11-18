import AppKit
import Darwin
import Foundation

enum GroupKind { case app, task, system, other }

enum MemoryPressure {
    case normal, elevated, high, unknown

    var label: String {
        switch self {
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .high: "High"
        case .unknown: "Unknown"
        }
    }
}

struct SystemReading {
    let cpu: Double?            // whole Mac, 0–100
    let usedMemory: UInt64
    let totalMemory: UInt64
    let swapUsed: UInt64?
    let pressure: MemoryPressure
    let thermal: ProcessInfo.ThermalState
    let timestamp: Date
}

struct ProcessLine {
    let pid: Int32
    let name: String
    let cpu: Double
    let memory: UInt64
}

/// One row in the list: an app with its helpers, a developer task, or a background service.
struct AppUsage: Identifiable {
    let id: String
    let name: String
    let kind: GroupKind
    let bundlePath: String?
    let bundleID: String?
    let folder: String?         // project folder for developer tasks
    let launchedBy: String?     // app that started a developer task
    let runningFor: TimeInterval?
    let hint: String?
    let pids: [Int32]
    let cpu: Double             // 100% = one core, like Activity Monitor
    let memory: UInt64
    let memoryEstimated: Bool   // resident size instead of footprint (other users' processes)
    let processes: [ProcessLine]
    let canQuit: Bool
    let canStop: Bool
    let startTimes: [Int32: UInt64] // to recognise the same process later (process IDs get reused)

    var isSelf: Bool { bundlePath == Bundle.main.bundlePath }
    var isBrowser: Bool { bundleID.map(Knowledge.browsers.contains) ?? false }
}

struct ProcessScan {
    let groups: [AppUsage]
    let cpuMeasured: Bool
    let timestamp: Date
    let error: String?
}

/// Reads macOS counters and groups processes the way a person thinks about them.
/// Not thread-safe: call it from one serial queue.
final class SystemMonitor {
    private struct RawProcess {
        let pid: Int32
        let ppid: Int32
        let uid: UInt32
        var cpuSeconds: Double
        let elapsed: Double?
        var memory: UInt64
        var memoryEstimated: Bool
        let command: String
        var started: UInt64?

        var executable: String { (command as NSString).lastPathComponent }
    }

    private struct Identity {
        let key: String
        var name: String
        let kind: GroupKind
        var bundlePath: String?
        var folder: String?
        var launchedBy: String?
        var hint: String?
        var rank = 0
    }

    private struct GroupBuilder {
        var identity: Identity
        var pids: [Int32] = []
        var cpu = 0.0
        var memory: UInt64 = 0
        var memoryEstimated = false
        var oldest: Double?
        var lines: [ProcessLine] = []
        var startTimes: [Int32: UInt64] = [:]
    }

    private struct Details {
        let cwd: String?
        let arguments: [String]
    }

    private var previousTicks: [UInt32]?
    private var previousCPU: [Int32: (command: String, seconds: Double)] = [:]
    private var previousScan: TimeInterval?
    private var detailsCache: [Int32: (command: String, details: Details)] = [:]
    private var appNames: [String: String] = [:]
    private var projectRoots: [String: String] = [:]
    private var bundleIDs: [String: String] = [:]
    private let ownUID = UInt32(getuid())
    private let home = NSHomeDirectory()
    private let tickSeconds: Double
    private let responsiblePID: (@convention(c) (pid_t) -> pid_t)?

    init() {
        // proc_pid_rusage reports CPU time in Mach ticks (41.67 ns each on Apple silicon), not nanoseconds.
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        tickSeconds = timebase.denom == 0 ? 1e-9 : Double(timebase.numer) / Double(timebase.denom) / 1e9
        // The same lookup Activity Monitor uses to attribute XPC helpers (e.g. WebKit) to their app.
        let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid")
        responsiblePID = symbol.map { unsafeBitCast($0, to: (@convention(c) (pid_t) -> pid_t).self) }
    }

    // MARK: Whole-Mac readings

    func sampleSystem() -> SystemReading {
        SystemReading(cpu: sampleCPU(), usedMemory: sampleMemory(), totalMemory: ProcessInfo.processInfo.physicalMemory,
                      swapUsed: sampleSwap(), pressure: samplePressure(),
                      thermal: ProcessInfo.processInfo.thermalState, timestamp: Date())
    }

    private func sampleCPU() -> Double? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = [load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3]
        defer { previousTicks = ticks }
        guard let previousTicks else { return nil }
        let changes = zip(ticks, previousTicks).map { UInt64($0 &- $1) }
        let total = changes.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(total - changes[Int(CPU_STATE_IDLE)]) / Double(total) * 100
    }

    private func sampleMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // Activity Monitor's "Memory Used": app memory + wired + compressed (file cache excluded).
        let anonymous = UInt64(stats.internal_page_count)
        let appMemory = anonymous - min(anonymous, UInt64(stats.purgeable_count))
        let pages = appMemory + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return min(ProcessInfo.processInfo.physicalMemory, pages * UInt64(vm_kernel_page_size))
    }

    private func sampleSwap() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : nil
    }

    private func samplePressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .unknown }
        switch level {
        case 1: return .normal
        case 2: return .elevated
        case 4: return .high
        default: return .unknown
        }
    }

    // MARK: Processes

    func scanProcesses() -> ProcessScan {
        let now = ProcessInfo.processInfo.systemUptime
        let interval = previousScan.map { now - $0 }
        let output: String
        do {
            // ps is setuid root, so it can see system processes (WindowServer, Spotlight…) that we can't query directly.
            output = try run("/bin/ps", ["-axo", "pid=,ppid=,uid=,time=,etime=,rss=,comm="])
        } catch {
            return ProcessScan(groups: [], cpuMeasured: false, timestamp: Date(),
                               error: "Couldn’t list running processes (\(error.localizedDescription)).")
        }

        var processes: [Int32: RawProcess] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            guard fields.count == 7, let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
                  let uid = UInt32(fields[2]), let residentKB = UInt64(fields[5]) else { continue }
            var process = RawProcess(pid: pid, ppid: ppid, uid: uid, cpuSeconds: Self.seconds(fields[3]) ?? 0,
                                     elapsed: Self.seconds(fields[4]), memory: residentKB * 1024, memoryEstimated: true,
                                     command: fields[6].trimmingCharacters(in: .whitespaces))
            // For our own processes, use precise CPU time and the same memory figure as Activity Monitor.
            if uid == ownUID, let usage = Self.resourceUsage(pid) {
                process.cpuSeconds = Double(usage.ri_user_time &+ usage.ri_system_time) * tickSeconds
                process.memory = usage.ri_phys_footprint
                process.memoryEstimated = false
                process.started = usage.ri_proc_start_abstime
            }
            processes[pid] = process
        }
        guard !processes.isEmpty else {
            return ProcessScan(groups: [], cpuMeasured: false, timestamp: Date(), error: "macOS returned an empty process list.")
        }

        // CPU over the time since the previous scan; 100% = one core.
        let maxCPU = Double(ProcessInfo.processInfo.activeProcessorCount) * 100
        var cpu: [Int32: Double] = [:]
        let measured = (interval ?? 0) >= 0.5
        if let interval, measured {
            for (pid, process) in processes {
                var used = 0.0
                if let previous = previousCPU[pid], previous.command == process.command {
                    used = max(0, process.cpuSeconds - previous.seconds)
                } else if let elapsed = process.elapsed, elapsed <= interval + 1 {
                    used = process.cpuSeconds // started since the last scan
                }
                cpu[pid] = min(maxCPU, used / interval * 100)
            }
        }
        previousCPU = processes.mapValues { (command: $0.command, seconds: $0.cpuSeconds) }
        previousScan = now
        detailsCache = detailsCache.filter { processes[$0.key]?.command == $0.value.command }

        var identities: [Int32: Identity] = [:]
        var builders: [String: GroupBuilder] = [:]
        for (pid, process) in processes {
            guard let identity = identify(pid, in: processes, memo: &identities, depth: 0) else { continue }
            var group = builders[identity.key] ?? GroupBuilder(identity: identity)
            if identity.rank > group.identity.rank
                || (identity.rank == group.identity.rank && identity.name < group.identity.name) {
                group.identity = identity // most specific name wins; ties broken alphabetically so it doesn't flicker
            }
            let processCPU = cpu[pid] ?? 0
            group.pids.append(pid)
            group.cpu += processCPU
            group.memory += process.memory
            group.memoryEstimated = group.memoryEstimated || process.memoryEstimated
            if let elapsed = process.elapsed { group.oldest = max(group.oldest ?? 0, elapsed) }
            group.lines.append(ProcessLine(pid: pid, name: process.executable, cpu: processCPU, memory: process.memory))
            if let started = process.started { group.startTimes[pid] = started }
            builders[identity.key] = group
        }

        let groups = builders.map { key, group -> AppUsage in
            let identity = group.identity
            var bundleID: String?
            var canQuit = false
            if let bundle = identity.bundlePath {
                bundleID = bundleIdentifier(bundle)
                if identity.kind == .app, bundle != Bundle.main.bundlePath, let bundleID {
                    canQuit = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
                }
            }
            let lines = group.lines.sorted { $0.cpu == $1.cpu ? $0.memory > $1.memory : $0.cpu > $1.cpu }
            let ownsAll = group.pids.allSatisfy { processes[$0]?.uid == ownUID }
            return AppUsage(id: key, name: identity.name, kind: identity.kind, bundlePath: identity.bundlePath,
                            bundleID: bundleID, folder: identity.folder, launchedBy: identity.launchedBy,
                            runningFor: group.oldest, hint: identity.hint, pids: group.pids.sorted(),
                            cpu: group.cpu, memory: group.memory, memoryEstimated: group.memoryEstimated,
                            processes: Array(lines.prefix(8)), canQuit: canQuit,
                            canStop: identity.kind == .task && ownsAll, startTimes: group.startTimes)
        }
        return ProcessScan(groups: groups, cpuMeasured: measured, timestamp: Date(), error: nil)
    }

    private func identify(_ pid: Int32, in processes: [Int32: RawProcess], memo: inout [Int32: Identity],
                          depth: Int) -> Identity? {
        if let known = memo[pid] { return known }
        guard let process = processes[pid] else { return nil }
        let identity = resolve(process, in: processes, memo: &memo, depth: depth)
        memo[pid] = identity
        return identity
    }

    private func resolve(_ process: RawProcess, in processes: [Int32: RawProcess], memo: inout [Int32: Identity],
                         depth: Int) -> Identity {
        // 1. Developer runtimes (node, Python…) working in a project get their own row, even when an
        //    editor or AI app started them. Tool servers running from caches stay with their app.
        let runtime = Knowledge.runtime(executable: process.executable, command: process.command)
        if let runtime {
            if depth < 24, process.ppid > 1, var parent = identify(process.ppid, in: processes, memo: &memo, depth: depth + 1),
               parent.kind == .task {
                // Same task as its parent, but a child can name it better (npm → next dev → next-server).
                let details = process.uid == ownUID ? details(for: process) : Details(cwd: nil, arguments: [])
                let label = Knowledge.taskName(runtime: runtime, command: process.command, arguments: details.arguments)
                if label.rank > parent.rank { parent.name = label.name; parent.rank = label.rank }
                return parent
            }
            if let task = taskIdentity(process, runtime: runtime, in: processes) { return task }
        }
        // 2. Anything inside an app bundle belongs to that app: helpers, extensions, bundled XPC services.
        //    Runtimes and developer tools that merely live in a bundle (Python.app, Xcode's git) don't.
        if runtime == nil, let bundle = Self.bundlePath(in: process.command) { return appIdentity(bundle) }
        if depth < 24 {
            // 3. Shells and tools started by a developer task stay with that task.
            if process.ppid > 1, let parent = identify(process.ppid, in: processes, memo: &memo, depth: depth + 1),
               parent.kind == .task {
                return parent
            }
            // 4. macOS records which app is responsible for a helper, e.g. WebKit processes for Safari.
            if process.uid == ownUID, let responsiblePID {
                let owner = responsiblePID(process.pid)
                if owner > 1, owner != process.pid,
                   let identity = identify(owner, in: processes, memo: &memo, depth: depth + 1),
                   identity.bundlePath != nil || identity.kind == .task {
                    return identity
                }
            }
            // 5. Otherwise inherit an app ancestor, e.g. a shell inside Terminal.
            if process.ppid > 1, let parent = identify(process.ppid, in: processes, memo: &memo, depth: depth + 1),
               parent.bundlePath != nil {
                return parent
            }
        }
        // 6. Standalone background processes, with friendly names for well-known macOS services.
        let known = Knowledge.services[process.executable]
        let system = known != nil || Knowledge.isSystemPath(process.command)
        let name = known?.name ?? process.executable
        return Identity(key: "proc|" + name, name: name, kind: system ? .system : .other,
                        hint: known?.hint ?? (system ? "Part of macOS." : nil))
    }

    private func taskIdentity(_ process: RawProcess, runtime: String, in processes: [Int32: RawProcess]) -> Identity? {
        let details = process.uid == ownUID ? details(for: process) : Details(cwd: nil, arguments: [])
        let folder = projectFolder(details).map(projectRoot)
        let launcher = launchingApp(of: process, in: processes)
        // Started by an app and not working in a project (e.g. an MCP server in a cache folder): part of that app.
        if launcher != nil && !looksLikeProject(folder) { return nil }
        let label = Knowledge.taskName(runtime: runtime, command: process.command, arguments: details.arguments)
        return Identity(key: "task|\(folder ?? runtime)|\(launcher ?? "")", name: label.name, kind: .task, folder: folder,
                        launchedBy: launcher, rank: label.rank)
    }

    private func looksLikeProject(_ folder: String?) -> Bool {
        guard let folder, folder != "/", folder != home else { return false }
        let scratch = ["/private/var/folders/", "/var/folders/", "/tmp/", "/private/tmp/", home + "/Library/", home + "/."]
        return !scratch.contains { folder.hasPrefix($0) }
    }

    /// The enclosing Git repository, so `app/tools/mcp` and `app` count as the same project.
    private func projectRoot(_ folder: String) -> String {
        if let cached = projectRoots[folder] { return cached }
        guard folder.hasPrefix(home + "/") else { return folder } // e.g. /opt/homebrew is itself a Git repo
        var candidate = folder
        var root = folder
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: candidate + "/.git") { root = candidate; break }
            let parent = (candidate as NSString).deletingLastPathComponent
            if parent == candidate || parent == home || parent == "/" { break }
            candidate = parent
        }
        projectRoots[folder] = root
        return root
    }

    private func appIdentity(_ bundle: String) -> Identity {
        let name = appName(bundle)
        let system = bundle.hasPrefix("/System/Library/") || bundle.hasPrefix("/Library/Apple/")
        let hint: String? = if bundle == Bundle.main.bundlePath {
            "This app"
        } else if system {
            Knowledge.services[name]?.hint ?? "Part of macOS."
        } else {
            nil
        }
        return Identity(key: "app|" + bundle, name: name, kind: system ? .system : .app, bundlePath: bundle, hint: hint)
    }

    private func launchingApp(of process: RawProcess, in processes: [Int32: RawProcess]) -> String? {
        var current = process.ppid
        for _ in 0..<24 {
            guard current > 1, let parent = processes[current] else { return nil }
            if let bundle = Self.bundlePath(in: parent.command) { return appName(bundle) }
            current = parent.ppid
        }
        return nil
    }

    private func projectFolder(_ details: Details) -> String? {
        if let cwd = details.cwd, cwd != "/", cwd != home { return cwd }
        // Started from home or /: fall back to the script's folder, e.g. `node ~/tv-remote/server.js`.
        for argument in details.arguments.dropFirst() where argument.hasPrefix("/") && !argument.contains("/node_modules/") {
            let folder = (argument as NSString).deletingLastPathComponent
            if folder != "/" && !folder.isEmpty { return folder }
        }
        return details.cwd
    }

    private func details(for process: RawProcess) -> Details {
        if let cached = detailsCache[process.pid], cached.command == process.command { return cached.details }
        let details = Details(cwd: Self.workingDirectory(process.pid), arguments: Self.arguments(process.pid))
        detailsCache[process.pid] = (process.command, details)
        return details
    }

    private func appName(_ bundle: String) -> String {
        if let cached = appNames[bundle] { return cached }
        var name = FileManager.default.displayName(atPath: bundle)
        if name.hasSuffix(".app") { name.removeLast(4) }
        if bundle.contains("/claude-code/") { name = "Claude Code" } // CLI sessions ship in a bare `claude.app`
        appNames[bundle] = name
        return name
    }

    private func bundleIdentifier(_ bundle: String) -> String? {
        if let cached = bundleIDs[bundle] { return cached.isEmpty ? nil : cached }
        let identifier = Bundle(path: bundle)?.bundleIdentifier ?? ""
        bundleIDs[bundle] = identifier
        return identifier.isEmpty ? nil : identifier
    }

    // MARK: Low-level helpers

    static func bundlePath(in command: String) -> String? {
        // Xcode's command-line tools (git, clang, python3) run from inside Xcode.app but aren't Xcode.
        guard command.hasPrefix("/"), !command.contains(".app/Contents/Developer/") else { return nil }
        if let range = command.range(of: ".app/") { return String(command[..<range.lowerBound]) + ".app" }
        return command.hasSuffix(".app") ? command : nil
    }

    /// Parses ps durations: "MMM:SS.cc" (CPU time) and "[[dd-]hh:]mm:ss" (elapsed).
    static func seconds(_ text: Substring) -> Double? {
        var days = 0.0
        var clock = text
        if let dash = clock.firstIndex(of: "-") {
            guard let value = Double(clock[..<dash]) else { return nil }
            days = value
            clock = clock[clock.index(after: dash)...]
        }
        var total = 0.0
        for part in clock.split(separator: ":") {
            guard let value = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
            total = total * 60 + value
        }
        return days * 86_400 + total
    }

    static func startTime(of pid: Int32) -> UInt64? { resourceUsage(pid)?.ri_proc_start_abstime }

    private static func resourceUsage(_ pid: Int32) -> rusage_info_v2? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return result == 0 ? usage : nil
    }

    private static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    private static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return [] }
        let count = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = 4
        while index < size && buffer[index] != 0 { index += 1 } // executable path
        while index < size && buffer[index] == 0 { index += 1 } // padding
        var arguments: [String] = []
        while arguments.count < min(count, 64) && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<min(index, start + 1024)], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    private func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = nil
        environment["LC_NUMERIC"] = "C" // "12:34.56", whatever the region's decimal separator
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty else {
            throw NSError(domain: "MacPulse", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ps exited with status \(process.terminationStatus)"])
        }
        return String(decoding: data, as: UTF8.self)
    }
}
