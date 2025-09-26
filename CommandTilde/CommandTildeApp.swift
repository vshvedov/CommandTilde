//
//  CommandTildeApp.swift
//  CommandTilde
//
//  Created by vsh on 2025-09-25.
//

import SwiftUI
import AppKit
import Foundation
import Combine

struct DirectoryItem {
    let name: String
    let icon: NSImage
    let url: URL
}

class DirectoryManager: ObservableObject {
    @Published var directories: [DirectoryItem] = []
    private let folderName = "CommandTilde"
    private var fileSystemWatcher: DispatchSourceFileSystemObject?

    var commandTildeURL: URL {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        return homeURL.appendingPathComponent(folderName)
    }

    func setupCommandTildeFolder() {
        print("Setting up CommandTilde folder in home directory...")

        let commandTildeURL = commandTildeURL

        print("📁 Target folder: \(commandTildeURL.path)")

        // Create CommandTilde folder if it doesn't exist
        if !FileManager.default.fileExists(atPath: commandTildeURL.path) {
            do {
                try FileManager.default.createDirectory(at: commandTildeURL, withIntermediateDirectories: true, attributes: nil)
                print("✅ Created CommandTilde folder in home directory")
            } catch {
                print("❌ Failed to create CommandTilde folder: \(error)")
            }
        } else {
            print("📁 CommandTilde folder already exists")
        }

        loadDirectories()
        setupFileSystemWatcher()
    }

    private func setupFileSystemWatcher() {
        let commandTildeURL = commandTildeURL

        let fileDescriptor = open(commandTildeURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("❌ Failed to open directory for monitoring")
            return
        }

        fileSystemWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        fileSystemWatcher?.setEventHandler { [weak self] in
            print("📁 Directory changed, reloading...")
            self?.loadDirectories()
        }

        fileSystemWatcher?.setCancelHandler {
            close(fileDescriptor)
        }

        fileSystemWatcher?.resume()
        print("👀 Started monitoring CommandTilde directory for changes")
    }

    deinit {
        fileSystemWatcher?.cancel()
    }

    func loadDirectories() {
        let commandTildeURL = commandTildeURL

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: commandTildeURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

            directories = contents.compactMap { url in
                let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                guard isDirectory == true else { return nil }

                let icon = getIconForDirectory(at: url)
                return DirectoryItem(name: url.lastPathComponent, icon: icon, url: url)
            }.sorted { $0.name < $1.name }

        } catch {
            print("Failed to load directories: \(error)")
            directories = []
        }
    }

    private func getIconForDirectory(at url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }
}

class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private override init() {}

    func showWindow() {
        if window == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            window?.title = "CommandTilde Settings"
            window?.contentViewController = hostingController
            window?.center()
            window?.setFrameAutosaveName("SettingsWindow")
            window?.delegate = self
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == window {
            // Remove delegate reference immediately to prevent callback issues
            closingWindow.delegate = nil
        }
    }

    func windowDidClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == window {
            DispatchQueue.main.async { [weak self] in
                self?.window = nil
            }
        }
    }
}

class AboutWindowController: NSObject, NSWindowDelegate {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    private override init() {}

    func showWindow() {
        if window == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )

            window?.title = "About CommandTilde"
            window?.contentViewController = hostingController
            window?.center()
            window?.isRestorable = false
            window?.delegate = self
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == window {
            // Remove delegate reference immediately to prevent callback issues
            closingWindow.delegate = nil
        }
    }

    func windowDidClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == window {
            DispatchQueue.main.async { [weak self] in
                self?.window = nil
            }
        }
    }
}

@main
struct CommandTildeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem, addition: { })
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var globalEventMonitor: Any?
    var localEventMonitor: Any?
    var directoryManager = DirectoryManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon and make app accessory
        NSApp.setActivationPolicy(.accessory)

        // Close any default windows
        for window in NSApp.windows {
            window.close()
        }

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
        popover.behavior = .transient
        popover.animates = true

        // Create the content view
        let contentView = PopoverContentView(directoryManager: directoryManager)
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Setup CommandTilde folder
        directoryManager.setupCommandTildeFolder()

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
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
}

struct PopoverContentView: View {
    @ObservedObject var directoryManager: DirectoryManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CommandTilde Folders")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: {
                    directoryManager.loadDirectories()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Content Area
            VStack {
                if directoryManager.directories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text("No folders found")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("Create folders in ~/CommandTilde/")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                            ForEach(directoryManager.directories, id: \.name) { directory in
                                VStack(spacing: 8) {
                                    Image(nsImage: directory.icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 64, height: 64)

                                    Text(directory.name)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .truncationMode(.middle)
                                        .frame(width: 80)
                                }
                                .padding(.vertical, 8)
                                .background(Color.clear)
                                .onTapGesture {
                                    print("Tapped folder: \(directory.name)")
                                    NSWorkspace.shared.open(directory.url)
                                }
                                .onHover { isHovered in
                                    // Add subtle hover effect if needed
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Bottom Toolbar
            Divider()

            HStack(spacing: 20) {
                Button(action: {
                    openSettingsWindow()
                }) {
                    Image(systemName: "gearshape")
                        .imageScale(.medium)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Settings")

                Spacer()

                Button(action: {
                    openAboutWindow()
                }) {
                    Image(systemName: "questionmark.circle")
                        .imageScale(.medium)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("About")

                Spacer()

                Button(action: {
                    confirmQuit()
                }) {
                    Image(systemName: "power")
                        .imageScale(.medium)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Quit CommandTilde")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 400)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func openSettingsWindow() {
        SettingsWindowController.shared.showWindow()
    }

    private func openAboutWindow() {
        AboutWindowController.shared.showWindow()
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit CommandTilde?"
        alert.informativeText = "Are you sure you want to quit CommandTilde?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}
