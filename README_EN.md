# TBControl — macOS Turbo Boost Control Tool

<p align="center">
  <img src="Resources/AppIcon.png" width="96" alt="TBControl Icon"/>
</p>

<p align="center">
  <img src="Resources/Screenshot.png" width="700" alt="TBControl Dashboard"/>
  <br/>
  <em>Dashboard — Sidebar Navigation + Gauge + Real-time Charts</em>
</p>

<p align="center">
  <img src="Resources/Screenshot2.png" width="280" alt="TBControl Settings"/>
  <br/>
  <em>Settings — Grouped Form with Mode Selection</em>
</p>

<p align="center">
  <img src="Resources/Screenshot3.png" width="400" alt="TBControl Touch Bar"/>
  <br/>
  <em>Touch Bar Real-time Monitoring</em>
</p>

A lightweight Turbo Boost control utility for Intel Macs. Controls CPU Turbo Boost at the kernel level via a kernel extension (Kext), with multiple intelligent auto modes.

---

## Features

- **Manual Control** — One-click enable/disable Turbo Boost
- **Auto Modes**:
  - **Temperature** — Disable above 75°C, re-enable below 65°C (10°C hysteresis)
  - **CPU Load** — Disable when load ≥ 75% for 10+ seconds
  - **Battery** — Disable on battery power ≤ 30%
  - **Fan** — Disable above 5500 RPM, re-enable below 4000 RPM for 10s
- **Real-time Dashboard**:
  - **Menu Bar** — CPU temp, fan speed, load, and current mode
  - **Touch Bar** — Frequency, temp, fan, battery, network on MacBook Pro Touch Bar
- **Smart Experience**:
  - Native notifications on state changes
  - Login item auto-launch
  - Persistent state across restarts
- **Production Ready**:
  - One-click uninstall (cleans Kext, daemon, and config)
  - Auto version check against GitHub releases
  - `os_log` integration for Console.app debugging

## Compatibility

| Requirement | Note |
|-------------|------|
| **CPU** | Intel only (MacBook Pro/Air/iMac, etc.) |
| **Touch Bar** | MacBook Pro models with Touch Bar |
| **OS** | macOS 11.0 (Big Sur) and later |
| **⚠️ Apple Silicon** | **Not supported** |

## Installation

### 1. Prerequisites (Important)

This tool uses a third-party unsigned kernel extension. You must:

1. **Disable SIP**: Boot into Recovery Mode → Terminal → `csrutil disable`
2. **Allow kernel extension**: macOS 11+ → System Settings → Privacy & Security → allow the extension

### 2. Build from Source

```bash
# Clone
git clone https://github.com/BestWaveRock/TBControl.git
cd TBControl

# Build App & DMG
./Scripts/build.sh
```

Output in `build/TBControl.app` and `build/TBControl.dmg`.

### 3. Install

1. Drag `TBControl.app` to **Applications**
2. First launch may prompt for admin password to install daemon (`tbcontrold`)
3. If menu bar shows `⚠️`, check System Settings for kext approval

## Operation Modes

| Mode | Behaviour |
|------|-----------|
| **Manual** | User-controlled, all auto logic suspended |
| **Auto — Temperature** | TB off when temp > 75°C, on when < 65°C |
| **Auto — Load** | TB off when CPU ≥ 75% for 10s |
| **Auto — Battery** | TB off on battery ≤ 30% |
| **Auto — Fan** | TB off when fan > 5500 RPM, on when < 4000 RPM for 10s |

## Technical Details

- **Kext**: Controls Turbo Boost via `MSR_IA32_MISC_ENABLE` register (bit 38)
- **SMC**: Reads hardware metrics via IOKit (System Management Controller)
- **Daemon**: Background process `tbcontrold` handles logic; the App is the UI layer

## License

MIT License — see [LICENSE](LICENSE)

## Disclaimer

This tool performs kernel-level register operations. Use at your own risk. The author is not responsible for any hardware damage or data loss.
