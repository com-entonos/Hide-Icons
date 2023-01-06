//
//  AppDelegate.swift
//  HideIcons
//
//  Created by parker on 4/25/21.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // status bar item
    var statusBarItem: NSStatusItem?
    
    // Hider class which hides/shows icons
    var hider: Hider? = Hider()
    
    // status bar item images
    let sbiPicture = NSImage(named: "BBarButtonImage")
    let sbiNoPicture = NSImage(named: "AlphaBarButtonImage")
    
    // to figure out if Services started the app
    var startDate: Date!
    
    // start out w/ status bar item visible
    var sbiHidden = false
    
    // show menu on left click?
    var defaultClick = true
    
    // type of Desktop
    var desktop: DesktopTypes = .allDesktop
    var desktopColor : NSColor = .black
    var lastDesktopColor : NSColor = .black
    
    let defaultTimeList = ["Never", "5 seconds", "30 seconds", "1 minute", "5 minutes", "15 minutes", "1 hour"]
    let defaultTimes = [315576000.0, 5.0, 30.0, 60.0, 300.0, 900.0, 3600.0]
    var defaultTime = "Never"
    
    var version = "0.0.0"
    let appStore = false    // this app destined to macOS App Store?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        //print("version: \(version), in preferences: \(UserDefaults.standard.string(forKey: "donate")), appStore=\(appStore)")
        
        // restore user preferences
        if !NSEvent.modifierFlags.contains(.command) { setDefaultValues() }
        else { // reset to defaults
            UserDefaults.standard.set(defaultTime, forKey: "defaultTime")
            UserDefaults.standard.set(sbiHidden, forKey: "sbiHidden")
            UserDefaults.standard.set(defaultClick, forKey: "defaultClick")
        }
        
        // construct status bar item (or not!)
        statusBarItem = setStatusBarItem(image: sbiHidden ? sbiNoPicture : sbiPicture)
        
        // create some Services
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        
        // let's go setup a background timer- lazy way to capture changing desktop backgrounds
        NotificationCenter.default.post(name: .timeBG, object: defaultTimes[defaultTimeList.firstIndex(where: {$0 == defaultTime}) ?? 0])
        
        // date the app started + 2 second
        startDate = Date(timeIntervalSinceNow: TimeInterval(2.0))
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        hider = nil // remove observers
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if statusBarItem == nil || sbiHidden {
            if statusBarItem == nil { statusBarItem = setStatusBarItem(image: sbiPicture) }
            sbiHidden = false
        }
        return false
    }
    
    @objc func powerOff(notification: NSNotification) { // does this catch logoff, restart and shutdown?
        NSApplication.shared.terminate(self)
    }
    // called from Services menu
    @objc func toggleService(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        if Date() < startDate { //hack to see if Service started the app
            statusBarItem = nil // Services did start the app (therefore icons hidden); just turn off menu
        } else {
            toggle(nil)         // didn't start app, so toggle icons
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
    // status bar item clicked- do we toggle or do we construct and show menu?
    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        if NSApp.currentEvent!.isRightClick == defaultClick {
            toggle(nil)
        } else {
            statusBarItem!.menu = constructMenu(hider!.hidden)
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

        // Right or left click for menu?
        let menuClick = NSMenuItem(title: "Right-click to show menu", action: #selector(self.rightClicked(_:)), keyEquivalent: "")
        menuClick.state = defaultClick ? NSControl.StateValue.off : NSControl.StateValue.on
        menu.addItem(menuClick)
        
        // timer > submenu of possible times to update
        let timeSubMenu = NSMenu()
        let timeMenuItem = NSMenuItem() // Change menu > Hid/Show or Remove menu
        timeMenuItem.title = "Check for changing Desktop"
        menu.addItem(timeMenuItem)
        for time in defaultTimeList {
            let timeMI = NSMenuItem(title: time, action: #selector(self.selectTime(_:)), keyEquivalent: "")
            timeMI.state = defaultTime == time ? NSControl.StateValue.on : NSControl.StateValue.off
            timeSubMenu.addItem(timeMI)
        }
        menu.setSubmenu(timeSubMenu, for: timeMenuItem)

        // menu > submenu of Show/Hide or Remove remove
        let subMenu = NSMenu()
        let menuItem = NSMenuItem() // Change menu > Hid/Show or Remove menu
        menuItem.title = "Change menu"
        menu.addItem(menuItem)
        str = sbiHidden ? "Show menu" : "Hide menu"
        subMenu.addItem(NSMenuItem(title: str, action: #selector(self.sbiPic(_:)), keyEquivalent: ""))
        subMenu.addItem(NSMenuItem(title: "Remove menu", action: #selector(self.removeMenu(_:)), keyEquivalent: ""))
        menu.setSubmenu(subMenu, for: menuItem)
        
        // desktop menual > submenu of solid color oractual for just this screen or all
        if hidden {
        let (currentImage, currentColor, currentlyColored) = hider!.desktopFromPoint(NSEvent.mouseLocation, color: desktopColor)
        let previewSize = NSSize(width: 20, height: 20); lastDesktopColor = currentColor
        let bgSubMenu = NSMenu()
        let bgMenuItem = NSMenuItem()
        bgMenuItem.title = "Set Desktop wallpaper"
        menu.addItem(bgMenuItem)
        let bgT1 = NSMenuItem(title: "This Desktop", action: nil, keyEquivalent: "")
        bgSubMenu.addItem(bgT1)
        if hider!.numberOfDesktops > 1 {
            let bgMI = NSMenuItem(title: "actual", action: #selector(self.selectDesktop(_:)), keyEquivalent: "")
            if let desktopImage = currentImage { bgMI.image = NSImage(cgImage: desktopImage, size: previewSize) }
            bgMI.state = !currentlyColored && desktop != .allDesktop && desktop != .allSolidColorDesktop ? NSControl.StateValue.on : NSControl.StateValue.off
            bgMI.tag = 1
            bgSubMenu.addItem(bgMI)
            let scMI = NSMenuItem(title: "color", action: #selector(self.selectDesktop(_:)), keyEquivalent: "")
            scMI.image = NSImage.swatchWithColor(color: currentColor, size: previewSize)
            scMI.state = currentlyColored && desktop != .allDesktop && desktop != .allSolidColorDesktop ? NSControl.StateValue.on : NSControl.StateValue.off
            scMI.tag = 2
            bgSubMenu.addItem(scMI)
            bgSubMenu.addItem(NSMenuItem.separator())
            let bgT2 = NSMenuItem(title: "All Desktops", action: nil, keyEquivalent: "")
            bgSubMenu.addItem(bgT2)
        }
        // note if only one screen (monitor), MenuItem has tags > 2
        let abgMI = NSMenuItem(title: "actual", action: #selector(self.selectDesktop(_:)), keyEquivalent: "")
        if let desktopImage = currentImage { abgMI.image = NSImage(cgImage: desktopImage, size: previewSize) }
        abgMI.state = desktop == .allDesktop ? NSControl.StateValue.on : NSControl.StateValue.off
        abgMI.tag = 3
        bgSubMenu.addItem(abgMI)
        let ascMI = NSMenuItem(title: "color", action: #selector(self.selectDesktop(_:)), keyEquivalent: "")
        ascMI.image = NSImage.swatchWithColor(color: currentColor, size: previewSize)
        ascMI.state = desktop == .allSolidColorDesktop ? NSControl.StateValue.on : NSControl.StateValue.off
        ascMI.tag = 4
        bgSubMenu.addItem(ascMI)
        menu.setSubmenu(bgSubMenu, for: bgMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Force Desktop refresh", action: #selector(self.refreshDesktops(_:)), keyEquivalent: ""))
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Help", action: #selector(self.getHelp(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About", action: #selector(self.about(_:)), keyEquivalent: ""))
        
        let noDonate = UserDefaults.standard.object(forKey: "donate") == nil ? appStore : UserDefaults.standard.string(forKey: "donate") == version
        if noDonate { // for App Store
            menu.addItem(NSMenuItem(title: "Say \"Hi\" to entonos", action: #selector(self.donateClicked(_:)), keyEquivalent: ""))
        } else {
            let donateItem = NSMenuItem(title: "Donate...", action: #selector(self.donateClicked(_:)), keyEquivalent: "")
            donateItem.attributedTitle = NSAttributedString(string: "Donate...", attributes: [NSAttributedString.Key.foregroundColor: NSColor.red])
            menu.addItem(donateItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        return menu
    }
    @objc func refreshDesktops(_ sender: Any?) {  // force refresh of hider
        desktop = .allDesktop
        NotificationCenter.default.post(name: .createDesktops, object: nil)
        NotificationCenter.default.post(name: .desktopType, object: (lastDesktopColor, desktop, NSEvent.mouseLocation))
    }
    @objc func menuDidClose(_ menu: NSMenu) { // teardown menu for next time SBI is clicked
        statusBarItem?.menu = nil
    }
    @objc func selectDesktop(_ menu: NSMenuItem) { //print("in selectDesktop, menu.tag=\(menu.tag)") // selecting if desktop or all desktops are solid color or actual
        let option = menu.tag as Int
        switch option {
        case 2 :
            desktop = .solidColorDesktop
        case 4 :
            desktop = .allSolidColorDesktop
        case 3 :
            desktop = .allDesktop
        default:
            desktop = .desktop
        }
        
        NotificationCenter.default.post(name: .desktopType, object: (lastDesktopColor, desktop, NSEvent.mouseLocation))
        if option % 2 == 1 { return } // no need for color wheel
        // (re)set color wheel
        let picker = NSColorPanel.shared
        picker.mode = .wheel
        picker.showsAlpha = false
        picker.hidesOnDeactivate = false
        picker.isFloatingPanel = true
        picker.setTarget(self)
        picker.setAction(#selector(colorChosen(_:)))
        picker.color = lastDesktopColor
        picker.collectionBehavior = .canJoinAllSpaces
        picker.makeKeyAndOrderFront(nil)
    }
    @objc func colorChosen(_ picker: NSColorPanel) { // we got a color
        desktopColor = NSColorPanel.shared.color //; print("in colorChosen \(desktop) \(desktopColor)")
        NotificationCenter.default.post(name: .desktopType, object: (desktopColor, desktop, NSEvent.mouseLocation))
    }
    // called when icons should hidden or shown
    @objc func toggle(_ sender: Any?) {
        NotificationCenter.default.post(name: .doHide, object: nil)
    }
    // check for changing Desktop how often? default is never
    @objc func selectTime(_ menu: NSMenuItem) {
        defaultTime = menu.title
        NotificationCenter.default.post(name: .timeBG, object: defaultTimes[defaultTimeList.firstIndex(where: {$0 == defaultTime}) ?? 0])
        UserDefaults.standard.set(defaultTime, forKey: "defaultTime")
    }
    // called when status bar item should be hidden or shown
    @objc func sbiPic(_ sender: Any?) {
        statusBarItem?.button?.image = sbiHidden ? sbiPicture : sbiNoPicture
        sbiHidden = !sbiHidden
        UserDefaults.standard.set(sbiHidden, forKey: "sbiHidden") // save choice
    }
    // called when switching left & right clicks
    @objc func rightClicked(_ sender: Any?) {
        defaultClick = !defaultClick
        UserDefaults.standard.set(defaultClick, forKey: "defaultClick") // save choice
    }
    
    @objc func removeMenu(_ sender: Any?) {
        statusBarItem = nil
    }
    
    @objc func getHelp(_ sender: Any?) {
        if let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? NSHelpManager.BookName {
            NSHelpManager.shared.openHelpAnchor("Welcome", inBook: book)
        }
    }
    // say "Hi"
    @objc func donateClicked(_ sender: Any?) {
        let noDonate = UserDefaults.standard.object(forKey: "donate") == nil ? appStore : UserDefaults.standard.string(forKey: "donate") == version
        if noDonate {
            let url = URL(string: "https://entonos.com/index.php/the-geek-shop/")
            //let url = URL(string: "https://entonos.com/")
            NSWorkspace.shared.open(url!)
        } else {    // NO via Apple because of paypal donate link. apple's math is about as good as their physics engine (i.e. 30% of 0 is still 0)
            let url = URL(string: "http://www.parker9.com/d")
            NSWorkspace.shared.open(url!)
            UserDefaults.standard.set(version, forKey: "donate")
        }
    }
    
    @objc func about(_ sender: Any?) {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }
    // read in user preferences
    func setDefaultValues() {
        defaultClick = ( UserDefaults.standard.object(forKey: "defaultClick") == nil) ? defaultClick : UserDefaults.standard.bool(forKey: "defaultClick")
        sbiHidden = ( UserDefaults.standard.object(forKey: "sbiHidden") == nil) ? sbiHidden : UserDefaults.standard.bool(forKey: "sbiHidden")
        defaultTime = (( UserDefaults.standard.object(forKey: "defaultTime") == nil) ? defaultTime : UserDefaults.standard.string(forKey: "defaultTime")) ?? defaultTime
        defaultTime = defaultTimeList[defaultTimeList.firstIndex(where: {$0 == defaultTime}) ?? 0] // make sure defaultTime is a valid string
    }
}

extension NSEvent { // so .rightMouseDown does not capture control+.leftMouseDown; fix that.
    var isRightClick: Bool {
        return (self.type == .rightMouseDown) || (self.type == .leftMouseDown && self.modifierFlags.contains(.control))
    }
}

extension NSImage { // return an solid color image
  class func swatchWithColor(color: NSColor, size: NSSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    color.drawSwatch(in: NSRect(origin: .zero, size: size))
    image.unlockFocus()
    return image
  }
}

enum DesktopTypes: Int {    // different options for Desktop wallpapers
    case allDesktop = 1, desktop, allSolidColorDesktop, solidColorDesktop
}
