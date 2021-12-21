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

    // status bar item
    var statusBarItem: NSStatusItem?
    
    // Hider class which hides/shows icons
    let hider = Hider()
    
    // status bar item images
    let sbiPicture = NSImage(named: "BBarButtonImage")
    let sbiNoPicture = NSImage(named: "AlphaBarButtonImage")
    
    // to figure out if Services started the app
    var startDate: Date!
    
    // start out w/ status bar item visible
    var sbiHidden = false
    
    // show menu on left click?
    var defaultClick = true
    
    // Apple doc
    var observation: NSKeyValueObservation?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        // restore user preferences
        var noSBI = false
        if !NSEvent.modifierFlags.contains(.command) { noSBI = setDefaultValues() }
        
        // construct status bar item (or not!)
        if noSBI { statusBarItem = nil } else {
            statusBarItem = setStatusBarItem(image: sbiHidden ? sbiNoPicture : sbiPicture)
        }
        
        // this should capture in/out of Dark Mode
        if #available(OSX 10.14, *) {
            observation = NSApp.observe(\.effectiveAppearance) { (app, _) in
                if self.hider.hidden { // give 3 second delay to make sure the Desktop did in fact update
                    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { _ in
                                            NotificationCenter.default.post(name: .spaceChange, object: nil) })
                }
            }
        }
        
        // create some Services
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        
        // date the app started + 2 second
        startDate = Date(timeIntervalSinceNow: TimeInterval(2.0))
        
        // let's go hide icons (in 1 second so later versions of macOS are happy we are out of this function)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false, block: { _ in self.toggle(nil)})
    }
    // called from Services menu
    @objc func toggleService(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        if Date() > startDate { //hack to see if Service started the app, if so don't toggle since we are already hiding icons
            toggle(nil)
        } else {
            statusBarItem = nil // Services did start the app; just turn off menu
        }
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
    // construct status bar item
    func setStatusBarItem(image: NSImage? ) -> NSStatusItem? {
        let sBI = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        sBI.button?.image = image
        sBI.button?.action = #selector(self.statusBarButtonClicked(sender:))
        sBI.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        return sBI
    }
    // status bar item clicked- do we toggle or do we construct and show menu?
    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        if NSApp.currentEvent!.isRightClick == defaultClick {
            toggle(nil)
        } else {
            statusBarItem!.menu = constructMenu(hider.hidden)
            statusBarItem!.button!.performClick(nil) // pass the click along
        }
    }
    // construct menu
    func constructMenu(_ hidden : Bool) -> NSMenu? {
        let menu = NSMenu()
        menu.delegate = self

        // Show/Hide Desktop Icons
        var str = hidden ? "Show Desktop Icons" : "Hide Desktop Icons"
        menu.addItem(NSMenuItem(title: str, action: #selector(self.toggle(_:)), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Refresh Desktop", action: #selector(self.forceRefresh(_:)), keyEquivalent: ""))
        
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
    @objc func forceRefresh(_ sender: Any?) {
        hider.makeWindows()
    }
    @objc func menuDidClose(_ menu: NSMenu) { // teardown menu for next time SBI is clicked
        statusBarItem?.menu = nil
    }
    // called when icons should hidden or shown
    @objc func toggle(_ sender: Any?) {
        NotificationCenter.default.post(name: .doHide, object: nil)
    }
    // called when status bar item should be hidden or shown
    @objc func sbiPic(_ sender: Any?) {
        statusBarItem?.button?.image = sbiHidden ? sbiPicture : sbiNoPicture
        sbiHidden = !sbiHidden
        UserDefaults.standard.set(sbiHidden, forKey: "sbiHidden") // save choice
        //UserDefaults.standard.set(false, forKey: "noSBI") // clear noSBI
    }
    // called when switching left & right clicks
    @objc func rightClicked(_ sender: Any?) {
        defaultClick = !defaultClick
        UserDefaults.standard.set(defaultClick, forKey: "defaultClick") // save choice
    }
    
    @objc func removeMenu(_ sender: Any?) {
        statusBarItem = nil
        //UserDefaults.standard.set(true, forKey: "noSBI") // save choice
    }
    
    @objc func getHelp(_ sender: Any?) {
        if let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? NSHelpManager.BookName {
            NSHelpManager.shared.openHelpAnchor("Welcome", inBook: book)
        }
    }
    // say "Hi"
    @objc func donateClicked(_ sender: Any?) {
        //NSWorkspace.shared.open(URL(string: "https://entonos.com/index.php/the-geek-shop/")!) // NO via Apple because of paypal donate link. apple's math is about as good as their physics engine (i.e. 30% of 0 is still 0)
        NSWorkspace.shared.open(URL(string: "https://entonos.com/")!)
    }
    
    @objc func about(_ sender: Any?) {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }
    // read in user preferences
    func setDefaultValues() -> Bool {
        defaultClick = ( UserDefaults.standard.object(forKey: "defaultClick") == nil) ? true : UserDefaults.standard.bool(forKey: "defaultClick")
        sbiHidden = ( UserDefaults.standard.object(forKey: "sbiHidden") == nil) ? false : UserDefaults.standard.bool(forKey: "sbiHidden")
        return false
        //return( UserDefaults.standard.object(forKey: "noSBI") == nil) ? false : UserDefaults.standard.bool(forKey: "noSBI")  // do we construct the status bar item?
    }
}

extension NSEvent { // so .rightMouseDown does not capture control+.leftMouseDown; fix that.
    var isRightClick: Bool {
        return (self.type == .rightMouseDown) || (self.type == .leftMouseDown && self.modifierFlags.contains(.control))
    }
}
