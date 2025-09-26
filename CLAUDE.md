# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CommandTilde is a macOS menu bar application built with SwiftUI that provides a global popup interface accessible via the Command+` hotkey. The app runs as an accessory (no dock icon) and presents a popover when triggered. It creates and manages a "CommandTilde" folder in the user's home directory.

## Architecture

### Core Components

- **CommandTildeApp.swift**: Main app entry point with Settings scene and command configuration
- **AppDelegate**: Handles the core application lifecycle including:
  - Status bar item creation and management
  - Global hotkey registration (Command+` on key code 50)
  - Popover presentation and behavior
  - Accessibility permissions management
  - Event monitoring (both global and local)
  - CommandTilde folder initialization
- **DirectoryManager**: Manages home directory integration:
  - Creates "CommandTilde" folder in user's home directory
  - Loads and monitors subdirectories
  - Provides observable directory list for UI updates
- **PopoverContentView**: SwiftUI view that displays:
  - Grid of subdirectories as 64x64 icons
  - Directory names below each icon
  - Refresh button to reload directory contents
  - Empty state with helpful instructions

### Key Technical Details

- **Global Hotkey**: Uses NSEvent monitors to capture Command+` system-wide
- **Accessibility**: Requires accessibility permissions for global hotkey functionality
- **Directory Management**: Uses FileManager to access user's home directory
- **File System Monitoring**: Uses DispatchSource.makeFileSystemObjectSource for real-time directory changes
- **Icon Loading**: Uses NSWorkspace.shared.icon() to get system folder icons at 64x64 resolution
- **UI Framework**: SwiftUI with NSHostingController for popover content, LazyVGrid for icon layout
- **App Behavior**: Configured as `.accessory` to hide from dock and run in background
- **Data Storage**: Creates and manages "CommandTilde" folder in user's home directory (~)
- **Click Actions**: Clicking directory icons opens them in Finder

## Development Commands

### Building and Running
```bash
# Build the project
xcodebuild -project CommandTilde.xcodeproj -scheme CommandTilde build

# Build for release
xcodebuild -project CommandTilde.xcodeproj -scheme CommandTilde -configuration Release build

# Run from Xcode (recommended for development)
# Open CommandTilde.xcodeproj in Xcode and press Cmd+R
```

### Project Configuration
- **Target**: macOS 26.0+
- **Language**: Swift 5.0
- **Bundle ID**: com.vlad.codes.CommandTilde
- **Development Team**: G29V3JRMJJ
- **Sandboxing**: Disabled to allow home directory access
- **Entitlements**: Minimal configuration for debugging
- **Popover Size**: 520x400 pixels to accommodate icon grid

## Development Notes

- The app uses modern Swift concurrency features with MainActor isolation
- SwiftUI previews are enabled for UI development
- The status bar icon displays "⌘~" with monospaced font
- Popover dimensions are fixed at 520x400 pixels to accommodate icon grid
- Global event monitoring requires accessibility permissions which are requested at launch
- CommandTilde folder creation happens automatically on first launch
- The app displays subdirectories as 64x64 icons in a 4-column grid
- Icons are loaded from system using NSWorkspace for authentic folder appearances
- Directory listing refreshes automatically via file system monitoring and manual refresh button
- Clicking folder icons opens them directly in Finder
- Real-time monitoring detects new/deleted folders without needing manual refresh
- App runs without sandboxing to allow direct home directory access