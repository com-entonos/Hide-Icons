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
    static let timeBG = NSNotification.Name("timeBG")
}

class Hider {  // class that covers desktop w/ pictures of desktop- invoked by notifications and/or timers
    
    init() {  // set up observers and initial window lists for each screen
        NotificationCenter.default.addObserver(self, selector: #selector(self.doHide(_:)), name: .doHide, object: nil) // catch toggle
        NotificationCenter.default.addObserver(self, selector: #selector(self.timerChanged(_:)), name: .timeBG, object: nil) // catch background timer interval
        makeWindows() // go grab all the Desktops
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.screenChanged(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil) // Space changes
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshAll(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil) // Screens change
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshAll(_:)), name: .refreshDesktop, object: nil)
    }
    
    deinit {  // tear down observers (is this really necessary?)
        NotificationCenter.default.removeObserver(self, name: .doHide, object: nil)
        NotificationCenter.default.removeObserver(self, name: .timeBG, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .refreshDesktop, object: nil)
    }
    
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
            if showing { // if this is currently showing, bring to front and pin it to this Space
                self.orderFront(nil)
                self.collectionBehavior = .stationary
                self.animationBehavior = .none
            }
            if !hidden { self.orderOut(nil) }  // showing desktop, don't show this window at all
        }
    }
    
    var myScreen = [NSScreen : [MyWindow]]() // for each screen, a list of Desktop windows corresponding to number of Spaces for that screen
    var BGTimer : Timer?    // lazy update for Desktop pics
    var BGTime = TimeInterval(730000.0)
    var hidden_ = false     // are icons hidden?
    
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
            makeWindows()
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
            BGTimer = Timer.scheduledTimer(withTimeInterval: BGTime, repeats: true, block: { _ in self.refreshAll(nil)})
        }
    }
    
    @objc func timerChanged(_ notifier : Notification) { //print("in timerChanged, \(notifier.object as! TimeInterval)")
        if let time = notifier.object as? TimeInterval {
            BGTime = time
            if hidden { doTimer() }
            else { BGTimer?.invalidate() }
        }
    }

    @objc func refreshAll(_ notifier : Any?) { // update everything (including stuff not visible)
        makeWindows()
    }
    @objc func screenChanged(_ notifier : Any?) {  // update only windows visible
        makeWindows(.optionOnScreenOnly)
    }
    
    func makeWindows(_ option: CGWindowListOption = .optionAll){  // make window for each desktop

        let h0 = NSHeight((NSScreen.screens.filter({$0.frame.origin == CGPoint.zero}).first?.frame)!) // height of Screen that has menu bar
        
        let awakeScreen = whichScreensAreAwake(h0)  // dictionary [NSScreen : Bool] of not isAsleep
        if awakeScreen.allSatisfy({!$0.value}) { return } // are all screens sleeping? if so, just get out now
        
        //print("in makeWindows \(option) \(h0) \(awakeScreen)")

        // need to find Desktop windows...
        for window in (CGWindowListCopyWindowInfo(option, kCGNullWindowID) as! [[ String : Any]]).reversed() {  //    go through all windows (according to options)

            // we need window owned by Dock
            guard let owner = window["kCGWindowOwnerName"] as? String else {continue}
            if owner != "Dock" { continue }
            // we need window named like "Desktop Picture"
            guard let name = window["kCGWindowName"] as? String else {continue}
            if !name.hasPrefix("Desktop Picture ") { continue }
            
            // ok, this is a Desktop. grab the CGWindowID (invariant?)
            let cgID = window["kCGWindowNumber"] as! CGWindowID
            // grab the screen's worth picture CGImag?
            guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, cgID, .nominalResolution) else { continue }  // don't do .infinity, freaks out early versions of macOS
            let imageView = NSImageView(image: NSImage(cgImage: cgImage, size: NSZeroSize)) // create a view for it
            let showing = window["kCGWindowIsOnscreen"] as? Bool ?? false                   // is it in the active Space?
            let rectS = CGRect.init(dictionaryRepresentation: window["kCGWindowBounds"] as! CFDictionary)!  // get CGRect in CG coordinates (not Screen coordinates)
            let rect = CGRect(x: rectS.origin.x, y: h0 - rectS.origin.y - rectS.height, width: rectS.width, height: rectS.height) // translate from CG to Screen rect: y_screen = h0 - y_CG - CG_height
            
            //print("window:\(cgID) \"\(name)\" \(showing) \(rect) \(option)")
            for screen in NSScreen.screens { // loop over screens to find where these pictures go...
                if awakeScreen[screen] ?? false {  // for screens not IsAsleep
                    // find window for this screen
                    if let cWin = myScreen[screen]?.filter({$0.cgID == cgID && $0.frame == screen.frame}).last {
                        cWin.setWin(imageView: imageView, showing: showing, hidden: hidden)
                        //print("  F>\(screen.frame) \(cWin.cgID) \(showing) \(cWin.collectionBehavior)")
                        break // found a screen, get out of screen loop
                    } else if rect == screen.frame {  // new window for this screen
                        let win = MyWindow(contentRect: rect, cgID: cgID)
                        win.setWin(imageView: imageView, showing: showing, hidden: hidden)
                        if myScreen[screen] == nil {  myScreen[screen] = [win] } else { myScreen[screen]!.append(win) } //?
                        //print("  A>\(screen.frame) \(cgID) \(showing) \(win.collectionBehavior)")
                        break // found a screen, get out of screen loop
                    }
                }
            }
        }
        //print("number of myScreen:\(myScreen.count), desktops:\(myScreen.mapValues({$0.count}))")
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
        //print("screenAwake = \(screenAwake)")
        return screenAwake
    }
}

