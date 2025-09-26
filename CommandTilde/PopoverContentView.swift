//
//  PopoverContentView.swift
//  CommandTilde
//
//  Created by vsh on 2025-09-25.
//

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct PopoverContentView: View {
    @ObservedObject var fileSystemManager: FileSystemManager
    @ObservedObject var navigationState: NavigationState
    private let dragAndDropManager: DragAndDropManager
    @State private var dragOverItem: String? = nil

    // Actions for header buttons
    let onSettingsPressed: () -> Void
    let onAboutPressed: () -> Void
    let onExitPressed: () -> Void

    init(fileSystemManager: FileSystemManager,
         navigationState: NavigationState,
         appSettings: AppSettings,
         onSettingsPressed: @escaping () -> Void = {},
         onAboutPressed: @escaping () -> Void = {},
         onExitPressed: @escaping () -> Void = {}) {
        self.fileSystemManager = fileSystemManager
        self.navigationState = navigationState
        self.dragAndDropManager = DragAndDropManager(fileSystemManager: fileSystemManager, navigationState: navigationState, appSettings: appSettings)
        self.onSettingsPressed = onSettingsPressed
        self.onAboutPressed = onAboutPressed
        self.onExitPressed = onExitPressed
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            Divider()
            contentView
        }
        .frame(width: 520, height: 400)
        .onAppear {
            fileSystemManager.loadItems(at: navigationState.currentPath)
        }
        .onChange(of: navigationState.currentPath) { _, newPath in
            fileSystemManager.loadItems(at: newPath)
        }
        .onDrop(of: [.fileURL, .image, .url, .data, .item], isTargeted: nil) { providers in
            dragAndDropManager.handleDrop(providers: providers)
        }
    }

    private var navigationHeader: some View {
        HStack {
            backButton
            Spacer()
            Text(getCurrentFolderName())
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            headerActions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            settingsButton
            aboutButton
            refreshButton
            exitButton
        }
    }

    private var backButton: some View {
        Button(action: {
            navigationState.navigateToParent()
        }) {
            Image(systemName: "arrow.left")
                .font(.system(size: 16, weight: .medium))
        }
        .disabled(!navigationState.canGoBack)
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(navigationState.canGoBack ? .primary : .gray)
    }

    private var settingsButton: some View {
        Button(action: onSettingsPressed) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(.primary)
        .help("Settings")
    }

    private var aboutButton: some View {
        Button(action: onAboutPressed) {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(.primary)
        .help("About")
    }

    private var refreshButton: some View {
        Button(action: {
            fileSystemManager.loadItems(at: navigationState.currentPath)
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(.primary)
        .help("Refresh")
    }

    private var exitButton: some View {
        Button(action: onExitPressed) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(.primary)
        .help("Exit")
    }

    private var contentView: some View {
        Group {

            if fileSystemManager.isLoading {
                loadingView
            } else if fileSystemManager.items.isEmpty {
                emptyView
            } else {
                itemsGridView
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("Empty Folder")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Drag files or folders here to organize them")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }

    private var itemsGridView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 20) {
                ForEach(fileSystemManager.items, id: \.name) { item in
                    ItemView(item: item, dragOverItem: $dragOverItem, onTap: handleItemTap, dragAndDropManager: dragAndDropManager)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
}

struct ItemView: View {
    let item: FileSystemItem
    @Binding var dragOverItem: String?
    let onTap: (FileSystemItem) -> Void
    let dragAndDropManager: DragAndDropManager

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
        }
        .frame(width: 90, height: 90)
        .background(itemBackground)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            onTap(item)
        }
        .onDrop(of: [.fileURL, .image, .url, .data, .item], isTargeted: nil) { providers in
            guard item.isDirectory else { return false }
            return dragAndDropManager.handleDropOnFolder(providers: providers, folder: item)
        }
    }

    private var itemBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.clear)
            .background(
                Group {
                    if item.isDirectory && dragOverItem == item.name {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.2))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.clear)
                    }
                }
            )
    }
}
