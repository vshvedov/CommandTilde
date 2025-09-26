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

struct FileSystemItem {
    let name: String
    let icon: NSImage
    let url: URL
    let isDirectory: Bool
    let lastModified: Date?
}

class NavigationState: ObservableObject {
    @Published var currentPath: URL
    @Published var navigationHistory: [URL] = []

    init(rootPath: URL) {
        self.currentPath = rootPath
        self.navigationHistory = [rootPath]
    }

    func navigateToParent() {
        let parentURL = currentPath.deletingLastPathComponent()
        if navigationHistory.count > 1 {
            navigationHistory.removeLast()
            currentPath = navigationHistory.last ?? parentURL
        }
    }

    func navigateTo(url: URL) {
        navigationHistory.append(url)
        currentPath = url
    }

    var canGoBack: Bool {
        return navigationHistory.count > 1
    }
}

class FileSystemManager: ObservableObject {
    @Published var items: [FileSystemItem] = []
    @Published var isLoading = false
    private let folderName = "CommandTilde"
    private var fileSystemWatcher: DispatchSourceFileSystemObject?
    private let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "heif"]

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

        loadItems(at: commandTildeURL)
        setupFileSystemWatcher(for: commandTildeURL)
    }

    func setupFileSystemWatcher(for url: URL) {
        // Cancel existing watcher
        fileSystemWatcher?.cancel()

        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("❌ Failed to open directory for monitoring: \(url.path)")
            return
        }

        fileSystemWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        fileSystemWatcher?.setEventHandler { [weak self] in
            print("📁 Directory changed, reloading...")
            self?.loadItems(at: url)
        }

        fileSystemWatcher?.setCancelHandler {
            close(fileDescriptor)
        }

        fileSystemWatcher?.resume()
        print("👀 Started monitoring directory for changes: \(url.path)")
    }

    deinit {
        fileSystemWatcher?.cancel()
    }

    func loadItems(at url: URL) {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])

                let newItems = contents.compactMap { itemURL -> FileSystemItem? in
                    let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                    let isDirectory = resourceValues?.isDirectory ?? false
                    let lastModified = resourceValues?.contentModificationDate

                    let icon = self.getIcon(for: itemURL, isDirectory: isDirectory)
                    return FileSystemItem(
                        name: itemURL.lastPathComponent,
                        icon: icon,
                        url: itemURL,
                        isDirectory: isDirectory,
                        lastModified: lastModified
                    )
                }.sorted { item1, item2 in
                    // Sort directories first, then by name
                    if item1.isDirectory != item2.isDirectory {
                        return item1.isDirectory
                    }
                    return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                }

                DispatchQueue.main.async {
                    self.items = newItems
                    self.isLoading = false
                }

            } catch {
                print("Failed to load items: \(error)")
                DispatchQueue.main.async {
                    self.items = []
                    self.isLoading = false
                }
            }
        }
    }

    private func getIcon(for url: URL, isDirectory: Bool) -> NSImage {
        let fileExtension = url.pathExtension.lowercased()

        // Check if it's an image file and generate thumbnail
        if !isDirectory && imageExtensions.contains(fileExtension) {
            if let thumbnail = generateImageThumbnail(for: url) {
                return thumbnail
            }
        }

        // Fall back to system icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    private func generateImageThumbnail(for url: URL) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let thumbnailSize = CGSize(width: 64, height: 64)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(data: nil,
                                      width: Int(thumbnailSize.width),
                                      height: Int(thumbnailSize.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }

        // Calculate aspect ratio
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let aspectRatio = imageWidth / imageHeight

        var drawRect: CGRect
        if aspectRatio > 1 {
            // Wide image
            let height = thumbnailSize.height
            let width = height * aspectRatio
            drawRect = CGRect(x: (thumbnailSize.width - width) / 2, y: 0, width: width, height: height)
        } else {
            // Tall image
            let width = thumbnailSize.width
            let height = width / aspectRatio
            drawRect = CGRect(x: 0, y: (thumbnailSize.height - height) / 2, width: width, height: height)
        }

        context.draw(image, in: drawRect)

        guard let thumbnailImage = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: thumbnailImage, size: thumbnailSize)
    }
}

class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?

    private override init() {}

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        self.hostingController = hostingController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "CommandTilde Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false // ARC manages lifetime; avoid double-release
        window.isRestorable = false
        window.delegate = self
        window.center()

        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow == window else { return }
        closingWindow.delegate = nil
        // Break potential retain cycles and release references on close
        hostingController = nil
        window = nil
    }
}

class AboutWindowController: NSObject, NSWindowDelegate {
    static let shared = AboutWindowController()
    private var window: NSWindow?
    private var hostingController: NSHostingController<AboutView>?

    private override init() {}

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)
        self.hostingController = hostingController

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window?.title = "About CommandTilde"
        window?.contentViewController = hostingController
        window?.isReleasedWhenClosed = false
        window?.isRestorable = false
        window?.delegate = self
        window?.center()

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow == window else { return }
        closingWindow.delegate = nil
        // Break potential retain cycles and release references on close
        hostingController = nil
        window = nil
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
    var fileSystemManager = FileSystemManager()
    var navigationState: NavigationState!

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
        popover.behavior = .applicationDefined
        popover.animates = true

        // Initialize navigation state
        navigationState = NavigationState(rootPath: fileSystemManager.commandTildeURL)

        // Create the content view
        let contentView = PopoverContentView(fileSystemManager: fileSystemManager, navigationState: navigationState)
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
}

struct PopoverContentView: View {
    @ObservedObject var fileSystemManager: FileSystemManager
    @ObservedObject var navigationState: NavigationState
    @State private var isDragOver = false
    @State private var dragOverItem: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header with Navigation
            HStack {
                // Back Button
                Button(action: {
                    navigationState.navigateToParent()
                    fileSystemManager.loadItems(at: navigationState.currentPath)
                    fileSystemManager.setupFileSystemWatcher(for: navigationState.currentPath)
                }) {
                    Image(systemName: "chevron.left")
                        .imageScale(.medium)
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(!navigationState.canGoBack)
                .help("Go Back")

                // Current Path
                VStack(alignment: .leading, spacing: 2) {
                    Text(getCurrentFolderName())
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if navigationState.currentPath != fileSystemManager.commandTildeURL {
                        Text(getRelativePath())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Refresh Button
                Button(action: {
                    fileSystemManager.loadItems(at: navigationState.currentPath)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Refresh")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Content Area
            VStack {
                if fileSystemManager.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())

                        Text("Loading...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fileSystemManager.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text("No items found")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text(navigationState.currentPath == fileSystemManager.commandTildeURL ? "Create folders and files in ~/CommandTilde/" : "This folder is empty")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                            ForEach(fileSystemManager.items, id: \.name) { item in
                                VStack(spacing: 8) {
                                    Image(nsImage: item.icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 64, height: 64)

                                    VStack(spacing: 2) {
                                        Text(item.name)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .truncationMode(.middle)
                                            .frame(width: 80)

                                        if !item.isDirectory {
                                            Text(formatFileSize(for: item.url))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .background(
                                    // Highlight background when dragging over a folder
                                    item.isDirectory && dragOverItem == item.name ?
                                        Color.blue.opacity(0.2) : Color.clear
                                )
                                .cornerRadius(8)
                                .onTapGesture {
                                    handleItemTap(item)
                                }
                                .onDrop(of: ["public.file-url", "public.url", "public.image", "public.png", "public.jpeg", "com.compuserve.gif", "public.tiff", "public.data", "org.webmproject.webp", "public.webp", "public.heic"], isTargeted: .constant(false)) { providers in
                                    // Only allow drops on directories
                                    guard item.isDirectory else { return false }
                                    return handleDropOnFolder(providers: providers, folder: item)
                                }
                                .onHover { isHovered in
                                    // Update drag over state for visual feedback
                                    if isHovered && item.isDirectory {
                                        dragOverItem = item.name
                                    } else {
                                        dragOverItem = nil
                                    }
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
            .onChange(of: navigationState.currentPath) {
                fileSystemManager.loadItems(at: navigationState.currentPath)
                fileSystemManager.setupFileSystemWatcher(for: navigationState.currentPath)
            }

            // Bottom Toolbar
            Divider()

            HStack {
                // Path info
                Text("\(fileSystemManager.items.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 20) {
                    Button(action: {
                        openSettingsWindow()
                    }) {
                        Image(systemName: "gearshape")
                            .imageScale(.medium)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Settings")

                    Button(action: {
                        openAboutWindow()
                    }) {
                        Image(systemName: "questionmark.circle")
                            .imageScale(.medium)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("About")

                    Button(action: {
                        confirmQuit()
                    }) {
                        Image(systemName: "power")
                            .imageScale(.medium)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Quit CommandTilde")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 400)
        .background(isDragOver ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .onDrop(of: ["public.file-url", "public.url", "public.image", "public.png", "public.jpeg", "com.compuserve.gif", "public.tiff", "public.data", "org.webmproject.webp", "public.webp", "public.heic"], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        return handleDropToDestination(providers: providers, destination: navigationState.currentPath)
    }

    private func handleDropOnFolder(providers: [NSItemProvider], folder: FileSystemItem) -> Bool {
        guard folder.isDirectory else { return false }
        return handleDropToDestination(providers: providers, destination: folder.url)
    }

    private func handleDropToDestination(providers: [NSItemProvider], destination: URL) -> Bool {
        print("📦 Handling drop with \(providers.count) providers")

        for provider in providers {
            print("🔍 Available types: \(provider.registeredTypeIdentifiers)")

            // Handle local files first
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                    DispatchQueue.main.async {
                        if let data = item as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            print("✅ Found local file URL: \(url)")
                            self.copyFile(from: url, to: destination)
                        }
                    }
                }
                return true
            }

            // Handle WebP images specifically
            else if provider.hasItemConformingToTypeIdentifier("org.webmproject.webp") ||
                    provider.hasItemConformingToTypeIdentifier("public.webp") {
                let webpType = provider.hasItemConformingToTypeIdentifier("org.webmproject.webp") ? "org.webmproject.webp" : "public.webp"
                provider.loadItem(forTypeIdentifier: webpType, options: nil) { (item, error) in
                    DispatchQueue.main.async {
                        if let data = item as? Data {
                            print("✅ Found WebP image data: \(data.count) bytes")
                            let originalFilename = self.extractFilenameFromProvider(provider)
                            self.saveImageData(data, type: webpType, originalFilename: originalFilename, to: destination)
                        }
                    }
                }
                return true
            }

            // Handle direct image data (common for browser drags)
            else if provider.hasItemConformingToTypeIdentifier("public.image") ||
                    provider.hasItemConformingToTypeIdentifier("public.png") ||
                    provider.hasItemConformingToTypeIdentifier("public.jpeg") ||
                    provider.hasItemConformingToTypeIdentifier("com.compuserve.gif") ||
                    provider.hasItemConformingToTypeIdentifier("public.tiff") ||
                    provider.hasItemConformingToTypeIdentifier("public.heic") {

                // Find the most specific image type
                let imageTypes = ["public.png", "public.jpeg", "com.compuserve.gif", "public.tiff", "public.heic", "public.image"]
                let availableImageType = imageTypes.first { provider.hasItemConformingToTypeIdentifier($0) }

                if let imageType = availableImageType {
                    provider.loadItem(forTypeIdentifier: imageType, options: nil) { (item, error) in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("❌ Error loading image: \(error)")
                                return
                            }

                            var imageData: Data?
                            var originalFilename: String?

                            // Try different ways to get the data
                            if let data = item as? Data {
                                print("✅ Found direct image data (\(imageType)): \(data.count) bytes")
                                imageData = data
                                // Try to get filename from provider's suggested filename
                                originalFilename = self.extractFilenameFromProvider(provider)
                            } else if let image = item as? NSImage {
                                print("🌄 Found NSImage, converting to data...")
                                imageData = self.convertNSImageToData(image, type: imageType)
                                originalFilename = self.extractFilenameFromProvider(provider)
                            } else if let url = item as? URL {
                                print("🔗 Found image URL: \(url)")
                                imageData = try? Data(contentsOf: url)
                                originalFilename = url.lastPathComponent
                            } else {
                                print("⚠️ Unknown item type: \(type(of: item))")
                                // Try to load as generic object and convert
                                if item != nil {
                                    print("🔍 Attempting fallback data conversion...")
                                    // Try to get image through pasteboard
                                    if let pasteboardItem = NSPasteboard.general.pasteboardItems?.first {
                                        if let data = pasteboardItem.data(forType: .tiff) {
                                            imageData = data
                                            print("✅ Got image data from pasteboard")
                                        }
                                    }
                                }
                                originalFilename = self.extractFilenameFromProvider(provider)
                            }

                            if let data = imageData {
                                self.saveImageData(data, type: imageType, originalFilename: originalFilename, to: destination)
                            } else {
                                print("❌ Failed to extract image data from item")
                            }
                        }
                    }
                    return true
                }
            }

            // Handle URLs (including web URLs)
            else if provider.hasItemConformingToTypeIdentifier("public.url") {
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { (item, error) in
                    DispatchQueue.main.async {
                        var targetURL: URL?

                        if let data = item as? Data {
                            targetURL = URL(dataRepresentation: data, relativeTo: nil)
                        } else if let urlString = item as? String {
                            targetURL = URL(string: urlString)
                        } else if let url = item as? URL {
                            targetURL = url
                        }

                        if let url = targetURL {
                            print("✅ Found URL: \(url)")
                            if url.scheme == "http" || url.scheme == "https" {
                                self.downloadAndCopyFile(from: url, to: destination)
                            } else {
                                self.copyFile(from: url, to: destination)
                            }
                        } else {
                            print("❌ Failed to parse URL from item: \(String(describing: item))")
                        }
                    }
                }
                return true
            }

            // Handle generic data as fallback
            else if provider.hasItemConformingToTypeIdentifier("public.data") {
                provider.loadItem(forTypeIdentifier: "public.data", options: nil) { (item, error) in
                    DispatchQueue.main.async {
                        if let data = item as? Data {
                            print("✅ Found generic data: \(data.count) bytes")
                            let originalFilename = self.extractFilenameFromProvider(provider)
                            self.saveGenericData(data, originalFilename: originalFilename, to: destination)
                        }
                    }
                }
                return true
            }
        }

        print("❌ No supported data types found in providers")
        return false
    }

    private func copyFile(from sourceURL: URL, to destinationDirectory: URL) {
        let fileName = sourceURL.lastPathComponent
        let destinationURL = destinationDirectory.appendingPathComponent(fileName)

        do {
            // Check if file already exists and create unique name if needed
            var finalDestinationURL = destinationURL
            var counter = 1

            while FileManager.default.fileExists(atPath: finalDestinationURL.path) {
                let nameWithoutExtension = sourceURL.deletingPathExtension().lastPathComponent
                let fileExtension = sourceURL.pathExtension
                let newName = fileExtension.isEmpty ?
                    "\(nameWithoutExtension) (\(counter))" :
                    "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
                finalDestinationURL = destinationDirectory.appendingPathComponent(newName)
                counter += 1
            }

            try FileManager.default.copyItem(at: sourceURL, to: finalDestinationURL)
            print("✅ Copied file to: \(finalDestinationURL.path)")

            // Refresh the current directory view
            fileSystemManager.loadItems(at: navigationState.currentPath)

        } catch {
            print("❌ Failed to copy file: \(error)")
        }
    }

    private func downloadAndCopyFile(from url: URL, to destinationDirectory: URL) {
        guard url.scheme == "http" || url.scheme == "https" else {
            print("❌ Unsupported URL scheme: \(url.scheme ?? "unknown")")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    print("❌ Failed to download file: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }

                // Determine file name from URL or response
                var fileName = url.lastPathComponent
                if fileName.isEmpty || !fileName.contains(".") {
                    if let response = response as? HTTPURLResponse,
                       let contentDisposition = response.allHeaderFields["Content-Disposition"] as? String,
                       let range = contentDisposition.range(of: "filename=") {
                        let startIndex = contentDisposition.index(range.upperBound, offsetBy: 0)
                        fileName = String(contentDisposition[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        // Guess extension from content type
                        if let response = response as? HTTPURLResponse,
                           let contentType = response.allHeaderFields["Content-Type"] as? String {
                            if contentType.contains("image/jpeg") || contentType.contains("image/jpg") {
                                fileName = "downloaded_image.jpg"
                            } else if contentType.contains("image/png") {
                                fileName = "downloaded_image.png"
                            } else if contentType.contains("image/gif") {
                                fileName = "downloaded_image.gif"
                            } else {
                                fileName = "downloaded_file"
                            }
                        } else {
                            fileName = "downloaded_file"
                        }
                    }
                }

                let destinationURL = destinationDirectory.appendingPathComponent(fileName)

                // Check if file already exists and create unique name if needed
                var finalDestinationURL = destinationURL
                var counter = 1

                while FileManager.default.fileExists(atPath: finalDestinationURL.path) {
                    let nameWithoutExtension = destinationURL.deletingPathExtension().lastPathComponent
                    let fileExtension = destinationURL.pathExtension
                    let newName = fileExtension.isEmpty ?
                        "\(nameWithoutExtension) (\(counter))" :
                        "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
                    finalDestinationURL = destinationDirectory.appendingPathComponent(newName)
                    counter += 1
                }

                do {
                    try data.write(to: finalDestinationURL)
                    print("✅ Downloaded and saved file to: \(finalDestinationURL.path)")

                    // Refresh the current directory view
                    self.fileSystemManager.loadItems(at: self.navigationState.currentPath)

                } catch {
                    print("❌ Failed to save downloaded file: \(error)")
                }
            }
        }.resume()
    }

    private func convertNSImageToData(_ image: NSImage, type: String) -> Data? {
        // Try to get the best representation based on the type
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ Failed to get CGImage from NSImage")
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        switch type {
        case "public.png":
            return bitmap.representation(using: .png, properties: [:])
        case "public.jpeg":
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case "com.compuserve.gif":
            return bitmap.representation(using: .gif, properties: [:])
        case "public.tiff":
            return bitmap.representation(using: .tiff, properties: [:])
        default:
            // Default to PNG for unknown types
            return bitmap.representation(using: .png, properties: [:])
        }
    }

    private func saveImageData(_ data: Data, type: String, originalFilename: String?, to destinationDirectory: URL) {
        // Determine file extension from UTI type
        let typeExtension: String
        switch type {
        case "public.png":
            typeExtension = "png"
        case "public.jpeg":
            typeExtension = "jpg"
        case "com.compuserve.gif":
            typeExtension = "gif"
        case "public.tiff":
            typeExtension = "tiff"
        case "org.webmproject.webp", "public.webp":
            typeExtension = "webp"
        case "public.heic":
            typeExtension = "heic"
        default:
            typeExtension = "png" // Default fallback
        }

        // Use original filename if available, otherwise generate default name
        let fileName: String
        if let originalName = originalFilename, !originalName.isEmpty {
            // Check if original filename has extension
            let originalURL = URL(fileURLWithPath: originalName)
            let originalExtension = originalURL.pathExtension.lowercased()

            // Use original extension if it matches the data type, otherwise use type extension
            if originalExtension == typeExtension || originalExtension == "jpeg" && typeExtension == "jpg" {
                fileName = originalName
            } else if originalExtension.isEmpty {
                // Original name has no extension, add the type extension
                fileName = "\(originalName).\(typeExtension)"
            } else {
                // Original has different extension, replace it
                fileName = "\(originalURL.deletingPathExtension().lastPathComponent).\(typeExtension)"
            }
        } else {
            fileName = "dropped_image.\(typeExtension)"
        }

        let destinationURL = destinationDirectory.appendingPathComponent(fileName)

        // Check if file already exists and create unique name if needed
        var finalDestinationURL = destinationURL
        var counter = 1

        while FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            let baseURL = URL(fileURLWithPath: fileName)
            let nameWithoutExtension = baseURL.deletingPathExtension().lastPathComponent
            let fileExtension = baseURL.pathExtension
            let newName = fileExtension.isEmpty ?
                "\(nameWithoutExtension) (\(counter))" :
                "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
            finalDestinationURL = destinationDirectory.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try data.write(to: finalDestinationURL)
            print("✅ Saved image data to: \(finalDestinationURL.path)")

            // Refresh the current directory view
            fileSystemManager.loadItems(at: navigationState.currentPath)

        } catch {
            print("❌ Failed to save image data: \(error)")
        }
    }

    private func extractFilenameFromProvider(_ provider: NSItemProvider) -> String? {
        // Try to get the suggested filename from the item provider
        if let suggestedName = provider.suggestedName {
            print("🏷️ Found suggested filename: \(suggestedName)")
            return suggestedName
        }

        // Try to extract from registered type identifiers if they contain filename info
        for typeId in provider.registeredTypeIdentifiers {
            // Look for file URL type which might contain filename info
            if typeId.contains("file-url") || typeId.contains("public.file-url") {
                // This is handled separately in the main drag handler
                continue
            }

            // Try to infer filename from type identifiers that might contain it
            if typeId.contains(".") {
                let parts = typeId.split(separator: ".")
                if parts.count > 1 {
                    let lastPart = String(parts.last!)
                    // Skip common UTI components that aren't filenames
                    if !["public", "com", "org", "image", "data", "file", "url"].contains(lastPart.lowercased()) {
                        print("🔍 Trying to extract filename from UTI: \(typeId)")
                        // This might be a filename component, but it's speculative
                        // We'll return nil here to avoid false positives
                    }
                }
            }
        }

        print("❓ No filename found in provider metadata")
        return nil
    }

    private func saveGenericData(_ data: Data, originalFilename: String?, to destinationDirectory: URL) {
        // Use original filename if available, otherwise generate default name
        let fileName = originalFilename?.isEmpty == false ? originalFilename! : "dropped_file"
        let destinationURL = destinationDirectory.appendingPathComponent(fileName)

        // Check if file already exists and create unique name if needed
        var finalDestinationURL = destinationURL
        var counter = 1

        while FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            let baseURL = URL(fileURLWithPath: fileName)
            let nameWithoutExtension = baseURL.deletingPathExtension().lastPathComponent
            let fileExtension = baseURL.pathExtension
            let newName = fileExtension.isEmpty ?
                "\(nameWithoutExtension) (\(counter))" :
                "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
            finalDestinationURL = destinationDirectory.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try data.write(to: finalDestinationURL)
            print("✅ Saved generic data to: \(finalDestinationURL.path)")

            // Refresh the current directory view
            fileSystemManager.loadItems(at: navigationState.currentPath)

        } catch {
            print("❌ Failed to save generic data: \(error)")
        }
    }

    private func handleItemTap(_ item: FileSystemItem) {
        if item.isDirectory {
            // Navigate into the directory
            navigationState.navigateTo(url: item.url)
        } else {
            // Open file with default application
            NSWorkspace.shared.open(item.url)
        }
    }

    private func getCurrentFolderName() -> String {
        if navigationState.currentPath == fileSystemManager.commandTildeURL {
            return "CommandTilde"
        } else {
            return navigationState.currentPath.lastPathComponent
        }
    }

    private func getRelativePath() -> String {
        let relativePath = String(navigationState.currentPath.path.dropFirst(fileSystemManager.commandTildeURL.path.count))
        return relativePath.isEmpty ? "/" : relativePath
    }

    private func formatFileSize(for url: URL) -> String {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            }
        } catch {
            // Ignore errors
        }
        return ""
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
