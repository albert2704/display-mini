import ColorSync
import CoreGraphics
import Darwin
import Foundation
import IOKit

struct BuiltInPanelTarget: Equatable {
    let registryEntryID: UInt64

    static func capture(displayID: UInt32, expectedUUID: String) -> Self? {
        guard displayID != 0, displayID != .max, UUID(uuidString: expectedUUID) != nil,
              CGDisplayIsBuiltin(displayID) == 1,
              let value = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              CFUUIDCreateString(nil, value) as String == expectedUUID,
              let framework = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else { return nil }
        defer { dlclose(framework) }
        // Private Create function returns an owned Core Foundation dictionary.
        typealias CreateInfo = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
        guard let pointer = dlsym(framework, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        let createInfo = unsafeBitCast(pointer, to: CreateInfo.self)
        guard let info = createInfo(displayID)?.takeRetainedValue(),
              let location = (info as NSDictionary)["IODisplayLocation"] as? String else { return nil }
        let service = IORegistryEntryCopyFromPath(kIOMainPortDefault, location as CFString)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOObjectConformsTo(service, "IOMobileFramebuffer") == 1,
              BuiltInPanelWake.hasInternalMarker(service) else { return nil }
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
              let registered = BuiltInPanelWake.copyValidatedService(entryID: entryID) else { return nil }
        defer { IOObjectRelease(registered) }
        guard IOObjectIsEqualTo(service, registered) == 1 else { return nil }
        return Self(registryEntryID: entryID)
    }

    func isCurrentlyValid() -> Bool {
        guard let service = BuiltInPanelWake.copyValidatedService(entryID: registryEntryID) else { return false }
        IOObjectRelease(service)
        return true
    }
}

enum BuiltInPanelWake {
    /// Arguments exclude the executable path. This mode must run before AppKit
    /// startup and exit after returning its status, including after a failed open.
    static func runHelper(arguments: [String]) -> Int32? {
        guard arguments.first == "--wake-built-in-panel" else { return nil }
        // A parent process also enforces its own deadline. A stuck private call
        // cannot leave a long-lived helper or accumulate opaque framebuffer refs.
        alarm(2)
        defer { alarm(0) }
        guard arguments.count == 2, let entryID = UInt64(arguments[1]),
              String(entryID) == arguments[1], entryID != 0, entryID != .max else {
            print("panel wake: invalid arguments")
            return 2
        }
        guard let service = copyValidatedService(entryID: entryID) else {
            print("panel wake: captured internal service unavailable")
            return 3
        }
        defer { IOObjectRelease(service) }
        guard let framework = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY) else {
            print("panel wake: framework unavailable")
            return 4
        }
        // Clamless uses these private signatures. There is no verified Close
        // export here: the short-lived process owns the image and opaque ref
        // until exit, and never guesses a release function for the reference.
        typealias Open = @convention(c) (io_service_t, mach_port_t, UInt32, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> kern_return_t
        typealias RequestPowerChange = @convention(c) (UnsafeMutableRawPointer, UInt32) -> kern_return_t
        guard let openPointer = dlsym(framework, "IOMobileFramebufferOpen"),
              let powerPointer = dlsym(framework, "IOMobileFramebufferRequestPowerChange") else {
            print("panel wake: required symbols unavailable")
            return 4
        }
        let open = unsafeBitCast(openPointer, to: Open.self)
        let requestPowerChange = unsafeBitCast(powerPointer, to: RequestPowerChange.self)
        guard lidIsOpen() else {
            print("panel wake: lid is closed or unknown")
            return 5
        }
        var framebuffer: UnsafeMutableRawPointer?
        guard open(service, mach_task_self_, 0, &framebuffer) == KERN_SUCCESS,
              let framebuffer else {
            print("panel wake: open failed")
            return 6
        }
        guard lidIsOpen() else {
            print("panel wake: lid changed or unknown")
            return 5
        }
        guard requestPowerChange(framebuffer, 1) == KERN_SUCCESS else {
            print("panel wake: power request failed")
            return 7
        }
        print("panel wake: request accepted")
        return 0
    }

    fileprivate static func hasInternalMarker(_ service: io_service_t) -> Bool {
        guard let value = IORegistryEntryCreateCFProperty(service, "IONameMatched" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { return false }
        return value.split(separator: ",", omittingEmptySubsequences: false).first == "disp0"
    }

    /// The entry ID is retained only in memory by this app. Entry-ID matching
    /// requires a currently registered service; never reconstruct from a path,
    /// substitute a framebuffer GetID value, or use an Apple vendor fallback.
    fileprivate static func copyValidatedService(entryID: UInt64) -> io_service_t? {
        guard entryID != 0, entryID != .max,
              let match = IORegistryEntryIDMatching(entryID) else { return nil }
        let target = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard target != 0 else { return nil }
        guard IOObjectConformsTo(target, "IOMobileFramebuffer") == 1, hasInternalMarker(target) else {
            IOObjectRelease(target)
            return nil
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebuffer"), &iterator) == KERN_SUCCESS else {
            IOObjectRelease(target)
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var internalCount = 0, targetFound = false, count = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            count += 1
            if count > 64 { break }
            if hasInternalMarker(service) {
                internalCount += 1
                if IOObjectIsEqualTo(service, target) == 1 { targetFound = true }
            }
        }
        guard count <= 64, IOIteratorIsValid(iterator) == 1,
              internalCount == 1, targetFound else {
            IOObjectRelease(target)
            return nil
        }
        return target
    }

    private static func lidIsOpen() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        guard let closed = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool else { return false }
        return !closed
    }
}
