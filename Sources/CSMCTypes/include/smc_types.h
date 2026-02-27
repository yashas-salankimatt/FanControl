#ifndef SMC_TYPES_H
#define SMC_TYPES_H

#include <stdint.h>

// SMC command constants
#define SMC_SELECTOR         2
#define SMC_CMD_READ_BYTES   5
#define SMC_CMD_WRITE_BYTES  6
#define SMC_CMD_READ_INDEX   8
#define SMC_CMD_READ_KEYINFO 9

// Flat packed struct matching the exact 80-byte layout expected by the macOS kernel.
// All uint32_t fields use native endianness (little-endian on ARM64).
// The SMC value bytes (bytes[]) are always big-endian (network byte order).
#pragma pack(push, 1)
typedef struct {
    uint32_t key;                  // 0:  SMC key as 4CC (big-endian encoded in the uint32)
    // SMCVersion
    uint8_t  vers_major;           // 4
    uint8_t  vers_minor;           // 5
    uint8_t  vers_build;           // 6
    uint8_t  vers_reserved;        // 7
    uint16_t vers_release;         // 8
    // Alignment padding
    uint8_t  _pad1[2];            // 10
    // SMCPLimitData
    uint16_t pLimit_version;      // 12
    uint16_t pLimit_length;       // 14
    uint32_t pLimit_cpuPLimit;    // 16
    uint32_t pLimit_gpuPLimit;    // 20
    uint32_t pLimit_memPLimit;    // 24
    // SMCKeyInfoData
    uint32_t keyInfo_dataSize;    // 28
    uint32_t keyInfo_dataType;    // 32
    uint8_t  keyInfo_dataAttr;    // 36
    // Alignment padding
    uint8_t  _pad2;              // 37
    uint16_t padding;            // 38
    uint8_t  result;             // 40
    uint8_t  status;             // 41
    uint8_t  data8;              // 42
    // Alignment padding
    uint8_t  _pad3;              // 43
    uint32_t data32;             // 44
    uint8_t  bytes[32];          // 48
    // Total: 80 bytes
} SMCParamStruct;
#pragma pack(pop)

// Compile-time size check
_Static_assert(sizeof(SMCParamStruct) == 80, "SMCParamStruct must be exactly 80 bytes");

#endif
