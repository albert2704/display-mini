@import Foundation;
@import IOKit;
#include "i2c.h"
#include "ioregistry.h"
#include <assert.h>

static void checksum(UInt8 *reply) {
    reply[10] = 0x50;
    for (int i = 0; i < 10; i++) reply[10] ^= reply[i];
}
static void edidChecksum(UInt8 *bytes) {
    UInt8 sum = 0; bytes[127] = 0;
    for (int i = 0; i < 127; i++) sum += bytes[i];
    bytes[127] = (UInt8)(0 - sum);
}
int main(void) {
    UInt8 reply[11] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 75, 0};
    checksum(reply); assert(validateDDCReply(reply, 0x10) == DDCReplyValid);
    DDCValue value = convertI2CtoDDC((char *)reply); assert(value.curValue == 75 && value.maxValue == 100);
    reply[3] = 1; checksum(reply); assert(validateDDCReply(reply, 0x10) == DDCReplyUnsupported);
    assert(validateDDCReply(reply, 0x62) == DDCReplyInvalid);
    reply[10] ^= 1; assert(validateDDCReply(reply, 0x10) == DDCReplyInvalid);
    reply[3] = 2; checksum(reply); assert(validateDDCReply(reply, 0x10) == DDCReplyInvalid);
    setDDCReadDelayMS(150); assert(getDDCReadDelayMS() == 150);
    setDDCReadDelayMS(999999); assert(getDDCReadDelayMS() == 50);

    assert(MAX_DISPLAYS >= 64);
    DisplayInfos displays[6] = {0};
    for (int i = 0; i < 6; i++) displays[i].id = (UInt32)i + 1;
    char fifth[] = "5", zero[] = "0", negative[] = "-1", overflow[] = "999999999999999999999999999";
    assert(selectDisplay(displays, 6, fifth) == &displays[4]);
    assert(selectDisplay(displays, 6, zero) == NULL);
    assert(selectDisplay(displays, 6, negative) == NULL);
    assert(selectDisplay(displays, 6, overflow) == NULL);
    displays[0].uuid = @"synthetic-duplicate"; displays[1].uuid = @"synthetic-duplicate";
    char duplicate[] = "synthetic-duplicate";
    assert(selectDisplay(displays, 6, duplicate) == NULL);

    // Synthetic EDID identity, never a physical monitor's serial.
    UInt8 edid[128] = {0, 255, 255, 255, 255, 255, 255, 0};
    edid[8] = 0x12; edid[9] = 0x34; edid[10] = 0x78; edid[11] = 0x56; edid[12] = 42;
    edidChecksum(edid);
    DisplayInfos display = {.vendor = 0x1234, .model = 0x5678, .serial = 42};
    CFDataRef data = CFDataCreate(NULL, edid, 128);
    assert(displayIdentityMatchesEDID(&display, data));
    display.serial = 43; assert(!displayIdentityMatchesEDID(&display, data));
    display.serial = 42; CFRelease(data);
    edid[20] ^= 1; data = CFDataCreate(NULL, edid, 128);
    assert(!displayIdentityMatchesEDID(&display, data)); CFRelease(data);
    edid[20] ^= 1; edid[0] = 1; edidChecksum(edid); data = CFDataCreate(NULL, edid, 128);
    assert(!displayIdentityMatchesEDID(&display, data)); CFRelease(data);
    data = CFDataCreate(NULL, edid, 12); assert(!displayIdentityMatchesEDID(&display, data)); CFRelease(data);
    assert(!displayIdentityMatchesEDID(&display, NULL));
    puts("Passed helper protocol, identity, selector and timing checks (no monitor I/O).");
}
