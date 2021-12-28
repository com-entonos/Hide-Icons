//
//  Hider.swift
//
//  Created by G.J. Parker on 21/04/02.
//  Copyright © 2021 G.J. Parker. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let doHide = NSNotification.Name("doHide")
    static let refreshDesktop = NSNotification.Name("refreshDesktop")
    static let updateDesktop = NSNotification.Name("updateDesktop")
    static let timeBG = NSNotification.Name("timeBG")
}

class Hider {  // class that covers desktop w/ pictures of desktop- invoked by notifications and/or timers
    
    class MyWindow : NSWindow { // just add some data and methods for NSWindow- this will hold a window w/ a Desktop pic
        var cgID: CGWindowID  // CG window ID of a Desktop
        
        init(contentRect: NSRect, cgID: CGWindowID) {
            self.cgID = cgID
            super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false) // create NSWindow
            
            self.setFrame(contentRect, display: true, animate: false)  // is this necessary?
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
        
        func setWin(imageView: NSImageView, showing: Bool, hidden: Bool) { // update picture and pin if we found the correct Space
            self.contentView = imageView
            //print(self.cgID,showing,hidden,self.collectionBehavior == .stationary)
            if showing { // if this is currently showing, bring to front and pin it to this Space
                self.orderFront(nil)
                self.collectionBehavior = .stationary
                self.animationBehavior = .none
            }
            if !hidden { self.orderOut(nil) }  // showing desktop, don't show this window at all
        }
    }
    
    //var dbWin : [ NSScreen : NSWindow] = [:]
    //var dbSpace : [ CGWindowID : NSWindow] = [:]
    
    var myScreen: [NSScreen : [MyWindow]] = [:] // for each screen, a list of Desktop windows corresponding to number of Spaces for that screen
    var BGTimer : Timer?    // lazy update for Desktop pics
    var BGTime = TimeInterval(730000.0)
    var hidden_ = false     // are icons hidden?
    var deskCFArray : CFArray?
    var cgIDCFArray: [ CGWindowID : CFArray ] = [:]
    
    var hidden: Bool {  // are icons currently hidden?
        get { return hidden_ }
        set (value) { hidden_ = value }
    }
    
    @objc func doHide(_ notifier : Notification) { //print("in doHide \(!hidden) \(myScreen.isEmpty) \(notifier)")
        hidden = !hidden    // toggle hide/show icons
        if hidden {         // appears the user want to hide icons
            for (_, wins) in myScreen {
                for win in wins { //print("  windows: \(win.frame) \(win.cgID) \(win.collectionBehavior)")
                    if win.collectionBehavior == .stationary { win.orderFront(nil) }
                    else { win.orderBack(nil) }
                }
            }
            updateWindows(nil)
            doTimer()
        } else {
            // stop timer
            BGTimer?.invalidate()
            for (_, wins) in myScreen {  // don't show any of the Desktop windows
                for win in wins { win.orderOut(nil) }
            }
        }
    }
    
    func doTimer() { //print("in doTimer \(BGTime)")
        BGTimer?.invalidate()
        if BGTime < 720000.0 { //print("  starting timer...")
            BGTimer = Timer.scheduledTimer(withTimeInterval: BGTime, repeats: true, block: { _ in self.updateWindows(nil)})
        }
    }
    
    @objc func timerChanged(_ notifier : Notification) { //print("in timerChanged, \(notifier.object as! TimeInterval)")
        if let time = notifier.object as? TimeInterval {
            BGTime = time
            if hidden { doTimer() }
            else { BGTimer?.invalidate() }
        }
    }

    @objc func updateWindows(_ notifier : Any?) {
        if (notifier as? Notification)?.name == NSWorkspace.activeSpaceDidChangeNotification {usleep(100_000)} //ugh! FIXME apple
        let h0 = NSHeight((NSScreen.screens.filter({$0.frame.origin == CGPoint.zero}).first?.frame)!) // height of Screen that has menu bar
        let awakeScreen = whichScreensAreAwake(h0)  // dictionary [NSScreen : Bool] of not isAsleep
        if awakeScreen.allSatisfy({!$0.value}) { return } // are all screens sleeping? if so, just get out now
        
        BGTimer?.invalidate()
        for screen in NSScreen.screens {
            if awakeScreen[screen] ?? false {
                for window in myScreen[screen]! {  // for each Space for this screen, loop through windows
                    let cgID = window.cgID
                    if let winCG = (CGWindowListCreateDescriptionFromArray(cgIDCFArray[cgID]) as! [[ String : AnyObject]]).last { // get CG window
                        let showing = winCG[kCGWindowIsOnscreen as String] as? Bool ?? false
                        if showing { // only update image if we're showing
                            guard let cgImage = CGWindowListCreateImage(.null, [.optionIncludingWindow], cgID, [.nominalResolution]) else { continue }
                            //print("  U>\(screen.frame) \(window.cgID) \(window.collectionBehavior == .stationary) \(cgImage)")
                            let image = NSImage(cgImage: cgImage, size: NSZeroSize)
                            let imageView = NSImageView(image: image)
                            window.setWin(imageView: imageView, showing: showing, hidden: hidden)
                            //dbWin[screen]!.contentView = NSImageView(image: image)
                            //dbSpace[cgID]?.contentView = NSImageView(image: image)
                        }
                    }
                }
            }
        }
        doTimer()
        //print("number of myScreen:\(myScreen.count), desktops:\(myScreen.mapValues({$0.count}))")
    }
    
    @objc func createWindows(_ notifier : Any?) {  // make window for each desktop
        let h0 = NSHeight((NSScreen.screens.filter({$0.frame.origin == CGPoint.zero}).first?.frame)!) // height of Screen that has menu bar
        let awakeScreen = whichScreensAreAwake(h0)  // dictionary [NSScreen : Bool] of not isAsleep
        if awakeScreen.allSatisfy({!$0.value}) { return } // are all screens sleeping? if so, just get out now
        
        BGTimer?.invalidate()
        
        // need to find Desktop windows...
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)! as! [[String: AnyObject]]
        let desktopWindowLevel = CGWindowLevelForKey(.desktopWindow) - 1
        let desktopWindows = windows.filter {
            let windowLevel = $0[kCGWindowLayer as String] as! CGWindowLevel
            return windowLevel == desktopWindowLevel
        }
        let desktopCGID = desktopWindows.map { $0[kCGWindowNumber as String] as! CGWindowID}
        
        // now create a CFArray with all the CGWindowID that are Desktop pictures
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: desktopCGID.count)
        for (index, win) in desktopCGID.reversed().enumerated() {
            pointer[index] = UnsafeRawPointer(bitPattern: UInt(win))
        }
        deskCFArray = CFArrayCreate(kCFAllocatorDefault, pointer, desktopCGID.count, nil)  // there it is.
        
        // now create CFArray w/ one element for each of the CGWindowID that are Desktop picturess
        for cgID in desktopCGID {
            let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
            pointer[0] = UnsafeRawPointer(bitPattern: UInt(cgID))
            cgIDCFArray[cgID] = CFArrayCreate(kCFAllocatorDefault, pointer, 1, nil)       // there it is, store it as value in dictionary
        }
        
        for screen in myScreen.values { for win in screen { win.orderOut(nil) } }
        myScreen = [:]
        
        
        for screen in NSScreen.screens { // need to create a list of windows for this screen to accomodate the number of Spaces it has
            //var xoff : CGFloat = 0
            for window in CGWindowListCreateDescriptionFromArray(deskCFArray) as! [[ String : AnyObject]] {  // get all of the Desktop windows
                let rectCG = CGRect(dictionaryRepresentation: window[kCGWindowBounds as String] as! CFDictionary)!  // get CGRect in CG coordinates (not Screen coordinates)
                let origin = CGPoint(x: rectCG.origin.x, y: h0 - rectCG.origin.y - rectCG.height) // translate from CG to Screen origin: y_screen = h0 - y_CG - CG_height
                let rect = CGRect(origin: origin, size: rectCG.size)
                if screen.frame == rect {  // this Desktop window has the same frame as the screen, it must be one of the Spaces
                    let cgID = window[kCGWindowNumber as String] as! CGWindowID
                    let win = MyWindow(contentRect: rect, cgID: cgID)  // create a window for this Desktop picture
                    //guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, cgID, .nominalResolution) else { continue }
                    guard let cgImage = CGWindowListCreateImage(.null, [.optionIncludingWindow], cgID, [.nominalResolution]) else { continue }
                    
                    let image = NSImage(cgImage: cgImage, size: NSZeroSize)
                    let imageView = NSImageView(image: image)
                    win.setWin(imageView: imageView, showing: false, hidden: hidden)
                    
                    if myScreen[screen] == nil { myScreen[screen] = [win] } else { myScreen[screen]!.append(win) }
                    //print("  A>\(screen.frame) \(win.cgID) \(win.collectionBehavior == .stationary)")
                    
                    /*
                    if dbWin[screen] == nil && window[kCGWindowIsOnscreen as String] as? Bool ?? false {
                        let rs = screen.frame
                        let rect = CGRect(origin: rs.origin, size: CGSize(width: rs.width/2, height: rs.height/2))
                        dbWin[screen] = NSWindow(contentRect: rect, styleMask: [.miniaturizable, .closable, .resizable, .titled], backing: .buffered, defer: false)
                        dbWin[screen]?.title = "preview \(screen.frame.origin.y)"
                        //dbWin[screen]?.makeKeyAndOrderFront(nil)
                        dbWin[screen]?.orderFront(nil)
                        dbWin[screen]?.collectionBehavior = .canJoinAllSpaces
                        print(dbWin[screen]?.frame,rect,rs,dbWin[screen]?.canBecomeKey,dbWin[screen]?.canBecomeMain)
                    }
                    let rt = CGRect(x: xoff, y: rect.origin.y, width: rect.width / 6, height: rect.height / 6)
                    xoff = xoff + rect.width / 6
                    dbSpace[cgID] = NSWindow(contentRect: rt, styleMask: [.miniaturizable, .closable, .resizable, .titled], backing: .buffered, defer: false)
                    dbSpace[cgID]?.title = "\(cgID)"
                    dbSpace[cgID]?.orderFront(nil)
                    dbSpace[cgID]?.collectionBehavior = .canJoinAllSpaces
                    dbSpace[cgID]?.contentView = NSImageView(image: image)
                    print(cgID,dbSpace[cgID]!.frame,xoff)
                     */
                }
            }
        }
        updateWindows(nil)
    }
    
    func whichScreensAreAwake(_ h0: CGFloat) -> [ NSScreen : Bool] {  // return dictionary of [NSScreen : Bool] if not isAsleep
        var displayCount : UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount) // find the number of displays according to Core Graphics
        
        let maxDisplay : UInt32 = displayCount
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(maxDisplay, &onlineDisplays, &displayCount) // get a list of displays from Core Graphics

        var screenAwake = [NSScreen : Bool]() // dictionary to tell if NSScreen is awake
        for screen in NSScreen.screens {      // loop through NSScreen
            let oFrame = screen.frame
            let screenFrame = CGRect(origin: CGPoint(x: oFrame.origin.x, y: h0 - oFrame.origin.y - oFrame.height), size: oFrame.size) // shift NSScreen.frame CGRect to CG coordinates
            if let displayIndex = onlineDisplays.firstIndex(where: {CGDisplayBounds($0) == screenFrame}) {
                screenAwake[screen] = CGDisplayIsAsleep(onlineDisplays[displayIndex]) == 0 // is it not isAsleep?
            } else { screenAwake[screen] = true } // this screen wasn't found in CG- shouldn't happen.
        }
        //print("screenAwake = \(screenAwake.values)")
        return screenAwake
    }
    
    init() {  // set up observers and initial window lists for each screen
        NotificationCenter.default.addObserver(self, selector: #selector(self.doHide(_:)), name: .doHide, object: nil) // catch toggle
        NotificationCenter.default.addObserver(self, selector: #selector(self.timerChanged(_:)), name: .timeBG, object: nil) // catch background timer interval
        hidden = true
        createWindows(nil) // go grab all the Desktops
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.updateWindows(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil) // Space changes
        NotificationCenter.default.addObserver(self, selector: #selector(self.createWindows(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil) // Screens change
        NotificationCenter.default.addObserver(self, selector: #selector(self.createWindows(_:)), name: .refreshDesktop, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.updateWindows(_:)), name: .updateDesktop, object: nil)
    }
    
    deinit {  // tear down observers (is this really necessary?)
        NotificationCenter.default.removeObserver(self, name: .doHide, object: nil)
        NotificationCenter.default.removeObserver(self, name: .timeBG, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .refreshDesktop, object: nil)
        NotificationCenter.default.removeObserver(self, name: .updateDesktop, object: nil)
        BGTimer?.invalidate() // invalidate any background timers
        myScreen = [:] // and free up screen/window dictionary
    }
}

