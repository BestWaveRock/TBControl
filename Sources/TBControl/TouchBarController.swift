import AppKit

// Private function to ensure the icon stays in the Control Strip
// Correct signature: void DFRElementSetControlStripPresenceForIdentifier(NSString *identifier, BOOL present);
@_silgen_name("DFRElementSetControlStripPresenceForIdentifier")
func DFRElementSetControlStripPresenceForIdentifier(_ identifier: AnyObject, _ enabled: Bool)

class TouchBarController: NSObject, NSTouchBarDelegate {
    var touchBar: NSTouchBar?
    
    // Labels/Buttons for Touch Bar items
    private var tbStateButton: NSButton?
    private var modeButton: NSButton?
    private let tempLabel = createLabel()
    private let fanLabel = createLabel()
    private let loadLabel = createLabel()
    private let batteryLabel = createLabel()
    private let freqLabel = createLabel()
    private let memLabel = createLabel()
    private var statsButton: NSButton?
    
    // Callbacks for interactions
    var onToggleTurbo: (() -> Void)?
    var onToggleMode: (() -> Void)?
    
    private static func createLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.sizeToFit()
        return label
    }
    
    private static func createButton(target: Any?, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: target, action: action)
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.bezelStyle = .rounded
        button.alignment = .center
        return button
    }
    
    private lazy var baseFrequency: String = {
        var size = size_t()
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandString = String(cString: brand)
        
        // Match something like "2.30GHz" or "2.3GHz"
        if let range = brandString.range(of: #"\d+\.\d+GHz"#, options: .regularExpression) {
            return String(brandString[range])
        }
        return "2.3GHz" // Fallback
    }()
    
    override init() {
        super.init()
        self.tbStateButton = TouchBarController.createButton(target: self, action: #selector(toggleTurbo))
        self.modeButton = TouchBarController.createButton(target: self, action: #selector(toggleMode))
    }
    
    func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        
        let configuredItems = UserDefaults.standard.stringArray(forKey: "touchBarItems") ?? ["tbState", "mode", "temp", "fan", "load", "battery", "freq"]
        var identifiers: [NSTouchBarItem.Identifier] = [.statsItem]
        
        for key in configuredItems {
            identifiers.append(.fixedSpaceSmall)
            switch key {
            case "tbState": identifiers.append(.tbStateItem)
            case "mode": identifiers.append(.modeItem)
            case "temp": identifiers.append(.tempItem)
            case "fan": identifiers.append(.fanItem)
            case "load": identifiers.append(.loadItem)
            case "battery": identifiers.append(.batteryItem)
            case "freq": identifiers.append(.freqItem)
            case "memory": identifiers.append(.memItem)
            default: break
            }
        }
        
        touchBar.defaultItemIdentifiers = identifiers
        self.touchBar = touchBar
        
        // Force creation of the stats item and add it to the system tray
        if let item = touchBar.item(forIdentifier: .statsItem) {
            NSTouchBarItem.addSystemTrayItem(item)
        }
        
        // Ensure the item is present in the Control Strip
        let identifier = NSTouchBarItem.Identifier.statsItem.rawValue as NSString
        DFRElementSetControlStripPresenceForIdentifier(identifier, true)
        
        return touchBar
    }
    
    @objc private func toggleTurbo() {
        onToggleTurbo?()
    }
    
    @objc private func toggleMode() {
        onToggleMode?()
    }
    
    @objc private func toggleFullBar() {
        // This is called when the Control Strip icon is tapped
        if let touchBar = self.touchBar {
            if #available(macOS 10.12.2, *) {
                // Use the enhanced presentation method with placement
                NSTouchBar.presentSystemModalFunctionBar(touchBar, placement: 1, systemTrayItemIdentifier: .statsItem)
            }
        }
    }

    private func getMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let active = Double(stats.active_count)
            let inactive = Double(stats.inactive_count)
            let wire = Double(stats.wire_count)
            let compressed = Double(stats.compressor_page_count)
            let free = Double(stats.free_count)
            let used = active + inactive + wire + compressed
            let total = used + free
            return (used / total) * 100.0
        }
        return 0.0
    }

    func updateStats(temp: Double?, fanSpeeds: [Int]?, load: Double, tbEnabled: Bool, battery: Int, mode: String) {
        let tbIcon = tbEnabled ? "🔥" : "🧊"
        let tbText = tbEnabled ? "TB On" : "TB Off"
        
        let modeIcon: String
        let modeText: String
        switch mode {
        case "auto_temp": modeIcon = "🌡"; modeText = "Auto(T)"
        case "auto_battery": modeIcon = "🔋"; modeText = "Auto(B)"
        case "auto_load": modeIcon = "⚡️"; modeText = "Auto(L)"
        case "auto_fan": modeIcon = "🌀"; modeText = "Auto(F)"
        case "manual": modeIcon = "👤"; modeText = "Manual"
        default: modeIcon = "❓"; modeText = mode
        }
        
        let tempStr = temp != nil ? String(format: "%.0f°C", temp!) : "—"
        
        let fanStr: String
        if let fans = fanSpeeds, !fans.isEmpty {
            fanStr = fans.map { "\($0)" }.joined(separator: "/") + " rpm"
        } else {
            fanStr = "—"
        }
        
        let loadStr = String(format: "%.1f%%", load)
        let battStr = battery >= 0 ? "\(battery)%" : "—"
        let freqStr = tbEnabled ? "> \(baseFrequency)" : baseFrequency
        let memStr = String(format: "%.1f%%", getMemoryUsage())
        
        DispatchQueue.main.async {
            self.tbStateButton?.title = "\(tbIcon) \(tbText)"
            self.modeButton?.title = "\(modeIcon) \(modeText)"
            self.tempLabel.stringValue = "🌡 \(tempStr)"
            self.fanLabel.stringValue = "🌀 \(fanStr)"
            self.loadLabel.stringValue = "⚡️ \(loadStr)"
            self.batteryLabel.stringValue = "🔋 \(battStr)"
            self.freqLabel.stringValue = "🚀 \(freqStr)"
            self.memLabel.stringValue = "🧠 \(memStr)"
            
            // Force labels to recalculate their size
            self.tempLabel.sizeToFit()
            self.fanLabel.sizeToFit()
            self.loadLabel.sizeToFit()
            self.batteryLabel.sizeToFit()
            self.freqLabel.sizeToFit()
            self.memLabel.sizeToFit()
            self.tbStateButton?.sizeToFit()
            self.modeButton?.sizeToFit()
            
            // Update Control Strip button title to show temperature residentially
            // Use mode icon + temp for more density
            self.statsButton?.title = "\(modeIcon)\(tbIcon) \(tempStr)"
            self.statsButton?.sizeToFit()
        }
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .statsItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: "🧊", target: self, action: #selector(toggleFullBar))
            button.bezelStyle = .rounded
            item.view = button
            self.statsButton = button
            return item
        case .tbStateItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = tbStateButton ?? NSView()
            return item
        case .modeItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = modeButton ?? NSView()
            return item
        case .tempItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = tempLabel
            return item
        case .fanItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = fanLabel
            return item
        case .loadItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = loadLabel
            return item
        case .batteryItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = batteryLabel
            return item
        case .freqItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = freqLabel
            return item
        case .memItem:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = memLabel
            return item
        default:
            return nil
        }
    }
}

extension NSTouchBarItem.Identifier {
    static let statsItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.stats")
    static let tbStateItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.tbState")
    static let modeItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.mode")
    static let tempItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.temp")
    static let fanItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.fan")
    static let loadItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.load")
    static let batteryItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.battery")
    static let freqItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.freq")
    static let memItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.memory")
}
