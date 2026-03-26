#!/bin/bash
set -e

echo ""
echo "  ╔═════════════════════════════════════════════╗"
echo "  ║          MAC STATS INSTALLER                 ║"
echo "  ╚═════════════════════════════════════════════╝"
echo ""

if ! command -v swiftc &> /dev/null; then
    echo "  Swift not found. Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "  Run this script again after installation."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$HOME/.macstats"
DATA_FILE="$DATA_DIR/data.dat"
PLIST_NAME="com.macstats.daemon"
PLIST_DIR="$HOME/Library/LaunchAgents"

if [ -f "$DATA_FILE" ]; then
    echo "  Data file exists. Reinstalling binaries only."
    SKIP_INIT=true
else
    SKIP_INIT=false
fi

echo "  Compiling daemon..."
swiftc -O -o "$SCRIPT_DIR/macstats-daemon" "$SCRIPT_DIR/MacStatsDaemon.swift" -framework Cocoa -framework CoreGraphics 2>/dev/null
echo "  Compiling CLI..."
swiftc -O -o "$SCRIPT_DIR/macstats" "$SCRIPT_DIR/MacStats.swift" 2>/dev/null
echo "  ✓ Compiled"

sudo mkdir -p /usr/local/bin
sudo cp "$SCRIPT_DIR/macstats-daemon" /usr/local/bin/macstats-daemon
sudo cp "$SCRIPT_DIR/macstats" /usr/local/bin/macstats
sudo chmod +x /usr/local/bin/macstats-daemon
sudo chmod +x /usr/local/bin/macstats
echo "  ✓ Installed to /usr/local/bin"

if [ "$SKIP_INIT" = false ]; then
    mkdir -p "$DATA_DIR"

    cat > "/tmp/.ms_init.swift" << 'INITEOF'
import Foundation
import CryptoKit

let dataDir = CommandLine.arguments[1]
let dataFile = CommandLine.arguments[2]

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
    return SymmetricKey(data: SHA256.hash(data: Data(uuid.utf8)))
}

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
    var totalClicks: UInt64
    var clickCounts: [String: UInt64]
    var totalMousePoints: Double
}

let f = DateFormatter()
f.dateFormat = "yyyy-MM-dd"

let seed = MacStatsData(
    startDate: f.string(from: Date()),
    totalKeystrokes: 0, keyCounts: [:], dailyKeystrokes: [:],
    totalScrollPoints: 0,
    totalScreenOnSeconds: 0, dailyScreenSeconds: [:],
    totalNetworkBytesIn: 0, totalNetworkBytesOut: 0,
    totalSecondsPluggedIn: 0, totalSecondsOnBattery: 0, totalWattHoursConsumed: 0,
    appLaunchCounts: [:], appActiveSeconds: [:],
    totalFilesDownloaded: 0, totalDownloadedBytes: 0,
    totalClicks: 0, clickCounts: [:],
    totalMousePoints: 0
)

let key = getMachineKey()
let json = try! JSONEncoder().encode(seed)
let sealed = try! AES.GCM.seal(json, using: key)
try! sealed.combined!.write(to: URL(fileURLWithPath: dataFile))

let lk = Process()
lk.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
lk.arguments = ["uchg", dataFile]
try? lk.run()
lk.waitUntilExit()
INITEOF

    swiftc -O -o /tmp/.ms_init /tmp/.ms_init.swift 2>/dev/null
    /tmp/.ms_init "$DATA_DIR" "$DATA_FILE"
    rm -f /tmp/.ms_init /tmp/.ms_init.swift
    echo "  ✓ Data encrypted and locked"
fi

mkdir -p "$PLIST_DIR"
if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
    launchctl unload "$PLIST_DIR/$PLIST_NAME.plist" 2>/dev/null || true
fi
cp "$SCRIPT_DIR/$PLIST_NAME.plist" "$PLIST_DIR/"
launchctl load "$PLIST_DIR/$PLIST_NAME.plist"
echo "  ✓ Daemon running"

echo ""
echo "  ══════════════════════════════════════════════"
echo ""
echo "  REQUIRED: Grant Accessibility access"
echo ""
echo "  System Settings → Privacy & Security → Accessibility"
echo "  Click + → Add /usr/local/bin/macstats-daemon"
echo ""
echo "  Then restart the daemon:"
echo "    launchctl unload ~/Library/LaunchAgents/$PLIST_NAME.plist"
echo "    launchctl load ~/Library/LaunchAgents/$PLIST_NAME.plist"
echo ""
echo "  View stats:  macstats"
echo "  All options: macstats --help"
echo ""
