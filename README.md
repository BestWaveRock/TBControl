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

A lightweight Turbo Boost control utility for Intel Macs. Controls CPU Turbo Boost at the kernel level via a Kext, with multiple intelligent auto modes.

轻量级 Intel Mac 睿频控制工具，通过内核扩展实现 CPU 睿频状态底层控制，支持多种智能自动化模式。

---

## Features / 功能

- **Manual Control** — One-click enable/disable Turbo Boost · 一键启用/禁用
- **Auto Modes** · 自动模式：
  - **Temperature** — Disable above 75°C, re-enable below 65°C (10°C hysteresis) · 温度
  - **CPU Load** — Disable when load ≥ 75% for 10+ seconds · 负载
  - **Battery** — Disable on battery ≤ 30% · 电池
  - **Fan** — Disable above 5500 RPM, re-enable below 4000 RPM for 10s · 风扇
- **Real-time Dashboard** · 实时看板：
  - **Menu Bar** — CPU temp, fan speed, load, mode · 菜单栏
  - **Touch Bar** — Frequency, temp, fan, battery, network · Touch Bar 监控
- **Smart Experience** · 智能化体验：
  - Native notifications on state changes · 状态通知
  - Login item auto-launch · 开机自启
  - Persistent state across restarts · 状态持久化
- **Production Ready** · 生产级：
  - One-click uninstall · 一键卸载
  - Auto version check against GitHub releases · 版本检测
  - `os_log` integration for Console.app debugging · 系统日志

## Compatibility / 兼容性

| Requirement | Note |
|-------------|------|
| **CPU** | Intel only · 仅 Intel 架构 (MacBook Pro/Air/iMac) |
| **Touch Bar** | MacBook Pro models with Touch Bar |
| **OS** | macOS 11.0 (Big Sur) and later |
| **⚠️ Apple Silicon** | **Not supported** · 不支持 M 系列芯片 |

## Installation / 安装

### 1. Prerequisites (Important) / 环境准备

This tool uses a third-party unsigned kernel extension. You must:

- **Disable SIP**: Boot into Recovery Mode → Terminal → `csrutil disable`
- **Allow kext**: macOS 11+ → System Settings → Privacy & Security → allow the extension

### 2. Build from Source / 编译构建

```bash
# Clone / 克隆
git clone https://github.com/BestWaveRock/TBControl.git
cd TBControl

# Build App & DMG / 构建
./Scripts/build.sh
```

Output in `build/TBControl.app` and `build/TBControl.dmg`.

### 3. Install / 安装

1. Drag `TBControl.app` to **Applications**
2. First launch may prompt for admin password to install daemon (`tbcontrold`)
3. If menu bar shows `⚠️`, check System Settings for kext approval

## Operation Modes / 运行模式

| Mode | Behaviour |
|------|-----------|
| **Manual** | User-controlled, all auto logic suspended |
| **Auto — Temp** | TB off when temp > 75°C, on when < 65°C |
| **Auto — Load** | TB off when CPU ≥ 75% for 10s |
| **Auto — Battery** | TB off on battery ≤ 30% |
| **Auto — Fan** | TB off when fan > 5500 RPM, on when < 4000 RPM for 10s |

## Technical Details / 技术原理

- **Kext**: Controls Turbo Boost via `MSR_IA32_MISC_ENABLE` register (bit 38)
- **SMC**: Reads hardware metrics via IOKit (System Management Controller)
- **Daemon**: Background process `tbcontrold` handles logic; App is the UI layer

## License / 许可证

MIT License — see [LICENSE](LICENSE).

## Disclaimer / 免责声明

This tool performs kernel-level register operations. Use at your own risk. The author is not responsible for any hardware damage or data loss.

本工具涉及内核级别寄存器操作。作者不对因使用本工具导致的任何硬件损坏或数据丢失负责。
