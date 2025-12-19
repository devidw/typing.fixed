import Cocoa

class OverlayWindowController: NSWindowController, NSTextViewDelegate {
    var onDismiss: ((String) -> Void)?
    private var textView: NSTextView!
    private var containerView: NSView!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var draftText: String = ""  // Stores text when dismissed with Escape

    let fontSize: CGFloat = 24

    convenience init() {
        let panel = OverlayPanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.init(window: panel)

        panel.level = .mainMenu + 1
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        setupTextView(in: panel)
        setupHintLabel(in: panel)
    }

    private func setupTextView(in panel: NSPanel) {
        guard let contentView = panel.contentView else { return }
        let screenFrame = panel.frame

        // Container view that will be repositioned (no clipping)
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: 10000, height: 10000))
        containerView.wantsLayer = true

        // Create text system with fixed width container
        let textContainer = NSTextContainer(size: NSSize(width: screenFrame.width * 0.5, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: screenFrame.width * 0.5, height: 10000), textContainer: textContainer)
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.insertionPointColor = .white
        textView.delegate = self
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 0)

        // Double the line height
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.5
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle

        containerView.addSubview(textView)
        contentView.addSubview(containerView)
    }

    private func setupHintLabel(in panel: NSPanel) {
        guard let contentView = panel.contentView else { return }

        let label = NSTextField(labelWithString: "Cmd+Enter to insert | Esc to cancel")
        label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        label.textColor = NSColor.gray.withAlphaComponent(0.5)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
    }

    func show() {
        appLog("show() called")

        // Restore draft text if available, otherwise start empty
        textView.string = draftText

        if let screen = NSScreen.main {
            window?.setFrame(screen.frame, display: true)
        }

        // Activate app and focus
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        let responderResult = window?.makeFirstResponder(textView)
        appLog("makeFirstResponder result: \(String(describing: responderResult)), firstResponder: \(String(describing: window?.firstResponder))")

        // Move cursor to end of text
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        // Initial positioning
        repositionTextView()

        startInterceptingKeys()
        appLog("show() completed")
    }

    private func repositionTextView() {
        guard let windowFrame = window?.frame else { return }
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let centerX = windowFrame.width / 2
        let centerY = windowFrame.height / 2

        // Fallback line height from font (with multiplier)
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let fontLineHeight = (font.ascender - font.descender + font.leading) * 1.5

        let cursorIndex = textView.selectedRange().location
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = fontLineHeight

        let numGlyphs = layoutManager.numberOfGlyphs

        if numGlyphs == 0 {
            // Empty text - cursor at origin
            cursorX = 0
            cursorY = 0
        } else if cursorIndex >= textView.string.count {
            // Cursor at end of text
            let lastGlyphIndex = numGlyphs - 1
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            lineHeight = lineRect.height
            let glyphRange = NSRange(location: lastGlyphIndex, length: 1)
            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Check if last char is newline
            let lastChar = textView.string.last
            if lastChar == "\n" {
                // Cursor is on new line
                cursorX = 0
                cursorY = lineRect.maxY
            } else {
                cursorX = boundingRect.maxX
                cursorY = lineRect.origin.y
            }
        } else {
            // Cursor in middle of text
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorIndex)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            lineHeight = lineRect.height
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            cursorX = lineRect.origin.x + location.x
            cursorY = lineRect.origin.y
        }

        // Position container so cursor is at screen center
        let offsetX = centerX - cursorX
        let offsetY = centerY - cursorY - lineHeight / 2

        // Flip Y for NSView coordinates
        containerView.frame.origin = CGPoint(x: offsetX, y: windowFrame.height - offsetY - containerView.frame.height)
    }

    func dismiss(insertText: Bool) {
        appLog("dismiss() called, insertText: \(insertText)")
        stopInterceptingKeys()

        if insertText {
            // Proper submit - clear draft and return text
            let text = textView.string
            draftText = ""
            window?.orderOut(nil)
            onDismiss?(text)
        } else {
            // Escape - save draft for later restoration
            draftText = textView.string
            window?.orderOut(nil)
            onDismiss?("")
        }
        appLog("dismiss() completed")
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        repositionTextView()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        repositionTextView()
    }

    // MARK: - CGEventTap

    private func startInterceptingKeys() {
        appLog("startInterceptingKeys() called, existing eventTap: \(String(describing: eventTap))")

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    appLog("eventTap callback: userInfo is nil")
                    return Unmanaged.passRetained(event)
                }

                let controller = Unmanaged<OverlayWindowController>.fromOpaque(userInfo).takeUnretainedValue()

                guard controller.window?.isVisible == true else {
                    appLog("eventTap callback: window not visible, passing through")
                    return Unmanaged.passRetained(event)
                }

                // Convert to NSEvent
                guard let nsEvent = NSEvent(cgEvent: event) else {
                    appLog("eventTap callback: failed to convert CGEvent to NSEvent")
                    return Unmanaged.passRetained(event)
                }

                let keyCode = nsEvent.keyCode
                let modifiers = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                appLog("eventTap callback: keyCode=\(keyCode), modifiers=\(modifiers.rawValue)")

                // Check for Escape
                if nsEvent.keyCode == 53 {
                    appLog("eventTap: Escape pressed, dismissing")
                    DispatchQueue.main.async {
                        controller.dismiss(insertText: false)
                    }
                    return nil
                }

                // Check for Ctrl+Tab (toggle hotkey)
                if nsEvent.modifierFlags.contains(.control) && nsEvent.keyCode == 48 {
                    appLog("eventTap: Ctrl+Tab pressed, dismissing")
                    DispatchQueue.main.async {
                        controller.dismiss(insertText: false)
                    }
                    return nil
                }

                // Check for Cmd+Enter
                if nsEvent.modifierFlags.contains(.command) && nsEvent.keyCode == 36 {
                    appLog("eventTap: Cmd+Enter pressed, submitting")
                    DispatchQueue.main.async {
                        controller.dismiss(insertText: true)
                    }
                    return nil
                }

                // Forward to textView on main thread
                DispatchQueue.main.async {
                    if nsEvent.modifierFlags.contains(.command) {
                        // Handle Cmd shortcuts directly on textView
                        switch nsEvent.keyCode {
                        case 0:  // A - Select All
                            controller.textView.selectAll(nil)
                        case 6:  // Z - Undo/Redo
                            if nsEvent.modifierFlags.contains(.shift) {
                                controller.textView.undoManager?.redo()
                            } else {
                                controller.textView.undoManager?.undo()
                            }
                        case 7:  // X - Cut
                            controller.textView.cut(nil)
                        case 8:  // C - Copy
                            controller.textView.copy(nil)
                        case 9:  // V - Paste
                            controller.textView.paste(nil)
                        default:
                            break
                        }
                    } else {
                        controller.textView.keyDown(with: nsEvent)
                    }
                }

                return nil // Consume event
            },
            userInfo: userInfo
        ) else {
            appLog("ERROR: Failed to create event tap!")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            appLog("Added run loop source")
        } else {
            appLog("ERROR: Failed to create run loop source!")
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        appLog("startInterceptingKeys() completed, eventTap: \(String(describing: eventTap))")
    }

    private func stopInterceptingKeys() {
        appLog("stopInterceptingKeys() called, eventTap: \(String(describing: eventTap)), runLoopSource: \(String(describing: runLoopSource))")

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            appLog("Disabled event tap")
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            appLog("Removed run loop source")
        }

        eventTap = nil
        runLoopSource = nil
        appLog("stopInterceptingKeys() completed")
    }
}

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
