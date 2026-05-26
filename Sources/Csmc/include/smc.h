#ifndef SMC_H
#define SMC_H

#include <stdint.h>

#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    uint16_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfo_t;

typedef struct {
    uint32_t   key;
    uint8_t    vers[4];
    uint8_t    pLimitData[6];
    SMCKeyInfo_t keyInfo;
    uint8_t    result;
    uint8_t    status;
    uint8_t    cmd;
    uint32_t   data32;
    uint8_t    bytes[32];
} SMCKeyData_t;

int smc_get_fan_speed(int *rpm);

#endif
