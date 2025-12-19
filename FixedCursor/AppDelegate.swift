import Cocoa
import Carbon
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var overlayWindowController: OverlayWindowController?
    var hotKeyRef: EventHotKeyRef?

    // Store previous app focus
    var previousApp: NSRunningApplication?
    var previousFocusedElement: AXUIElement?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        setupStatusItem()

        // Create Edit menu for Cmd shortcuts
        setupMainMenu()

        // Register global hotkey (Cmd+Shift+Space)
        registerGlobalHotKey()

        // Check accessibility permissions
        checkAccessibilityPermissions()

        // Create overlay window (hidden initially)
        overlayWindowController = OverlayWindowController()
        overlayWindowController?.onDismiss = { [weak self] text in
            self?.insertTextAndRestore(text)
        }
    }

    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu with standard shortcuts
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: "FixedCursor")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open (Cmd+Shift+Space)", action: #selector(toggleOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Global Hotkey

    func registerGlobalHotKey() {
        // Cmd+Shift+Space
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 49 // Space key

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4658_4358) // "FXCX"
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        // Install handler
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            appDelegate.toggleOverlay()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        // Register hotkey
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Accessibility

    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !trusted {
            print("Accessibility permissions required. Please enable in System Settings.")
        }
    }

    func storePreviousFocus() {
        // Store the frontmost app
        previousApp = NSWorkspace.shared.frontmostApplication

        // Store the focused UI element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success {
            previousFocusedElement = (focusedElement as! AXUIElement)
        }
    }

    // MARK: - Overlay Control

    @objc func toggleOverlay() {
        if overlayWindowController?.window?.isVisible == true {
            overlayWindowController?.dismiss(insertText: false)
        } else {
            storePreviousFocus()
            overlayWindowController?.show()
        }
    }

    func insertTextAndRestore(_ text: String) {
        guard !text.isEmpty else {
            restoreFocus()
            return
        }

        // Put text on clipboard
        let pasteboard = NSPasteboard.general
        let oldClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Restore focus to previous app
        restoreFocus()

        // Small delay to ensure app is focused
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Simulate Cmd+V
            self.simulatePaste()

            // Restore old clipboard after paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let old = oldClipboard {
                    pasteboard.clearContents()
                    pasteboard.setString(old, forType: .string)
                }
            }
        }
    }

    func restoreFocus() {
        previousApp?.activate(options: .activateIgnoringOtherApps)
    }

    func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
