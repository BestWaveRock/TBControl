import Foundation

func getPowerMetrics() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
    task.arguments = ["-n", "1", "--samplers", "cpu_power"]
    
    let out = Pipe()
    task.standardOutput = out
    
    do {
        try task.run()
        task.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            print("--- Powermetrics Output ---")
            print(output)
            
            // Extract frequency
            if let range = output.range(of: #"CPU Average frequency: (\d+\.\d+) MHz"#, options: .regularExpression) {
                print("Found Average Freq: \(output[range])")
            }
        }
    } catch {
        print("Failed to run powermetrics: \(error)")
    }
}
getPowerMetrics()
