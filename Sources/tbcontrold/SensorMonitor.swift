import Foundation
import IOKit

struct SensorData {
    let cpuTemp: Double?
    let fanSpeed: Int?
}

class SensorMonitor {
    private var conn: io_connect_t = 0

    init() {
        let service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"))
        if service != 0 {
            let res = IOServiceOpen(service, mach_task_self_, 0, &conn)
            if res != kIOReturnSuccess {
                print("DEBUG: IOServiceOpen failed: \(res)")
            }
            IOObjectRelease(service)
        }
    }

    deinit {
        if conn != 0 {
            IOServiceClose(conn)
        }
    }

    func readSensors() -> SensorData? {
        guard conn != 0 else { return nil }

        // Intel CPU Temperature Keys prioritized for MacBook Pro
        let tempKeys = ["TC0P", "TC0D", "TC0C", "TC1C", "TCP0", "TC0H", "TC0E", "TC0F"]
        var finalTemp: Double? = nil
        
        for key in tempKeys {
            if let temp = readKey(key) {
                if temp > 10 && temp < 110 {
                    finalTemp = temp
                    break
                }
            }
        }

        // Fan Speed - Try multiple fans and keys
        var maxFanSpeed: Int? = nil
        if let fanCount = readKey("FNum"), fanCount > 0 && fanCount < 10 {
            for i in 0..<Int(fanCount) {
                // Try multiple keys for current fan
                let keys = ["F\(i)Ac", "F\(i)Rn", "F\(i)Sp"]
                for key in keys {
                    if let speed = readKey(key) {
                        // Sanity check: MacBook fans rarely exceed 15000 RPM
                        // Allow 0 RPM as valid (stopped)
                        if speed >= 0 && speed < 15000 {
                            maxFanSpeed = max(maxFanSpeed ?? 0, Int(speed))
                            break
                        }
                    }
                }
            }
        } else {
            // Fallback if FNum fails or returns 0
            let fanKeys = ["F0Ac", "F1Ac", "F2Ac", "F0Rn", "F1Rn", "F2Rn"]
            for key in fanKeys {
                if let speed = readKey(key) {
                    if speed >= 0 && speed < 15000 {
                        maxFanSpeed = max(maxFanSpeed ?? 0, Int(speed))
                    }
                }
            }
        }

        return SensorData(cpuTemp: finalTemp, fanSpeed: maxFanSpeed)
    }

    private func readKey(_ key: String) -> Double? {
        let info = getInfo(key)
        guard info.size > 0 else { return nil }

        var inputStruct = SMCParamStruct()
        inputStruct.key = fourCharCode(key)
        inputStruct.keyInfo.dataSize = info.size
        inputStruct.data8 = UInt8(SMC_CMD_READ_BYTES)

        var outputStruct = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size

        let result = IOConnectCallMethod(conn, UInt32(KERNEL_INDEX_SMC), nil, 0, &inputStruct, MemoryLayout<SMCParamStruct>.size, nil, nil, &outputStruct, &outputSize)

        guard result == kIOReturnSuccess && outputStruct.result == 0 else { return nil }

        return parseValue(data: outputStruct.bytes, type: info.type)
    }

    private func getInfo(_ key: String) -> (size: UInt32, type: String) {
        var inputStruct = SMCParamStruct()
        inputStruct.key = fourCharCode(key)
        inputStruct.data8 = UInt8(SMC_CMD_READ_KEYINFO)

        var outputStruct = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size

        let result = IOConnectCallMethod(conn, UInt32(KERNEL_INDEX_SMC), nil, 0, &inputStruct, MemoryLayout<SMCParamStruct>.size, nil, nil, &outputStruct, &outputSize)

        guard result == kIOReturnSuccess && outputStruct.result == 0 else { return (0, "") }

        return (outputStruct.keyInfo.dataSize, stringFromFourCharCode(outputStruct.keyInfo.dataType))
    }

    private func parseValue(data: SMCBytes, type: String) -> Double? {
        let t = type.trimmingCharacters(in: .whitespaces)
        switch t {
        case "sp78":
            let val = (UInt16(data.0) << 8) | UInt16(data.1)
            return Double(Int16(bitPattern: val)) / 256.0
        case "fpe2":
            let val = (UInt16(data.0) << 8) | UInt16(data.1)
            return Double(val) / 4.0
        case "ui8", "hex8":
            return Double(data.0)
        case "ui16":
            let val = (UInt16(data.0) << 8) | UInt16(data.1)
            return Double(val)
        case "ui32":
            let val = (UInt32(data.0) << 24) | (UInt32(data.1) << 16) | (UInt32(data.2) << 8) | UInt32(data.3)
            return Double(val)
        case "flt ":
            let val = (UInt32(data.0) << 24) | (UInt32(data.1) << 16) | (UInt32(data.2) << 8) | UInt32(data.3)
            return Double(Float32(bitPattern: val))
        default:
            return nil
        }
    }

    private func fourCharCode(_ s: String) -> UInt32 {
        var res: UInt32 = 0
        for char in s.utf8.prefix(4) {
            res = (res << 8) | UInt32(char)
        }
        return res
    }

    private func stringFromFourCharCode(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes.compactMap { UnicodeScalar($0).isASCII ? Character(UnicodeScalar($0)) : nil })
    }
}

// exelban/stats aligned 80-byte SMCParamStruct
private struct SMCParamStruct {
    struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var padding2: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private let KERNEL_INDEX_SMC = 2
private let SMC_CMD_READ_BYTES = 5
private let SMC_CMD_READ_KEYINFO = 9
