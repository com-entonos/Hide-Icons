//
//  Hider.swift
//  DIM
//
//  Created by G.J. Parker on 19/11/4.
//  Copyright © 2021 G.J. Parker. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let doHide = NSNotification.Name("doHide")
    static let spaceChange = NSNotification.Name("spaceChange")
}

class MyWindow : NSWindow {
    var cgID: CGWindowID = 0
    var name: String = ""
    var showing: Bool = false
    func setWin(imageView: NSImageView, name: String, showing: Bool, hidden: Bool) {
        self.contentView = imageView
        self.name = name
        self.showing = true
        if showing {
            self.orderFront(nil)
            self.collectionBehavior = .stationary
        }
        if !hidden { self.orderOut(nil) }
    }
}

class Hider {
    init() {  // get notified when user wants to toggle
        NotificationCenter.default.addObserver(self, selector: #selector(self.doHide), name: .doHide, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .doHide, object: nil)
    }
    
    var myScreen = [NSScreen : [MyWindow]]() // for each screen, a list of Desktop windows
    var BGTimer : Timer?    // lazy update for Desktop pics
    var hidden_ = false
    
    var hidden: Bool {
        get { return hidden_ }
        set (value) { hidden_ = value }
    }
    
    @objc func doHide() {
        hidden = !hidden
        if hidden {  // appears the user want to hide icons
            if myScreen.isEmpty { // make windows for all of the Desktops on each screen
                makeWindows()
                
                // get notified when ...
                NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.spaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil) // Space changes
                NotificationCenter.default.addObserver(self, selector: #selector(self.spaceChange), name: NSApplication.didChangeScreenParametersNotification, object: nil) // Screens change
                NotificationCenter.default.addObserver(self, selector: #selector(self.spaceChange), name: .spaceChange, object: nil)  // user wants to toggle (via menu or shortcut)
            } else { // not first time, just show windows and update
                for (_, wins) in myScreen {
                    for win in wins { win.orderBack(nil) }
                }
                spaceChange()
            }
            print("doHider:\(myScreen.count)")

            BGTimer = Timer.scheduledTimer(timeInterval: TimeInterval(60.0), target: self, selector: #selector(self.spaceChange), userInfo: nil, repeats: true)  // this is a lazy capture if the desktop pictures vary w/ time
        } else {
            // stop timer
            BGTimer?.invalidate()
            for (_, wins) in myScreen {
                for win in wins { win.orderOut(nil) }
            }
        }
    }
    
    @objc func spaceChange() {
        makeWindows()
    }
    
    func makeWindows(_ option: CGWindowListOption = .optionAll){  // for each desktop we find, take a picture add it onto an array and return it
        
        // need to find the Desktop window...
        //    go through all windows that are on screen
        for window in CGWindowListCopyWindowInfo(option, kCGNullWindowID) as! [[ String : Any]] {

            // we need window owned by Dock
            guard let owner = window["kCGWindowOwnerName"] as? String else {continue}
            if owner != "Dock" { continue }
            // we need window named like "Desktop Picture %"
            guard let name = window["kCGWindowName"] as? String else {continue}
            if !name.hasPrefix("Desktop Picture") { continue }
            // ok, this belongs to a screen. grab the CGWindowID (invariant)
            let index = window["kCGWindowNumber"] as! CGWindowID
            
            // grab the screen's worth picture CGImag?
            guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, index, .nominalResolution) else { continue }  // don't do .infinity, freaks out early versions of macOS
            
            // so, owned by Dock and has name starting w/ "Desktop Picture"
            let imageView = NSImageView(image: NSImage(cgImage: cgImage, size: NSZeroSize))
            let showing = window["kCGWindowIsOnscreen"] as? Bool ?? false // is it in the active Space?
            
            for screen in NSScreen.screens { // loop over screens
                
                // find window for this screen
                let cWin = myScreen[screen]?.filter({$0.cgID == index}).first
                if cWin != nil {
                    print("found a window!")
                    cWin?.setWin(imageView: imageView, name: name, showing: showing, hidden: hidden)
                } else {  // new window for this screen
                    print("need to create a window!")
                    let win = createWin(CGRect.init(dictionaryRepresentation: window["kCGWindowBounds"] as! CFDictionary)!)
                    win.cgID = index
                    win.setWin(imageView: imageView, name: name, showing: showing, hidden: hidden)
                    if myScreen[screen] == nil {  myScreen[screen] = [win] } else { myScreen[screen]!.append(win) }
                    if #available(macOS 10.15, *) {
                        print("screen:\(screen.localizedName), name:\(win.name), winID:\(win.cgID),rect:\(win.frame),onScreen:\(win.showing)")
                    } else {
                        print("screen:\(screen), name:\(win.name), winID:\(win.cgID),rect:\(win.frame),onScreen:\(win.showing)")
                    }
                }
            }
        }
        // return the array of windows w/ all Desktop picture(s)
        print("number of nscreens:\(myScreen.count), desktops:\(myScreen.mapValues({$0.count}))")
        return
    }
    
    func createWin(_ frame : CGRect) -> MyWindow {
        let win = MyWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        win.setFrame(frame, display: false, animate: false)
        win.collectionBehavior = .canJoinAllSpaces  // we want the window to follow Spaces around
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))  //hack? this makes mission control and expose ignore the window
        // rest is to make the window dumb
        win.canHide = false
        win.isExcludedFromWindowsMenu = true
        win.hidesOnDeactivate = false
        win.discardCursorRects()
        win.discardEvents(matching: .any, before: nil)
        win.ignoresMouseEvents = true
        win.orderBack(nil)
        win.isRestorable = false
        win.animationBehavior = .none
        return win
    }
}
