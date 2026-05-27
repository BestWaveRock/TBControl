import AppKit

class TouchBarController: NSObject, NSTouchBarDelegate {
    var touchBar: NSTouchBar?
    private let statsLabel = NSTextField(labelWithString: "加载中...")
    
    override init() {
        super.init()
    }
    
    func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [.statsItem]
        self.touchBar = touchBar
        return touchBar
    }
    
    func updateStats(temp: Double?, fan: Int?, load: Double, tbEnabled: Bool, battery: Int) {
        let tbIcon = tbEnabled ? "🔥" : "🧊"
        let tempStr = temp != nil ? String(format: "%.0f°C", temp!) : "—"
        let fanStr = fan != nil ? "\(fan!)" : "—"
        let loadStr = String(format: "%.0f%%", load)
        let battStr = battery >= 0 ? "\(battery)%" : "—"
        
        // Simplified frequency estimation for display
        let baseFreq = 2.3 // Hardcoded base for UI display
        let freqStr = tbEnabled ? "> 2.3GHz" : "2.3GHz"
        
        let stats = "\(tbIcon) TB | 🌡 \(tempStr) | 🌀 \(fanStr) rpm | ⚡️ \(loadStr) | 🔋 \(battStr) | 🚀 \(freqStr)"
        
        DispatchQueue.main.async {
            self.statsLabel.stringValue = stats
            self.statsLabel.font = .systemFont(ofSize: 14, weight: .medium)
            self.statsLabel.textColor = .white
        }
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == .statsItem {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = statsLabel
            return item
        }
        return nil
    }
}

extension NSTouchBarItem.Identifier {
    static let statsItem = NSTouchBarItem.Identifier("com.tbcontrol.touchbar.stats")
}
