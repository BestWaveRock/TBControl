import Foundation
import AppKit
import OSLog

class UpdateManager {
    static let shared = UpdateManager()
    private let githubRepo = "BestWaveRock/TBControl"
    private let logger = OSLog(subsystem: "com.tbcontrol.app", category: "Update")
    
    var onUpdateAvailable: ((String) -> Void)?
    var onDownloadProgress: ((Double) -> Void)?
    var onUpdateError: ((String) -> Void)?
    
    func checkForUpdates(force: Bool = false) {
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                os_log("Update check error: %@", log: self.logger, type: .error, error.localizedDescription)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else {
                return
            }
            
            let latestVersion = tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0").trimmingCharacters(in: .whitespacesAndNewlines)
            
            if force || latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                os_log("Update available: %@ -> %@", log: self.logger, type: .info, currentVersion, latestVersion)
                
                // Find DMG asset
                if let asset = assets.first(where: { ($0["name"] as? String ?? "").contains(".dmg") }),
                   let downloadUrl = asset["browser_download_url"] as? String {
                    DispatchQueue.main.async {
                        self.onUpdateAvailable?(latestVersion)
                        if force {
                            self.downloadAndInstall(url: URL(string: downloadUrl)!, version: latestVersion)
                        }
                    }
                }
            }
        }.resume()
    }
    
    func downloadAndInstall(url: URL, version: String) {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("TBControl_\(version).dmg")
        
        // Remove if exists
        try? FileManager.default.removeItem(at: destination)
        
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                DispatchQueue.main.async { self.onUpdateError?("下载失败: \(error.localizedDescription)") }
                return
            }
            
            guard let localURL = localURL else { return }
            
            do {
                try FileManager.default.moveItem(at: localURL, to: destination)
                self.installDMG(path: destination.path)
            } catch {
                DispatchQueue.main.async { self.onUpdateError?("移动文件失败: \(error.localizedDescription)") }
            }
        }
        task.resume()
    }
    
    private func installDMG(path: String) {
        let script = """
        set dmgPath to "\(path)"
        set appName to "TBControl.app"
        set targetPath to "/Applications/"
        
        do shell script "hdiutil mount " & quoted form of dmgPath
        delay 2
        
        set volName to do shell script "ls /Volumes | grep TBControl | head -n 1"
        set sourcePath to "/Volumes/" & volName & "/" & appName
        
        -- Replace the app
        do shell script "rm -rf " & quoted form of (targetPath & appName)
        do shell script "cp -R " & quoted form of sourcePath & " " & quoted form of targetPath
        
        -- Unmount
        do shell script "hdiutil unmount " & quoted form of ("/Volumes/" & volName)
        
        -- Restart
        do shell script "open " & quoted form of (targetPath & appName)
        tell application "TBControl" to quit
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let err = error {
            os_log("Install error: %@", log: self.logger, type: .error, String(describing: err))
            DispatchQueue.main.async { self.onUpdateError?("安装失败，请手动更新。") }
        }
    }
}
