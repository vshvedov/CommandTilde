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

class DirectoryManager: ObservableObject {
    @Published var directories: [String] = []
    private let folderName = "CommandTilde"

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
    }

    func loadDirectories() {
        let commandTildeURL = commandTildeURL

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: commandTildeURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

            directories = contents.compactMap { url in
                let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                return isDirectory == true ? url.lastPathComponent : nil
            }.sorted()

        } catch {
            print("Failed to load directories: \(error)")
            directories = []
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
        popover.contentSize = NSSize(width: 500, height: 300)
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
        VStack(spacing: 20) {
            Text("Command Tilde")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("This is the Command Tilde popup")
                .font(.body)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("CommandTilde Folders", systemImage: "folder.fill")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        directoryManager.loadDirectories()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                if directoryManager.directories.isEmpty {
                    Text("No folders found in CommandTilde")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(directoryManager.directories, id: \.self) { directory in
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.blue)
                                    Text(directory)
                                        .font(.body)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.clear)
                                .cornerRadius(6)
                                .onTapGesture {
                                    // Future: Open folder or perform action
                                    print("Tapped folder: \(directory)")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }

            Spacer()
        }
        .padding()
        .frame(width: 500, height: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
