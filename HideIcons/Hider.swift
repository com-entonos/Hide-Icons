//
//  Hider.swift
//
//  Created by G.J. Parker on 21/04/02.
//  Copyright © 2021 G.J. Parker. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let doHide = NSNotification.Name("doHide")                       //toggle hide/show Desktop icons
    static let createDesktops = NSNotification.Name("createDesktops")       //recreate windows for all Desktops
    static let updateDesktop = NSNotification.Name("updateDesktop")         //update only windows that are on screen (i.e. current Desktop(s))
    static let updateAllDesktops = NSNotification.Name("updateAllDesktops") //update all windows to reflect current Desktops
    static let timeBG = NSNotification.Name("timeBG")                       //change the time interval for background updates
    static let desktopType = NSNotification.Name("desktopType")             //support for solid color or actual Desktop wallpaper
}

class Hider {  // class that covers Desktop w/ pictures of Desktop- invoked by notifications and/or internal timers
    
    class MyWindow : NSWindow { // just add some data and methods for NSWindow- this will hold a window w/ a Desktop pic
        var cgID: CGWindowID        // CGWindowID of a Desktop
        var color: NSColor? = nil   // display solid color instead of actual Desktop? nil means actual, otherwise that color
        var cgIDCF: CFArray? = nil  // CFArray of CGWindowID used for CG routines
        
        init(contentRect: NSRect, cgID: CGWindowID) {
            self.cgID = cgID
            let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1) // construct CFArray for this CGWindowID
            pointer[0] = UnsafeRawPointer(bitPattern: UInt(cgID))
            cgIDCF = CFArrayCreate(kCFAllocatorDefault, pointer, 1, nil)                //used in CGWindowListCreateDescriptionFromArray call
            super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false) // create NSWindow
            reset(contentRect: contentRect)
        }
        
        func reset(contentRect: NSRect) {
            self.setFrame(contentRect, display: true, animate: false)   // force the correct frame for window
            self.collectionBehavior = .canJoinAllSpaces  // we want the window to follow Spaces around (until we find the correct space then we'll pin it on top)
            self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))  //hack? this makes mission control and expose ignore the window
            self.orderBack(nil)  // critical we place on back
            // rest is to make the window dumb
            self.canHide = false; self.isExcludedFromWindowsMenu = true; self.isOpaque = true
            self.hasShadow = false; self.hidesOnDeactivate = false; self.discardCursorRects()
            self.discardEvents(matching: .any, before: nil); self.ignoresMouseEvents = true; self.isRestorable = false
            self.animationBehavior = .none
            //self.animationBehavior = .default
        }
        
        func setWin(imageView: NSImageView, onScreen: Bool, hidden: Bool) { // update picture and pin if we found the correct Space
            if onScreen {   // if this is currently showing, bring to front and pin it to this Space
                self.orderFront(nil); self.collectionBehavior = .stationary; self.animationBehavior = .none
                //if self.screen?.frame != self.frame { self.setFrame(self.screen!.frame, display: true, animate: false)}
            }
            self.contentView = imageView
            if !hidden { self.orderOut(nil) }  // showing desktop, don't show this window at all
            print("in setWin, cgID=\(self.cgID), onScreen=\(onScreen), hidden=\(hidden), stationary?\(self.collectionBehavior == .stationary), screen.frame==frame?\(self.screen?.frame == self.frame)")
        }
    }
    
    var myDesktops : [ CGWindowID : MyWindow] = [:] //
    var BGTimer : Timer?                        // lazy update for Desktop pics
    var BGTime = TimeInterval(730000.0)         // time interveral for lazy updates
    var hidden_ = false                         // are icons hidden?
    var cgIDCFArray: [ CGWindowID : CFArray ] = [:] // dictionary that holds CGWindowID in a CFArray used in CG routines
    var observation: NSKeyValueObservation?     // Apple doc- to detect dark/light mode switch
    
    var hidden: Bool {                          // are icons currently hidden?
        get { return hidden_ }
        set (value) { hidden_ = value }
    }
    // hide or show Desktop icons
    func doHide() { print("in doHide, hidden=\(!hidden), empty myDesktops?\(myDesktops.isEmpty)")
        hidden = !hidden        // toggle hide/show icons
        if hidden {             // appears the user want to hide icons
            for (_, win) in myDesktops {
                if win.collectionBehavior == .stationary { win.orderFront(nil) } else { win.orderBack(nil) }
            }
            updateDesktops(true) // force all Desktops to be updated
        } else {
            BGTimer?.invalidate()        // stop timer since icons are not hidden
            for (_, win) in myDesktops { win.orderOut(nil) }   // don't show any of the Desktop windows
        }
    }
    // start a repeating timer to update all Desktops
    func doTimer() { print("in doTimer, BGTime=\(BGTime), valid?\(BGTime < 720000.0)")
        BGTimer?.invalidate()
        if BGTime < 720000.0 {  // only start timer if time interval is less than 200 hours
            BGTimer = Timer.scheduledTimer(withTimeInterval: BGTime, repeats: true, block: { _ in self.updateDesktops(true) })
        }
    }
    // called when user changes the repeating timer interval
    @objc func timerChanged(_ notifier : Notification) { print("in timerChanged, TimeInterval=\(notifier.object as! TimeInterval)")
        if let time = notifier.object as? TimeInterval {
            BGTime = time
            if hidden { doTimer() }         // only start timer if icons are hidden
            else { BGTimer?.invalidate() }
        }
    }

    func updateDesktops(_ doAll : Bool = false) {  // update pictures of Desktop(s)
        BGTimer?.invalidate()           // stop any timers
        print("updateDesktops, doAll=\(doAll) number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count)")
        
        for cgWin in getDesktopArray(doAll ? .optionAll: .optionOnScreenOnly) {
            if let win = myDesktops[cgWin] {
                let desc = (CGWindowListCreateDescriptionFromArray(win.cgIDCF) as! [[String : AnyObject]]).last
                let onScreen = desc![kCGWindowIsOnscreen as String] as? Bool ?? false
                if win.color == nil {
                    guard let cgImage = CGWindowListCreateImage(.null, [.optionIncludingWindow], cgWin, [.nominalResolution]) else { continue }
                    let image = NSImage(cgImage: cgImage, size: NSZeroSize)
                    let imageView = NSImageView(image: image)
                    win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden)
                } else {
                    let image = NSImage.swatchWithColor(color: win.color!, size: win.frame.size)
                    let imageView = NSImageView(image: image)
                    win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden)
                }
            } else {print("oh no- \(cgWin) is not in MyDesktops!")}
        }
        doTimer()                                           // restart any timers
        print("number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count)")
    }
    
    func getDesktopArray(_ option: CGWindowListOption = .optionAll) -> [CGWindowID] {
        // need to find Desktop windows... (let's use apple's approved way so we don't trip up security guards)
        let windows = CGWindowListCopyWindowInfo([option], kCGNullWindowID)! as! [[String: AnyObject]]  // get (all or onscreen) windows
        let desktopWindowLevel = CGWindowLevelForKey(.desktopWindow) - 1                                    // level of Desktop background image
        let desktopWindows = windows.filter {
            let windowLevel = $0[kCGWindowLayer as String] as! CGWindowLevel
            return windowLevel == desktopWindowLevel
        }
        return desktopWindows.map { $0[kCGWindowNumber as String] as! CGWindowID}       // array of CGWindowID that are Desktop windows
    }
    
    func getDesktopCGWindowID(_ option: CGWindowListOption = .optionAll) -> CFArray? {
        let desktopCGID = getDesktopArray(option)              // array of CGWindowID for (all or onscreen) Desktops

        // now create a CFArray with all the CGWindowID that are Desktop pictures
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: desktopCGID.count)
        for (index, win) in desktopCGID.reversed().enumerated() {       // we reverse simply so when we create the windows, they stack up in a way that makes more sense
            pointer[index] = UnsafeRawPointer(bitPattern: UInt(win))
        }
        return CFArrayCreate(kCFAllocatorDefault, pointer, desktopCGID.count, nil)  // there it is. used in CGWindowListCreateDescriptionFromArray call
    }
    
    func createDesktops() {      // make window for each desktop
        BGTimer?.invalidate()   // stop any timer
        let h0 = NSHeight((NSScreen.screens.filter({$0.frame.origin == CGPoint.zero}).first?.frame)!)   // height of Screen that has menu bar
        
        print("createDesktops, myDesktop.count=\(myDesktops.count)")

        for desktopWindows in CGWindowListCreateDescriptionFromArray(getDesktopCGWindowID()) as! [[String : AnyObject]] { // loop over CGWindows that are Desktops...
            let rectCG = CGRect(dictionaryRepresentation: desktopWindows[kCGWindowBounds as String] as! CFDictionary)!
            let origin = CGPoint(x: rectCG.origin.x, y: h0 - rectCG.origin.y - rectCG.height)
            let rect = CGRect(origin: origin, size: rectCG.size)            // CGrect is in Screen coordinates
            let cgID = desktopWindows[kCGWindowNumber as String] as! CGWindowID
            if myDesktops[cgID] == nil {
                myDesktops[cgID] = MyWindow(contentRect: rect, cgID: cgID)
            } else {
                myDesktops[cgID]!.reset(contentRect: rect)
            }
            let onScreen = desktopWindows[kCGWindowIsOnscreen as String] as? Bool ?? false
            if let win = myDesktops[cgID] {
                if win.color == nil {
                    guard let cgImage = CGWindowListCreateImage(.null, [.optionIncludingWindow], cgID, [.nominalResolution]) else { continue }
                    let image = NSImage(cgImage: cgImage, size: NSZeroSize)
                    let imageView = NSImageView(image: image)
                    win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden)
                } else {
                    let image = NSImage.swatchWithColor(color: win.color!, size: rect.size)
                    let imageView = NSImageView(image: image)
                    win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden)
                }
            }
        }
        print("number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count)")
    }
    // number of Desktops
    var numberOfDesktops: Int {
        get { return getDesktopArray().count }
    }
    // given a point on screen, return the Desktop image and color
    func desktopFromPoint(_ point : CGPoint, color : NSColor) -> (CGImage?, NSColor, Bool) {
        for screen in NSScreen.screens.filter({$0.frame.contains(point)}) {
            for cgID in getDesktopArray(.optionOnScreenOnly) {
                if myDesktops[cgID]?.screen == screen {
                    guard let cgImage = CGWindowListCreateImage(.null, [.optionIncludingWindow], cgID, [.nominalResolution]) else { continue }
                    return (cgImage, myDesktops[cgID]!.color ?? color, myDesktops[cgID]!.color != nil)
                }
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
                for cgID in getDesktopArray(.optionOnScreenOnly) {
                    if myDesktops[cgID]?.screen == screen { myDesktops[cgID]!.color = (desktop == .solidColorDesktop) ? color :  nil }
                }
            }
        case .allSolidColorDesktop: // all Desktops get a solid color
            for (_, win) in myDesktops { win.color = color }
        default:    // all Desktops are actual
            for (_, win) in myDesktops { win.color = nil }
        }
        updateDesktops(desktop == .allDesktop || desktop == .allSolidColorDesktop)  // will also restart timer
    }
    // screens either slept or awoke
    @objc func screensDidSleepWake(_ notifier: Notification) {
        if notifier.name == NSWorkspace.screensDidWakeNotification {// if awake, update all windows & start timers
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false, block: { _ in self.updateDesktops(true) }); print("didWake")
        } else {
            BGTimer?.invalidate(); print("didSleep")
        }
    }
    // set up initial window lists for each screen and observers
    init() {
        hidden = true
        createDesktops() // go grab all the Desktops
        
        let NCdefault = NotificationCenter.default
        NCdefault.addObserver(self, selector: #selector(self.timerChanged(_:)), name: .timeBG, object: nil)             // catch background timer interval
        NCdefault.addObserver(self, selector: #selector(self.desktopTypeChange(_:)), name: .desktopType, object: nil)   // desktops are actual or solid color, for one or all
        NCdefault.addObserver(forName: .createDesktops, object: nil, queue: OperationQueue.current, using: { not in self.createDesktops() })
        NCdefault.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: OperationQueue.current, using: {_ in self.createDesktops()})
        NCdefault.addObserver(forName: .updateDesktop, object: nil, queue: OperationQueue.current, using: { _ in self.updateDesktops(false)})
        NCdefault.addObserver(forName: .updateAllDesktops, object: nil, queue: OperationQueue.current, using: { _ in self.updateDesktops(true)})
        NCdefault.addObserver(forName: .doHide, object: nil, queue: OperationQueue.current, using: {_ in self.doHide() })
        let WSsharedNC = NSWorkspace.shared.notificationCenter
        WSsharedNC.addObserver(self, selector: #selector(screensDidSleepWake(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        WSsharedNC.addObserver(self, selector: #selector(screensDidSleepWake(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        WSsharedNC.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: OperationQueue.current, using: { _ in usleep(150_000); self.updateDesktops(false)}) //ugh! FIXME apple
        
        // this should capture in/out of Dark Mode
        if #available(OSX 10.14, *) {
            observation = NSApp.observe(\.effectiveAppearance) { (app, _) in
                if self.hidden { // give 3 second delay to make sure the Desktop did in fact update
                    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { _ in self.updateDesktops(true) })
                }
            }
        }
    }
    // tear down observers (is this really necessary?)
    deinit {
        BGTimer?.invalidate() // invalidate any background timers
        let WSsharedNC = NSWorkspace.shared.notificationCenter
        WSsharedNC.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        WSsharedNC.removeObserver(self, name: NSWorkspace.screensDidWakeNotification, object: nil)
        WSsharedNC.removeObserver(self, name: NSWorkspace.screensDidSleepNotification, object: nil)
        let NCdefault = NotificationCenter.default
        NCdefault.removeObserver(self, name: .doHide, object: nil)
        NCdefault.removeObserver(self, name: .timeBG, object: nil)
        NCdefault.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NCdefault.removeObserver(self, name: .createDesktops, object: nil)
        NCdefault.removeObserver(self, name: .updateDesktop, object: nil)
        NCdefault.removeObserver(self, name: .updateAllDesktops, object: nil)
        NCdefault.removeObserver(self, name: .desktopType, object: nil)
        observation?.invalidate(); myDesktops.removeAll() // and free up screen/window dictionary
    }
}
