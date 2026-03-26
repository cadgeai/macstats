# macstats

A silent, encrypted daemon that tracks everything you do on your Mac, forever.

Every keystroke, every click, every pixel your cursor moves, every watt your machine consumes. One command to see it all.

## What it tracks

| Metric | Detail |
|--------|--------|
| **Keystrokes** | Every key, individually mapped — letters, modifiers, F-keys, arrows, everything |
| **Clicks** | Left, right, middle — each counted separately |
| **Cursor movement** | Total distance your cursor has traveled, in miles |
| **Scroll distance** | Total scroll distance, in miles |
| **Screen time** | Every second your screen is on and unlocked, broken down by day |
| **Active app time** | Minutes spent in each app (frontmost + not idle) |
| **App launches** | How many times you've opened each app |
| **Network** | Total bytes downloaded and uploaded over WiFi |
| **Power** | Kilowatt-hours consumed, time on AC vs battery |
| **Downloads** | Total files downloaded and their combined size |

## Demo

```
  ┌─────────────────────────────────────────┐
  │         M A C   L I F E T I M E          │
  └─────────────────────────────────────────┘

  tracking since 2026-01-01

  2,847,391 keystrokes
  743,218 clicks

  ⌨  KEYBOARD
    today            8,412
    most pressed     Space (389,201)

  ◎  TRACKPAD
    LeftClick        698,442
    RightClick       41,519

  ⤳  CURSOR
    distance         26.41 miles

  ↕  SCROLL
    distance         14.72 miles

  ◉  SCREEN TIME
    lifetime         94d 7h 23m
    today            6h 41m

  ⚡  POWER
    consumed         87.34 kWh
    on AC            62d 14h 8m
    on battery       31d 17h 15m

  ⇅  NETWORK
    ↓ downloaded     1.4 TB
    ↑ uploaded       247.8 GB
```

Output is color-coded in your terminal.

## Install

Requires macOS and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/cadgeai/macstats.git
cd macstats
chmod +x install.sh
swiftc -O -o macstats-daemon MacStatsDaemon.swift -framework Cocoa -framework CoreGraphics
swiftc -O -o macstats MacStats.swift
sudo cp macstats-daemon macstats /usr/local/bin/
./install.sh
```

Then grant Accessibility access (required to capture keystrokes and clicks):

1. **System Settings → Privacy & Security → Accessibility**
2. Click **+**, press **Cmd+Shift+G**, type `/usr/local/bin/`
3. Select `macstats-daemon`, click Open, toggle ON

Restart the daemon to pick up the permission:

```bash
launchctl unload ~/Library/LaunchAgents/com.macstats.daemon.plist
launchctl load ~/Library/LaunchAgents/com.macstats.daemon.plist
```

Verify:

```bash
macstats
```

That's it. It runs on every login, restarts on crash, and never makes a sound.

## Usage

```
macstats              full overview
macstats --keys       per-key breakdown with bar chart
macstats --clicks     click type breakdown
macstats --apps       active app time ranking
macstats --launches   app launch counts
macstats --screen     daily screen time
macstats --days       daily keystrokes
macstats --json       raw decrypted JSON
macstats --help       show all commands
```

## How it works

- **CGEventTap** listens for keystrokes, clicks, scroll, and cursor movement
- **NSWorkspace** tracks frontmost app and app launches
- **IOKit** reads battery amperage and voltage every 10 seconds
- **netstat** polls network interface bytes
- **FSEvents** watches `~/Downloads` for new files
- Data is **AES-256-GCM encrypted** using a key derived from your Mac's hardware UUID
- Data file is marked **immutable** (`chflags uchg`) to prevent accidental deletion
- Everything flushes to disk every 10 seconds, and immediately on sleep or screen lock
- LaunchAgent auto-starts on login with `KeepAlive` for crash recovery

## Where data lives

```
~/.macstats/data.dat          encrypted data file
/usr/local/bin/macstats-daemon   the daemon
/usr/local/bin/macstats          the CLI viewer
~/Library/LaunchAgents/com.macstats.daemon.plist   auto-start config
```

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.macstats.daemon.plist
rm ~/Library/LaunchAgents/com.macstats.daemon.plist
sudo rm /usr/local/bin/macstats-daemon /usr/local/bin/macstats
chflags nouchg ~/.macstats/data.dat
rm -rf ~/.macstats
```

Remove `macstats-daemon` from System Settings → Accessibility.

## Limitations

- Cannot capture keystrokes on the lock screen or FileVault pre-boot (macOS blocks this for security)
- Power tracking is estimated from battery sensor data, not wall power — accurate to ~5-10%
- Downloads are tracked by watching `~/Downloads` only, not browser-level
- A force shutdown (holding power 5+ seconds) can lose up to 10 seconds of data

## License

MIT