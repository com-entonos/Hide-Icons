//
//  main.swift
//  Hide Icons
//
//  Created by G.J. Parker on 16/09/23.
//


import Cocoa

if CommandLine.arguments.contains("--watchdog"), // are we watchdog?
   let parentPIDString = CommandLine.arguments.last {
    guard let parentPID = Int32(parentPIDString) else { exit(1) }
    let hideDesktopIcons = Bool(CommandLine.arguments[CommandLine.arguments.count-2]) ?? false
    let kq = kqueue() // man kqueue/kevent- bsd hooks
    var kr: Int32 = 0
    if kq != -1 {
        var ke = kevent(ident: UInt(parentPID), filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_CLEAR), fflags: UInt32(NOTE_EXIT),
            data: 0, udata: nil)
        var keOut = kevent()
        kr = kevent(kq, &ke, 1, &keOut, 1, nil)
    }
    if kq == -1 || kr < 0 { // Fallback polling loop if kernel queue encounters an error
        while kill(parentPID, 0) == 0 {Thread.sleep(forTimeInterval: 1.0) }// man 2 kill- bsd kill
    }
    // finally, let's restore the original setting...
    if #available(macOS 14.0, *) {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesSetAppValue("StandardHideDesktopIcons" as CFString, hideDesktopIcons as CFPropertyList, domain)
        CFPreferencesAppSynchronize(domain)
    } else {
        let domain = "com.apple.finder" as CFString
        CFPreferencesSetAppValue("CreateDesktop" as CFString, hideDesktopIcons as CFPropertyList, domain)
        CFPreferencesAppSynchronize(domain)
        if let finderApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) { finderApp.terminate() }
    }
    exit(0)
 } else {
    // find initial setting
     var  hideDesktopIcons = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "StandardHideDesktopIcons") ?? false
     if #unavailable(macOS 14.0) {hideDesktopIcons = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "CreateDesktop") ?? true}
     
     // Spawn watchdog before spinning up AppKit
     let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
     let PID = getpid()
     let watchdog = Process()
     watchdog.executableURL = execURL
     watchdog.arguments = ["--watchdog", String(hideDesktopIcons), String(PID)]
     do { try watchdog.run() } catch { NSLog("Failed to fire watchdog background listener: \(error)") }
     
     // continue...
     let app = NSApplication.shared
     autoreleasepool {
         let delegate = AppDelegate()
         withExtendedLifetime(delegate, {
             app.delegate = delegate
             _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
         })
     }
 }


