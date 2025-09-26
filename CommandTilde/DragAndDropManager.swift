//
//  DragAndDropManager.swift
//  CommandTilde
//
//  Created by vsh on 2025-09-25.
//

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

class DragAndDropManager {
    private let fileSystemManager: FileSystemManager
    private let navigationState: NavigationState

    init(fileSystemManager: FileSystemManager, navigationState: NavigationState) {
        self.fileSystemManager = fileSystemManager
        self.navigationState = navigationState
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        return handleDropToDestination(providers: providers, destination: navigationState.currentPath)
    }

    func handleDropOnFolder(providers: [NSItemProvider], folder: FileSystemItem) -> Bool {
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
}