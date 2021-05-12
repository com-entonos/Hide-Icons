//
//  Hider.swift
//
//  Created by G.J. Parker on 21/04/02.
//  Copyright © 2021 G.J. Parker. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let doHide = NSNotification.Name("doHide")
    static let spaceChange = NSNotification.Name("spaceChange")
}

class Hider {  // class that covers desktop w/ pictures of desktop- invoked by notifications and/or timers
    
    init() {  // get notified when user wants to toggle
        NotificationCenter.default.addObserver(self, selector: #selector(self.doHide), name: .doHide, object: nil)
    }
    
    deinit {  // don't care
        NotificationCenter.default.removeObserver(self, name: .doHide, object: nil)
    }
    
    class MyWindow : NSWindow { // just add some data and methods for NSWindow- this will hold windows w/ Desktop pics
        var cgID: CGWindowID
        var showing: Bool
        func setWin(imageView: NSImageView, showing: Bool, hidden: Bool) {
            self.contentView = imageView
            self.showing = showing
            if showing {
                self.orderFront(nil)
                self.collectionBehavior = .stationary
            }
            if !hidden { self.orderOut(nil) }
        }
        init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool, index: CGWindowID) {
            self.cgID = index
            self.showing = false
            super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        }
    }
    
    var myScreen = [NSScreen : [MyWindow]]() // for each screen, a list of Desktop windows corresponding to number of Spaces
    var BGTimer : Timer?    // lazy update for Desktop pics
    var hidden_ = false
    
    var hidden: Bool {  // are icons currently hidden?
        get { return hidden_ }
        set (value) { hidden_ = value }
    }
    
    @objc func doHide() { // toggle hide/show icons
        hidden = !hidden
        if hidden {  // appears the user want to hide icons
            if myScreen.isEmpty { // make windows for all of the Desktops on each screen (done only at start)
                makeWindows()
                // get notified when ...
                NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.screenChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil) // Space changes
                NotificationCenter.default.addObserver(self, selector: #selector(self.timedChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil) // Screens change
                NotificationCenter.default.addObserver(self, selector: #selector(self.screenChanged), name: .spaceChange, object: nil)  // user wants to toggle (via menu or shortcut)
            } else { // not first time, just show windows and update
                for (_, wins) in myScreen {
                    for win in wins {
                        if win.collectionBehavior == .stationary { win.orderFront(nil) }
                        else { win.orderBack(nil) }
                    }
                }
                makeWindows()
            }
            BGTimer = Timer.scheduledTimer(timeInterval: TimeInterval(60.0), target: self, selector: #selector(self.timedChanged), userInfo: nil, repeats: true)  // this is a lazy capture if the desktop pictures vary w/ time
        } else {
            // stop timer
            BGTimer?.invalidate()
            for (_, wins) in myScreen {  // don't show any of the Desktop windows
                for win in wins { win.orderOut(nil) }
            }
        }
    }

    @objc func timedChanged() { // update everything (including stuff not visible)
        makeWindows()
    }
    @objc func screenChanged() {  // update only windows visible
        makeWindows(.optionOnScreenOnly)
    }
    
    @objc func makeWindows(_ option: CGWindowListOption = .optionAll){  // make window for each desktop = Screens * Spaces
        
        let h0 = NSHeight((NSScreen.screens.filter({$0.frame.origin == CGPoint.zero}).first?.frame)!) // height of Screen that has menu bar
        
        // need to find Desktop windows...
        for window in (CGWindowListCopyWindowInfo(option, kCGNullWindowID) as! [[ String : Any]]).reversed() {  //    go through all windows (according to options)

            // we need window owned by Dock
            guard let owner = window["kCGWindowOwnerName"] as? String else {continue}
            if owner != "Dock" { continue }
            // we need window named like "Desktop Picture"
            guard let name = window["kCGWindowName"] as? String else {continue}
            if !name.hasPrefix("Desktop Picture") { continue }
            
            // ok, this is a Desktop. grab the CGWindowID (invariant?)
            let index = window["kCGWindowNumber"] as! CGWindowID
            // grab the screen's worth picture CGImag?
            guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, index, .nominalResolution) else { continue }  // don't do .infinity, freaks out early versions of macOS
            let imageView = NSImageView(image: NSImage(cgImage: cgImage, size: NSZeroSize)) // create a view for it
            let showing = window["kCGWindowIsOnscreen"] as? Bool ?? false                   // is it in the active Space?
            let rectS = CGRect.init(dictionaryRepresentation: window["kCGWindowBounds"] as! CFDictionary)!  // get CGRect in CG coordinates (not Screen coordinates)
            let rect = CGRect(x: rectS.origin.x, y: h0 - rectS.origin.y - rectS.height, width: rectS.width, height: rectS.height) // translate from CG to Screen rect: y_screen = h0 - y_CG - CG_height
            
            //print("window:\(index) \"\(name)\" \(showing) \(rect)")
            for screen in NSScreen.screens { // loop over screens to find where these pictures go...
                // find window for this screen
                let cWin = myScreen[screen]?.filter({$0.cgID == index && $0.frame == screen.frame}).first
                if cWin != nil {  // window exists, just update image and settings
                    //print("  F>\"\(NSWorkspace.shared.desktopImageURL(for: screen)!.lastPathComponent)\" \(screen.frame) \(screen.frame == rect)")
                    cWin?.setWin(imageView: imageView, showing: showing, hidden: hidden)
                    break // found a screen, get out of screen loop
                } else if rect == screen.frame {  // new window for this screen
                    //print("  A>\"\(NSWorkspace.shared.desktopImageURL(for: screen)!.lastPathComponent)\" \(screen.frame) \(screen.frame == rect)")
                    let win = createWin(rect, index)
                    win.setWin(imageView: imageView, showing: showing, hidden: hidden)
                    if myScreen[screen] == nil {  myScreen[screen] = [win] } else { myScreen[screen]!.append(win) } //?
                    break // found a screen, get out of screen loop
                }
            }
        }
        //print("number of myScreen:\(myScreen.count), desktops:\(myScreen.mapValues({$0.count}))")
        return
    }
    
    func createWin(_ frame : CGRect,_ index: CGWindowID) -> MyWindow {
        let win = MyWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true, index: index)
        win.setFrame(frame, display: false, animate: false)
        win.collectionBehavior = .canJoinAllSpaces  // we want the window to follow Spaces around (until we find the correct space then we'll pin it on top)
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))  //hack? this makes mission control and expose ignore the window
        // rest is to make the window dumb
        win.canHide = false
        win.isExcludedFromWindowsMenu = true
        win.hidesOnDeactivate = false
        win.discardCursorRects()
        win.discardEvents(matching: .any, before: nil)
        win.ignoresMouseEvents = true
        win.orderBack(nil)  // critical we place on back
        win.isRestorable = false
        win.animationBehavior = .none
        return win
    }
}

