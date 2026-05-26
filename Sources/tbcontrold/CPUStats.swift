import Foundation
import MachO

class CPUStats {
    private var previousLoad: host_cpu_load_info? = nil

    func getLoad() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
                                intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        if let prev = previousLoad {
            let user = info.cpu_ticks.0 - prev.cpu_ticks.0
            let system = info.cpu_ticks.1 - prev.cpu_ticks.1
            let idle = info.cpu_ticks.2 - prev.cpu_ticks.2
            let nice = info.cpu_ticks.3 - prev.cpu_ticks.3
            let total = user + system + idle + nice

            previousLoad = info
            guard total > 0 else { return 0 }
            return Double(user + system + nice) / Double(total) * 100
        }

        previousLoad = info
        return 0
    }
}
