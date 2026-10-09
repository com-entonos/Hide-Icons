//
//  Hider.swift
//
//  Created by G.J. Parker on 21/04/02.
//  Copyright © 2026 G.J. Parker. All rights reserved.
//

import Cocoa
import ScreenCaptureKit   // macOS 27+ capture path — CGWindowListCreateImage stopped returning real pixel data for the Desktop window

extension Notification.Name {
    static let doHide = NSNotification.Name("doHide")                       //toggle hide/show Desktop icons
    static let createDesktops = NSNotification.Name("createDesktops")       //recreate windows for all Desktops
    static let timeBG = NSNotification.Name("timeBG")                       //change the time interval for background updates
    static let desktopType = NSNotification.Name("desktopType")             //support for solid color or actual Desktop wallpaper
}

extension NSWindow.Level {
    static let hiddenLayer = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow))-2)
    static let floatLayer  = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow))+1)
    static let staticLayer = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow))+5)
}

class Hider {  // class that covers Desktop w/ pictures of Desktop- invoked by notifications and/or internal timers
    
    class MyWindow : NSWindow { // just add some data and methods for NSWindow- this will hold a window w/ a Desktop pic
        var color: NSColor? = nil   // display solid color instead of actual Desktop? nil means actual, otherwise that color
        var beingUsed = false
        var lastGoodImage: CGImage? = nil   // cache of the last successful capture; reused on failure and for menu previews
        
        init(contentRect: NSRect, hidden: Bool) {
            super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false) // create NSWindow
            reset(contentRect: contentRect, hidden: hidden)
        }
        
        func reset(contentRect: NSRect, hidden: Bool) {
            self.setFrame(contentRect, display: true)   // force the correct frame for window
            self.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
            self.level = hidden ? .floatLayer : .hiddenLayer
            //self.orderFrontRegardless() //place on top of this level
            self.beingUsed = true
            // rest is to make the window dumb
            self.canHide = false; self.isExcludedFromWindowsMenu = true; self.isOpaque = true
            self.hasShadow = false; self.hidesOnDeactivate = false; self.discardCursorRects()
            self.discardEvents(matching: .any, before: nil); self.ignoresMouseEvents = true; self.isRestorable = false
            self.animationBehavior = .none
        }
        
        func setWin(imageView: NSImageView, onScreen: Bool, hidden: Bool) { // update picture and pin if we found the correct Space
            self.contentView = nil; self.contentView = imageView
            if onScreen && !self.collectionBehavior.contains(.stationary) {
                // pin this window to this Space
                self.collectionBehavior = [.stationary, .fullScreenNone, .ignoresCycle]
                self.level = hidden ? .staticLayer : .hiddenLayer //; print("set")    // move to top of this level
            }
            //print("in setWin, beingUsed=\(self.beingUsed), onScreen=\(onScreen) \(self.isOnActiveSpace), hidden=\(hidden), stationary?=\(self.collectionBehavior.contains(.stationary)), screen.frame==frame?\(self.screen?.frame == self.frame), frame=\(self.frame)")
        }
    }
    
    private var myDesktops : [ CGWindowID : MyWindow] = [:] //
    private var backupDesktops : [ MyWindow] = []
    private var BGTimer : Timer?                        // lazy update for Desktop pics
    private var BGTime = TimeInterval(730000.0)         // time interveral for lazy updates
    private var hidden_ = false                         // are icons hidden?
    private var observation: NSKeyValueObservation?     // Apple doc- to detect dark/light mode switch
    private var currentImages : [CGRect : CGImage] = [:]  // copy of background image being shown for screen
    
    var hidden: Bool {                          // are icons currently hidden?
        get { return hidden_ }
        set (value) { hidden_ = value }
    }
    // hide or show Desktop icons
    func doHide() { //print("in doHide, hidden=\(!hidden), empty myDesktops?\(myDesktops.isEmpty)")
        hidden = !hidden        // toggle hide/show icons
        UserDefaults.standard.set(hidden, forKey: "hidden") // save state
        if hidden {             // appears the user want to hide icons
            updateDesktops(true) // force all Desktops to be updated
            backupDesktops.filter({return $0.beingUsed}).forEach({win in win.level = .floatLayer})
            myDesktops.forEach({_, win in win.level = win.collectionBehavior.contains(.stationary) ? .staticLayer : .floatLayer})
        } else {
            BGTimer?.invalidate()        // stop timer since icons are not hidden
            myDesktops.forEach({ _, win in win.level = .hiddenLayer})    // don't show any of the Desktop windows
            backupDesktops.forEach({win in win.level = .hiddenLayer})
        }
    }
    // start a repeating timer to update all Desktops
    func doTimer() { //print("in doTimer, BGTime=\(BGTime), valid?\(BGTime < 720000.0)")
        BGTimer?.invalidate()
        if BGTime < 720000.0 && hidden {  //print("start BGTimer")  only start timer if time interval is less than 200 hours
            BGTimer = Timer.scheduledTimer(withTimeInterval: BGTime, repeats: true, block: { _ in self.updateDesktops(true) })//; print(BGTimer) })
        }
    }
    // called when user changes the repeating timer interval
    @objc func timerChanged(_ notifier : Notification) { //print("in timerChanged, TimeInterval=\(notifier.object as! TimeInterval)")
        if let time = notifier.object as? TimeInterval {
            BGTime = time
            doTimer()
        }
    }

    @available(macOS 27.0, *)
    private func refreshDesktopImage( cgWin: CGWindowID, win: MyWindow, onScreen: Bool) {
        let scale = win.screen?.backingScaleFactor ?? 1
        let origin = win.frame.origin
        Task {
            do {
                //let content0 = try await SCShareableContent.current  //everything we are allowed?
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: onScreen)
                guard let desktopWindow = content.windows.first(where: { $0.windowID == cgWin }) else { return }
                
                //print("isOnScreen: \(desktopWindow.isOnScreen), isActive: \(desktopWindow.isActive), frame: \(desktopWindow.frame)")
                let config = SCStreamConfiguration()
                config.width = Int((desktopWindow.frame.width * scale).rounded())
                config.height = Int((desktopWindow.frame.height * scale).rounded())
                config.showsCursor = false
                config.captureResolution = .best
                
                //guard let targetDisplay = content.displays.first(where: { $0.frame.contains(origin) }) else { return }
                //guard let targetWindow = content.windows.first(where: { $0.windowID == cgWin }) else { return }
                //let filter = SCContentFilter(display: targetDisplay, excludingApplications: content.applications, exceptingWindows: [])
                let filter = SCContentFilter(desktopIndependentWindow: desktopWindow)
                let cgImage = try await SCScreenshotManager.captureImage( contentFilter: filter, configuration: config)
                
                await MainActor.run {
                    // Avoid applying an old async result to a reused window.
                    guard self.myDesktops[cgWin] === win else { return }
                    
                    win.lastGoodImage = cgImage
                    currentImages[win.frame] = cgImage
                    win.setWin(image: cgImage, onScreen: onScreen, hidden: self.hidden)
                }
            } catch {
                NSLog("Desktop capture failed: \(error)")
            }
        }
        
            
    }
    func updateDesktops(_ doAll : Bool = false) {  // update pictures of Desktop(s)
        BGTimer?.invalidate()           // stop any timers
        //print("updateDesktops, doAll=\(doAll) number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count) (\(myDesktops.reduce(0) {n, w in return n + (w.value.screen != nil ? 1 : 0)}))  (\(NSScreen.screens.count)) number of CGDesktop on screen: \(getDesktopArray().reduce(0) { numOnScreen, window in let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false; return numOnScreen + (onScreen ? 1 : 0)}) \(memoryFootprint()) # of backups:\(backupDesktops.count)")
        
        for (cgWin, onScreen, frame) in getDesktopArray(doAll ? .optionAll : .optionOnScreenOnly).map({ ($0[kCGWindowNumber as String] as! CGWindowID, $0[kCGWindowIsOnscreen as String] as? Bool ?? false, CGRect(dictionaryRepresentation: $0[kCGWindowBounds as String] as! CFDictionary)!)}) {
            if myDesktops[cgWin] == nil { addDesktop(cgWin: cgWin, frame: frame, onScreen: onScreen) }
            setImageView(cgWin: cgWin, win: myDesktops[cgWin]!, onScreen: onScreen)
        } //;print(" ")
        guessImage()
        doTimer()                                           // restart any timers
        //print("number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count), NSScreen:\(NSScreen.screens.count) \(memoryFootprint())")
    }
    
    func setImageView(cgWin: CGWindowID, win : MyWindow, onScreen : Bool) {
        if let color = win.color {
            let image = NSImage.swatchWithColor(color: color, size: NSSize(width: 1, height: 1))
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleAxesIndependently
            win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden)
            return
        }

        if #available(macOS 27.0, *) {
            if onScreen { refreshDesktopImage(cgWin: cgWin, win: win, onScreen: onScreen) }
            //refreshDesktopImage(cgWin: cgWin, win: win, onScreen: onScreen)
        } else {
            guard let cgImage = CGWindowListCreateImage(CGRectNull, [.optionIncludingWindow], cgWin, [.bestResolution]) else { return }
            win.lastGoodImage = cgImage
            //currentImages[win.frame] = cgImage  //shouldn't be necessary
            win.setWin(image: cgImage, onScreen: onScreen, hidden: hidden)
        }
    }
    
    func getDesktopArray(_ option: CGWindowListOption = .optionAll) -> [[String: AnyObject]] {
        var nTry = 0
        repeat {
            // need to find Desktop windows... (let's use apple's approved way so we don't trip up security guards)
            let windows = CGWindowListCopyWindowInfo([option], kCGNullWindowID)! as! [[String: AnyObject]]  // get (all or onscreen) windows
            let desktopWindowLevel = CGWindowLevelForKey(.desktopWindow) - 1                                // level of Desktop background image
            let desktopWindows = windows.filter {                                                           // get array of dictionaries for Desktop CGWindows
                let windowLevel = $0[kCGWindowLayer as String] as! CGWindowLevel
                return windowLevel == desktopWindowLevel
            }
            var screenRect: [CGRect] = []
            let numOnScreen = desktopWindows.reduce(0) { numOnScreen, window in             // find the number of desktops onScreen and also construct array of unique screen CGRects
                let rect = CGRect(dictionaryRepresentation: window[kCGWindowBounds as String] as! CFDictionary)!
                if !screenRect.contains(rect) { screenRect.append(rect)}
                let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
                return numOnScreen + (onScreen ? 1 : 0)
            }
            let n = screenRect.count
            let good = n == NSScreen.screens.count || n == backupDesktops.count || n == backupDesktops.filter({return $0.beingUsed}).count
            //print("numOnScreen=\(numOnScreen), screenRect.count=\(screenRect.count), backup.count=\(backupDesktops.filter({return $0.beingUsed}).count), screens.count=\(NSScreen.screens.count), good=\(good), nTry=\(nTry)")
            if (numOnScreen == screenRect.count && good) || nTry > 20 { return desktopWindows }
            usleep(150_000)
            nTry += 1   // FIX ME?
        } while true
    }
    
    func addDesktop(cgWin: CGWindowID, frame: CGRect, onScreen: Bool ) {
        let h0 = NSHeight(NSScreen.screens[0].frame)
        let origin = CGPoint(x: frame.origin.x, y: h0 - frame.origin.y - frame.height)
        let rect = CGRect(origin: origin, size: frame.size)
        if let w = myDesktops[cgWin] {
            w.reset(contentRect: rect, hidden: hidden)
            NSLog("Hide Icons: [\(cgWin)] reset window, frame=\(frame), onScreen=\(onScreen)")
        } else {
            myDesktops[cgWin] = MyWindow(contentRect: rect, hidden: hidden)
            NSLog("Hide Icons: [\(cgWin)] new window, frame=\(frame), onScreen=\(onScreen)")
        }
    }
    func createDesktops() { //print("createDesktops, myDesktop.count=\(myDesktops.count)")     // make window for each desktop
        BGTimer?.invalidate()   // stop any timer
        
        //print("createDesktops, myDesktop.count=\(myDesktops.count) (\(myDesktops.reduce(0) {n, w in return n + (w.value.screen != nil ? 1 : 0)})) number of CGDesktop on screen: \(getDesktopArray().reduce(0) { numOnScreen, window in let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false; return numOnScreen + (onScreen ? 1 : 0)}) number of monitors: \(Set(myDesktops.map({$0.value.screen})).count) \(memoryFootprint())")
        //print("number of backupDesktops:\(backupDesktops.count), \(backupDesktops.filter({return $0.beingUsed}).count), \(NSScreen.screens.count)")
        createBackups() //;print("number of backupDesktops:\(backupDesktops.count), \(backupDesktops.filter({return $0.beingUsed}).count), \(NSScreen.screens.count)")
        
        let screens = NSScreen.screens; let h0 = NSHeight(screens[0].frame) // height of Screen that has menu bar
        myDesktops.forEach({ _, win in win.beingUsed = false; win.level = .hiddenLayer; win.orderOut(nil) })  // assume window is not going to be used
        for (cgID, onScreen, rectCG) in getDesktopArray().map({ ($0[kCGWindowNumber as String] as! CGWindowID, $0[kCGWindowIsOnscreen as String] as? Bool ?? false, CGRect(dictionaryRepresentation: $0[kCGWindowBounds as String] as! CFDictionary)!)}) {
            let origin = CGPoint(x: rectCG.origin.x, y: h0 - rectCG.origin.y - rectCG.height)
            let rect = CGRect(origin: origin, size: rectCG.size)            // CGrect is in Screen coordinate
            //print("is cgID not in myDesktops? \(myDesktops[cgID]==nil)")
            if let win = myDesktops[cgID] {
                win.reset(contentRect: rect, hidden: hidden)
            } else {
                myDesktops[cgID] = MyWindow(contentRect: rect, hidden: hidden)
            }
            setImageView(cgWin: cgID, win: myDesktops[cgID]!, onScreen: onScreen)   //;print(cgID,myDesktops[cgID]!.frame)
        }
        //print("number of myDesktops:\(myDesktops.count), \(NSScreen.screens.count)")
        for cgID in myDesktops.filter({ return !$0.value.beingUsed}).keys { //print(cgID,myDesktops[cgID]!.frame,myDesktops[cgID]!.beingUsed)   // remove any myDesktops that are not being used
            myDesktops[cgID]?.orderOut(nil); myDesktops.removeValue(forKey: cgID)//if let myD = myDesktops.removeValue(forKey: cgID) {myD.close()}    //?.close()
        }   //;print("number of myDesktops:\(myDesktops.count), \(NSScreen.screens.count)")
        guessImage()
        myDesktops.forEach({_, win in win.orderFrontRegardless()})

        //getDesktopArray().reduce(0,{$1[kCGWindowIsOnscreen as String] as? Bool ?? false})
        //print("createDesktops, myDesktop.count=\(myDesktops.count) (\(myDesktops.reduce(0) {n, w in return n + (w.value.screen != nil ? 1 : 0)})) number of CGDesktop on screen: \(getDesktopArray().reduce(0) { numOnScreen, window in let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false; return numOnScreen + (onScreen ? 1 : 0)}) number of monitors: \(Set(myDesktops.map({$0.value.screen})).count)")
        doTimer()
        //print("number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count) \(memoryFootprint())")
    }

    func guessImage() {
        if #available(macOS 27.0, *) {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false, block: { _ in
                self.currentImages.forEach({frame, image in
                    self.myDesktops.forEach({cgID , win in
                        if !win.collectionBehavior.contains(.stationary) && win.frame == frame  {
                            win.lastGoodImage = image
                            win.setWin(image: image, onScreen: false, hidden: self.hidden)
                            win.orderFrontRegardless()
                        }
                    })
                })
            })
        }
    }
    func createBackups() {
        backupDesktops.forEach({ win in win.beingUsed = false; win.orderOut(nil); win.level = .hiddenLayer })
        while NSScreen.screens.count < 1 { usleep(150_000) }
        let screens = NSScreen.screens
        for (idx, screen) in screens.enumerated() {
            if idx >= backupDesktops.count {
                backupDesktops.append(MyWindow(contentRect: screen.frame, hidden: hidden))
            } else {
                backupDesktops[idx].reset(contentRect: screen.frame, hidden: hidden)
            }
            backupDesktops[idx].color = .black
            setImageView(cgWin: 0, win: backupDesktops[idx], onScreen: false)
        }
        backupDesktops.forEach({win in if win.beingUsed {win.orderFrontRegardless()}})  //; backupDesktops.forEach({win in print(win.frame,win.beingUsed)})
    }
    // number of Desktops
    var numberOfDesktops: Int {
        get { return getDesktopArray().count }
    }
    // Given a point on screen, return a small preview image
    func desktopFromPoint(_ point: CGPoint, color: NSColor, thumbnailSize: NSSize) -> (NSImage?, NSColor, Bool) {
        for screen in NSScreen.screens.filter({return $0.frame.contains(point)}) {
            for cgID in getDesktopArray(.optionOnScreenOnly).map({ $0[kCGWindowNumber as String] as! CGWindowID}) {
                guard let win = myDesktops[cgID], win.screen == screen else { continue }
                let thumbnail = win.lastGoodImage.map { cgImage -> NSImage in
                    let thumb = NSImage(size: thumbnailSize)
                    thumb.lockFocus()
                    NSGraphicsContext.current?.imageInterpolation = .high
                    NSImage(cgImage: cgImage, size: NSZeroSize).draw(in: NSRect(origin: .zero, size: thumbnailSize), from: .zero, operation: .copy, fraction: 1.0)
                    thumb.unlockFocus()
                    return thumb
                }
                return (thumbnail, win.color ?? color, win.color != nil)
            }
        }
        return (nil, color, false)
    }
    // want solid color or actual wallpaper for Desktop
    @objc func desktopTypeChange(_ notifier: Notification) {
        BGTimer?.invalidate()
        let (color, desktop, mousePoint ) = notifier.object as? (NSColor, DesktopTypes, CGPoint) ?? (NSColor.black, .allDesktop, CGPoint.zero)
        switch desktop {
        case .solidColorDesktop, .desktop: // one Desktop is either getting a solid color or the actual Desktop, find it
            for screen in NSScreen.screens.filter({$0.frame.contains(mousePoint)}) { // only if the mouse click was on this screen
                for cgID in getDesktopArray(.optionOnScreenOnly).map({ $0[kCGWindowNumber as String] as! CGWindowID}) {
                    if myDesktops[cgID]?.screen == screen { myDesktops[cgID]!.color = (desktop == .solidColorDesktop) ? color :  nil }
                }
            }
        default:    // all Desktops are actual or solid color
            myDesktops.forEach({ _, win in win.color = (desktop == .allSolidColorDesktop) ? color : nil })
        }
        updateDesktops(desktop == .allDesktop || desktop == .allSolidColorDesktop)  // will also restart timer
    }

    @available(macOS 27.0, *)
    func showAlert() {
        let alert = NSAlert()
        alert.messageText = "Hide Icons Requires Permissions"
        alert.informativeText = "Snapshot of Desktop wallpaper is required for functionality.\n\nNo snapshots, audio or video streams are stored or shared."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Continue")
        let _ = alert.runModal()
        //if !CGRequestScreenCaptureAccess() {NSApp.terminate(nil)}
        CGRequestScreenCaptureAccess()
    }
    // set up initial window lists for each screen and observers
    init() {
        if #available(macOS 27.0, *) {
            // Checks whether Screen Recording access is already granted, and if not, triggers the system's standard permission dialog.
            if !CGPreflightScreenCaptureAccess() { showAlert() }
        }
        hidden = ( UserDefaults.standard.object(forKey: "hidden") == nil) ? true : UserDefaults.standard.bool(forKey: "hidden")
        createDesktops() // go grab all the Desktops
        
        let NCdefault = NotificationCenter.default
        NCdefault.addObserver(self, selector: #selector(self.timerChanged(_:)), name: .timeBG, object: nil)             // catch background timer interval
        NCdefault.addObserver(self, selector: #selector(self.desktopTypeChange(_:)), name: .desktopType, object: nil)   // desktops are actual or solid color, for one or all
        NCdefault.addObserver(forName: .createDesktops, object: nil, queue: .main, using: { not in self.createDesktops() })
        NCdefault.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: {_ in //print("didChangeScreenParameters \(self.memoryFootprint())");
            self.BGTimer?.invalidate(); usleep(500_000); self.createDesktops()})    //;print("didChangeScreenParameters done  \(self.memoryFootprint())")})
        NCdefault.addObserver(forName: .doHide, object: nil, queue: .main, using: {_ in self.doHide() })
        let WSsharedNC = NSWorkspace.shared.notificationCenter
        WSsharedNC.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: {_ in self.BGTimer?.invalidate()  })//; print("didSleep") })
        WSsharedNC.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: {_ in //print("didWake \(self.memoryFootprint())")
            usleep(500_000); self.updateDesktops(true)}) //; print("didWake done \(self.memoryFootprint())") })
        WSsharedNC.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: { _ in //print("activeSpaceDidChange  \(self.memoryFootprint())")
            self.BGTimer?.invalidate(); usleep(150_000);  self.updateDesktops(true)})   //;print("activeSpaceDidChange done \(self.memoryFootprint())")}) //ugh! FIXME apple
        
        // this should capture in/out of Dark Mode
        if #available(OSX 10.14, *) {
            observation = NSApp.observe(\.effectiveAppearance) { (app, _) in
                if self.hidden { // give 3 second delay to make sure the Desktop did in fact update
                    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { _ in self.updateDesktops(true)})   //; print("mode change!") })
                }
            }
        }
    }
    // tear down observers (is this really necessary?)
    deinit {
        observation?.invalidate(); BGTimer?.invalidate() // invalidate any background timers
        let WSsharedNC = NSWorkspace.shared.notificationCenter
        WSsharedNC.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        WSsharedNC.removeObserver(self, name: NSWorkspace.screensDidWakeNotification, object: nil)
        WSsharedNC.removeObserver(self, name: NSWorkspace.screensDidSleepNotification, object: nil)
        let NCdefault = NotificationCenter.default
        NCdefault.removeObserver(self, name: .doHide, object: nil)
        NCdefault.removeObserver(self, name: .timeBG, object: nil)
        NCdefault.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NCdefault.removeObserver(self, name: .createDesktops, object: nil)
        NCdefault.removeObserver(self, name: .desktopType, object: nil)
        myDesktops.removeAll(); backupDesktops.removeAll() // and free up screen/window dictionary
    }
    
    func memoryFootprint() -> String {
        // The `TASK_VM_INFO_COUNT` and `TASK_VM_INFO_REV1_COUNT` macros are too
        // complex for the Swift C importer, so we have to define them ourselves.
        let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        guard let offset = MemoryLayout.offset(of: \task_vm_info_data_t.min_address) else {return "memory: NA"}
        let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t(offset / MemoryLayout<integer_t>.size)
        var info = task_vm_info_data_t()
        var count = TASK_VM_INFO_COUNT
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard
            kr == KERN_SUCCESS,
            count >= TASK_VM_INFO_REV1_COUNT
        else { return "memory: NA" }
        
        let usedBytes = Float(info.phys_footprint)
        let usedBytesInt: UInt64 = UInt64(usedBytes)
        let usedMB = usedBytesInt / 1024 / 1024
        let usedMBAsString: String = "memory: \(usedMB) MB"
        return usedMBAsString
    }
}
