// SPDX-License-Identifier: MIT
import Foundation
import IOKit.hid

private final class ProbeResult { var observed = false }
extension HardwareController {
  /// Development check: only watches F13 on this kit; no ordinary input is retained.
  public func waitForF13(_ endpoint: Endpoint, seconds: TimeInterval = 45) -> Bool {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    IOHIDManagerSetDeviceMatching(
      manager, [kIOHIDVendorIDKey: 12815, kIOHIDProductIDKey: endpoint.productID] as CFDictionary)
    let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    let result = ProbeResult()
    let loop = CFRunLoopGetCurrent()!
    var opened: [IOHIDDevice] = []
    for device in devices where IOHIDDeviceOpen(device, 0) == 0 {
      IOHIDDeviceRegisterInputValueCallback(
        device,
        { context, status, sender, value in
          guard status == 0, let context else { return }
          let element = IOHIDValueGetElement(value)
          if IOHIDElementGetUsagePage(element) == 7, IOHIDElementGetUsage(element) == 0x68,
            IOHIDValueGetIntegerValue(value) == 1
          {
            Unmanaged<ProbeResult>.fromOpaque(context).takeUnretainedValue().observed = true
          }
        }, Unmanaged.passUnretained(result).toOpaque())
      IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
      opened.append(device)
    }
    let deadline = Date().addingTimeInterval(seconds)
    while !result.observed && Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.02, false) }
    for device in opened {
      IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
      IOHIDDeviceClose(device, 0)
    }
    return result.observed
  }
}
