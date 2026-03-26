import Foundation
import CoreGraphics
import CryptoKit
import Cocoa

// MARK: - Config
let dataDir = NSString(string: "~/.macstats").expandingTildeInPath
let dataFile = "\(dataDir)/data.dat"
let idleThresholdSeconds: Double = 120

// MARK: - Data Model
struct MacStatsData: Codable {
    var startDate: String
    // Keystrokes
    var totalKeystrokes: UInt64
    var keyCounts: [String: UInt64]
    var dailyKeystrokes: [String: UInt64]

    // Scroll (accumulated absolute points — converted to miles at display)
    var totalScrollPoints: Double

    // Screen time (seconds with screen on + unlocked)
    var totalScreenOnSeconds: UInt64
    var dailyScreenSeconds: [String: UInt64]

    // Network (cumulative bytes)
    var totalNetworkBytesIn: UInt64
    var totalNetworkBytesOut: UInt64

    // Power
    var totalSecondsPluggedIn: UInt64
    var totalSecondsOnBattery: UInt64
    var totalWattHoursConsumed: Double

    // App launches
    var appLaunchCounts: [String: UInt64]

    // Active app time (seconds, converted to minutes at display)
    var appActiveSeconds: [String: UInt64]

    // Downloads
    var totalFilesDownloaded: UInt64
    var totalDownloadedBytes: UInt64

    // Clicks
    var totalClicks: UInt64
    var clickCounts: [String: UInt64]

    // Mouse movement (accumulated points)
    var totalMousePoints: Double
}

// MARK: - Encryption
func getMachineKey() -> SymmetricKey {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
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

func encrypt(_ data: Data, key: SymmetricKey) -> Data? {
    guard let sealed = try? AES.GCM.seal(data, using: key) else { return nil }
    return sealed.combined
}

func decrypt(_ data: Data, key: SymmetricKey) -> Data? {
    guard let box = try? AES.GCM.SealedBox(combined: data),
          let opened = try? AES.GCM.open(box, using: key) else { return nil }
    return opened
}

// MARK: - Globals
let encKey = getMachineKey()
var stats: MacStatsData!
var tapRef: CFMachPort?

// Pending changes (flushed periodically)
var pKeystrokes: UInt64 = 0
var pKeyCounts: [String: UInt64] = [:]
var pDailyKeystrokes: [String: UInt64] = [:]
var pScrollPoints: Double = 0
var pScreenSeconds: UInt64 = 0
var pDailyScreenSeconds: [String: UInt64] = [:]
var pNetBytesIn: UInt64 = 0
var pNetBytesOut: UInt64 = 0
var pSecondsPluggedIn: UInt64 = 0
var pSecondsOnBattery: UInt64 = 0
var pWattHours: Double = 0
var pAppLaunches: [String: UInt64] = [:]
var pAppActiveSeconds: [String: UInt64] = [:]
var pFilesDownloaded: UInt64 = 0
var pDownloadedBytes: UInt64 = 0
var pClicks: UInt64 = 0
var pClickCounts: [String: UInt64] = [:]
var pMousePoints: Double = 0

// State tracking
var lastNetBytesIn: UInt64 = 0
var lastNetBytesOut: UInt64 = 0
var lastMouseX: Double = 0
var lastMouseY: Double = 0
var lastMouseInitialized = false
var lastFrontmostApp: String = ""
var knownDownloads: Set<String> = []
var runningApps: Set<String> = []

// MARK: - Keycode Map
let keycodeNames: [Int64: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
    8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
    16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
    23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
    30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
    36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
    42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
    48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape",
    54: "RightCmd", 55: "LeftCmd", 56: "LeftShift", 57: "CapsLock",
    58: "LeftOption", 59: "LeftControl", 60: "RightShift",
    61: "RightOption", 62: "RightControl", 63: "Fn",
    65: "NumpadDecimal", 67: "Numpad*", 69: "Numpad+",
    71: "NumpadClear", 75: "Numpad/", 76: "NumpadEnter",
    78: "Numpad-", 81: "Numpad=", 82: "Numpad0", 83: "Numpad1",
    84: "Numpad2", 85: "Numpad3", 86: "Numpad4", 87: "Numpad5",
    88: "Numpad6", 89: "Numpad7", 91: "Numpad8", 92: "Numpad9",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
    103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
    113: "F15", 115: "Home", 116: "PageUp", 117: "ForwardDelete",
    118: "F4", 119: "End", 120: "F2", 121: "PageDown", 122: "F1",
    123: "LeftArrow", 124: "RightArrow", 125: "DownArrow", 126: "UpArrow"
]

// MARK: - Helpers
func today() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

func unlockFile() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
    p.arguments = ["nouchg", dataFile]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

func lockFile() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
    p.arguments = ["uchg", dataFile]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

func runCommand(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

// MARK: - Load / Save
func loadData() -> MacStatsData {
    guard let encrypted = try? Data(contentsOf: URL(fileURLWithPath: dataFile)),
          let decrypted = decrypt(encrypted, key: encKey),
          let d = try? JSONDecoder().decode(MacStatsData.self, from: decrypted) else {
        exit(1)
    }
    return d
}

func flush() {
    // Merge pending into stats
    stats.totalKeystrokes += pKeystrokes
    for (k, v) in pKeyCounts { stats.keyCounts[k, default: 0] += v }
    for (k, v) in pDailyKeystrokes { stats.dailyKeystrokes[k, default: 0] += v }
    stats.totalScrollPoints += pScrollPoints
    stats.totalScreenOnSeconds += pScreenSeconds
    for (k, v) in pDailyScreenSeconds { stats.dailyScreenSeconds[k, default: 0] += v }
    stats.totalNetworkBytesIn += pNetBytesIn
    stats.totalNetworkBytesOut += pNetBytesOut
    stats.totalSecondsPluggedIn += pSecondsPluggedIn
    stats.totalSecondsOnBattery += pSecondsOnBattery
    stats.totalWattHoursConsumed += pWattHours
    for (k, v) in pAppLaunches { stats.appLaunchCounts[k, default: 0] += v }
    for (k, v) in pAppActiveSeconds { stats.appActiveSeconds[k, default: 0] += v }
    stats.totalFilesDownloaded += pFilesDownloaded
    stats.totalDownloadedBytes += pDownloadedBytes
    stats.totalClicks += pClicks
    for (k, v) in pClickCounts { stats.clickCounts[k, default: 0] += v }
    stats.totalMousePoints += pMousePoints

    // Reset pending
    pKeystrokes = 0; pKeyCounts = [:]; pDailyKeystrokes = [:]
    pScrollPoints = 0
    pScreenSeconds = 0; pDailyScreenSeconds = [:]
    pNetBytesIn = 0; pNetBytesOut = 0
    pSecondsPluggedIn = 0; pSecondsOnBattery = 0; pWattHours = 0
    pAppLaunches = [:]; pAppActiveSeconds = [:]
    pFilesDownloaded = 0; pDownloadedBytes = 0
    pClicks = 0; pClickCounts = [:]
    pMousePoints = 0

    // Write encrypted
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let json = try? encoder.encode(stats),
          let encrypted = encrypt(json, key: encKey) else { return }

    unlockFile()
    try? encrypted.write(to: URL(fileURLWithPath: dataFile), options: .atomic)
    lockFile()
}

// MARK: - Screen State
func isScreenOnAndUnlocked() -> Bool {
    // Check display sleep
    if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
        return false
    }

    // Check screen lock via session dictionary
    if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool, locked {
            return false
        }
    }

    return true
}

// MARK: - Network Bytes
func getNetworkBytes() -> (bytesIn: UInt64, bytesOut: UInt64) {
    let output = runCommand("/usr/sbin/netstat", ["-ib"])
    var totalIn: UInt64 = 0
    var totalOut: UInt64 = 0

    for line in output.components(separatedBy: "\n") {
        // Match en* interfaces (en0 = WiFi, en* = others)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("en") else { continue }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        // netstat -ib format: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes
        // Some rows have fewer columns (link-level vs ip rows)
        guard parts.count >= 10 else { continue }

        // Only count rows that have numeric byte values
        if let bIn = UInt64(parts[6]), let bOut = UInt64(parts[9]) {
            totalIn += bIn
            totalOut += bOut
        }
    }

    return (totalIn, totalOut)
}

// MARK: - Battery / Power
struct PowerState {
    var isPluggedIn: Bool
    var watts: Double // instantaneous power draw
}

func getPowerState() -> PowerState {
    let output = runCommand("/usr/sbin/ioreg", ["-r", "-w0", "-c", "AppleSmartBattery"])

    var isPluggedIn = false
    var amperage: Int64 = 0
    var voltage: Int64 = 0

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("\"ExternalConnected\"") {
            isPluggedIn = trimmed.contains("Yes")
        }
        if trimmed.hasPrefix("\"Amperage\"") {
            if let match = trimmed.split(separator: "=").last {
                let numStr = match.trimmingCharacters(in: .whitespaces)
                if let unsigned = UInt64(numStr) {
                    amperage = Int64(bitPattern: unsigned)
                }
            }
        }
        if trimmed.hasPrefix("\"Voltage\"") && !trimmed.contains("CellVoltage") && !trimmed.contains("Soc1Voltage") && !trimmed.contains("MinimumPack") && !trimmed.contains("MaximumPack") {
            if let match = trimmed.split(separator: "=").last {
                let numStr = match.trimmingCharacters(in: .whitespaces)
                voltage = Int64(numStr) ?? 0
            }
        }
    }

    // Amperage is in mA (negative when discharging), Voltage in mV
    // Power = |A| * V / 1,000,000 = Watts
    let watts = Double(abs(amperage)) * Double(voltage) / 1_000_000.0

    return PowerState(isPluggedIn: isPluggedIn, watts: watts)
}

// MARK: - Downloads Scanner
func scanDownloads() {
    let downloadsPath = NSString(string: "~/Downloads").expandingTildeInPath
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(atPath: downloadsPath) else { return }

    for filename in contents {
        guard !filename.hasPrefix(".") else { continue }
        let fullPath = "\(downloadsPath)/\(filename)"

        guard let attrs = try? fm.attributesOfItem(atPath: fullPath) else { continue }
        let fileSize = attrs[.size] as? UInt64 ?? 0

        // Use filename + size as unique identifier
        let fileKey = "\(filename)|\(fileSize)"

        if !knownDownloads.contains(fileKey) {
            knownDownloads.insert(fileKey)

            // Only count files modified in the last 60 seconds as new downloads
            if let modDate = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) < 60 {
                pFilesDownloaded += 1
                pDownloadedBytes += fileSize
            }
        }
    }
}

func initializeKnownDownloads() {
    let downloadsPath = NSString(string: "~/Downloads").expandingTildeInPath
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(atPath: downloadsPath) else { return }

    for filename in contents {
        guard !filename.hasPrefix(".") else { continue }
        let fullPath = "\(downloadsPath)/\(filename)"
        guard let attrs = try? fm.attributesOfItem(atPath: fullPath) else { continue }
        let fileSize = attrs[.size] as? UInt64 ?? 0
        knownDownloads.insert("\(filename)|\(fileSize)")
    }
}

// MARK: - App Tracking
func initializeRunningApps() {
    for app in NSWorkspace.shared.runningApplications {
        if let name = app.localizedName, app.activationPolicy == .regular {
            runningApps.insert(name)
        }
    }
}

func checkAppLaunches() {
    var currentApps: Set<String> = []
    for app in NSWorkspace.shared.runningApplications {
        if let name = app.localizedName, app.activationPolicy == .regular {
            currentApps.insert(name)
        }
    }

    // New apps = launched since last check
    let newApps = currentApps.subtracting(runningApps)
    for app in newApps {
        pAppLaunches[app, default: 0] += 1
    }

    runningApps = currentApps
}

// MARK: - CGEventTap Callback
let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
    // Re-enable tap if disabled
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = tapRef {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    switch type {
    case .keyDown:
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyName = keycodeNames[keycode] ?? "Key\(keycode)"
        pKeystrokes += 1
        pKeyCounts[keyName, default: 0] += 1
        pDailyKeystrokes[today(), default: 0] += 1

    case .scrollWheel:
        let deltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let deltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        pScrollPoints += abs(deltaX) + abs(deltaY)

    case .leftMouseDown:
        pClicks += 1
        pClickCounts["LeftClick", default: 0] += 1

    case .rightMouseDown:
        pClicks += 1
        pClickCounts["RightClick", default: 0] += 1

    case .otherMouseDown:
        pClicks += 1
        pClickCounts["MiddleClick", default: 0] += 1

    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        let x = event.location.x
        let y = event.location.y
        if lastMouseInitialized {
            let dx = x - lastMouseX
            let dy = y - lastMouseY
            pMousePoints += sqrt(dx * dx + dy * dy)
        }
        lastMouseX = x
        lastMouseY = y
        lastMouseInitialized = true

    default:
        break
    }

    return Unmanaged.passRetained(event)
}

// MARK: - Signal Handling
signal(SIGTERM) { _ in flush(); exit(0) }
signal(SIGINT) { _ in flush(); exit(0) }

// MARK: - Main
stats = loadData()

// Initialize baselines
let initialNet = getNetworkBytes()
lastNetBytesIn = initialNet.bytesIn
lastNetBytesOut = initialNet.bytesOut
initializeKnownDownloads()
initializeRunningApps()

// Event tap: keys + scroll + clicks + mouse movement
let eventMask: CGEventMask = (
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.scrollWheel.rawValue) |
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.mouseMoved.rawValue) |
    (1 << CGEventType.leftMouseDragged.rawValue) |
    (1 << CGEventType.rightMouseDragged.rawValue) |
    (1 << CGEventType.otherMouseDragged.rawValue)
)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
) else {
    exit(1)
}

tapRef = tap
let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

// MARK: - 5-Second Timer (screen time, active app)
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    let day = today()

    // Screen time
    if isScreenOnAndUnlocked() {
        pScreenSeconds += 5
        pDailyScreenSeconds[day, default: 0] += 5
    }

    // Active app tracking (only if not idle)
    let idleTime = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    if idleTime < idleThresholdSeconds, isScreenOnAndUnlocked() {
        if let app = NSWorkspace.shared.frontmostApplication?.localizedName {
            pAppActiveSeconds[app, default: 0] += 5
        }
    }
}

// MARK: - 10-Second Timer (power, network)
Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
    // Power
    let power = getPowerState()
    if power.isPluggedIn {
        pSecondsPluggedIn += 10
    } else {
        pSecondsOnBattery += 10
    }
    // Accumulate watt-hours: watts * (10 seconds / 3600 seconds per hour)
    pWattHours += power.watts * (10.0 / 3600.0)

    // Network
    let net = getNetworkBytes()
    let deltaIn: UInt64
    let deltaOut: UInt64

    // Handle reboot (counters reset to low values)
    if net.bytesIn >= lastNetBytesIn {
        deltaIn = net.bytesIn - lastNetBytesIn
    } else {
        deltaIn = net.bytesIn
    }
    if net.bytesOut >= lastNetBytesOut {
        deltaOut = net.bytesOut - lastNetBytesOut
    } else {
        deltaOut = net.bytesOut
    }

    pNetBytesIn += deltaIn
    pNetBytesOut += deltaOut
    lastNetBytesIn = net.bytesIn
    lastNetBytesOut = net.bytesOut
}

// MARK: - 10-Second Timer (downloads, app launches, save)
Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
    scanDownloads()
    checkAppLaunches()
    flush()
}

// MARK: - Flush on Sleep (prevent data loss if battery dies during sleep)
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.willSleepNotification,
    object: nil,
    queue: .main
) { _ in
    flush()
}

// Also flush on screen lock
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.screenIsLocked"),
    object: nil,
    queue: .main
) { _ in
    flush()
}

// Run forever
CFRunLoopRun()
