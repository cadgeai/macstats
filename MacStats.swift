import Foundation
import CryptoKit

let dataDir = NSString(string: "~/.macstats").expandingTildeInPath
let dataFile = "\(dataDir)/data.dat"

// MARK: - ANSI Colors
let reset   = "\u{001B}[0m"
let bold    = "\u{001B}[1m"
let dim     = "\u{001B}[2m"
let italic  = "\u{001B}[3m"

let white   = "\u{001B}[97m"
let gray    = "\u{001B}[90m"
let cyan    = "\u{001B}[36m"
let brightCyan = "\u{001B}[96m"
let blue    = "\u{001B}[34m"
let brightBlue = "\u{001B}[94m"
let green   = "\u{001B}[32m"
let brightGreen = "\u{001B}[92m"
let yellow  = "\u{001B}[33m"
let brightYellow = "\u{001B}[93m"
let magenta = "\u{001B}[35m"
let brightMagenta = "\u{001B}[95m"
let red     = "\u{001B}[31m"
let brightRed = "\u{001B}[91m"

let cyanBg  = "\u{001B}[46m\u{001B}[30m"

// MARK: - Encryption
func getMachineKey() -> SymmetricKey {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    p.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    var uuid = "fallback-key-macstats-2026"
    if let range = output.range(of: "IOPlatformUUID") {
        let after = output[range.upperBound...]
        if let qStart = after.firstIndex(of: "\""),
           let qEnd = after[after.index(after: qStart)...].firstIndex(of: "\"") {
            uuid = String(after[after.index(after: qStart)..<qEnd])
        }
    }

    let hash = SHA256.hash(data: Data(uuid.utf8))
    return SymmetricKey(data: hash)
}

func decrypt(_ data: Data, key: SymmetricKey) -> Data? {
    guard let box = try? AES.GCM.SealedBox(combined: data),
          let opened = try? AES.GCM.open(box, using: key) else { return nil }
    return opened
}

// MARK: - Data Model
struct MacStatsData: Codable {
    var startDate: String
    var totalKeystrokes: UInt64
    var keyCounts: [String: UInt64]
    var dailyKeystrokes: [String: UInt64]
    var totalScrollPoints: Double
    var totalScreenOnSeconds: UInt64
    var dailyScreenSeconds: [String: UInt64]
    var totalNetworkBytesIn: UInt64
    var totalNetworkBytesOut: UInt64
    var totalSecondsPluggedIn: UInt64
    var totalSecondsOnBattery: UInt64
    var totalWattHoursConsumed: Double
    var appLaunchCounts: [String: UInt64]
    var appActiveSeconds: [String: UInt64]
    var totalFilesDownloaded: UInt64
    var totalDownloadedBytes: UInt64
    var totalFilesCreated: UInt64
    var totalFilesCreatedBytes: UInt64

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try c.decode(String.self, forKey: .startDate)
        totalKeystrokes = try c.decode(UInt64.self, forKey: .totalKeystrokes)
        keyCounts = try c.decode([String: UInt64].self, forKey: .keyCounts)
        dailyKeystrokes = try c.decode([String: UInt64].self, forKey: .dailyKeystrokes)
        totalScrollPoints = try c.decode(Double.self, forKey: .totalScrollPoints)
        totalScreenOnSeconds = try c.decode(UInt64.self, forKey: .totalScreenOnSeconds)
        dailyScreenSeconds = try c.decode([String: UInt64].self, forKey: .dailyScreenSeconds)
        totalNetworkBytesIn = try c.decode(UInt64.self, forKey: .totalNetworkBytesIn)
        totalNetworkBytesOut = try c.decode(UInt64.self, forKey: .totalNetworkBytesOut)
        totalSecondsPluggedIn = try c.decode(UInt64.self, forKey: .totalSecondsPluggedIn)
        totalSecondsOnBattery = try c.decode(UInt64.self, forKey: .totalSecondsOnBattery)
        totalWattHoursConsumed = try c.decode(Double.self, forKey: .totalWattHoursConsumed)
        appLaunchCounts = try c.decode([String: UInt64].self, forKey: .appLaunchCounts)
        appActiveSeconds = try c.decode([String: UInt64].self, forKey: .appActiveSeconds)
        totalFilesDownloaded = try c.decode(UInt64.self, forKey: .totalFilesDownloaded)
        totalDownloadedBytes = try c.decode(UInt64.self, forKey: .totalDownloadedBytes)
        totalFilesCreated = try c.decodeIfPresent(UInt64.self, forKey: .totalFilesCreated) ?? 0
        totalFilesCreatedBytes = try c.decodeIfPresent(UInt64.self, forKey: .totalFilesCreatedBytes) ?? 0
        totalClicks = try c.decode(UInt64.self, forKey: .totalClicks)
        clickCounts = try c.decode([String: UInt64].self, forKey: .clickCounts)
        totalMousePoints = try c.decode(Double.self, forKey: .totalMousePoints)
    }
    var totalClicks: UInt64
    var clickCounts: [String: UInt64]
    var totalMousePoints: Double
}

// MARK: - Formatting
func num(_ n: UInt64) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

func num(_ n: Double, decimals: Int = 1) -> String {
    return String(format: "%.\(decimals)f", n)
}

func formatTime(_ totalSeconds: UInt64) -> String {
    let days = totalSeconds / 86400
    let hours = (totalSeconds % 86400) / 3600
    let minutes = (totalSeconds % 3600) / 60
    if days > 0 {
        return "\(days)d \(hours)h \(minutes)m"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var value = Double(bytes)
    var i = 0
    while value >= 1024 && i < units.count - 1 {
        value /= 1024
        i += 1
    }
    if i == 0 { return "\(bytes) B" }
    return "\(num(value)) \(units[i])"
}

func scrollPointsToMiles(_ points: Double) -> Double {
    let inches = points / 72.0
    let miles = inches / 12.0 / 5280.0
    return miles
}

func mousePointsToMiles(_ points: Double) -> Double {
    // 1 point = 1 pixel on standard display, ~1/72 inch
    let inches = points / 72.0
    let miles = inches / 12.0 / 5280.0
    return miles
}

func today() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

func bar(_ value: UInt64, max maxVal: UInt64, width: Int = 25, color: String = cyan) -> String {
    let filled = max(1, min(width, Int(value * UInt64(width) / max(maxVal, 1))))
    let empty = width - filled
    return "\(color)\(String(repeating: "▓", count: filled))\(gray)\(String(repeating: "░", count: empty))\(reset)"
}

func pad(_ s: String, _ width: Int, right: Bool = false) -> String {
    let stripped = s.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    let need = max(0, width - stripped.count)
    if right {
        return String(repeating: " ", count: need) + s
    }
    return s + String(repeating: " ", count: need)
}

func header(_ title: String) {
    print("\n  \(cyan)\(bold)─── \(title) ───\(reset)\n")
}

func label(_ text: String, _ value: String) {
    print("  \(dim)\(text)\(reset)  \(bold)\(white)\(value)\(reset)")
}

func section(_ icon: String, _ title: String) {
    print("  \(yellow)\(icon)\(reset)  \(bold)\(title)\(reset)")
}

// MARK: - Load
let encKey = getMachineKey()

guard let encrypted = try? Data(contentsOf: URL(fileURLWithPath: dataFile)),
      let decrypted = decrypt(encrypted, key: encKey),
      let s = try? JSONDecoder().decode(MacStatsData.self, from: decrypted) else {
    print("  \(red)No data found. Is the daemon installed?\(reset)")
    exit(1)
}

let args = CommandLine.arguments
let sub = args.count > 1 ? args[1] : ""

switch sub {

case "--keys":
    let sorted = s.keyCounts.sorted { $0.value > $1.value }
    header("Per-Key Breakdown")
    let maxVal = sorted.first?.value ?? 1
    for (i, (key, count)) in sorted.prefix(40).enumerated() {
        let rank = "\(dim)\(String(format: "%2d", i + 1)).\(reset)"
        let keyStr = "\(bold)\(white)\(key)\(reset)"
        let countStr = "\(cyan)\(num(count))\(reset)"
        print("  \(rank) \(pad(keyStr, 18)) \(pad(countStr, 12, right: true))  \(bar(count, max: maxVal))")
    }
    if sorted.count > 40 { print("\n  \(dim)... and \(sorted.count - 40) more keys\(reset)") }
    print()

case "--clicks":
    let sorted = s.clickCounts.sorted { $0.value > $1.value }
    header("Click Breakdown")
    label("Total", num(s.totalClicks))
    print()
    let maxVal = sorted.first?.value ?? 1
    for (click, count) in sorted {
        print("  \(bold)\(white)\(pad(click, 15))\(reset) \(cyan)\(pad(num(count), 12, right: true))\(reset)  \(bar(count, max: maxVal, color: magenta))")
    }
    print()

case "--apps":
    let sorted = s.appActiveSeconds.sorted { $0.value > $1.value }
    header("Active App Time")
    let maxVal = sorted.first?.value ?? 1
    for (i, (app, seconds)) in sorted.prefix(30).enumerated() {
        let rank = "\(dim)\(String(format: "%2d", i + 1)).\(reset)"
        print("  \(rank) \(bold)\(white)\(pad(app, 22))\(reset) \(green)\(pad(formatTime(seconds), 10, right: true))\(reset)  \(bar(seconds, max: maxVal, color: green))")
    }
    if sorted.count > 30 { print("\n  \(dim)... and \(sorted.count - 30) more apps\(reset)") }
    print()

case "--launches":
    let sorted = s.appLaunchCounts.sorted { $0.value > $1.value }
    header("App Launch Counts")
    let maxVal = sorted.first?.value ?? 1
    for (i, (app, count)) in sorted.prefix(30).enumerated() {
        let rank = "\(dim)\(String(format: "%2d", i + 1)).\(reset)"
        print("  \(rank) \(bold)\(white)\(pad(app, 22))\(reset) \(yellow)\(pad(num(count), 8, right: true))\(reset)  \(bar(count, max: maxVal, color: yellow))")
    }
    print()

case "--screen":
    let sorted = s.dailyScreenSeconds.sorted { $0.key > $1.key }
    header("Daily Screen Time")
    label("Lifetime", formatTime(s.totalScreenOnSeconds))
    print()
    let maxVal = sorted.map(\.value).max() ?? 1
    for (day, seconds) in sorted.prefix(30) {
        let isToday = day == today()
        let dayColor = isToday ? "\(bold)\(white)" : "\(dim)"
        let marker = isToday ? " \(cyan)◀\(reset)" : ""
        print("  \(dayColor)\(day)\(reset)  \(green)\(pad(formatTime(seconds), 10, right: true))\(reset)  \(bar(seconds, max: maxVal, color: green))\(marker)")
    }
    print()

case "--days":
    let sorted = s.dailyKeystrokes.sorted { $0.key > $1.key }
    header("Daily Keystrokes")
    let maxVal = sorted.map(\.value).max() ?? 1
    for (day, count) in sorted.prefix(30) {
        let isToday = day == today()
        let dayColor = isToday ? "\(bold)\(white)" : "\(dim)"
        let marker = isToday ? " \(cyan)◀\(reset)" : ""
        print("  \(dayColor)\(day)\(reset)  \(cyan)\(pad(num(count), 10, right: true))\(reset)  \(bar(count, max: maxVal))\(marker)")
    }
    print()

case "--json":
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let out = try? encoder.encode(s) {
        print(String(data: out, encoding: .utf8)!)
    }

case "--help":
    print()
    print("  \(bold)\(white)macstats\(reset) \(dim)— lifetime Mac tracker\(reset)")
    print()
    print("  \(cyan)macstats\(reset)              \(dim)full overview\(reset)")
    print("  \(cyan)macstats --keys\(reset)       \(dim)per-key breakdown\(reset)")
    print("  \(cyan)macstats --clicks\(reset)     \(dim)click type breakdown\(reset)")
    print("  \(cyan)macstats --apps\(reset)       \(dim)active app time ranking\(reset)")
    print("  \(cyan)macstats --launches\(reset)   \(dim)app launch counts\(reset)")
    print("  \(cyan)macstats --screen\(reset)     \(dim)daily screen time\(reset)")
    print("  \(cyan)macstats --days\(reset)       \(dim)daily keystrokes\(reset)")
    print("  \(cyan)macstats --json\(reset)       \(dim)raw decrypted JSON\(reset)")
    print()

default:
    // Full overview
    let todayKeys = s.dailyKeystrokes[today()] ?? 0
    let todayScreen = s.dailyScreenSeconds[today()] ?? 0
    let topKey = s.keyCounts.max(by: { $0.value < $1.value })
    let scrollMiles = scrollPointsToMiles(s.totalScrollPoints)
    let mouseMiles = mousePointsToMiles(s.totalMousePoints)
    let kWh = s.totalWattHoursConsumed / 1000.0

    let w = 47 // content width inside box

    // Title box
    print()
    print("  \(bold)\(brightCyan)┏\(String(repeating: "━", count: w))┓\(reset)")
    print("  \(bold)\(brightCyan)┃\(reset)          \(bold)\(white)M A C   L I F E T I M E\(reset)           \(bold)\(brightCyan)┃\(reset)")
    print("  \(bold)\(brightCyan)┃\(reset)            \(dim)since \(s.startDate)\(reset)              \(bold)\(brightCyan)┃\(reset)")
    print("  \(bold)\(brightCyan)┗\(String(repeating: "━", count: w))┛\(reset)")
    print()

    // Hero stats
    print("       \(bold)\(brightCyan)\(num(s.totalKeystrokes))\(reset)             \(bold)\(brightMagenta)\(num(s.totalClicks))\(reset)             \(bold)\(brightGreen)\(formatTime(s.totalScreenOnSeconds))\(reset)")
    print("    \(dim)keystrokes\(reset)          \(dim)clicks\(reset)           \(dim)screen time\(reset)")
    print()

    // Keyboard
    print("  \(bold)\(brightCyan)── ⌨️  KEYBOARD \(String(repeating: "─", count: 31))\(reset)")
    print("  \(brightCyan)│\(reset)  \(dim)today\(reset)               \(bold)\(brightCyan)\(num(todayKeys))\(reset)")
    if let top = topKey {
        print("  \(brightCyan)│\(reset)  \(dim)most pressed\(reset)         \(bold)\(brightCyan)\(top.key)\(reset) \(dim)(\(num(top.value)))\(reset)")
    }
    print("  \(brightCyan)│\(reset)")

    // Trackpad
    print("  \(bold)\(brightMagenta)── 🖱️  TRACKPAD \(String(repeating: "─", count: 31))\(reset)")
    let clickMax = s.clickCounts.values.max() ?? 1
    for (click, count) in s.clickCounts.sorted(by: { $0.value > $1.value }) {
        print("  \(brightMagenta)│\(reset)  \(dim)\(pad(click, 20))\(reset) \(bar(count, max: clickMax, width: 15, color: brightMagenta))  \(bold)\(brightMagenta)\(num(count))\(reset)")
    }
    print("  \(brightMagenta)│\(reset)")

    // Movement
    print("  \(bold)\(brightBlue)── 🏃 MOVEMENT \(String(repeating: "─", count: 32))\(reset)")
    if mouseMiles >= 0.01 {
        print("  \(brightBlue)│\(reset)  \(dim)cursor\(reset)              \(bold)\(brightBlue)\(num(mouseMiles, decimals: 2))\(reset) \(dim)miles\(reset)")
    } else {
        let feet = mouseMiles * 5280
        print("  \(brightBlue)│\(reset)  \(dim)cursor\(reset)              \(bold)\(brightBlue)\(num(feet, decimals: 1))\(reset) \(dim)feet\(reset)")
    }
    if scrollMiles >= 0.01 {
        print("  \(brightBlue)│\(reset)  \(dim)scroll\(reset)              \(bold)\(brightBlue)\(num(scrollMiles, decimals: 2))\(reset) \(dim)miles\(reset)")
    } else {
        let feet = scrollMiles * 5280
        print("  \(brightBlue)│\(reset)  \(dim)scroll\(reset)              \(bold)\(brightBlue)\(num(feet, decimals: 1))\(reset) \(dim)feet\(reset)")
    }
    print("  \(brightBlue)│\(reset)")

    // Screen time
    print("  \(bold)\(brightGreen)── 🖥️  SCREEN TIME \(String(repeating: "─", count: 28))\(reset)")
    print("  \(brightGreen)│\(reset)  \(dim)lifetime\(reset)            \(bold)\(brightGreen)\(formatTime(s.totalScreenOnSeconds))\(reset)")
    print("  \(brightGreen)│\(reset)  \(dim)today\(reset)               \(bold)\(brightGreen)\(formatTime(todayScreen))\(reset)")
    print("  \(brightGreen)│\(reset)")

    // Top apps
    if !s.appActiveSeconds.isEmpty {
        print("  \(bold)\(brightYellow)── 📊 TOP APPS \(String(repeating: "─", count: 32))\(reset)")
        let sortedApps = s.appActiveSeconds.sorted { $0.value > $1.value }
        let appMax = sortedApps.first?.value ?? 1
        for (i, (app, seconds)) in sortedApps.prefix(5).enumerated() {
            let medal = i == 0 ? "🥇" : i == 1 ? "🥈" : i == 2 ? "🥉" : "  "
            print("  \(brightYellow)│\(reset)  \(medal) \(bold)\(white)\(pad(app, 16))\(reset) \(bar(seconds, max: appMax, width: 12, color: brightYellow))  \(bold)\(brightYellow)\(formatTime(seconds))\(reset)")
        }
        print("  \(brightYellow)│\(reset)")
    }

    // App launches
    if !s.appLaunchCounts.isEmpty {
        print("  \(bold)\(yellow)── 🚀 LAUNCHES \(String(repeating: "─", count: 32))\(reset)")
        let sortedLaunches = s.appLaunchCounts.sorted { $0.value > $1.value }
        for (app, count) in sortedLaunches.prefix(5) {
            print("  \(yellow)│\(reset)  \(dim)·\(reset) \(bold)\(white)\(pad(app, 18))\(reset) \(bold)\(yellow)\(num(count))\(reset)")
        }
        print("  \(yellow)│\(reset)")
    }

    // Network
    print("  \(bold)\(brightBlue)── 🌐 NETWORK \(String(repeating: "─", count: 33))\(reset)")
    print("  \(brightBlue)│\(reset)  \(brightGreen)↓\(reset) \(dim)downloaded\(reset)       \(bold)\(brightGreen)\(formatBytes(s.totalNetworkBytesIn))\(reset)")
    print("  \(brightBlue)│\(reset)  \(brightRed)↑\(reset) \(dim)uploaded\(reset)         \(bold)\(brightRed)\(formatBytes(s.totalNetworkBytesOut))\(reset)")
    print("  \(brightBlue)│\(reset)")

    // Power
    print("  \(bold)\(brightYellow)── ⚡ POWER \(String(repeating: "─", count: 35))\(reset)")
    print("  \(brightYellow)│\(reset)  \(dim)consumed\(reset)            \(bold)\(brightYellow)\(num(kWh, decimals: 2))\(reset) \(dim)kWh\(reset)")
    print("  \(brightYellow)│\(reset)  \(dim)on AC\(reset)               \(bold)\(brightGreen)\(formatTime(s.totalSecondsPluggedIn))\(reset) \(brightGreen)●\(reset)")
    print("  \(brightYellow)│\(reset)  \(dim)on battery\(reset)          \(bold)\(brightRed)\(formatTime(s.totalSecondsOnBattery))\(reset) \(brightRed)●\(reset)")
    print("  \(brightYellow)│\(reset)")

    // Downloads
    print("  \(bold)\(magenta)── 📥 DOWNLOADS \(String(repeating: "─", count: 31))\(reset)")
    print("  \(magenta)│\(reset)  \(dim)files\(reset)               \(bold)\(brightMagenta)\(num(s.totalFilesDownloaded))\(reset)")
    print("  \(magenta)│\(reset)  \(dim)total size\(reset)          \(bold)\(brightMagenta)\(formatBytes(s.totalDownloadedBytes))\(reset)")
    print("  \(magenta)│\(reset)")

    // Files created
    print("  \(bold)\(cyan)── 📁 FILES CREATED \(String(repeating: "─", count: 27))\(reset)")
    print("  \(cyan)│\(reset)  \(dim)files\(reset)               \(bold)\(brightCyan)\(num(s.totalFilesCreated))\(reset)")
    print("  \(cyan)│\(reset)  \(dim)total size\(reset)          \(bold)\(brightCyan)\(formatBytes(s.totalFilesCreatedBytes))\(reset)")
    print()

    print("  \(dim)run \(brightCyan)macstats --help\(dim) for detailed views\(reset)")
    print()
}
