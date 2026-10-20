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
            //self.level = hidden ? .floatLayer : .hiddenLayer
            //self.orderFrontRegardless() //place on top of this level
            if hidden {
                self.level = .floatLayer
                self.orderFrontRegardless()
            } else {
                self.orderOut(nil)
            }
            self.beingUsed = true
            // rest is to make the window dumb
            self.canHide = false; self.isExcludedFromWindowsMenu = true; self.isOpaque = true
            self.hasShadow = false; self.hidesOnDeactivate = false; self.discardCursorRects()
            self.discardEvents(matching: .any, before: nil); self.ignoresMouseEvents = true; self.isRestorable = false
            self.animationBehavior = .none
        }
        
        func setWin(image : CGImage?, onScreen: Bool, hidden: Bool) {  //given image, create NSImageView
            let nsImageView = image == nil ? nil : NSImageView(image: NSImage(cgImage: image!, size: NSZeroSize))
            self.setWin(imageView: nsImageView, onScreen: onScreen, hidden: hidden)
        }
        func setWin(imageView: NSImageView?, onScreen: Bool, hidden: Bool) { // update picture and pin if we found the correct Space
            self.contentView = nil; self.contentView = imageView
            if onScreen && !self.collectionBehavior.contains(.stationary) {
                // pin this window to this Space
                self.collectionBehavior = [.stationary, .fullScreenNone, .ignoresCycle]
                self.level = .staticLayer
            }
            if !hidden || imageView == nil {self.orderOut(nil)} else {self.orderFrontRegardless()}
        }
    }
    
    private var myDesktops : [ CGWindowID : MyWindow] = [:] //
    private var BGTimer : Timer?                        // lazy update for Desktop pics
    private var BGTime = TimeInterval(730000.0)         // time interveral for lazy updates
    private var hidden_ = false                         // are icons hidden?
    private var observation: NSKeyValueObservation?     // Apple doc- to detect dark/light mode switch
    
    var hidden: Bool {                          // are icons currently hidden?
        get { return hidden_ }
        set (value) { hidden_ = value }
    }
    // hide or show Desktop icons
    func doHide() { //print("in doHide, hidden=\(!hidden), empty myDesktops?\(myDesktops.isEmpty)")
        hidden = !hidden        // toggle hide/show icons
        UserDefaults.standard.set(hidden, forKey: "hidden") // save state
        updateDesktops(true) // force all Desktops to be updated
        if !hidden { BGTimer?.invalidate() }       // stop timer since icons are not hidden
        if #available(macOS 14.0, *) {
            let domain = "com.apple.WindowManager" as CFString
            CFPreferencesSetAppValue("StandardHideDesktopIcons" as CFString, hidden as CFPropertyList, domain)
            CFPreferencesAppSynchronize(domain)
        } else {
            let domain = "com.apple.finder" as CFString
            CFPreferencesSetAppValue("CreateDesktop" as CFString, !hidden as CFPropertyList, domain)
            CFPreferencesAppSynchronize(domain)
            if let finderApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) { finderApp.terminate() }
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

    func updateDesktops(_ doAll : Bool = false, _ reset : Bool = false) {  // update pictures of Desktop(s)
        BGTimer?.invalidate()           // stop any timers
        print("doAll? \(doAll), reset? \(reset)")
        var showingDesktop : [NSScreen:MyWindow] = [:]
        for (cgWin, onScreen, frame) in getDesktopArray(doAll ? .optionAll : .optionOnScreenOnly).map({ ($0[kCGWindowNumber as String] as! CGWindowID, $0[kCGWindowIsOnscreen as String] as? Bool ?? false, CGRect(dictionaryRepresentation: $0[kCGWindowBounds as String] as! CFDictionary)!)}) {
            if reset || myDesktops[cgWin] == nil { addDesktop(cgWin: cgWin, frame: frame) }
            setImageView(cgWin: cgWin, win: myDesktops[cgWin]!, onScreen: onScreen)
            if onScreen { showingDesktop[myDesktops[cgWin]!.screen!] = myDesktops[cgWin] }
        }
        showingDesktop.forEach({screen, win in
            if win.color == nil || !hidden {
                myDesktops.forEach({cgWin, w in if win.screen == screen && !w.collectionBehavior.contains(.stationary) {w.orderOut(nil)} })
            } else {
                myDesktops.forEach({cgID, w in
                    if w.screen == screen {
                        if !hidden || w.color == nil {
                            w.orderOut(nil)
                        } else {
                            w.level = w.collectionBehavior.contains(.stationary) ? .staticLayer : .floatLayer
                            w.orderFrontRegardless()
                        }
                    }
                })
            }
            print("screen: \(screen)")
            myDesktops.forEach({cgID, w in if w.screen == screen {
                print("cgID: \(cgID), color? \(w.color != nil), level: \(!w.isVisible ? "orderOut" : w.level == .floatLayer ? "float" : w.level == .staticLayer ? "static" :  "unknown"), onScreen? \(w === win), stationary? \(w.collectionBehavior.contains(.stationary))") }
            })
        })
        doTimer()                       // restart any timers
    }
    
    func setImageView(cgWin: CGWindowID, win : MyWindow, onScreen : Bool) {
        if let color = win.color {
            let image = NSImage.swatchWithColor(color: color, size: NSSize(width: 1, height: 1))
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleAxesIndependently
            win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden)
        } else {
            if #unavailable(macOS 27.0) { if let cgImage = CGWindowListCreateImage(CGRectNull, [.optionIncludingWindow], cgWin, [.bestResolution]) { win.lastGoodImage = cgImage} }
            win.setWin(image: nil, onScreen: onScreen, hidden: hidden)
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
            let good = n == NSScreen.screens.count
            if (numOnScreen == screenRect.count && good) || nTry > 20 { return desktopWindows }
            usleep(150_000)
            nTry += 1   // FIX ME?
        } while true
    }
    
    func addDesktop(cgWin: CGWindowID, frame: CGRect) {
        let h0 = NSHeight(NSScreen.screens[0].frame)
        let origin = CGPoint(x: frame.origin.x, y: h0 - frame.origin.y - frame.height)
        let rect = CGRect(origin: origin, size: frame.size)
        if let w = myDesktops[cgWin] {
            w.reset(contentRect: rect, hidden: hidden)
        } else {
            myDesktops[cgWin] = MyWindow(contentRect: rect, hidden: hidden)
        }
    }
    func createDesktops() { //print("createDesktops, myDesktop.count=\(myDesktops.count)")     // make window for each desktop
        BGTimer?.invalidate()   // stop any timer
        
        myDesktops.forEach({ _, win in win.beingUsed = false; win.orderOut(nil) })  // assume window is not going to be used
        updateDesktops(true, true)
        // remove any myDesktops that are not being used
        for cgID in myDesktops.filter({ return !$0.value.beingUsed}).keys {
            myDesktops[cgID]?.orderOut(nil); myDesktops.removeValue(forKey: cgID)
        }
        myDesktops.forEach({_, win in if let _ = win.color {win.orderFrontRegardless()}})
        hidden = !hidden; doHide()
        
        doTimer()
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

    // set up initial window lists for each screen and observers
    init() {
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
        WSsharedNC.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: {_ in self.BGTimer?.invalidate()  })
        WSsharedNC.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: {_ in //print("didWake \(self.memoryFootprint())")
            usleep(500_000); self.updateDesktops(true)}) //; print("didWake done \(self.memoryFootprint())") })
        WSsharedNC.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: { _ in //print("activeSpaceDidChange  \(self.memoryFootprint())")
            self.BGTimer?.invalidate(); usleep(150_000);  self.updateDesktops(true)})   //ugh! FIXME apple
        
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
        print("Hider.deinit called")
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
        myDesktops.forEach({$0.value.close()})  // should not be necessary, but make sure we don't leave anything on screen
        myDesktops.removeAll()                 // and free up screen/window dictionary
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
