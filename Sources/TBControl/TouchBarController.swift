import AppKit

// Private function to ensure the icon stays in the Control Strip
// Correct signature: void DFRElementSetControlStripPresenceForIdentifier(NSString *identifier, BOOL present);
@_silgen_name("DFRElementSetControlStripPresenceForIdentifier")
func DFRElementSetControlStripPresenceForIdentifier(_ identifier: AnyObject, _ enabled: Bool)

class TouchBarController: NSObject, NSTouchBarDelegate {
    var touchBar: NSTouchBar?
    
    private let tbStateLabel = createLabel()
    private let tempLabel = createLabel()
    private let fanLabel = createLabel()
    private let loadLabel = createLabel()
    private let batteryLabel = createLabel()
    private let freqLabel = createLabel()
    private var statsButton: NSButton?
    
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
    }
    
    func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        // Include statsItem in the bar's items so the system can resolve it
        touchBar.defaultItemIdentifiers = [
            .statsItem, .fixedSpaceSmall,
            .tbStateItem, .fixedSpaceSmall,
            .tempItem, .fixedSpaceSmall,
            .fanItem, .fixedSpaceSmall,
            .loadItem, .fixedSpaceSmall,
            .batteryItem, .fixedSpaceSmall,
            .freqItem
        ]
        self.touchBar = touchBar
        
        // Ensure the item is present in the Control Strip
        let identifier = NSTouchBarItem.Identifier.statsItem.rawValue as NSString
        DFRElementSetControlStripPresenceForIdentifier(identifier, true)
        
        return touchBar
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

    func updateStats(temp: Double?, fanSpeeds: [Int]?, load: Double, tbEnabled: Bool, battery: Int) {
        let tbIcon = tbEnabled ? "🔥" : "🧊"
        let tbText = tbEnabled ? "On" : "Off"
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
        
        DispatchQueue.main.async {
            self.tbStateLabel.stringValue = "\(tbIcon) \(tbText)"
            self.tempLabel.stringValue = "🌡 \(tempStr)"
            self.fanLabel.stringValue = "🌀 \(fanStr)"
            self.loadLabel.stringValue = "⚡️ \(loadStr)"
            self.batteryLabel.stringValue = "🔋 \(battStr)"
            self.freqLabel.stringValue = "🚀 \(freqStr)"
            
            // Force labels to recalculate their size
            self.tbStateLabel.sizeToFit()
            self.tempLabel.sizeToFit()
            self.fanLabel.sizeToFit()
            self.loadLabel.sizeToFit()
            self.batteryLabel.sizeToFit()
            self.freqLabel.sizeToFit()
            
            // Update Control Strip button title to show temperature residentially
            self.statsButton?.title = "\(tbIcon) \(tempStr)"
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
            item.view = tbStateLabel
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
        default:
            return nil
        }
    }
}

extension NSTouchBarItem.Identifier {
    static let statsItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.stats")
    static let tbStateItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.tbState")
    static let tempItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.temp")
    static let fanItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.fan")
    static let loadItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.load")
    static let batteryItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.battery")
    static let freqItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.freq")
}
