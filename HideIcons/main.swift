//
//  main.swift
//  Hide Icons
//
//  Created by G.J. Parker on 16/09/23.
//


import Cocoa
let app = NSApplication.shared

autoreleasepool {
    let delegate = AppDelegate()
    withExtendedLifetime(delegate, {
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    })
}
