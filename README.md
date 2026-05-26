# TBControl

macOS 菜单栏工具，用于控制 Intel Mac 的 **Turbo Boost** 睿频功能。支持手动开关和自动模式（基于 CPU 温度/电池电量）。

## 功能

- **手动开关** Turbo Boost — 菜单栏一键切换
- **实时监控** — CPU 负载、电池电量（macOS 26 暂无法读取 CPU 温度与风扇转速）
- **自动模式**：
  - 温度模式：超过阈值（默认 75°C）自动关睿频，低于阈值自动开
  - 电池模式：低于阈值（默认 30%）自动关睿频省电
- **后台守护进程** — launchd 管理，自启自愈，root 权限运行
- **温度保护** — kernel_task 高占用时自动限制睿频

## 架构

```
┌──────────────────┐     Unix Socket      ┌──────────────────┐
│  TBControl.app   │ ◄──────────────────► │  tbcontrold      │
│  (菜单栏 UI)      │    /tmp/tbcontrol.sock │  (root daemon)  │
│  Swift + AppKit  │     JSON 协议         │  Swift + C       │
└──────────────────┘                      └────────┬─────────┘
                                                   │
                                          ┌────────▼─────────┐
                                          │  DisableTurboBoost│
                                          │  .kext            │
                                          │  (MSR 0x1a0 bit38)│
                                          └──────────────────┘
```

## 构建

本地构建（需要 Xcode Command Line Tools）：

```bash
cd TBControl
bash Scripts/build.sh
```

产物在 `build/TBControl.dmg`。

GitHub Actions（无需本地 Xcode）：

1. 推送代码到 GitHub 仓库的 main 分支
2. Actions 自动编译，产物 Artifacts 中下载 DMG

## 安装

```bash
sudo bash Scripts/install.sh
```

安装步骤：
1. 复制 `.app` 到 `/Applications`
2. 安装内核扩展 `.kext` 到 `/Library/Application Support/TBControl/`
3. 安装 launchd daemon `com.tbcontrol.daemon`
4. 启动守护进程

**首次使用需要加载内核扩展：**

```bash
sudo kextutil -v /Library/Application\ Support/TBControl/DisableTurboBoost.kext
```

然后在 **系统设置 → 隐私与安全性** 中点击"允许"。

### SIP 要求

加载内核扩展需要 SIP（System Integrity Protection）关闭或设置为 `--without kext`：

1. 重启按住 `Cmd+R` 进入恢复模式
2. 菜单栏 → 终端
3. 执行：

```bash
csrutil enable --without kext
```

4. 重启

## 卸载

```bash
sudo bash Scripts/uninstall.sh
```

## 项目结构

```
TBControl/
├── Kext/                   # 内核扩展 (MSR 寄存器控制)
├── Sources/tbcontrold/     # 守护进程
├── Sources/TBControl/      # 菜单栏 App
├── Sources/Csmc/           # SMC 传感器读取 (C)
├── Scripts/                # 构建 & 安装脚本
└── .github/workflows/      # GitHub Actions 自动构建
```

## 许可证

Apache 2.0
