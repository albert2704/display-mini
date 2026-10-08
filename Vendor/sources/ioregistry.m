@import Foundation;
@import IOKit;
@import ApplicationServices;
@import CoreGraphics;

#include "ioregistry.h"
#include "utils.h"
#include <dlfcn.h>

static CFTypeRef getCFStringRef(io_service_t service, char* key) {
    CFStringRef cfstring = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingASCII);
    CFTypeRef value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, cfstring, kCFAllocatorDefault, kIORegistryIterateRecursively);
    CFRelease(cfstring);
    return value;
}

static Boolean isMCDP29XXProxy(io_service_t proxy) {
    io_registry_entry_t parent = MACH_PORT_NULL;
    if (IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) != KERN_SUCCESS) {
        return false;
    }

    Boolean isMCDP29XX = false;
    CFTypeRef providerClass = IORegistryEntryCreateCFProperty(
        parent,
        CFSTR("EPICProviderClass"),
        kCFAllocatorDefault,
        0
    );
    if (providerClass != NULL && CFGetTypeID(providerClass) == CFStringGetTypeID()) {
        isMCDP29XX = CFStringCompare(providerClass, CFSTR("AppleDCPMCDP29XX"), 0) == kCFCompareEqualTo;
    }

    if (providerClass != NULL) {
        CFRelease(providerClass);
    }
    IOObjectRelease(parent);
    return isMCDP29XX;
}

CGDisplayCount getOnlineDisplayInfos(DisplayInfos* displayInfos) {
    // Getting online display list and count
    CGDisplayCount screenCount = 0;
    CGDirectDisplayID screenList[MAX_DISPLAYS];
    if (CGGetOnlineDisplayList(MAX_DISPLAYS, screenList, &screenCount) != kCGErrorSuccess) {
        return 0;
    }

    int validDisplayCount = 0;
    // Fetching each display infos from IOKit
    for (int i = 0; i < (int)MIN(screenCount, MAX_DISPLAYS) && validDisplayCount < MAX_DISPLAYS; i++) {
        DisplayInfos *currDisplay = displayInfos + validDisplayCount;
        *currDisplay = (DisplayInfos){0};
        currDisplay->productName = @"Unknown Display";
        currDisplay->id = screenList[i];

        // This is a private API, but it's a shortcut to get the system UUID
        CFDictionaryRef displayInfoDict = CoreDisplay_DisplayCreateInfoDictionary(currDisplay->id);
        currDisplay->serial = CGDisplaySerialNumber(currDisplay->id);
        currDisplay->model = CGDisplayModelNumber(currDisplay->id);
        currDisplay->vendor = CGDisplayVendorNumber(currDisplay->id);

        CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(currDisplay->id);
        if (uuid) { currDisplay->uuid = (NSString *)CFUUIDCreateString(NULL, uuid); CFRelease(uuid); }
        if (displayInfoDict) {
            if (!currDisplay->uuid) { currDisplay->uuid = CFDictionaryGetValue(displayInfoDict, CFSTR("kCGDisplayUUID")); }
            currDisplay->ioLocation = CFDictionaryGetValue(displayInfoDict, CFSTR("IODisplayLocation"));
        }

        // Retrieving IORegistry entry for display
        if (currDisplay->ioLocation) { currDisplay->adapter = IORegistryEntryCopyFromPath(kIOMainPortDefault, (CFStringRef)currDisplay->ioLocation); }
        if (currDisplay->adapter == MACH_PORT_NULL) {
            // Keep the CoreGraphics identity even when metadata is absent.
            validDisplayCount++;
            continue;
        }

        // If successful, we can retrieve the EDID UUID, and other display attributes
        currDisplay->edid = getCFStringRef(currDisplay->adapter, "EDID UUID");
        CFDictionaryRef displayAttrs = getCFStringRef(currDisplay->adapter, "DisplayAttributes");
        if (displayAttrs) {
            NSDictionary* displayAttrsNS = (NSDictionary*)displayAttrs;
            NSDictionary* productAttrs = [displayAttrsNS objectForKey:@"ProductAttributes"];
            if (productAttrs) {
                currDisplay->productName = [productAttrs objectForKey:@"ProductName"] ?: @"Unknown Display";
                currDisplay->manufacturer = [productAttrs objectForKey:@"ManufacturerID"];
                currDisplay->alphNumSerial = [productAttrs objectForKey:@"AlphanumericSerialNumber"];
            }
        }

        validDisplayCount++;
    }

    return validDisplayCount;
}

/*
 *  Returns display identifier based on identification method
 *  Allowed methods are:
 *  - id    Display ID                          "<id>"
 *  - uuid  Display UUID                        "<uuid>"
 *  - edid  Display EDID UUID                   "<edid>"
 *  - seid  Display Alphnum SN + EDID UUID      "<an_serial>:<edid>"
 *  - basic Match basic identifiers             "<vendor>:<model>:<serial>"
 *  - ext   Match basic + extended identifiers  "<vendor>:<model>:<serial>:<manufacturer>:<an_serial>:<name>"
 *  - full  Match basic + extended + location   "<vendor>:<model>:<serial>:<manufacturer>:<an_serial>:<name>:<location>"
 */
NSString *getDisplayIdentifier(DisplayInfos *display, char *identificationMethod) {
    if (STR_EQ(identificationMethod, "id")) {
        return [NSString stringWithFormat:@"%u", display->id];
    } else if (STR_EQ(identificationMethod, "uuid")) {
        return display->uuid ?: @"";
    } else if (STR_EQ(identificationMethod, "edid")) {
        return display->edid ?: @"";
    } else if (STR_EQ(identificationMethod, "seid")) {
        return [NSString stringWithFormat:@"%@:%@",
            display->alphNumSerial ?: @"",
            display->edid ?: @""];
    } else if (STR_EQ(identificationMethod, "basic")) {
        return [NSString stringWithFormat:@"%u:%u:%u",
            display->vendor,
            display->model,
            display->serial];
    } else if (STR_EQ(identificationMethod, "ext")) {
        return [NSString stringWithFormat:@"%d:%d:%d:%@:%@:%@",
            display->vendor,
            display->model,
            display->serial,
            display->manufacturer ?: @"",
            display->alphNumSerial ?: @"",
            display->productName ?: @""];
    } else if (STR_EQ(identificationMethod, "full")) {
        return [NSString stringWithFormat:@"%d:%d:%d:%@:%@:%@:%@",
            display->vendor,
            display->model,
            display->serial,
            display->manufacturer ?: @"",
            display->alphNumSerial ?: @"",
            display->productName ?: @"",
            display->ioLocation ?: @""];
    }
    return NULL;
}

DisplayInfos* selectDisplay(DisplayInfos *displays, int connectedDisplays, char *displayIdentifier) {

    // Checking if display identifier is a display index from the "list" command
    char *stop;
    errno = 0;
    long displayNumber = strtol(displayIdentifier, &stop, 10);
    if (*stop == '\0') {
        return errno == 0 && displayNumber >= 1 && displayNumber <= connectedDisplays ? displays + (displayNumber - 1) : NULL;
    }

    // Checking if an identification method is specified, otherwise defaulting to UUID
    char *identificationMethod = "uuid";
    char *delimiter = strstr(displayIdentifier, "=");
    if (delimiter != NULL) {
        // Delimiter should not be at the beginning or end of the string
        if (delimiter == displayIdentifier || delimiter == displayIdentifier + strlen(displayIdentifier) - 1) return NULL;
        // Splitting display identifier into identification method and value
        *delimiter = '\0';
        identificationMethod = displayIdentifier;
        displayIdentifier = delimiter + 1;
    }

    // Searching for display that matchs the identifier for the given identification method
    DisplayInfos *match = NULL;
    for (int i = 0; i < connectedDisplays; i++) {
        const char *displayValue = getDisplayIdentifier(displays + i, identificationMethod).UTF8String;
        if (displayValue != NULL && STR_EQ(displayIdentifier, displayValue)) {
            if (match != NULL) { return NULL; }
            match = displays + i;
        }
    }
    return match;
}

IOAVServiceRef getDefaultDisplayAVService() {
    return IOAVServiceCreate(kCFAllocatorDefault);
}

Boolean displayIdentityMatchesEDID(const DisplayInfos *display, CFDataRef edid) {
    if (!display || display->vendor == 0 || display->model == 0 || !edid ||
        CFGetTypeID(edid) != CFDataGetTypeID() || CFDataGetLength(edid) < 128) { return false; }
    const UInt8 *b = CFDataGetBytePtr(edid);
    const UInt8 header[] = {0, 255, 255, 255, 255, 255, 255, 0};
    UInt8 checksum = 0;
    for (int i = 0; i < 128; i++) { checksum += b[i]; }
    if (memcmp(b, header, 8) != 0 || checksum != 0) { return false; }
    UInt32 vendor = ((UInt32)b[8] << 8) | b[9];
    UInt32 model = b[10] | ((UInt32)b[11] << 8);
    UInt32 serial = b[12] | ((UInt32)b[13] << 8) | ((UInt32)b[14] << 16) | ((UInt32)b[15] << 24);
    return vendor == display->vendor && model == display->model && serial == display->serial;
}

Boolean displayIdentityIsUnique(const DisplayInfos *display, const DisplayInfos *online, CGDisplayCount count) {
    unsigned int matches = 0;
    for (CGDisplayCount i = 0; i < count; i++) {
        if (online[i].vendor == display->vendor && online[i].model == display->model &&
            online[i].serial == display->serial) { matches++; }
    }
    return matches == 1;
}

DDCTransport getDisplayDDCTransport(DisplayInfos* displayInfos) {

    DDCTransport transport = {
        .service = NULL,
        .chipAddress = DDC_CHIP_ADDRESS_DEFAULT,
    };
    if (displayInfos == NULL) {
        return transport;
    }

    // Framebuffers and DCP services can be in separate branches. Verify identity
    // against EDID read from the service itself, never registry traversal order.
    typedef IOReturn (*CopyEDID)(IOAVServiceRef, CFDataRef *);
    CopyEDID copyEDID = (CopyEDID)dlsym(RTLD_DEFAULT, "IOAVServiceCopyEDID");
    if (!copyEDID) { return transport; }
    DisplayInfos online[MAX_DISPLAYS] = {0};
    CGDirectDisplayID ids[MAX_DISPLAYS] = {0};
    CGDisplayCount count = 0;
    if (CGGetOnlineDisplayList(MAX_DISPLAYS, ids, &count) != kCGErrorSuccess || count > MAX_DISPLAYS) { return transport; }
    for (CGDisplayCount i = 0; i < count; i++) {
        online[i].vendor = CGDisplayVendorNumber(ids[i]);
        online[i].model = CGDisplayModelNumber(ids[i]);
        online[i].serial = CGDisplaySerialNumber(ids[i]);
    }
    if (!displayIdentityIsUnique(displayInfos, online, count)) { transport.ambiguous = true; return transport; }
    io_iterator_t iter = MACH_PORT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) != KERN_SUCCESS) {
        return transport;
    }

    io_service_t service;

	// Iterating through IORegistry
    while ((service = IOIteratorNext(iter)) != MACH_PORT_NULL) {
        // Searching for DCPAVServiceProxy associated with the selected display
        io_name_t name;
        if (IORegistryEntryGetName(service, name) != KERN_SUCCESS || !STR_EQ(name, "DCPAVServiceProxy")) {
            IOObjectRelease(service);
            continue;
        }

        // Creating IOAVServiceRef from DCPAVServiceProxy
        IOAVServiceRef avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
        if (avService == NULL) {
            IOObjectRelease(service);
            continue;
        }

        CFStringRef location = getCFStringRef(service, "Location");
        Boolean isExternal = location != NULL &&
            CFGetTypeID(location) == CFStringGetTypeID() &&
            CFStringCompare(CFSTR("External"), location, 0) == kCFCompareEqualTo;
        if (location != NULL) {
            CFRelease(location);
        }

        if (!isExternal) {
            CFRelease(avService);
            IOObjectRelease(service);
            continue;
        }

        CFDataRef edid = NULL;
        IOReturn readResult = copyEDID(avService, &edid);
        Boolean identityMatches = readResult == kIOReturnSuccess && displayIdentityMatchesEDID(displayInfos, edid);
        if (edid != NULL) { CFRelease(edid); }
        if (!identityMatches) { CFRelease(avService); IOObjectRelease(service); continue; }

        transport.serviceCount++;
        if (transport.serviceCount > 1) {
            transport.ambiguous = true;
            CFRelease(avService);
            if (transport.service != NULL) { CFRelease(transport.service); transport.service = NULL; }
            IOObjectRelease(service);
            continue;
        }
        transport.service = avService;
        // MCDP29xx routes DDC through chip address 0xB7.
        transport.chipAddress = isMCDP29XXProxy(service)
            ? DDC_CHIP_ADDRESS_MCDP29XX
            : DDC_CHIP_ADDRESS_DEFAULT;
        IOObjectRelease(service);
    }

    IOObjectRelease(iter);
    return transport;
}

IOAVServiceRef getDisplayAVService(DisplayInfos* displayInfos) {
    return getDisplayDDCTransport(displayInfos).service;
}
