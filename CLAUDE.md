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
  - App title and description
  - List of subdirectories from CommandTilde home folder
  - Refresh button to reload directory contents

### Key Technical Details

- **Global Hotkey**: Uses NSEvent monitors to capture Command+` system-wide
- **Accessibility**: Requires accessibility permissions for global hotkey functionality
- **Directory Management**: Uses FileManager to access user's home directory
- **UI Framework**: SwiftUI with NSHostingController for popover content
- **App Behavior**: Configured as `.accessory` to hide from dock and run in background
- **Data Storage**: Creates and manages "CommandTilde" folder in user's home directory (~)

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

## Development Notes

- The app uses modern Swift concurrency features with MainActor isolation
- SwiftUI previews are enabled for UI development
- The status bar icon displays "⌘~" with monospaced font
- Popover dimensions are fixed at 500x300 pixels
- Global event monitoring requires accessibility permissions which are requested at launch
- CommandTilde folder creation happens automatically on first launch
- The app will display all subdirectories found in ~/CommandTilde/
- Directory listing refreshes automatically when popover opens and can be manually refreshed
- App runs without sandboxing to allow direct home directory access