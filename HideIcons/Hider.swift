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
    var onScreen: Bool = false
    var name: String = ""
    
}
class Hider {
    init() {  // get notified when user wants to toggle
        NotificationCenter.default.addObserver(self, selector: #selector(self.doHide), name: .doHide, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .doHide, object: nil)
    }
    
    
    var myWin = [MyWindow]()
    var myScreen = [NSScreen : MyWindow]()
    var BGTimer : Timer?
    
    func hidden() -> Bool {
        return myWin.count != 0
    }
    
    
    @objc func doHide() {
        if myWin.count == 0 {  // appears the user want to hide icons
            myWin = makeWindows()  // make windows for all of the Desktops
            myScreen = setScreens(myWin: myWin)
            // get notified when Spaces or Screens change
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.spaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.spaceChange), name: .spaceChange, object: nil)
            BGTimer = Timer.scheduledTimer(timeInterval: TimeInterval(60.0), target: self, selector: #selector(self.timedChange), userInfo: nil, repeats: true)  // this is a lazy capture if the desktop pictures vary w/ time
        } else {
            // stop notifications for Screen and Space chages and timer
            BGTimer?.invalidate()
            NotificationCenter.default.removeObserver(self, name: .spaceChange, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            // teardown
            myScreen.removeAll()
            for win in myWin {
                win.orderOut(nil)
                win.windowController?.window = nil
            }
            // we use the fact that transWindow.count = 0 keep track if the icons are hidden or not.
            myWin.removeAll()
        }
    }
    
    func setScreens( myWin: [MyWindow] ) -> [NSScreen: MyWindow] {
        var myScreen = [NSScreen: MyWindow]()
        for screen in NSScreen.screens {  // create the corresponding windows
            let picName = NSWorkspace.shared.desktopImageURL(for: screen)?.lastPathComponent ?? "no such url"
            print("desktop name:\(picName), \(myWin.filter( {$0.onScreen && $0.frame == screen.frame && $0.name.hasSuffix(picName) }).count)")
            if let win = myWin.filter( {$0.onScreen && $0.frame == screen.frame && $0.name.hasSuffix(picName) }).first {
                myScreen[screen] = win
            }
            
        }
        return myScreen
    }
    
    @objc func screenChanged() {  // call back for when the user reconfigured the Screen
        let newMyWin = makeWindows()
        myScreen = setScreens(myWin: newMyWin)
        myWin = newMyWin
    }

    @objc func timedChange() {
        for screen in NSScreen.screens {
            let picName = NSWorkspace.shared.desktopImageURL(for: screen)?.lastPathComponent ?? "no such url"
            if !myScreen[screen]!.name.hasSuffix(picName) || myScreen[screen]!.frame != screen.frame {
                spaceChange()
                break
            }
        }
    }

    @objc func spaceChange() {
        var newMyWin = makeWindows(.optionOnScreenOnly, currentWindow: myWin)
        if newMyWin.count > 0 {
            for screen in NSScreen.screens {  // create the corresponding windows
                let picName = NSWorkspace.shared.desktopImageURL(for: screen)?.lastPathComponent ?? "no such url"
                if let win = newMyWin.filter( {$0.frame == screen.frame && $0.name.hasSuffix(picName) }).first {
                    win.orderFront(nil)
                    win.collectionBehavior = .stationary
                    myWin.removeAll(where: {$0.cgID == win.cgID})
                    myWin.append(win)
                    myScreen[screen] = myWin.last!
                    newMyWin.removeAll(where: {$0 == win})
                }
            }
        }
    }
    
    func makeWindows(_ option: CGWindowListOption = .optionAll, currentWindow: [MyWindow]? = nil) -> [MyWindow] {  // for each desktop we find, take a picture add it onto an array and return it
        var myWin = [MyWindow]()
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
            
            if let cWin = currentWindow?.filter({ $0.cgID == index && $0.name == name }).first {
                if window["kCGWindowIsOnscreen"] as? Bool ?? false {
                    cWin.contentView = imageView
                    cWin.orderFront(nil)
                    cWin.collectionBehavior = .stationary
                    print("set to stationary")
                }
            } else {
                let win=createWin(CGRect.init(dictionaryRepresentation: window["kCGWindowBounds"] as! CFDictionary)!)
                win.contentView = imageView
                win.cgID = index
                win.name = name
                win.onScreen = window["kCGWindowIsOnscreen"] as? Bool ?? false
                if win.onScreen {
                    win.orderFront(nil)
                    win.collectionBehavior = .stationary
                }
                myWin.append(win)
                print("name:\(win.name), winID:\(win.cgID),rect:\(win.frame),onScreen:\(win.onScreen)")
            }
        }
        // return the array of windows w/ all Desktop picture(s)
        print("number of Desktop pictures:\(myWin.count) \(myWin.filter({$0.onScreen}).count)")
        return myWin
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
