//
//  AppDelegate.swift
//  HideIcons
//
//  Created by parker on 4/25/21.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // create menu item on menu bar
    var statusItem: NSStatusItem? = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    
    // Hider class which hides/shows icons
    let hider = Hider()
    
    // menu picture or not
    let menuPicture = NSImage(named: "BBarButtonImage")
    let menuNoPicture = NSImage(named: "AlphaBarButtonImage")
    
    // to figure out if Services started the app
    var startDate: Date!
    
    // start out w/ menu item visible
    var menuHidden = false
    
    // Apple doc
    var observation: NSKeyValueObservation?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        // assign image to menu item
        statusItem?.button?.image = menuPicture
        
        // let's go hide icons
        toggle(nil)
        
        // this should capture in/out of Dark Mode
        if #available(OSX 10.14, *) {
            observation = NSApp.observe(\.effectiveAppearance) { (app, _) in
                if self.hider.hidden() {
                    print("effectiveAppearance change triggered")
                    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { _ in
                                            NotificationCenter.default.post(name: .spaceChange, object: nil) })
                }
            }
        }
        
        // date the app started + 1 second
        startDate = Date(timeIntervalSinceNow: TimeInterval(1.0))
        
        // create some Services
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if statusItem == nil || menuHidden {
            print("turning on menu")
            if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength) }
            menuHidden = true
            menuPic(nil)
        }
        return false
    }
    
    // called from Services menu
    @objc func toggleService(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
       // if Date() > startDate { //hack to see if Service started the app, if so don't toggle since we are already hiding icons
            toggle(nil)
       // } else {
       //     statusItem = nil
       // }
    }
    
    // called when menu item should be hidden or shown
    @objc func menuPic(_ sender: Any?) {
        if menuHidden {
            statusItem?.button?.image = menuPicture
        } else {
            statusItem?.button?.image = menuNoPicture
        }
        menuHidden = !menuHidden
        constructMenu(hider.hidden())
    }
    
    // called when icons should hidden or shown
    @objc func toggle(_ sender: Any?) {
        constructMenu(!hider.hidden())
        NotificationCenter.default.post(name: .doHide, object: nil)
    }
    
    // construct our menu item list of options
    func constructMenu(_ hidden : Bool) {
        if let sItem = statusItem {
            let menu = NSMenu()

            // Show/Hide Desktop Icons
            var str = hidden ? "Show Desktop Icons" : "Hide Desktop Icons"
            menu.addItem(NSMenuItem(title: str, action: #selector(self.toggle(_:)), keyEquivalent: ""))
 
            menu.addItem(NSMenuItem.separator())
            
            // menu > submenu of Show/Hide or Remove remove
            let subMenu = NSMenu()
            
            let menuItem = NSMenuItem()
            menuItem.title = "Change menu"
            menu.addItem(menuItem)
            str = menuHidden ? "Show menu" : "Hide menu"
            subMenu.addItem(NSMenuItem(title: str, action: #selector(self.menuPic(_:)), keyEquivalent: ""))
            subMenu.addItem(NSMenuItem(title: "Remove menu", action: #selector(self.removeMenu(_:)), keyEquivalent: ""))
            menu.setSubmenu(subMenu, for: menuItem)
            
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Say \"Hi\" to entonos", action: #selector(AppDelegate.donateClicked(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

            sItem.menu = menu
        }
      
    }
    
    @objc func removeMenu(_ sender: Any?) {
        statusItem = nil
    }

    // say "Hi"
    @objc func donateClicked(_ sender: Any?) {
        let url = URL(string: "https://entonos.com/index.php/the-geek-shop/")
        NSWorkspace.shared.open(url!)
    }
}

