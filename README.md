Hide Icons

![Hide_256x256](https://user-images.githubusercontent.com/51520928/116168137-a0fb1400-a6b6-11eb-84ae-5248dab9d62a.png) 

Simple AppKit that's just a menu item that hides/shows Desktop icons.

Nosandbox version simply toggles System Settings...>Desktop & Dock>Desktop & Stage Manager>Show Items>On Desktop instead of taking a picture of the Desktop. If showing solid color, then show window of solid color just above Desktop. If we crash/force quit, we must restore the original On Desktop setting. We do this in main.swift by forking a watchdog process that intercepts when the main app exited (NOTE_EXIT for EVFILT_PROC filter. Also try to be efficient, if we're not showing a solid color, swap out our window entirely so it's never drawn (no more .hiddenLayer)
