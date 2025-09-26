//
//  WindowControllers.swift
//  CommandTilde
//
//  Created by vsh on 2025-09-25.
//

import SwiftUI
import AppKit
import Foundation

class SettingsWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow!

    override init() {
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        let contentView = SettingsView()
        let hostingController = NSHostingController(rootView: contentView)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "CommandTilde Settings"
        window.contentViewController = hostingController
        window.delegate = self

        // Make window appear above other windows but not always on top
        window.level = NSWindow.Level.floating

        // Set minimum size
        window.minSize = NSSize(width: 400, height: 250)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(self)
    }

    func hide() {
        window.orderOut(self)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Window is closing, we can perform cleanup if needed
        NSApp.activate(ignoringOtherApps: false)
    }
}

class AboutWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow!

    override init() {
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        let contentView = AboutView()
        let hostingController = NSHostingController(rootView: contentView)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "About CommandTilde"
        window.contentViewController = hostingController
        window.delegate = self

        // Make window appear above other windows but not always on top
        window.level = NSWindow.Level.floating

        // Disable resizing for about window
        window.minSize = window.frame.size
        window.maxSize = window.frame.size
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(self)
    }

    func hide() {
        window.orderOut(self)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Window is closing, we can perform cleanup if needed
        NSApp.activate(ignoringOtherApps: false)
    }
}