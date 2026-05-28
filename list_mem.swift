import Foundation

func getMemoryUsage() -> Double {
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
print(getMemoryUsage())
