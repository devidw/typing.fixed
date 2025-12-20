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
        appLog("App launching...")

        // Create menu bar item
        setupStatusItem()

        // Create Edit menu for Cmd shortcuts
        setupMainMenu()

        // Register global hotkey (Ctrl+Tab)
        registerGlobalHotKey()

        // Check accessibility permissions
        checkAccessibilityPermissions()

        // Create overlay window (hidden initially)
        overlayWindowController = OverlayWindowController()
        overlayWindowController?.onDismiss = { [weak self] text, completion in
            self?.insertTextAndRestore(text, completion: completion)
        }

        appLog("App launched. Log file: \(Logger.shared.logPath)")
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
        menu.addItem(NSMenuItem(title: "Open (Ctrl+Tab)", action: #selector(toggleOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Global Hotkey

    func registerGlobalHotKey() {
        appLog("Registering global hotkey (Ctrl+Tab)...")

        // Ctrl+Tab
        let modifiers: UInt32 = UInt32(controlKey)
        let keyCode: UInt32 = 48 // Tab key

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4658_4358) // "FXCX"
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        // Install handler
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            appLog("Global hotkey triggered (Ctrl+Tab)")
            appDelegate.toggleOverlay()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        appLog("InstallEventHandler result: \(handlerResult)")

        // Register hotkey
        let registerResult = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        appLog("RegisterEventHotKey result: \(registerResult), hotKeyRef: \(String(describing: hotKeyRef))")
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
        let isVisible = overlayWindowController?.window?.isVisible == true
        appLog("toggleOverlay called, isVisible: \(isVisible)")

        if isVisible {
            appLog("Dismissing overlay")
            overlayWindowController?.dismiss(insertText: false)
        } else {
            appLog("Showing overlay")
            storePreviousFocus()
            overlayWindowController?.show()
        }
    }

    func insertTextAndRestore(_ text: String, completion: @escaping (Bool) -> Void) {
        guard !text.isEmpty else {
            restoreFocus()
            completion(true) // Empty text is considered success
            return
        }

        // Validate using stored element BEFORE restoring focus (no delay needed)
        guard isValidTextInputTarget() else {
            appLog("No valid text input target found - keeping buffer")
            restoreFocus()
            completion(false)
            return
        }

        appLog("Valid text input target found - proceeding with paste")
        completion(true) // Valid target, clear buffer

        // Put text on clipboard
        let pasteboard = NSPasteboard.general
        let oldClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Restore focus to previous app
        restoreFocus()

        // Small delay to ensure app is focused before paste
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

    func isValidTextInputTarget() -> Bool {
        // Use stored element - check if it's still valid and is a text input
        guard let element = previousFocusedElement else {
            appLog("isValidTextInputTarget: No previous focused element")
            return false
        }

        // Check if element still exists by getting its role
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)

        guard result == .success, let role = roleRef as? String else {
            appLog("isValidTextInputTarget: Element no longer valid (result: \(result.rawValue))")
            return false
        }

        appLog("isValidTextInputTarget: Stored element role is '\(role)'")

        // Roles that typically accept text input
        let textInputRoles = [
            "AXTextField",
            "AXTextArea",
            "AXSearchField",
            "AXComboBox"
        ]

        if textInputRoles.contains(role) {
            return true
        }

        // Also check if element is editable (for cases like terminal)
        var editableRef: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRef)
        if editableResult == .success, let editable = editableRef as? Bool, editable {
            appLog("isValidTextInputTarget: Element is editable")
            return true
        }

        appLog("isValidTextInputTarget: Not a text input target")
        return false
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
