#include "CSMC.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

typedef struct { UInt8 major, minor, build, reserved; UInt16 release; } vers_t;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } plim_t;
typedef struct { UInt32 dataSize; UInt32 dataType; UInt8 dataAttributes; } kinfo_t;
typedef struct {
    UInt32 key;
    vers_t vers;
    plim_t pLimitData;
    kinfo_t keyInfo;
    UInt8 result, status, data8;
    UInt32 data32;
    UInt8 bytes[32];
} SMCKeyData_t;

enum { KERNEL_INDEX_SMC = 2, SMC_CMD_READ_BYTES = 5, SMC_CMD_READ_KEYINFO = 9,
       SMC_CMD_READ_INDEX = 8 };

static io_connect_t sConn = 0;

static UInt32 str2key(const char *s) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) | ((UInt32)s[2] << 8) | (UInt32)s[3];
}
static void key2str(UInt32 k, char *o) {
    o[0] = k >> 24; o[1] = k >> 16; o[2] = k >> 8; o[3] = k; o[4] = 0;
}

static kern_return_t smc_call(SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(sConn, KERNEL_INDEX_SMC,
                                     in, sizeof(SMCKeyData_t), out, &outSize);
}

bool smc_open(void) {
    if (sConn) return true;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                                   IOServiceMatching("AppleSMC"));
    if (!svc) return false;
    kern_return_t rc = IOServiceOpen(svc, mach_task_self(), 0, &sConn);
    IOObjectRelease(svc);
    return rc == kIOReturnSuccess;
}

void smc_close(void) {
    if (sConn) { IOServiceClose(sConn); sConn = 0; }
}

static double decode(const char *type, const UInt8 *b) {
    if (!strcmp(type, "flt "))      { float f; memcpy(&f, b, 4); return f; }
    else if (!strcmp(type, "fpe2")) { return (double)(((b[0] << 8) | b[1]) >> 2); }
    else if (!strcmp(type, "ui8 ")) { return b[0]; }
    else if (!strcmp(type, "ui16")) { return (b[0] << 8) | b[1]; }
    else if (!strcmp(type, "ui32")) { return ((UInt32)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]; }
    else if (!strcmp(type, "sp78")) { return ((SInt16)((b[0] << 8) | b[1])) / 256.0; }
    return 0;
}

bool smc_read(const char *key, char *typeOut, double *valueOut) {
    if (!sConn) return false;
    SMCKeyData_t in = {0}, out = {0};
    in.key = str2key(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != kIOReturnSuccess) return false;

    kinfo_t ki = out.keyInfo;
    char type[5]; key2str(ki.dataType, type);
    memcpy(typeOut, type, 5);

    memset(&out, 0, sizeof(out));
    in.keyInfo.dataSize = ki.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(&in, &out) != kIOReturnSuccess) return false;

    *valueOut = decode(type, out.bytes);
    return true;
}

int smc_key_count(void) {
    char type[5]; double v;
    if (smc_read("#KEY", type, &v)) return (int)v;
    return 0;
}

bool smc_key_at_index(int index, char *keyOut) {
    if (!sConn) return false;
    SMCKeyData_t in = {0}, out = {0};
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = (UInt32)index;
    if (smc_call(&in, &out) != kIOReturnSuccess) return false;
    key2str(out.key, keyOut);
    return true;
}
