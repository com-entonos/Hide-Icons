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
                myScreen = makeWindows()
                
                // get notified when ...
                NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.spaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil) // Space changes
                NotificationCenter.default.addObserver(self, selector: #selector(self.screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil) // Screens change
                NotificationCenter.default.addObserver(self, selector: #selector(self.spaceChange), name: .spaceChange, object: nil)  // user wants to toggle (via menu or shortcut)
            } else {
                for (_, wins) in myScreen {
                    for win in wins { win.orderBack(nil) }
                }
                spaceChange()
            }
            print("doHider:\(myScreen.count)")
            // get notified when Spaces or Screens change

            BGTimer = Timer.scheduledTimer(timeInterval: TimeInterval(60.0), target: self, selector: #selector(self.timedChange), userInfo: nil, repeats: true)  // this is a lazy capture if the desktop pictures vary w/ time
        } else {
            // stop timer
            BGTimer?.invalidate()
            for (_, wins) in myScreen {
                for win in wins { win.orderOut(nil) }
            }
        }
    }
    
    @objc func screenChanged() {  // call back for when the user reconfigured the Screen
        print("screenChanged called!")
        let newMyScreen = makeWindows()
        var oldMyScreen = myScreen
        myScreen = newMyScreen
        for (screen, wins) in oldMyScreen {
            for win in wins {
                win.orderOut(nil)
                win.windowController?.window = nil
                //win.close()
            }
            oldMyScreen.removeValue(forKey: screen)
        }
    }

    @objc func timedChange() {
        spaceChange()
/*
        print("timedChange")
        for screen in NSScreen.screens {
            let desktopPic = (NSWorkspace.shared.desktopImageURL(for: screen)?.lastPathComponent)!
            print("desktopPic:\(desktopPic)")
            for win in myScreen[screen]! {
                print("   windows, name:\(win.name), visible:\(win.showing), ID:\(win.cgID)")
            }
            if let win = myScreen[screen]?.filter({$0.showing}).first {
                if !win.name.hasSuffix(desktopPic) {
                    print("  window, name:\(win.name), visible:\(win.showing)")
                    spaceChange()
                }
            }
        }
 */
    }
    @objc func spaceChange() {
        let _ = makeWindows(.optionOnScreenOnly, currentScreens: myScreen)
    }
    
    func makeWindows(_ option: CGWindowListOption = .optionAll, currentScreens: [NSScreen: [MyWindow]]? = nil) -> [NSScreen:[MyWindow]] {  // for each desktop we find, take a picture add it onto an array and return it
        var myScreens = [NSScreen:[MyWindow]]()
        
        // need to find the Desktop window...
        //    go through all windows that are on screen
        for window in CGWindowListCopyWindowInfo(option, kCGNullWindowID) as! [[ String : Any]] {

            // we need window owned by Dock
            guard let owner = window["kCGWindowOwnerName"] as? String else {continue}
            if owner != "Dock" { continue }
            // we need window named like "Desktop Picture %"
            guard let name = window["kCGWindowName"] as? String else {continue}
            if !name.hasPrefix("Desktop Picture") { continue }
            // ok, this belongs to a screen. grab a picture of it and append to the return array
            let index = window["kCGWindowNumber"] as! CGWindowID
            
            // grab the screen's worth picture CGImag?
            guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, index, .nominalResolution) else { continue }  // don't do .infinity, freaks out early versions of macOS
            
            // so, owned by Dock and has name starting w/ "Desktop Picture"
            let imageView = NSImageView(image: NSImage(cgImage: cgImage, size: NSZeroSize))

            for screen in NSScreen.screens { // find which screen
                
                // find window for this screen
                let cWin = currentScreens?[screen]?.filter({$0.cgID == index}).first
                if cWin != nil {
                    print("found a window!")
                    cWin?.contentView?.removeFromSuperview()
                    cWin?.contentView = imageView // update image and image name
                    cWin?.name = name
                    cWin?.showing = false
                    if window["kCGWindowIsOnscreen"] as? Bool ?? false { // and show if onScreen
                        cWin?.showing = true
                        cWin?.orderFront(nil)
                        cWin?.collectionBehavior = .stationary
                        print("set to stationary")
                    }
                    if !hidden { cWin?.orderOut(nil) }
                } else {  // new window for this screen
                    print("need to create a window!")
                    let win = createWin(CGRect.init(dictionaryRepresentation: window["kCGWindowBounds"] as! CFDictionary)!)
                    win.contentView = imageView
                    win.cgID = index
                    win.name = name
                    win.showing = false
                    let onScreen = window["kCGWindowIsOnscreen"] as? Bool ?? false
                    if onScreen {
                        win.showing = true
                        win.orderFront(nil)
                        win.collectionBehavior = .stationary
                    }
                    if !hidden { win.orderOut(nil) }
                    if myScreens[screen] == nil {
                        myScreens[screen] = [win]
                    } else { myScreens[screen]!.append(win)}
                    if #available(macOS 10.15, *) {
                        print("screen:\(screen.localizedName), name:\(win.name), winID:\(win.cgID),rect:\(win.frame),onScreen:\(onScreen)")
                    } else {
                        print("screen:\(screen), name:\(win.name), winID:\(win.cgID),rect:\(win.frame),onScreen:\(onScreen)")
                    }
                }
            }
        }
        // return the array of windows w/ all Desktop picture(s)
        if myScreens.isEmpty {
            print("number of cscreens:\(currentScreens!.count), desktops:\(currentScreens!.mapValues({$0.count}))")
        } else {
            print("number of nscreens:\(myScreens.count), desktops:\(myScreens.mapValues({$0.count}))")
        }
        return myScreens
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
