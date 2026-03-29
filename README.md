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
| **Network** | Total bytes downloaded and uploaded over WiFi/Ethernet |
| **Power** | Kilowatt-hours consumed, time on AC vs battery |
| **Downloads** | Files downloaded from the internet (detected via macOS quarantine attribute), tracked filesystem-wide |
| **Files created** | Every new file created on disk — total count and size |

## Demo

```
  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
  ┃          M A C   L I F E T I M E              ┃
  ┃            since 2025-04-09                   ┃
  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

       2,847,391          743,218          94d 7h 23m
      keystrokes          clicks           screen time

  ── ⌨️  KEYBOARD ───────────────────────────────
  │  today               8,412
  │  most pressed        Space (389,201)
  │
  ── 🖱️  TRACKPAD ───────────────────────────────
  │  LeftClick           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░  698,442
  │  RightClick          ▓░░░░░░░░░░░░░░░░   41,519
  │
  ── 🏃 MOVEMENT ────────────────────────────────
  │  cursor              26.41 miles
  │  scroll              14.72 miles
  │
  ── 🖥️  SCREEN TIME ───────────────────────────
  │  lifetime            94d 7h 23m
  │  today               6h 41m
  │
  ── 📊 TOP APPS ────────────────────────────────
  │  🥇 Google Chrome    ▓▓▓▓▓▓▓▓▓▓▓▓░░  48d 2h
  │  🥈 Terminal         ▓▓▓▓▓░░░░░░░░░  22d 11h
  │  🥉 VS Code          ▓▓▓░░░░░░░░░░░  14d 6h
  │
  ── 🌐 NETWORK ─────────────────────────────────
  │  ↓ downloaded        1.4 TB
  │  ↑ uploaded          247.8 GB
  │
  ── ⚡ POWER ───────────────────────────────────
  │  consumed            87.34 kWh
  │  on AC               62d 14h 8m  ●
  │  on battery          31d 17h 15m ●
  │
  ── 📥 DOWNLOADS ───────────────────────────────
  │  files               2,847
  │  total size          142.7 GB
  │
  ── 📁 FILES CREATED ──────────────────────────
  │  files               1,247,391
  │  total size          892.4 GB
```

Output is color-coded in your terminal.

## Install

Requires macOS and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/cadgeai/macstats.git
cd macstats
chmod +x install.sh
./install.sh
```

The installer compiles, installs, code-signs, and starts the daemon automatically. It will open System Settings and guide you through granting **Accessibility** and **Input Monitoring** permissions — just follow the on-screen instructions.

Once complete, verify:

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

- **CGEventTap** listens for keystrokes (including modifier keys via `flagsChanged`), clicks, scroll, and cursor movement
- **NSWorkspace** tracks frontmost app and app launches
- **IOKit** reads battery amperage and voltage every 10 seconds
- **netstat** polls network interface bytes (deduplicated per interface)
- **FSEvents** watches `/Users` filesystem-wide for new file creation
- **Quarantine attribute** (`com.apple.quarantine`) identifies real internet downloads vs regular files
- **Inode tracking + stable-size detection** ensures accurate file count and final file size
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
# 1. Remove plist first (prevents daemon from restarting)
rm -f ~/Library/LaunchAgents/com.macstats.daemon.plist

# 2. Kill the daemon
pkill -9 macstats-daemon 2>/dev/null

# 3. Remove binaries
sudo rm -f /usr/local/bin/macstats-daemon /usr/local/bin/macstats

# 4. Unlock and remove data
sudo chflags nouchg ~/.macstats/data.dat
sudo rm -rf ~/.macstats
```

Then remove `macstats-daemon` from both:
- **System Settings → Privacy & Security → Accessibility**
- **System Settings → Privacy & Security → Input Monitoring**

## Limitations

- Cannot capture keystrokes on the lock screen or FileVault pre-boot (macOS blocks this for security)
- Power tracking is estimated from battery sensor data, not wall power — accurate to ~5-10%
- Downloads are detected via macOS quarantine attribute in user-facing directories (~/Downloads, ~/Desktop, ~/Documents) — covers browsers and system curl, but not git, wget, or scp
- A force shutdown (holding power 5+ seconds) can lose up to 10 seconds of data

## License

MIT
