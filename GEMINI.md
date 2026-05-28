# TBControl 项目指南 (GEMINI.md)

本文件记录了 TBControl 项目的核心架构、开发流程及关键技术决策，作为 AI 助手及开发者的持久化上下文。

## 1. 项目架构

项目由三个核心组件组成：
- **Kext (DisableTurboBoost)**: 内核扩展，通过修改 `MSR_IA32_MISC_ENABLE` 寄存器 (0x1a0) 的第 38 位来控制睿频。
- **Daemon (tbcontrold)**: 以 root 权限运行的后台进程。负责：
  - 加载/卸载 Kext。
  - 通过 SMC 读取 CPU 温度和风扇转速（支持双风扇取最高值）。
  - 支持手动控制风扇模式与转速（集成 Fan Helper 功能）。
  - 维护自动模式逻辑（温度、负载、电池、风扇阈值降至 4600 RPM）。
  - 提供 Unix Socket IPC 服务 (`/tmp/tbcontrol.sock`)。
  - 支持的新指令：`set_fan_speed` (设置转速), `reset_fans` (恢复自动)。
  - 持久化配置 (`/Library/Application Support/TBControl/settings.json`)。
- **App (TBControl)**: 菜单栏 UI 程序。负责：
  - 显示硬件状态。
  - 提供用户交互界面。
  - Touch Bar 实时看板显示（组件化布局，采用等宽数字字体防止抖动）。
  - 自动版本检测（支持点击菜单触发，带 1 小时冷却机制）与自启管理。

## 2. 关键技术细节

- **IPC 协议**: 使用基于 Unix Socket 的 JSON 文本协议。所有指令需以 `\n` 结尾。
- **SMC 读取**: 
  - 参考 `Stats` 开源项目优化了数据解析逻辑。
  - 支持通用 `spxx` 固定小数点类型解析。
  - 自动识别并显示 0 RPM（风扇停止状态）。
- **Touch Bar**: 
  - 采用 **System Modal** 机制实现跨应用常驻显示。使用私有 API `presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:` 并设置 `placement: 1` (System 级别) 以获得最高显示优先级。
  - 调用私有函数 `DFRElementSetControlStripPresenceForIdentifier` 确保图标在 Control Strip 中常驻，并实时显示核心状态（如温度）。
  - **重要**: 调用私有 C/ObjC API 时，必须显式将 Swift 类型桥接为 Objective-C 对象（如 `NSString`），直接传递 Swift 结构体或 String 会导致 `SIGSEGV` 崩溃。
  - **布局**: 组件化布局，采用等宽数字字体。更新文本后必须调用 `sizeToFit()` 以确保组件尺寸正确，防止界面空白。
  - 动态从 `sysctl machdep.cpu.brand_string` 提取 CPU 基础频率。

- **架构兼容性**: 
  - 必须构建 **Universal Binaries (x86_64 + arm64)**。
  - 链接私有框架：在 `Package.swift` 中需通过 `unsafeFlags` 链接 `/System/Library/PrivateFrameworks/DFRFoundation.framework`。
  - Kext 加载需要禁用 SIP 或设置为 `--without kext`。
  - 守护进程必须以 root 权限运行。

## 3. 开发与发布流程

### 本地构建
使用脚本进行完整构建：
```bash
./Scripts/build.sh
```
此脚本会执行 Kext 编译、Swift 编译、二进制瘦身 (Strip)、自签名及 DMG 打包。

### 版本发布 (GitHub Actions)
项目已集成自动化发布流水线：
1. **触发方式**: 推送格式为 `v*` 的 Git Tag（例如 `v1.2.0`）。
2. **自动逻辑**:
   - CI 会自动获取 Tag 名并注入到 App 的 `Info.plist` 中。
   - CI 会编译并打包出 `TBControl.dmg`。
   - 自动在 GitHub 上创建 Release 并上传附件。

### 安装与卸载
- **安装**: 建议通过 App 内的“安装守护进程”或 `sudo ./Scripts/install.sh`。
- **卸载**: 使用 App 菜单中的“彻底卸载组件”或 `sudo ./Scripts/uninstall.sh`。

## 4. 常见问题排查
- **状态栏显示 ⚠️**: 通常是 Kext 未被系统允许加载。需前往“系统设置 > 隐私与安全性”允许。
- **Touch Bar 空白**: 
  - 确保系统设置中的 Touch Bar 显示模式包含“App 控件”。
  - 代码层面：更新文本后必须调用 `sizeToFit()` 以重新计算组件尺寸，否则会被系统识别为 0x0 而不显示。
- **转速异常**: 硬件读取偶发脏数据，代码中已增加 15000 RPM 的阈值过滤。
