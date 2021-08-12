//
//  AppDelegate.swift
//  HideIcons
//
//  Created by parker on 4/25/21.
//

import Cocoa

//@NSApplicationMain // for older versions of xcode
@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // create status bar item on menu bar
    var statusBarItem: NSStatusItem?
    
    // Hider class which hides/shows icons
    let hider = Hider()
    
    // menu picture or not
    let sbiPicture = NSImage(named: "BBarButtonImage")
    let sbiNoPicture = NSImage(named: "AlphaBarButtonImage")
    
    // to figure out if Services started the app
    var startDate: Date!
    
    // start out w/ menu item visible
    var sbiHidden = false
    
    // show menu on left click?
    var defaultClick = true
    
    // Apple doc
    var observation: NSKeyValueObservation?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        defaultClick = ( UserDefaults.standard.object(forKey: "defaultClick") == nil) ? true : UserDefaults.standard.bool(forKey: "defaultClick")
        sbiHidden = ( UserDefaults.standard.object(forKey: "sbiHidden") == nil) ? false : UserDefaults.standard.bool(forKey: "sbiHidden")
        let removeMenu = ( UserDefaults.standard.object(forKey: "removeMenu") == nil) ? false : UserDefaults.standard.bool(forKey: "removeMenu")
        
        // assign image to menu item
        if removeMenu { statusBarItem = nil } else {
            statusBarItem = setStatusBarItem(image: sbiHidden ? sbiNoPicture : sbiPicture)
        }
        
        // let's go hide icons
        
        // this should capture in/out of Dark Mode
        if #available(OSX 10.14, *) {
            observation = NSApp.observe(\.effectiveAppearance) { (app, _) in
                if self.hider.hidden { // give 3 second delay to make sure the Desktop did in fact update
                    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { _ in
                                            NotificationCenter.default.post(name: .spaceChange, object: nil) })
                }
            }
        }
        
        // let's go hide icons (in 1 second so we get out of this function so later versions of macOS are happy
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false, block: { _ in self.toggle(nil)})
        
        // create some Services
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        
        // date the app started + 2 second
        startDate = Date(timeIntervalSinceNow: TimeInterval(2.0))
        
    }

    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        let rightClick = NSApp.currentEvent!.isRightClick
        print("rightClick: \(rightClick)   defaultClick: \(defaultClick)")
        if rightClick == defaultClick {
            print("toggle!")
            toggle(nil)
        } else {
            print("show menu!")
            statusBarItem!.menu = constructMenu(hider.hidden)
            statusBarItem!.button!.performClick(nil)
        }
    }
    
    @objc func menuDidClose(_ menu: NSMenu) {
        statusBarItem?.menu = nil
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if statusBarItem == nil || sbiHidden {
            if statusBarItem == nil { statusBarItem = setStatusBarItem(image: sbiPicture) }
            sbiHidden = false
        }
        return false
    }
    
    // called from Services menu
    @objc func toggleService(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        if Date() > startDate { //hack to see if Service started the app, if so don't toggle since we are already hiding icons
            toggle(nil)
        } else {
            statusBarItem = nil // Services did start the app; just turn off menu
        }
    }
    
    // construct status bar item
    func setStatusBarItem(image: NSImage? ) -> NSStatusItem? {
        let sBI = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        sBI.button?.image = image
        sBI.button?.action = #selector(self.statusBarButtonClicked(sender:))
        sBI.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        return sBI
    }
    
    // construct our menu item list of options
    func constructMenu(_ hidden : Bool) -> NSMenu? {
        if statusBarItem == nil { return nil } //never happens?
        
        let menu = NSMenu()
        menu.delegate = self

        // Show/Hide Desktop Icons
        var str = hidden ? "Show Desktop Icons" : "Hide Desktop Icons"
        menu.addItem(NSMenuItem(title: str, action: #selector(self.toggle(_:)), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())

        // response to right/left click
        let menuClick = NSMenuItem(title: "Right-click to show menu", action: #selector(self.rightClicked(_:)), keyEquivalent: "")
        menuClick.state = defaultClick ? NSControl.StateValue.off : NSControl.StateValue.on
        menu.addItem(menuClick)
        
        // menu > submenu of Show/Hide or Remove remove
        let subMenu = NSMenu()
        
        let menuItem = NSMenuItem() // Change menu > Hid/Show or Remove menu
        menuItem.title = "Change menu"
        menu.addItem(menuItem)
        str = sbiHidden ? "Show menu" : "Hide menu"
        subMenu.addItem(NSMenuItem(title: str, action: #selector(self.sbiPic(_:)), keyEquivalent: ""))
        subMenu.addItem(NSMenuItem(title: "Remove menu", action: #selector(self.removeMenu(_:)), keyEquivalent: ""))
        menu.setSubmenu(subMenu, for: menuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Help", action: #selector(AppDelegate.getHelp(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About", action: #selector(AppDelegate.about(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Say \"Hi\" to entonos", action: #selector(AppDelegate.donateClicked(_:)), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        return menu
      
    }
    // called when icons should hidden or shown
    @objc func toggle(_ sender: Any?) {
        NotificationCenter.default.post(name: .doHide, object: nil)
    }
    // called when menu item should be hidden or shown
    @objc func sbiPic(_ sender: Any?) {
        statusBarItem?.button?.image = sbiHidden ? sbiPicture : sbiNoPicture
        sbiHidden = !sbiHidden
        UserDefaults.standard.set(sbiHidden, forKey: "sbiHidden")
        UserDefaults.standard.set(false, forKey: "removeMenu")
    }
    // called when switching left & right clicks
    @objc func rightClicked(_ sender: Any?) {
        defaultClick = !defaultClick
        UserDefaults.standard.set(defaultClick, forKey: "defaultClick")
    }
    
    @objc func getHelp(_ sender: Any?) {
        if let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? NSHelpManager.BookName {
            NSHelpManager.shared.openHelpAnchor("Welcome", inBook: book)
        }
    }
    
    @objc func removeMenu(_ sender: Any?) {
        statusBarItem = nil
        UserDefaults.standard.set(true, forKey: "removeMenu")
    }

    // say "Hi"
    @objc func donateClicked(_ sender: Any?) {
        //NSWorkspace.shared.open(URL(string: "https://entonos.com/index.php/the-geek-shop/")!) // NO via Apple because of paypal donate link. apple's math is about as good as their physics engine (i.e. 30% of 0 is still 0)
        NSWorkspace.shared.open(URL(string: "https://entonos.com/")!)
    }
    
    @objc func about(_ sender: Any?) {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }
}

extension NSEvent {
    var isRightClick: Bool {
        let rightClick = (self.type == .rightMouseDown)
        let controlClick = self.modifierFlags.contains(.control)
        return rightClick || controlClick
    }
}
