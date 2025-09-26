//
//  CommandTildeApp.swift
//  CommandTilde
//
//  Created by vsh on 2025-09-25.
//

import SwiftUI
import AppKit
import Foundation

@main
struct CommandTildeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var fileSystemManager: FileSystemManager!
    var navigationState: NavigationState!
    var appSettings: AppSettings!

    // Window controllers
    var settingsWindowController: SettingsWindowController?
    var aboutWindowController: AboutWindowController?

    // Event monitors for global hotkey
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app to be an accessory (won't appear in dock)
        NSApp.setActivationPolicy(.accessory)

        // Initialize file system manager
        fileSystemManager = FileSystemManager()
        appSettings = AppSettings()

        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem.button {
            button.title = "⌘~"
            button.action = #selector(togglePopover)
            button.target = self
            button.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        }

        // Initialize popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 520, height: 400)
        popover.behavior = .applicationDefined
        popover.animates = true

        // Initialize navigation state
        navigationState = NavigationState(rootPath: fileSystemManager.commandTildeURL)

        // Create the content view
        let contentView = PopoverContentView(
            fileSystemManager: fileSystemManager,
            navigationState: navigationState,
            appSettings: appSettings,
            onSettingsPressed: { [weak self] in
                self?.showSettings()
            },
            onAboutPressed: { [weak self] in
                self?.showAbout()
            },
            onExitPressed: { [weak self] in
                self?.quitApp()
            }
        )
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        popover.contentViewController = hostingController

        // Setup CommandTilde folder
        fileSystemManager.setupCommandTildeFolder()

        // Register global hotkey for Command+Tilde
        setupGlobalHotkey()
        requestAccessibilityPermissions()
    }

    private func setupGlobalHotkey() {
        // Global event monitor (works when other apps are focused)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyEvent(event)
        }

        // Local event monitor (works when this app is focused)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let self = self, self.handleKeyEvent(event) {
                return nil // Consume the event
            }
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check for Command+` (backtick/tilde key)
        if event.modifierFlags.contains(.command) && event.keyCode == 50 {
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover()
            }
            return true
        }
        return false
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !accessEnabled {
            print("Accessibility permissions required for global hotkeys. Please enable CommandTilde in System Preferences > Security & Privacy > Privacy > Accessibility")
        }
    }

    @objc func togglePopover() {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                // Activate the app and bring it to foreground
                NSApp.activate(ignoringOtherApps: true)

                // Show the popover
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

                // Force focus on the popover content
                if let contentViewController = popover.contentViewController {
                    contentViewController.view.window?.makeKeyAndOrderFront(nil)
                    contentViewController.view.window?.level = NSWindow.Level.statusBar
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up event monitors
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Menu Actions

    @objc func showSettings() {
        if popover?.isShown == true {
            popover.performClose(nil)
        }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appSettings: appSettings)
        }
        settingsWindowController?.show()
    }

    @objc func showAbout() {
        if popover?.isShown == true {
            popover.performClose(nil)
        }
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.show()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
}
