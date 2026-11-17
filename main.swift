// CatMode: a menu-bar app that locks the keyboard (not the screen or trackpad) against cats.
import Cocoa

let escKey: Int64 = 53
let catThreshold = 4          // non-modifier keys held at once = cat
let escPresses = 4
let escWindow: TimeInterval = 2
let auxControlSubtype: Int16 = 8 // system-defined subtype for media/volume/brightness keys

// Pure lock logic, kept free of AppKit so --selftest can drive it.
struct Guard {
    var locked = false
    var autoLock = true
    var held = Set<Int64>()
    var escTimes: [TimeInterval] = []
    var swallowEscUp = false

    mutating func lock() { locked = true; escTimes = [] }
    mutating func unlock() { locked = false; escTimes = [] }

    /// Returns true when the event must be swallowed.
    mutating func key(down: Bool, code: Int64, isRepeat: Bool, at t: TimeInterval) -> Bool {
        if !down {
            held.remove(code)
            if code == escKey && swallowEscUp { swallowEscUp = false; return true }
            return locked
        }
        if !isRepeat { held.insert(code) }
        if !locked {
            if autoLock && held.count >= catThreshold { lock(); return true }
            return false
        }
        if code == escKey {
            if isRepeat { return true } // a cat sitting on ESC must not unlock
            escTimes = escTimes.filter { t - $0 < escWindow } + [t]
            if escTimes.count >= escPresses { unlock(); swallowEscUp = true } // ESC would exit fullscreen video
        } else if !isRepeat {
            escTimes = [] // a fresh other key breaks the sequence; autorepeat of a sat-on key does not
        }
        return true
    }
}

func selfTest() {
    var g = Guard()
    // Normal typing passes, rollover of 3 keys does not lock.
    for c: Int64 in [0, 1, 2] { precondition(!g.key(down: true, code: c, isRepeat: false, at: 0)) }
    precondition(!g.locked)
    // 4th simultaneous key = cat.
    precondition(g.key(down: true, code: 3, isRepeat: false, at: 0) && g.locked)
    // Cat sitting on ESC (autorepeat) does not unlock.
    for _ in 0..<10 { _ = g.key(down: true, code: escKey, isRepeat: true, at: 1) }
    precondition(g.locked)
    // Human taps ESC 4x while cat's keys autorepeat: unlocks.
    for i in 0..<4 {
        _ = g.key(down: true, code: 5, isRepeat: true, at: 2 + Double(i) * 0.1)
        precondition(g.key(down: true, code: escKey, isRepeat: false, at: 2 + Double(i) * 0.2))
        if i < 3 { _ = g.key(down: false, code: escKey, isRepeat: false, at: 2.05 + Double(i) * 0.2) }
    }
    precondition(!g.locked)
    precondition(g.key(down: false, code: escKey, isRepeat: false, at: 3)) // 4th ESC up swallowed
    // A different key in between resets; too slow does not unlock.
    g = Guard(); g.lock()
    for (i, c) in [escKey, escKey, 7, escKey, escKey].enumerated() { _ = g.key(down: true, code: c, isRepeat: false, at: Double(i) * 0.1) }
    precondition(g.locked)
    g = Guard(); g.lock()
    for i in 0..<4 { _ = g.key(down: true, code: escKey, isRepeat: false, at: Double(i) * 1.0) }
    precondition(g.locked)
    // Auto-lock off: no lock.
    g = Guard(); g.autoLock = false
    for c: Int64 in 0..<6 { _ = g.key(down: true, code: c, isRepeat: false, at: 0) }
    precondition(!g.locked)
    print("selftest ok")
}

var state = Guard()
var tap: CFMachPort?
var screenLocked = false // never block the password prompt
let app = NSApplication.shared
var delegate: AppDelegate?

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        state.held.removeAll()
        return pass
    }
    if screenLocked { return pass }
    let wasLocked = state.locked
    var swallow = false
    switch type {
    case .keyDown, .keyUp:
        // Drop keys whose keyUp we never saw (e.g. eaten by a secure-input field) so they can't fake a cat.
        state.held = state.held.filter { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) }
        swallow = state.key(down: type == .keyDown,
                            code: event.getIntegerValueField(.keyboardEventKeycode),
                            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                            at: ProcessInfo.processInfo.systemUptime)
    case .flagsChanged:
        swallow = state.locked
    default: // system-defined (type 14): media, volume, brightness keys
        swallow = state.locked && NSEvent(cgEvent: event)?.subtype.rawValue == auxControlSubtype
    }
    if wasLocked != state.locked { MainActor.assumeIsolated { delegate?.refresh() } }
    return swallow ? nil : pass
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let toggleItem = NSMenuItem(title: "", action: #selector(toggleLock), keyEquivalent: "")
    let autoItem = NSMenuItem(title: "Auto-lock when cat detected", action: #selector(toggleAuto), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        UserDefaults.standard.register(defaults: ["autoLock": true])
        state.autoLock = UserDefaults.standard.bool(forKey: "autoLock")
        let menu = NSMenu()
        menu.autoenablesItems = false
        for i in [toggleItem, autoItem] { i.target = self; menu.addItem(i) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit CatMode", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { screenLocked = true; state.unlock(); state.held.removeAll(); self.refresh() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { screenLocked = false }
        }
        installTap()
        refresh()
    }

    // Accessibility may not be granted yet: retry until it is, instead of quitting.
    func installTap() {
        let types: [UInt32] = [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue, 14]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1) }
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.installTap() }
            return
        }
        tap = t
        // commonModes: keep the tap serviced while the status menu is open.
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        refresh()
    }

    func refresh() {
        let ready = tap != nil
        let name = state.locked ? "cat.fill" : "keyboard"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: state.locked ? "Keyboard locked" : "Keyboard unlocked")
        item.button?.toolTip = !ready ? "CatMode needs Accessibility permission"
            : state.locked ? "Keyboard locked. Press ESC 4x or click to unlock" : "Keyboard unlocked"
        toggleItem.title = !ready ? "Waiting for Accessibility permission…" : state.locked ? "Unlock Keyboard" : "Lock Keyboard"
        toggleItem.isEnabled = ready
        autoItem.state = state.autoLock ? .on : .off
    }

    @objc func toggleLock() { state.locked ? state.unlock() : state.lock(); refresh() }

    @objc func toggleAuto() {
        state.autoLock.toggle()
        UserDefaults.standard.set(state.autoLock, forKey: "autoLock")
        refresh()
    }
}

if CommandLine.arguments.contains("--selftest") { selfTest(); exit(0) }
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { delegate = AppDelegate(); app.delegate = delegate }
app.run()
