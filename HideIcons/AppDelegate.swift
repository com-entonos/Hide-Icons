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
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    
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
        
        // date the app started + 1 second
        startDate = Date(timeIntervalSinceNow: TimeInterval(1.0))
        
        // assign image to menu item
        statusItem.button?.image = menuPicture
        
        // let's go hide icons
        toggle(nil)
        
        // this should capture in/out of Dark Mode
        if #available(OSX 10.14, *) {
            observation = NSApp.observe(\.effectiveAppearance) { (app, _) in
                if self.hider.hidden() {
                    print("effectiveAppearance change triggered")
                    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { _ in
                                            NotificationCenter.default.post(name: NSNotification.Name("spaceChange"), object: nil) })
                }
            }
        }
        
        // create some Services
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    // called from Services menu
    @objc func toggleService(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        if Date() > startDate { //hack to see if Service started the app, if so don't toggle since we are already hiding icons
            toggle(nil)
        }
    }
    
    // called when menu item should be hidden or shown
    @objc func menuPic(_ sender: Any?) {
        if menuHidden {
            statusItem.button?.image = menuPicture
        } else {
            statusItem.button?.image = menuNoPicture
        }
        menuHidden = !menuHidden
        constructMenu(hider.hidden())
    }
    
    // called when icons should hidden or shown
    @objc func toggle(_ sender: Any?) {
        constructMenu(!hider.hidden())
        NotificationCenter.default.post(name: NSNotification.Name("doHide"), object: nil)
    }
    
    // construct our menu item list of options
    func constructMenu(_ hidden : Bool) {
      let menu = NSMenu()

        // Show/Hide Desktop Icons
        if hidden {
            menu.addItem(NSMenuItem(title: "Show Desktop Icons", action: #selector(AppDelegate.toggle(_:)), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Hide Desktop Icons", action: #selector(AppDelegate.toggle(_:)), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        
        // Show/Hide menu item picture
        if menuHidden {
            menu.addItem(NSMenuItem(title: "Show Menu", action: #selector(AppDelegate.menuPic(_:)), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Hide Menu", action: #selector(AppDelegate.menuPic(_:)), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Say \"Hi\" to entonos", action: #selector(AppDelegate.donateClicked(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

      statusItem.menu = menu
    }

    // say "Hi"
    @objc func donateClicked(_ sender: Any?) {
        let url = URL(string: "https://entonos.com/index.php/the-geek-shop/")
        NSWorkspace.shared.open(url!)
    }
}

