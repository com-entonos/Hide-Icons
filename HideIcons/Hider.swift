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
    
    let hiddenLayer = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow))-2)
    let floatLayer  = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow))+1)
    let staticLayer = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow))+5)
    
    class MyWindow : NSWindow { // just add some data and methods for NSWindow- this will hold a window w/ a Desktop pic
        var color: NSColor? = nil   // display solid color instead of actual Desktop? nil means actual, otherwise that color
        var beingUsed = false
        
        init(contentRect: NSRect, hidden: Bool, level: NSWindow.Level) {
            super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false) // create NSWindow
            reset(contentRect: contentRect, hidden: hidden, level: level)
        }
        
        func reset(contentRect: NSRect, hidden: Bool, level: NSWindow.Level) {
            self.setFrame(contentRect, display: true, animate: false)   // force the correct frame for window
            //if #available(macOS 13.0, *) { self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenNone, .ignoresCycle] } else { self.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle] }
            self.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
            self.level = level
            //self.orderFrontRegardless() //place on top of this level
            self.beingUsed = true
            // rest is to make the window dumb
            self.canHide = false; self.isExcludedFromWindowsMenu = true; self.isOpaque = true
            self.hasShadow = false; self.hidesOnDeactivate = false; self.discardCursorRects()
            self.discardEvents(matching: .any, before: nil); self.ignoresMouseEvents = true; self.isRestorable = false
            self.animationBehavior = .none
        }
        
        func setWin(imageView: NSImageView, onScreen: Bool, hidden: Bool, level: NSWindow.Level) { // update picture and pin if we found the correct Space
            self.contentView = imageView
            /*if !onScreen && self.isOnActiveSpace && self.collectionBehavior.contains(.stationary) {
               self.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
               self.orderBack(nil)
            }*/
            if onScreen && !self.collectionBehavior.contains(.stationary) {
                //if #available(macOS 13.0, *) { self.collectionBehavior = [.stationary, .canJoinAllApplications, .fullScreenNone, .ignoresCycle] } else { self.collectionBehavior = [.stationary, .fullScreenNone, .ignoresCycle] }   // pin this window to this Space
                self.collectionBehavior = [.stationary, .fullScreenNone, .ignoresCycle]
                //if hidden { self.level = staticLayer }
                self.level = level//; print("set")    // move to top of this level
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
    
    var hidden: Bool {                          // are icons currently hidden?
        get { return hidden_ }
        set (value) { hidden_ = value }
    }
    // hide or show Desktop icons
    func doHide() { //print("in doHide, hidden=\(!hidden), empty myDesktops?\(myDesktops.isEmpty)")
        hidden = !hidden        // toggle hide/show icons
        if hidden {             // appears the user want to hide icons
            updateDesktops(true) // force all Desktops to be updated
            backupDesktops.filter({$0.beingUsed}).forEach({win in win.level = floatLayer})
            myDesktops.forEach({_, win in win.level = win.collectionBehavior.contains(.stationary) ? staticLayer : floatLayer})
        } else {
            BGTimer?.invalidate()        // stop timer since icons are not hidden
            myDesktops.forEach({ _, win in win.level = hiddenLayer})    // don't show any of the Desktop windows
            backupDesktops.forEach({win in win.level = hiddenLayer})
        }
    }
    // start a repeating timer to update all Desktops
    func doTimer() { //print("in doTimer, BGTime=\(BGTime), valid?\(BGTime < 720000.0)")
        BGTimer?.invalidate()
        if BGTime < 720000.0 && hidden {  // only start timer if time interval is less than 200 hours
            BGTimer = Timer.scheduledTimer(withTimeInterval: BGTime, repeats: true, block: { _ in self.updateDesktops(true) })
        }
    }
    // called when user changes the repeating timer interval
    @objc func timerChanged(_ notifier : Notification) { //print("in timerChanged, TimeInterval=\(notifier.object as! TimeInterval)")
        if let time = notifier.object as? TimeInterval {
            BGTime = time
            doTimer()
        }
    }

    func updateDesktops(_ doAll : Bool = false) {  // update pictures of Desktop(s)
        BGTimer?.invalidate()           // stop any timers
        //print("updateDesktops, doAll=\(doAll) number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count)")
        
        let dict = getDesktopArray(doAll ? .optionAll: .optionOnScreenOnly)
        for (cgWin, onScreen) in dict.map({ ($0[kCGWindowNumber as String] as! CGWindowID, $0[kCGWindowIsOnscreen as String] as? Bool ?? false)}) {
            if let win = myDesktops[cgWin] { //print("cgWin=\(cgWin), onScreen=\(onScreen), stationary?\(myDesktops[cgWin]?.collectionBehavior == .stationary)")
                setImageView(cgWin: cgWin, win: win, onScreen: onScreen, level: hidden ? (onScreen ? staticLayer : floatLayer) : hiddenLayer)
            } // else { print("    OOPS- \(cgWin) is not in MyDesktops!") }
        } //;print(" ")
        doTimer()                                           // restart any timers
        //print("number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count)")
    }
    
    func setImageView(cgWin: CGWindowID, win : MyWindow, onScreen : Bool, level: NSWindow.Level) {
        if let color = win.color {
            let image = NSImage.swatchWithColor(color: color, size: win.frame.size)
            let imageView = NSImageView(image: image)
            win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden, level: level)
        } else {
            guard let cgImage = CGWindowListCreateImage(CGRectNull, [.optionIncludingWindow], cgWin, [.nominalResolution]) else { return }
            let image = NSImage(cgImage: cgImage, size: NSZeroSize)
            let imageView = NSImageView(image: image)
            win.setWin(imageView: imageView, onScreen: onScreen, hidden: hidden, level: level)
        }
        //print(cgWin, onScreen, win.isOnActiveSpace, hidden, win == nil, win.level == hiddenLayer, win.level == floatLayer, win.level == staticLayer)
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
/*
            let desktopIconWindowLevel = CGWindowLevelForKey(.desktopIconWindow) //- 1                                // level of Desktop background image
            let desktopIconWindows = windows.filter {                                                           // get array of dictionaries for Desktop CGWindows
                let windowLevel = $0[kCGWindowLayer as String] as! CGWindowLevel
                return windowLevel == desktopIconWindowLevel
            }
            print("number of desktopIconWindows: \(desktopIconWindows.count)")
            for win in desktopIconWindows {
                print(win[kCGWindowBounds as String],win[kCGWindowOwnerPID as String],win[kCGWindowOwnerName as String],win[kCGWindowLayer as String],win[kCGWindowIsOnscreen as String] as? Bool ?? false)
            }
            for win in backupDesktops { print(win.isOpaque,win.isVisible,win.orderedIndex,win.level)}
            print("number of desktops: \(desktopWindows.count)")
*/
            var screenRect: [CGRect] = []
            let numOnScreen = desktopWindows.reduce(0) { numOnScreen, window in             // find the number of desktops onScreen and also construct array of unique screen CGRects
                let rect = CGRect(dictionaryRepresentation: window[kCGWindowBounds as String] as! CFDictionary)!
                if !screenRect.contains(rect) { screenRect.append(rect)}
                let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
                return numOnScreen + (onScreen ? 1 : 0)
            }
            let n = screenRect.count
            let good = n == NSScreen.screens.count || n == backupDesktops.count || n == backupDesktops.filter({$0.beingUsed}).count
            //print("numOnScreen=\(numOnScreen), screenRect.count=\(screenRect.count), backup.count=\(backupDesktops.filter({return $0.beingUsed}).count), screens.count=\(NSScreen.screens.count), good=\(good), nTry=\(nTry)")
            if (numOnScreen == screenRect.count && good) || nTry > 20 { return desktopWindows }
            usleep(150_000)
            nTry += 1   // FIX ME?
        } while true
    }
    
    func createDesktops() { //print("createDesktops, myDesktop.count=\(myDesktops.count)")     // make window for each desktop
        BGTimer?.invalidate()   // stop any timer
        let screens = NSScreen.screens; let h0 = NSHeight(screens[0].frame) // height of Screen that has menu bar
        myDesktops.forEach({ _, win in win.beingUsed = false; win.level = hiddenLayer; win.orderOut(nil) })  // assume window is not going to be used
        for desktopWindows in getDesktopArray() {   // loop over CGWindows that are Desktops...
            let rectCG = CGRect(dictionaryRepresentation: desktopWindows[kCGWindowBounds as String] as! CFDictionary)!
            let origin = CGPoint(x: rectCG.origin.x, y: h0 - rectCG.origin.y - rectCG.height)
            let rect = CGRect(origin: origin, size: rectCG.size)            // CGrect is in Screen coordinates
            let cgID = desktopWindows[kCGWindowNumber as String] as! CGWindowID
            //print("is cgID not in myDesktops? \(myDesktops[cgID]==nil)")
            if let win = myDesktops[cgID] {
                win.reset(contentRect: rect, hidden: hidden, level: hidden ? floatLayer : hiddenLayer)
            } else {
                myDesktops[cgID] = MyWindow(contentRect: rect, hidden: hidden, level: hidden ? floatLayer : hiddenLayer)
            }
            let onScreen = desktopWindows[kCGWindowIsOnscreen as String] as? Bool ?? false
            setImageView(cgWin: cgID, win: myDesktops[cgID]!, onScreen: onScreen, level: hidden ? (onScreen ? staticLayer : floatLayer) : hiddenLayer)
        }
        //print("number of myDesktops:\(myDesktops.count)")
        for cgID in myDesktops.filter({ return !$0.value.beingUsed}).keys {
            myDesktops[cgID]?.orderOut(nil)
            myDesktops[cgID]?.close()
            myDesktops.removeValue(forKey: cgID)
        }   // remove any myDesktops that are not being used
        //print("number of myDesktops:\(myDesktops.count)")
        
        createBackups()
        myDesktops.forEach({_, win in win.orderFrontRegardless()})

        doTimer()
        //print("number of myDesktops:\(myDesktops.count), screens:\(Set(myDesktops.map({$0.value.screen})).count)")
    }
    func createBackups() {
        backupDesktops.forEach({ win in win.beingUsed = false; win.orderOut(nil); win.level = hiddenLayer })
        var screenRect: [CGRect] = []
        for (_, win) in myDesktops {
            if !screenRect.contains(win.frame) {
                screenRect.append(win.frame)
                let idx = screenRect.count
                if idx > backupDesktops.count {
                    backupDesktops.append(MyWindow(contentRect: win.frame, hidden: hidden, level: hidden ? floatLayer : hiddenLayer))
                } else {
                    backupDesktops[idx-1].reset(contentRect: win.frame, hidden: hidden, level: hidden ? floatLayer : hiddenLayer)
                }
                backupDesktops[idx-1].color =  .black
                setImageView(cgWin: 0, win: backupDesktops[idx-1], onScreen: false, level: hidden ? floatLayer : hiddenLayer)
            }
        }
        //print("number of backupDesktops:\(backupDesktops.count), \(backupDesktops.filter({return $0.beingUsed}).count)")
    }
    // number of Desktops
    var numberOfDesktops: Int {
        get { return getDesktopArray().count }
    }
    // given a point on screen, return the Desktop image and color
    func desktopFromPoint(_ point : CGPoint, color : NSColor) -> (CGImage?, NSColor, Bool) {
        for screen in NSScreen.screens.filter({$0.frame.contains(point)}) {
            for cgID in getDesktopArray(.optionOnScreenOnly).map({ $0[kCGWindowNumber as String] as! CGWindowID}) {
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
                for cgID in getDesktopArray(.optionOnScreenOnly).map({ $0[kCGWindowNumber as String] as! CGWindowID}) {
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
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false, block: { _ in self.updateDesktops(true) })//; print("didWake")
            Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false, block: { _ in self.updateDesktops(true) })//; print("didWake")
        } else {
            BGTimer?.invalidate()//; print("didSleep")
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
        NCdefault.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: OperationQueue.current, using: {_ in //print("didChangeScreenParameters");
            self.BGTimer?.invalidate(); usleep(500_000); self.createDesktops()})
        NCdefault.addObserver(forName: .updateDesktop, object: nil, queue: OperationQueue.current, using: { _ in self.updateDesktops()})
        NCdefault.addObserver(forName: .updateAllDesktops, object: nil, queue: OperationQueue.current, using: { _ in self.updateDesktops(true)})
        NCdefault.addObserver(forName: .doHide, object: nil, queue: OperationQueue.current, using: {_ in self.doHide() })
        let WSsharedNC = NSWorkspace.shared.notificationCenter
        WSsharedNC.addObserver(self, selector: #selector(screensDidSleepWake(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        WSsharedNC.addObserver(self, selector: #selector(screensDidSleepWake(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        WSsharedNC.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: OperationQueue.current, using: { _ in //print("activeSpaceDidChange")
            self.BGTimer?.invalidate(); usleep(150_000);  self.updateDesktops(true)}) //ugh! FIXME apple
        
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
        NCdefault.removeObserver(self, name: .updateDesktop, object: nil)
        NCdefault.removeObserver(self, name: .updateAllDesktops, object: nil)
        NCdefault.removeObserver(self, name: .desktopType, object: nil)
        myDesktops.removeAll(); backupDesktops.removeAll() // and free up screen/window dictionary
    }
}
