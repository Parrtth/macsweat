import Foundation

struct KnownService {
    let name: String
    let hint: String
}

/// Plain-language names for well-known macOS services and developer tools.
enum Knowledge {
    private static let spotlight = KnownService(name: "Spotlight indexing", hint: "Indexing files for search. Settles down on its own.")
    private static let timeMachine = KnownService(name: "Time Machine", hint: "Backing up your Mac. Best to let it finish.")
    private static let update = KnownService(name: "Software Update", hint: "Checking for or preparing macOS updates.")
    private static let photos = KnownService(name: "Photos analysis", hint: "Analyzing your photo library. Mostly runs when you're idle.")
    private static let iCloud = KnownService(name: "iCloud sync", hint: "Syncing with iCloud. Settles once syncing finishes.")
    private static let security = KnownService(name: "Security checks", hint: "macOS checking apps and files for malware. Usually brief.")
    private static let diagnostics = KnownService(name: "Crash & hang reports", hint: "Collecting diagnostics after an app hung or crashed.")
    private static let virtualMachine = KnownService(name: "Virtual machine", hint: "A VM (e.g. Docker or UTM). Stop it from the app that started it.")

    static let services: [String: KnownService] = [
        "WindowServer": KnownService(name: "WindowServer", hint: "Draws the screen. Busier with many windows, displays or animations."),
        "mds": spotlight, "mds_stores": spotlight, "mdworker": spotlight, "mdworker_shared": spotlight,
        "mdsync": spotlight, "mdbulkimport": spotlight, "corespotlightd": spotlight,
        "backupd": timeMachine, "backupd-helper": timeMachine,
        "softwareupdated": update, "SoftwareUpdateNotificationManager": update,
        "com.apple.MobileSoftwareUpdate.UpdateBrainService": update,
        "photoanalysisd": photos, "mediaanalysisd": photos, "photolibraryd": photos,
        "bird": iCloud, "cloudd": iCloud, "fileproviderd": iCloud,
        "nsurlsessiond": KnownService(name: "Background downloads", hint: "Downloading or uploading for apps and iCloud."),
        "XprotectService": security, "XProtect": security, "syspolicyd": security, "trustd": security,
        "spindump": diagnostics, "ReportCrash": diagnostics, "osanalyticshelper": diagnostics,
        "coreaudiod": KnownService(name: "Core Audio", hint: "Plays and records sound. Busier during calls and media."),
        "logd": KnownService(name: "System logging", hint: "Writes system logs. Spikes when an app logs heavily."),
        "com.apple.siri.embeddedspeech": KnownService(name: "Speech recognition", hint: "On-device dictation or Siri listening."),
        "launchd": KnownService(name: "launchd", hint: "Starts and manages every other process."),
        "com.apple.WebKit.WebContent": KnownService(name: "Web content", hint: "Web pages shown by Safari, Mail or another app."),
        "com.apple.Virtualization.VirtualMachine": virtualMachine,
        "qemu-system-aarch64": virtualMachine, "qemu-system-x86_64": virtualMachine,
    ]

    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/",
                                         "/Library/Apple/", "/private/var/db/", "/usr/lib/"]

    static func isSystemPath(_ command: String) -> Bool {
        systemPrefixes.contains { command.hasPrefix($0) }
    }

    static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "com.apple.Safari", "org.mozilla.firefox",
    ]

    private static let runtimes: [String: String] = [
        "node": "Node.js", "nodejs": "Node.js", "next-server": "Next.js server", "npm": "npm", "npx": "npx",
        "pnpm": "pnpm", "yarn": "Yarn", "bun": "Bun", "bunx": "Bun", "deno": "Deno", "tsx": "tsx", "ts-node": "ts-node",
        "ruby": "Ruby", "rails": "Rails", "puma": "Puma", "java": "Java", "php": "PHP", "php-fpm": "PHP",
        "dotnet": ".NET", "esbuild": "esbuild", "vite": "Vite", "turbo": "Turborepo", "uvicorn": "Uvicorn",
        "gunicorn": "Gunicorn", "celery": "Celery", "postgres": "PostgreSQL", "redis-server": "Redis",
        "mongod": "MongoDB", "mysqld": "MySQL", "cargo": "Cargo", "beam.smp": "Erlang/Elixir",
    ]

    /// Developer runtime name if this process is one and isn't shipped inside an app bundle.
    static func runtime(executable: String, command: String) -> String? {
        if command.contains("/Python.framework/") || command.contains("/Python3.framework/") { return "Python" }
        guard !command.contains(".app/") else { return nil }
        let token = executable.split(separator: " ").first.map { String($0).lowercased() } ?? ""
        if token.hasPrefix("python") { return "Python" }
        return runtimes[token]
    }

    /// A specific name for well-known dev servers; higher rank wins when a task has several processes.
    static func taskName(runtime: String, command: String, arguments: [String]) -> (name: String, rank: Int) {
        let text = ([command] + arguments).joined(separator: " ").lowercased()
        let next = text.contains("next-server") || text.contains("/next/dist/") || text.contains(".bin/next")
        if next && (text.contains(" dev") || text.contains("--turbo")) { return ("Next.js dev server", 4) }
        if next { return ("Next.js server", 3) }
        if text.contains("/vite/") || text.contains(".bin/vite") || text.hasSuffix(" vite") { return ("Vite dev server", 3) }
        if text.contains("storybook") { return ("Storybook", 3) }
        if text.contains("jest") || text.contains("vitest") { return ("Test runner", 2) }
        if text.contains("tsserver") { return ("TypeScript server", 2) }
        if text.contains("webpack") { return ("webpack", 2) }
        let packageManagers: Set<String> = ["npm", "npx", "pnpm", "Yarn", "Bun"]
        return (runtime, packageManagers.contains(runtime) ? 0 : 1)
    }
}
