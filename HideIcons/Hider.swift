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

class Hider {
    init() {  // get notified when user wants to toggle
        NotificationCenter.default.addObserver(self, selector: #selector(self.doHide), name: .doHide, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .doHide, object: nil)
    }
    
    var transWindow = [NSWindow]()  // our current Desktop pictures (empty means we're in the Show state)
    var BGTimer : Timer?
    
    func hidden() -> Bool {
        return transWindow.count != 0
    }
    
    @objc func doHide() {
        if transWindow.count == 0 {  // appears the user want to hide icons
            for screen in NSScreen.screens {  // create the corresponding windows
                transWindow.append(createWin(screen))
            }
            spaceChange() // and go display them
            // get notified when Spaces or Screens change
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.spaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.spaceChange), name: .spaceChange, object: nil)
            BGTimer = Timer.scheduledTimer(timeInterval: TimeInterval(60.0), target: self, selector: #selector(self.spaceChange), userInfo: nil, repeats: true)  // this is a lazy capture if the desktop pictures vary w/ time
        } else {
            // stop notifications for Screen and Space chages and timer
            BGTimer?.invalidate()
            NotificationCenter.default.removeObserver(self, name: .spaceChange, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            // teardown
            for (index, win) in transWindow.enumerated() {
                win.orderOut(self)
                transWindow[index].windowController?.window = nil
            }
            // we use the fact that transWindow.count = 0 keep track if the icons are hidden or not.
            transWindow.removeAll()
        }
    }
    
    @objc func screenChanged() {  // call back for when the user reconfigured the Screen
        let screens = NSScreen.screens
        if screens.count > transWindow.count {  // number of screens increase, so create some new windows
            for i in (transWindow.count)..<screens.count {
                transWindow.append(createWin(screens[i]))
            }
        }
        spaceChange()  // regardless of what happened, update the overlays just in case
    }
    
    func createWin(_ screen: NSScreen) -> NSWindow {
        let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: true, screen: screen)
        win.setFrame(screen.frame, display: false, animate: false)
        
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
    
    @objc func spaceChange() {
        var desktopPics = NSImage.desktopPictures()  // grab picture(s) of the Desktop(s)
        for (index, screen) in NSScreen.screens.enumerated() {  // cycle through the physical Screens
            for (numPic, desktopPic) in desktopPics.enumerated() {  // find the first desktop picture that has the same size as this screen
                if desktopPic.size == screen.frame.size {
                    // ok, replace the view
                    let imageView = NSImageView(image: desktopPic)
                    if screen.frame != transWindow[index].frame {transWindow[index].setFrame(screen.frame, display: false, animate: false)}
                    transWindow[index].contentView = imageView
                    // hopefully to avoid problems on which screen and which desktop, get rid of the ones we've done
                    desktopPics.remove(at: numPic)
                    break
                }
            }
        }
    }
}
extension NSImage { //don't need to do an extension, but it appears fun, so let's do it.
    
    static func desktopPictures() -> [NSImage] {  // for each desktop we find, take a picture add it onto an array and return it
        var images = [NSImage]()
        
        // need to find the Desktop window...
        //    go through all windows that are on screen
        //for window in CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[ String : Any]] {
        for window in CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[ String : Any]] {

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
            
            // TODO kCGWindowBounds is string of the coordinates of the rectangle, specified in screen space, where the origin is in the upper-left corner of the main display. way to tie to screen?
            //  print(owner,name,index,window["kCGWindowBounds"],window["kCGWindowIsOnscreen"])
            
            // so, owned by Dock and has name starting w/ "Desktop Picture"
            images.append(NSImage(cgImage: cgImage, size: NSZeroSize)) //ZeroSize means it will use image's size
        }
        // return the array of Desktop picture(s)
        return images
    }
}
