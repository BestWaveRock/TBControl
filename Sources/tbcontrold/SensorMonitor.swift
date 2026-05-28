import Foundation
import IOKit

struct SensorData {
    let cpuTemp: Double?
    let fanSpeeds: [Int]?
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
        var fanSpeeds: [Int] = []
        let fanCountVal = readKey("FNum") ?? 0
        let fanCount = Int(fanCountVal)
        
        if fanCount > 0 && fanCount < 10 {
            for i in 0..<fanCount {
                var currentFanSpeed: Int? = nil
                // Try multiple keys for current fan
                let keys = ["F\(i)Ac", "F\(i)Rn", "F\(i)Sp"]
                for key in keys {
                    if let speed = readKey(key) {
                        // Sanity check: MacBook fans rarely exceed 15000 RPM
                        if speed >= 0 && speed < 15000 {
                            currentFanSpeed = Int(speed)
                            break
                        }
                    }
                }
                if let speed = currentFanSpeed {
                    fanSpeeds.append(speed)
                } else {
                    fanSpeeds.append(0)
                }
            }
        }
        
        // If we still have nil or 0, try a more aggressive fallback
        if fanSpeeds.isEmpty || fanSpeeds.allSatisfy({ $0 == 0 }) {
            fanSpeeds = []
            let fallbackKeys = ["F0Ac", "F1Ac", "F2Ac", "F0Rn", "F1Rn", "F2Rn", "F0Sp", "F1Sp"]
            for key in fallbackKeys {
                if let speed = readKey(key) {
                    if speed > 0 && speed < 15000 {
                        fanSpeeds.append(Int(speed))
                    }
                }
            }
        }

        return SensorData(cpuTemp: finalTemp, fanSpeeds: fanSpeeds.isEmpty ? nil : fanSpeeds)
    }

    func setFanMode(id: Int, isManual: Bool) -> Bool {
        guard conn != 0 else { return false }
        
        // Intel Fan Control logic using "FS! " key
        let fansMode = Int(readKey("FS! ") ?? 0)
        var newMode: UInt8 = 0
        
        if fansMode == 0 && id == 0 && isManual {
            newMode = 1
        } else if fansMode == 0 && id == 1 && isManual {
            newMode = 2
        } else if fansMode == 1 && id == 0 && !isManual {
            newMode = 0
        } else if fansMode == 1 && id == 1 && isManual {
            newMode = 3
        } else if fansMode == 2 && id == 1 && !isManual {
            newMode = 0
        } else if fansMode == 2 && id == 0 && isManual {
            newMode = 3
        } else if fansMode == 3 && id == 0 && !isManual {
            newMode = 2
        } else if fansMode == 3 && id == 1 && !isManual {
            newMode = 1
        } else {
            newMode = UInt8(fansMode)
        }
        
        if fansMode == Int(newMode) { return true }
        
        var bytes: [UInt8] = Array(repeating: 0, count: 32)
        bytes[0] = newMode
        return writeKey("FS! ", bytes: bytes, size: 2)
    }

    func setFanSpeed(id: Int, rpm: Int) -> Bool {
        // First set to manual mode if not already
        _ = setFanMode(id: id, isManual: true)
        
        // FxTg is the target speed key
        let key = "F\(id)Tg"
        // Most Intel fans use fpe2 (14.2 fixed point) for target speed
        let val = UInt16(rpm * 4)
        var bytes: [UInt8] = Array(repeating: 0, count: 32)
        bytes[0] = UInt8((val >> 8) & 0xFF)
        bytes[1] = UInt8(val & 0xFF)
        
        return writeKey(key, bytes: bytes, size: 2)
    }

    func resetFanControl() -> Bool {
        var bytes: [UInt8] = Array(repeating: 0, count: 32)
        bytes[0] = 0
        return writeKey("FS! ", bytes: bytes, size: 2)
    }

    private func writeKey(_ key: String, bytes: [UInt8], size: UInt32) -> Bool {
        guard conn != 0 else { return false }
        
        var inputStruct = SMCParamStruct()
        inputStruct.key = fourCharCode(key)
        inputStruct.keyInfo.dataSize = size
        inputStruct.data8 = UInt8(SMC_CMD_WRITE_BYTES)
        
        for (i, byte) in bytes.enumerated() {
            if i >= 32 { break }
            switch i {
            case 0: inputStruct.bytes.0 = byte
            case 1: inputStruct.bytes.1 = byte
            case 2: inputStruct.bytes.2 = byte
            case 3: inputStruct.bytes.3 = byte
            case 4: inputStruct.bytes.4 = byte
            case 5: inputStruct.bytes.5 = byte
            case 6: inputStruct.bytes.6 = byte
            case 7: inputStruct.bytes.7 = byte
            case 8: inputStruct.bytes.8 = byte
            case 9: inputStruct.bytes.9 = byte
            case 10: inputStruct.bytes.10 = byte
            case 11: inputStruct.bytes.11 = byte
            case 12: inputStruct.bytes.12 = byte
            case 13: inputStruct.bytes.13 = byte
            case 14: inputStruct.bytes.14 = byte
            case 15: inputStruct.bytes.15 = byte
            case 16: inputStruct.bytes.16 = byte
            case 17: inputStruct.bytes.17 = byte
            case 18: inputStruct.bytes.18 = byte
            case 19: inputStruct.bytes.19 = byte
            case 20: inputStruct.bytes.20 = byte
            case 21: inputStruct.bytes.21 = byte
            case 22: inputStruct.bytes.22 = byte
            case 23: inputStruct.bytes.23 = byte
            case 24: inputStruct.bytes.24 = byte
            case 25: inputStruct.bytes.25 = byte
            case 26: inputStruct.bytes.26 = byte
            case 27: inputStruct.bytes.27 = byte
            case 28: inputStruct.bytes.28 = byte
            case 29: inputStruct.bytes.29 = byte
            case 30: inputStruct.bytes.30 = byte
            case 31: inputStruct.bytes.31 = byte
            default: break
            }
        }

        var outputStruct = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size

        let result = IOConnectCallMethod(conn, UInt32(KERNEL_INDEX_SMC), nil, 0, &inputStruct, MemoryLayout<SMCParamStruct>.size, nil, nil, &outputStruct, &outputSize)

        return result == kIOReturnSuccess && outputStruct.result == 0
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
        let t = type.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Generic SPxx type parsing (e.g., sp78, spb4)
        if t.hasPrefix("sp") && t.count == 4 {
            let chars = Array(t)
            if let fractionBits = Int(String(chars[3]), radix: 16) {
                let val = (UInt16(data.0) << 8) | UInt16(data.1)
                // Use signed Int16 for SP types as they are typically fixed-point signed
                return Double(Int16(bitPattern: val)) / pow(2.0, Double(fractionBits))
            }
        }

        switch t {
        case "fpe2", "fp2e":
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
        case "flt":
            let val = (UInt32(data.3) << 24) | (UInt32(data.2) << 16) | (UInt32(data.1) << 8) | UInt32(data.0)
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
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private let KERNEL_INDEX_SMC = 2
private let SMC_CMD_READ_BYTES = 5
private let SMC_CMD_WRITE_BYTES = 6
private let SMC_CMD_READ_KEYINFO = 9
