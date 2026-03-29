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
swiftc -O -o "$SCRIPT_DIR/macstats-daemon" "$SCRIPT_DIR/MacStatsDaemon.swift" -framework Cocoa -framework CoreGraphics -framework CoreServices 2>/dev/null
echo "  Compiling CLI..."
swiftc -O -o "$SCRIPT_DIR/macstats" "$SCRIPT_DIR/MacStats.swift" 2>/dev/null
echo "  ✓ Compiled"

sudo mkdir -p /usr/local/bin
sudo cp "$SCRIPT_DIR/macstats-daemon" /usr/local/bin/macstats-daemon
sudo cp "$SCRIPT_DIR/macstats" /usr/local/bin/macstats
sudo chmod +x /usr/local/bin/macstats-daemon
sudo chmod +x /usr/local/bin/macstats
sudo codesign -f -s - /usr/local/bin/macstats-daemon 2>/dev/null
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
    var totalFilesCreated: UInt64
    var totalFilesCreatedBytes: UInt64
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
    totalFilesCreated: 0, totalFilesCreatedBytes: 0,
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

# ANSI colors
RED='\033[1;31m'
YEL='\033[1;33m'
GRN='\033[1;32m'
CYN='\033[1;36m'
WHT='\033[1;97m'
DIM='\033[2m'
RST='\033[0m'
BG_RED='\033[41;97;1m'
CLR='\033[2K\r'

# Build a tiny Swift helper that tests if event tap can be created
cat > /tmp/.ms_check.swift << 'CHECKEOF'
import Foundation
import CoreGraphics
let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: { _, _, event, _ in Unmanaged.passRetained(event) },
    userInfo: nil
)
exit(tap != nil ? 0 : 1)
CHECKEOF
swiftc -O -o /tmp/.ms_check /tmp/.ms_check.swift -framework CoreGraphics 2>/dev/null

SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

echo ""
echo -e "  ${BG_RED}                                                ${RST}"
echo -e "  ${BG_RED}   ⚠️  ACTION REQUIRED — DO THIS NOW            ${RST}"
echo -e "  ${BG_RED}                                                ${RST}"
echo ""
echo -e "  ${WHT}macstats needs two permissions to track your input.${RST}"
echo ""

# --- STEP 1: Accessibility ---
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo -e "  ${YEL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "  ${YEL}  STEP 1 of 2: ACCESSIBILITY${RST}"
echo -e "  ${YEL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  ${CYN}1.${RST} Click the ${WHT}+${RST} button at the bottom"
echo -e "  ${CYN}2.${RST} Press ${WHT}Cmd+Shift+G${RST} and type: ${WHT}/usr/local/bin/${RST}"
echo -e "  ${CYN}3.${RST} Select ${WHT}macstats-daemon${RST} → click ${WHT}Open${RST}"
echo -e "  ${CYN}4.${RST} Make sure the toggle is ${WHT}ON${RST}"
echo ""

# Poll every 1 second until event tap works (accessibility granted)
i=0
while true; do
    if /tmp/.ms_check 2>/dev/null; then
        echo -e "${CLR}  ${GRN}✓ Accessibility permission granted!${RST}"
        break
    fi
    echo -ne "${CLR}  ${DIM}${SPINNER[$((i % 10))]} Waiting for Accessibility permission...${RST}"
    sleep 1
    i=$((i + 1))
done

echo ""

# --- STEP 2: Input Monitoring ---
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

echo -e "  ${YEL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "  ${YEL}  STEP 2 of 2: INPUT MONITORING${RST}"
echo -e "  ${YEL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  ${CYN}1.${RST} Click the ${WHT}+${RST} button at the bottom"
echo -e "  ${CYN}2.${RST} Press ${WHT}Cmd+Shift+G${RST} and type: ${WHT}/usr/local/bin/${RST}"
echo -e "  ${CYN}3.${RST} Select ${WHT}macstats-daemon${RST} → click ${WHT}Open${RST}"
echo -e "  ${CYN}4.${RST} Make sure the toggle is ${WHT}ON${RST}"
echo ""
echo -e "  ${DIM}(Input Monitoring cannot be auto-detected.${RST}"
echo -e "  ${DIM} It will be verified when the daemon starts.)${RST}"
echo ""
echo -e "  ${DIM}Press Enter when done...${RST}"
read -r
echo -e "  ${GRN}✓ Input Monitoring configured!${RST}"
echo ""

# Restart daemon to pick up permissions
launchctl unload "$PLIST_DIR/$PLIST_NAME.plist" 2>/dev/null || true
launchctl load "$PLIST_DIR/$PLIST_NAME.plist"

# Clean up
rm -f /tmp/.ms_check /tmp/.ms_check.swift

echo -e "  ${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "  ${GRN}  ✓ INSTALLATION COMPLETE${RST}"
echo -e "  ${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  ${WHT}macstats is now tracking in the background.${RST}"
echo -e "  ${WHT}Close this terminal and use your Mac normally.${RST}"
echo ""
echo -e "  ${WHT}To view your stats anytime:${RST}"
echo -e "  ${CYN}  macstats${RST}              ${DIM}full overview${RST}"
echo -e "  ${CYN}  macstats --help${RST}       ${DIM}all commands${RST}"
echo ""
