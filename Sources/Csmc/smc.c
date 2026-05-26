#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

static UInt32 strKey(const char *s) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) |
           ((UInt32)s[2] << 8) | s[3];
}

static kern_return_t smcCall(io_connect_t conn, UInt32 index,
                             SMCKeyData_t *input, SMCKeyData_t *output) {
    size_t size = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, index, input, size, output, &size);
}

int smc_get_fan_speed(int *rpm) {
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault,
                           IOServiceMatching("AppleSMC"));
    if (!service) return -1;

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess) return -1;

    const char *keys[] = {"F0Ac", "F1Ac"};
    int result = -1;

    for (int i = 0; i < 2; i++) {
        SMCKeyData_t in, out;
        memset(&in, 0, sizeof(in));
        memset(&out, 0, sizeof(out));

        in.key = strKey(keys[i]);
        in.cmd = SMC_CMD_READ_KEYINFO;

        if (smcCall(conn, 2, &in, &out) != kIOReturnSuccess) continue;
        if (out.keyInfo.dataSize < 2) continue;

        memset(&in, 0, sizeof(in));
        memset(&out, 0, sizeof(out));
        in.key = strKey(keys[i]);
        in.cmd = SMC_CMD_READ_BYTES;
        in.keyInfo.dataSize = out.keyInfo.dataSize;

        if (smcCall(conn, 2, &in, &out) != kIOReturnSuccess) continue;

        int speed = (out.bytes[0] << 8 | out.bytes[1]) >> 2;
        if (speed > 0) {
            *rpm = speed;
            result = 0;
            break;
        }
    }

    IOServiceClose(conn);
    return result;
}
