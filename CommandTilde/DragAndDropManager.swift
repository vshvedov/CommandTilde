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
    private let appSettings: AppSettings
    private lazy var dropSound: NSSound? = {
        let possibleURLs: [URL?] = [
            Bundle.main.url(forResource: "drop", withExtension: "wav"),
            Bundle.main.url(forResource: "drop", withExtension: "wav", subdirectory: "Sounds")
        ]

        for case let url? in possibleURLs {
            if let sound = NSSound(contentsOf: url, byReference: false) {
                sound.volume = 1.0
                return sound
            }
        }

        if let fallback = NSSound(named: NSSound.Name("Glass")) {
            fallback.volume = 1.0
            return fallback
        }

        print("⚠️ Unable to locate drop sound resource in bundle")
        return nil
    }()

    init(fileSystemManager: FileSystemManager, navigationState: NavigationState, appSettings: AppSettings) {
        self.fileSystemManager = fileSystemManager
        self.navigationState = navigationState
        self.appSettings = appSettings
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        return handleDropToDestination(providers: providers, destination: navigationState.currentPath)
    }

    func handleDropOnFolder(providers: [NSItemProvider], folder: FileSystemItem) -> Bool {
        return handleDropToDestination(providers: providers, destination: folder.url)
    }

    private func handleDropToDestination(providers: [NSItemProvider], destination: URL) -> Bool {
        print("📦 Handling drop with \(providers.count) providers")

        var handledAnyProvider = false

        for provider in providers {
            print("🔍 Available types: \(provider.registeredTypeIdentifiers)")
            let providerHandled = processProvider(provider, destination: destination)
            handledAnyProvider = handledAnyProvider || providerHandled
        }

        if !handledAnyProvider {
            print("❌ No supported data types found in providers")
        }

        return handledAnyProvider
    }

    private func processProvider(_ provider: NSItemProvider, destination: URL) -> Bool {
        let identifiers = preferredTypeIdentifiers(for: provider)
        guard !identifiers.isEmpty else {
            print("❌ Provider returned no type identifiers")
            return false
        }

        attemptLoad(provider: provider, destination: destination, typeIdentifiers: identifiers)
        return true
    }

    private func preferredTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        var seen = Set<String>()
        var identifiers: [String] = []

        func appendIfNeeded(_ identifier: String) {
            if seen.insert(identifier).inserted {
                identifiers.append(identifier)
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            appendIfNeeded(UTType.fileURL.identifier)
        }

        for identifier in provider.registeredTypeIdentifiers {
            appendIfNeeded(identifier)
        }

        appendIfNeeded(UTType.item.identifier)
        appendIfNeeded(UTType.data.identifier)
        appendIfNeeded(UTType.url.identifier)

        return identifiers
    }

    private func attemptLoad(provider: NSItemProvider, destination: URL, typeIdentifiers: [String]) {
        guard let typeIdentifier = typeIdentifiers.first else {
            print("❌ Exhausted type identifiers for provider")
            return
        }

        let remainingIdentifiers = Array(typeIdentifiers.dropFirst())

        provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _, error in
            guard let self = self else { return }

            if let url = url {
                print("✅ In-place representation for \(typeIdentifier): \(url)")
                self.copyFile(from: url, to: destination, preferredFilename: provider.suggestedName)
                return
            }

            if let error = error {
                print("⚠️ loadInPlaceFileRepresentation failed for \(typeIdentifier): \(error.localizedDescription)")
            }

            self.loadTemporaryFile(provider: provider, destination: destination, typeIdentifier: typeIdentifier, remainingIdentifiers: remainingIdentifiers)
        }
    }

    private func loadTemporaryFile(provider: NSItemProvider, destination: URL, typeIdentifier: String, remainingIdentifiers: [String]) {
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] tempURL, error in
            guard let self = self else { return }

            if let tempURL = tempURL {
                print("✅ Temporary file representation for \(typeIdentifier): \(tempURL)")
                self.copyFile(from: tempURL, to: destination, preferredFilename: provider.suggestedName)
                return
            }

            if let error = error {
                print("⚠️ loadFileRepresentation failed for \(typeIdentifier): \(error.localizedDescription)")
            }

            self.loadItemRepresentation(provider: provider, destination: destination, typeIdentifier: typeIdentifier, remainingIdentifiers: remainingIdentifiers)
        }
    }

    private func loadItemRepresentation(provider: NSItemProvider, destination: URL, typeIdentifier: String, remainingIdentifiers: [String]) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            if let error = error {
                print("⚠️ loadItem failed for \(typeIdentifier): \(error.localizedDescription)")
            }

            guard let item = item else {
                self.tryNextType(provider: provider, destination: destination, remainingIdentifiers: remainingIdentifiers)
                return
            }

            let handled = self.handleLoadedItem(item, typeIdentifier: typeIdentifier, provider: provider, destination: destination)

            if !handled {
                self.tryNextType(provider: provider, destination: destination, remainingIdentifiers: remainingIdentifiers)
            }
        }
    }

    private func tryNextType(provider: NSItemProvider, destination: URL, remainingIdentifiers: [String]) {
        guard !remainingIdentifiers.isEmpty else {
            print("❌ Could not process provider; no remaining type identifiers")
            return
        }

        attemptLoad(provider: provider, destination: destination, typeIdentifiers: remainingIdentifiers)
    }

    private func handleLoadedItem(_ item: NSSecureCoding, typeIdentifier: String, provider: NSItemProvider, destination: URL) -> Bool {
        if let url = resolveFileURL(from: item) {
            print("✅ Resolved URL for \(typeIdentifier): \(url)")
            if url.isFileURL {
                copyFile(from: url, to: destination, preferredFilename: provider.suggestedName)
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                downloadAndCopyFile(from: url, to: destination)
            } else {
                print("⚠️ Unsupported URL scheme \(url.scheme ?? "none") for item; skipping copy")
                return false
            }
            return true
        }

        if let data = item as? Data {
            print("✅ Received Data for \(typeIdentifier): \(data.count) bytes")
            let filename = provider.suggestedName ?? extractFilenameFromProvider(provider)
            if isImageType(typeIdentifier) {
                saveImageData(data, type: typeIdentifier, originalFilename: filename, to: destination)
            } else {
                saveGenericData(data, originalFilename: filename, typeIdentifier: typeIdentifier, to: destination)
            }
            return true
        }

        if let image = item as? NSImage {
            print("🌄 Received NSImage for \(typeIdentifier)")
            if let imageData = convertNSImageToData(image, type: typeIdentifier) {
                let filename = provider.suggestedName ?? extractFilenameFromProvider(provider)
                saveImageData(imageData, type: typeIdentifier, originalFilename: filename, to: destination)
                return true
            }
        }

        if let string = item as? String {
            print("📝 Received String for \(typeIdentifier)")
            if let url = URL(string: string), url.scheme != nil {
                if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
                    downloadAndCopyFile(from: url, to: destination)
                } else {
                    copyFile(from: url, to: destination, preferredFilename: provider.suggestedName)
                }
            } else {
                let data = Data(string.utf8)
                let filename = provider.suggestedName ?? extractFilenameFromProvider(provider) ?? "dropped_text.txt"
                saveGenericData(data, originalFilename: filename, typeIdentifier: typeIdentifier, to: destination)
            }
            return true
        }

        print("⚠️ Could not handle item of type \(type(of: item)) for identifier \(typeIdentifier)")
        return false
    }

    private func resolveFileURL(from item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let path = item as? String {
            if path.hasPrefix("file://"), let url = URL(string: path) {
                return url
            }
            return URL(fileURLWithPath: path)
        }

        if let nsURL = item as? NSURL {
            return nsURL as URL
        }

        return nil
    }

    private func isImageType(_ typeIdentifier: String) -> Bool {
        if let type = UTType(typeIdentifier) {
            return type.conforms(to: .image)
        }

        let knownImageTypes: Set<String> = [
            "public.image",
            "public.png",
            "public.jpeg",
            "com.compuserve.gif",
            "public.tiff",
            "public.heic",
            "public.heif",
            "org.webmproject.webp",
            "public.webp"
        ]

        return knownImageTypes.contains(typeIdentifier)
    }

    private func copyFile(from sourceURL: URL, to destinationDirectory: URL, preferredFilename: String? = nil) {
        let preferredName = preferredFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        var fileName = (preferredName?.isEmpty == false ? preferredName! : sourceURL.lastPathComponent)
        fileName = (fileName as NSString).lastPathComponent

        if fileName.isEmpty {
            fileName = sourceURL.lastPathComponent.isEmpty ? "dropped_file" : sourceURL.lastPathComponent
        }

        let destinationURL = destinationDirectory.appendingPathComponent(fileName)

        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()

        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
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

            try FileManager.default.copyItem(at: sourceURL, to: finalDestinationURL)
            print("✅ Copied file to: \(finalDestinationURL.path)")

            // Refresh the current directory view on the main queue to keep UI updates predictable
            DispatchQueue.main.async {
                self.fileSystemManager.loadItems(at: self.navigationState.currentPath)
                self.playDropFeedback()
            }

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

                fileName = (fileName as NSString).lastPathComponent
                if fileName.isEmpty {
                    fileName = "downloaded_file"
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
                    DispatchQueue.main.async {
                        self.fileSystemManager.loadItems(at: self.navigationState.currentPath)
                        self.playDropFeedback()
                    }

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

        let sanitizedName = (fileName as NSString).lastPathComponent
        let destinationURL = destinationDirectory.appendingPathComponent(sanitizedName)

        // Check if file already exists and create unique name if needed
        var finalDestinationURL = destinationURL
        var counter = 1

        while FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            let baseURL = URL(fileURLWithPath: sanitizedName)
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

            DispatchQueue.main.async {
                self.fileSystemManager.loadItems(at: self.navigationState.currentPath)
                self.playDropFeedback()
            }

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

    private func saveGenericData(_ data: Data, originalFilename: String?, typeIdentifier: String?, to destinationDirectory: URL) {
        let trimmedName = originalFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        var fileName = (trimmedName?.isEmpty == false ? trimmedName! : "dropped_file")

        if !fileName.contains("."), let typeIdentifier, let type = UTType(typeIdentifier), let ext = type.preferredFilenameExtension {
            fileName.append(".\(ext)")
        }

        fileName = (fileName as NSString).lastPathComponent

        if fileName.isEmpty {
            fileName = "dropped_file"
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
            print("✅ Saved generic data to: \(finalDestinationURL.path)")

            DispatchQueue.main.async {
                self.fileSystemManager.loadItems(at: self.navigationState.currentPath)
                self.playDropFeedback()
            }

        } catch {
            print("❌ Failed to save generic data: \(error)")
        }
    }

    private func playDropFeedback() {
        let playSound: () -> Void = { [weak self] in
            guard let self = self else { return }
            guard self.appSettings.playDropSound else { return }

            self.dropSound?.stop()
            self.dropSound?.currentTime = 0
            if self.dropSound?.play() != true {
                print("⚠️ Failed to play drop sound")
            }
        }

        if Thread.isMainThread {
            playSound()
        } else {
            DispatchQueue.main.async(execute: playSound)
        }
    }
}
