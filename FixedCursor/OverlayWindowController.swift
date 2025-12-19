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
        // Restore draft text if available, otherwise start empty
        textView.string = draftText

        if let screen = NSScreen.main {
            window?.setFrame(screen.frame, display: true)
        }

        // Activate app and focus
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)

        // Move cursor to end of text
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        // Initial positioning
        repositionTextView()

        startInterceptingKeys()
    }

    private func repositionTextView() {
        guard let windowFrame = window?.frame else { return }
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let centerX = windowFrame.width / 2
        let centerY = windowFrame.height / 2

        // Get line height from font
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHeight = font.ascender - font.descender + font.leading

        let cursorIndex = textView.selectedRange().location
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0

        let numGlyphs = layoutManager.numberOfGlyphs

        if numGlyphs == 0 {
            // Empty text - cursor at origin
            cursorX = 0
            cursorY = 0
        } else if cursorIndex >= textView.string.count {
            // Cursor at end of text
            let lastGlyphIndex = numGlyphs - 1
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
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
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }

                let controller = Unmanaged<OverlayWindowController>.fromOpaque(userInfo).takeUnretainedValue()

                guard controller.window?.isVisible == true else {
                    return Unmanaged.passRetained(event)
                }

                // Convert to NSEvent
                guard let nsEvent = NSEvent(cgEvent: event) else {
                    return Unmanaged.passRetained(event)
                }

                // Check for Escape
                if nsEvent.keyCode == 53 {
                    DispatchQueue.main.async {
                        controller.dismiss(insertText: false)
                    }
                    return nil
                }

                // Check for Cmd+Enter
                if nsEvent.modifierFlags.contains(.command) && nsEvent.keyCode == 36 {
                    DispatchQueue.main.async {
                        controller.dismiss(insertText: true)
                    }
                    return nil
                }

                // Forward to textView on main thread
                DispatchQueue.main.async {
                    // Cmd shortcuts go through menu's performKeyEquivalent
                    if nsEvent.modifierFlags.contains(.command) {
                        NSApp.mainMenu?.performKeyEquivalent(with: nsEvent)
                    } else {
                        controller.textView.keyDown(with: nsEvent)
                    }
                }

                return nil // Consume event
            },
            userInfo: userInfo
        ) else {
            print("Failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopInterceptingKeys() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }
}

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
