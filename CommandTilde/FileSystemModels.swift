//
//  FileSystemModels.swift
//  CommandTilde
//
//  Created by vsh on 2025-09-25.
//

import SwiftUI
import AppKit
import Foundation
import Combine
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

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

    private var fileMonitor: DispatchSourceFileSystemObject?
    private var currentMonitoredDirectory: URL?

    let commandTildeURL: URL

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.commandTildeURL = homeDirectory.appendingPathComponent("CommandTilde")
    }

    func setupCommandTildeFolder() {
        if !FileManager.default.fileExists(atPath: commandTildeURL.path) {
            do {
                try FileManager.default.createDirectory(at: commandTildeURL, withIntermediateDirectories: true)
                print("✅ Created CommandTilde directory at: \(commandTildeURL.path)")

                // Create some initial subdirectories as examples
                let exampleDirs = ["Documents", "Downloads", "Screenshots"]
                for dirName in exampleDirs {
                    let dirURL = commandTildeURL.appendingPathComponent(dirName)
                    if !FileManager.default.fileExists(atPath: dirURL.path) {
                        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: false)
                    }
                }
            } catch {
                print("❌ Failed to create CommandTilde directory: \(error)")
            }
        } else {
            print("✅ CommandTilde directory already exists at: \(commandTildeURL.path)")
        }
    }

    func loadItems(at directory: URL) {
        isLoading = true

        // Stop monitoring previous directory
        stopMonitoring()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey, .typeIdentifierKey],
                    options: [.skipsHiddenFiles]
                )

                let fileSystemItems = contents.compactMap { url -> FileSystemItem? in
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

                    do {
                        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .typeIdentifierKey])
                        let lastModified = resourceValues.contentModificationDate

                        let icon = self.generateIcon(
                            for: url,
                            typeIdentifier: resourceValues.typeIdentifier,
                            isDirectory: isDirectory.boolValue
                        )
                        icon.size = NSSize(width: 64, height: 64)

                        return FileSystemItem(
                            name: url.lastPathComponent,
                            icon: icon,
                            url: url,
                            isDirectory: isDirectory.boolValue,
                            lastModified: lastModified
                        )
                    } catch {
                        print("⚠️ Could not read metadata for: \(url.lastPathComponent)")
                        let icon = self.generateIcon(for: url, typeIdentifier: nil, isDirectory: isDirectory.boolValue)
                        icon.size = NSSize(width: 64, height: 64)

                        return FileSystemItem(
                            name: url.lastPathComponent,
                            icon: icon,
                            url: url,
                            isDirectory: isDirectory.boolValue,
                            lastModified: nil
                        )
                    }
                }

                // Sort directories first, then files, both alphabetically
                let sortedItems = fileSystemItems.sorted { first, second in
                    if first.isDirectory && !second.isDirectory {
                        return true
                    } else if !first.isDirectory && second.isDirectory {
                        return false
                    } else {
                        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                    }
                }

                DispatchQueue.main.async {
                    self.items = sortedItems
                    self.isLoading = false

                    // Start monitoring this directory
                    self.startMonitoring(directory: directory)
                }

            } catch {
                print("❌ Error loading directory contents: \(error)")
                DispatchQueue.main.async {
                    self.items = []
                    self.isLoading = false
                }
            }
        }
    }

    private func startMonitoring(directory: URL) {
        guard directory != currentMonitoredDirectory else { return }

        currentMonitoredDirectory = directory

        do {
            let fileDescriptor = open(directory.path, O_EVTONLY)
            guard fileDescriptor != -1 else {
                print("❌ Could not open directory for monitoring: \(directory.path)")
                return
            }

            fileMonitor = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: DispatchQueue.global(qos: .background))

            fileMonitor?.setEventHandler { [weak self] in
                DispatchQueue.main.async {
                    print("📁 Directory changed, reloading...")
                    self?.loadItems(at: directory)
                }
            }

            fileMonitor?.setCancelHandler {
                close(fileDescriptor)
            }

            fileMonitor?.resume()
            print("👀 Started monitoring directory: \(directory.path)")

        } catch {
            print("❌ Error setting up directory monitoring: \(error)")
        }
    }

    private func stopMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
        currentMonitoredDirectory = nil
    }

    private func generateIcon(for url: URL, typeIdentifier: String?, isDirectory: Bool) -> NSImage {
        if isDirectory {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 64, height: 64)
            return icon
        }

        let defaultIcon = NSWorkspace.shared.icon(forFile: url.path)
        defaultIcon.size = NSSize(width: 64, height: 64)

        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]

        let isImageFile: Bool = {
            if let typeIdentifier,
               let type = UTType(typeIdentifier) {
                return type.conforms(to: .image)
            }
            return imageExtensions.contains(url.pathExtension.lowercased())
        }()

        if isImageFile, let thumbnail = generateImageThumbnail(for: url) {
            thumbnail.size = NSSize(width: 64, height: 64)
            return thumbnail
        }

        return defaultIcon
    }

    private func generateImageThumbnail(for url: URL) -> NSImage? {
        return autoreleasepool {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
            ]

            guard let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
                return nil
            }

            return NSImage(cgImage: thumbnailImage, size: NSSize(width: 64, height: 64))
        }
    }

    deinit {
        stopMonitoring()
    }
}
