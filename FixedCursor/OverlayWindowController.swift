import Cocoa
import Carbon

class OverlayWindowController: NSWindowController, NSTextViewDelegate {
    /// Callback when dismissing. Parameters: text to insert, completion handler (true = success, clear buffer)
    var onDismiss: ((String, @escaping (Bool) -> Void) -> Void)?
    private var textView: NSTextView!
    private var containerView: NSView!
    private var keyMonitor: Any?
    private var bufferManager = BufferManager()
    private var bufferIndicatorContainer: NSStackView!
    private var textBackdrop: NSView!
    private var textInnerShadow: NSView!
    private var indicatorBackdrop: NSView!
    private var indicatorInnerShadow: NSView!
    private var appearanceObserver: NSObjectProtocol?
    private var transparencyObserver: NSObjectProtocol?

    let fontSize: CGFloat = NSFont.systemFontSize

    private var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // Solarized colors (more saturated)
    private var foregroundColor: NSColor {
        isDarkMode
            ? NSColor(red: 0.576, green: 0.631, blue: 0.631, alpha: 1) // brighter base0
            : NSColor(red: 0.345, green: 0.431, blue: 0.459, alpha: 1) // darker base00
    }

    private var backgroundColor: NSColor {
        let base: NSColor = isDarkMode
            ? NSColor(red: 0.0, green: 0.141, blue: 0.180, alpha: 1)   // deeper teal
            : NSColor(red: 0.988, green: 0.945, blue: 0.820, alpha: 1) // warmer cream
        // Honor the macOS "Reduce transparency" accessibility setting: stay fully
        // opaque when it's enabled, otherwise let the overlay show 95% opacity.
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        return reduceTransparency ? base : base.withAlphaComponent(0.95)
    }

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
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        setupBackdrops(in: panel)
        setupTextView(in: panel)
        setupBufferIndicator(in: panel)
        setupAppearanceObserver()
        updateAppearance()
    }

    private func setupAppearanceObserver() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAppearance()
        }

        // Re-apply opacity when the "Reduce transparency" setting changes.
        transparencyObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAppearance()
        }
    }

    private func updateAppearance() {
        let fg = foregroundColor
        let bg = backgroundColor

        textView?.textColor = fg
        textView?.insertionPointColor = fg

        textBackdrop?.layer?.backgroundColor = bg.cgColor
        indicatorBackdrop?.layer?.backgroundColor = bg.cgColor

        updateBufferIndicator()
    }

    private let shadowSize: CGFloat = 12

    private func createInnerShadowView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        return container
    }

    private func updateInnerShadowFrames(_ view: NSView) {
        // Remove old sublayers
        view.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }

        let bounds = view.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }

        // Top shadow - fixed height, smooth gradient
        let topShadow = CAGradientLayer()
        topShadow.colors = [
            NSColor.black.withAlphaComponent(0.3).cgColor,
            NSColor.black.withAlphaComponent(0.15).cgColor,
            NSColor.black.withAlphaComponent(0.05).cgColor,
            NSColor.clear.cgColor
        ]
        topShadow.locations = [0, 0.15, 0.5, 1]
        topShadow.startPoint = CGPoint(x: 0.5, y: 1)
        topShadow.endPoint = CGPoint(x: 0.5, y: 0)
        topShadow.frame = CGRect(x: 0, y: bounds.height - shadowSize, width: bounds.width, height: shadowSize)
        view.layer?.addSublayer(topShadow)

        // Left shadow - fixed width, smooth gradient
        let leftShadow = CAGradientLayer()
        leftShadow.colors = [
            NSColor.black.withAlphaComponent(0.2).cgColor,
            NSColor.black.withAlphaComponent(0.1).cgColor,
            NSColor.black.withAlphaComponent(0.03).cgColor,
            NSColor.clear.cgColor
        ]
        leftShadow.locations = [0, 0.15, 0.5, 1]
        leftShadow.startPoint = CGPoint(x: 0, y: 0.5)
        leftShadow.endPoint = CGPoint(x: 1, y: 0.5)
        leftShadow.frame = CGRect(x: 0, y: 0, width: shadowSize, height: bounds.height)
        view.layer?.addSublayer(leftShadow)

        // Bottom highlight - fixed height, smooth gradient
        let bottomHighlight = CAGradientLayer()
        bottomHighlight.colors = [
            NSColor.white.withAlphaComponent(0.25).cgColor,
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor
        ]
        bottomHighlight.locations = [0, 0.15, 0.5, 1]
        bottomHighlight.startPoint = CGPoint(x: 0.5, y: 0)
        bottomHighlight.endPoint = CGPoint(x: 0.5, y: 1)
        bottomHighlight.frame = CGRect(x: 0, y: 0, width: bounds.width, height: shadowSize)
        view.layer?.addSublayer(bottomHighlight)

        // Right highlight - fixed width, smooth gradient
        let rightHighlight = CAGradientLayer()
        rightHighlight.colors = [
            NSColor.white.withAlphaComponent(0.2).cgColor,
            NSColor.white.withAlphaComponent(0.1).cgColor,
            NSColor.white.withAlphaComponent(0.03).cgColor,
            NSColor.clear.cgColor
        ]
        rightHighlight.locations = [0, 0.15, 0.5, 1]
        rightHighlight.startPoint = CGPoint(x: 1, y: 0.5)
        rightHighlight.endPoint = CGPoint(x: 0, y: 0.5)
        rightHighlight.frame = CGRect(x: bounds.width - shadowSize, y: 0, width: shadowSize, height: bounds.height)
        view.layer?.addSublayer(rightHighlight)
    }

    private func setupBackdrops(in panel: NSPanel) {
        guard let contentView = panel.contentView else { return }

        // Indicator backdrop - behind the buffer tabs
        indicatorBackdrop = NSView()
        indicatorBackdrop.wantsLayer = true
        indicatorBackdrop.layer?.cornerRadius = 8
        indicatorBackdrop.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(indicatorBackdrop)

        // Inner shadow for indicator (engraved look)
        indicatorInnerShadow = createInnerShadowView()
        indicatorInnerShadow.translatesAutoresizingMaskIntoConstraints = false
        indicatorBackdrop.addSubview(indicatorInnerShadow)
        NSLayoutConstraint.activate([
            indicatorInnerShadow.topAnchor.constraint(equalTo: indicatorBackdrop.topAnchor),
            indicatorInnerShadow.bottomAnchor.constraint(equalTo: indicatorBackdrop.bottomAnchor),
            indicatorInnerShadow.leadingAnchor.constraint(equalTo: indicatorBackdrop.leadingAnchor),
            indicatorInnerShadow.trailingAnchor.constraint(equalTo: indicatorBackdrop.trailingAnchor)
        ])
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
        textView.allowsUndo = true
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

        // Text backdrop - positioned at contentView level, updated in repositionTextView
        textBackdrop = NSView(frame: .zero)
        textBackdrop.wantsLayer = true
        textBackdrop.layer?.cornerRadius = 8

        // Inner shadow for text (engraved look)
        textInnerShadow = createInnerShadowView()
        textInnerShadow.autoresizingMask = [.width, .height]
        textBackdrop.addSubview(textInnerShadow)

        contentView.addSubview(textBackdrop)
        containerView.addSubview(textView)
        contentView.addSubview(containerView)
    }

    private func setupBufferIndicator(in panel: NSPanel) {
        guard let contentView = panel.contentView else { return }

        bufferIndicatorContainer = NSStackView()
        bufferIndicatorContainer.orientation = .horizontal
        bufferIndicatorContainer.spacing = 8
        bufferIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bufferIndicatorContainer)

        NSLayoutConstraint.activate([
            bufferIndicatorContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            bufferIndicatorContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])

        // Position indicator backdrop around the buffer tabs
        NSLayoutConstraint.activate([
            indicatorBackdrop.centerXAnchor.constraint(equalTo: bufferIndicatorContainer.centerXAnchor),
            indicatorBackdrop.centerYAnchor.constraint(equalTo: bufferIndicatorContainer.centerYAnchor),
            indicatorBackdrop.widthAnchor.constraint(equalTo: bufferIndicatorContainer.widthAnchor, constant: 24),
            indicatorBackdrop.heightAnchor.constraint(equalTo: bufferIndicatorContainer.heightAnchor, constant: 16)
        ])
    }

    private func updateBufferIndicator() {
        // Remove existing views
        for view in bufferIndicatorContainer.arrangedSubviews.reversed() {
            bufferIndicatorContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let count = bufferManager.bufferCount
        let current = bufferManager.currentIndex
        let size: CGFloat = 20

        let fg = foregroundColor

        for i in 0..<count {
            let square = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
            square.wantsLayer = true

            let label = NSTextField(frame: NSRect(x: 0, y: 0, width: size, height: size))
            label.stringValue = "\(i + 1)"
            label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            label.alignment = .center
            label.textColor = fg.withAlphaComponent(0.7)
            label.isBordered = false
            label.isEditable = false
            label.drawsBackground = false
            label.backgroundColor = .clear

            if i == current {
                square.layer?.borderColor = fg.withAlphaComponent(0.7).cgColor
                square.layer?.borderWidth = 2
            }

            square.addSubview(label)

            square.translatesAutoresizingMaskIntoConstraints = false
            label.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                square.widthAnchor.constraint(equalToConstant: size),
                square.heightAnchor.constraint(equalToConstant: size),
                label.centerXAnchor.constraint(equalTo: square.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: square.centerYAnchor)
            ])

            bufferIndicatorContainer.addArrangedSubview(square)
        }
    }

    func show() {
        appLog("show() called")

        // Restore buffer content
        textView.string = bufferManager.activeBuffer?.content ?? ""

        if let screen = NSScreen.main {
            window?.setFrame(screen.frame, display: true)
        }

        // Activate app and focus
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        let responderResult = window?.makeFirstResponder(textView)
        appLog("makeFirstResponder result: \(String(describing: responderResult)), firstResponder: \(String(describing: window?.firstResponder))")

        // Restore cursor position or move to end
        let cursorPos = bufferManager.activeBuffer?.cursorPosition ?? textView.string.count
        textView.setSelectedRange(NSRange(location: min(cursorPos, textView.string.count), length: 0))

        // Initial positioning and appearance
        updateAppearance()
        repositionTextView()

        startInterceptingKeys()
        // Activation can finish after the hotkey callback returns.
        DispatchQueue.main.async { [weak self] in
            self?.focusTextInput()
        }
        appLog("show() completed, secureInputEnabled: \(IsSecureEventInputEnabled())")
    }

    private func repositionTextView() {
        guard let windowFrame = window?.frame else { return }
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Ensure layout is complete before accessing glyphs
        layoutManager.ensureLayout(for: textContainer)

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
            let lastGlyphIndex = max(0, numGlyphs - 1)
            guard lastGlyphIndex < numGlyphs else {
                cursorX = 0
                cursorY = 0
                return
            }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            lineHeight = lineRect.height > 0 ? lineRect.height : fontLineHeight
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
            // Cursor in middle of text - safely get glyph index
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorIndex)
            guard glyphIndex < numGlyphs else {
                cursorX = 0
                cursorY = 0
                containerView.frame.origin = CGPoint(x: centerX, y: windowFrame.height - centerY - containerView.frame.height)
                return
            }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            lineHeight = lineRect.height > 0 ? lineRect.height : fontLineHeight
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            cursorX = lineRect.origin.x + location.x
            cursorY = lineRect.origin.y
        }

        // Position container so cursor is at screen center
        let offsetX = centerX - cursorX
        let offsetY = centerY - cursorY - lineHeight / 2

        // Flip Y for NSView coordinates
        containerView.frame.origin = CGPoint(x: offsetX, y: windowFrame.height - offsetY - containerView.frame.height)

        // Update text backdrop to match actual text content in screen coordinates
        let usedRect = layoutManager.usedRect(for: textContainer)
        let padding: CGFloat = 20

        // Calculate max line width based on actual text content
        var maxLineWidth: CGFloat = 0
        let glyphCount = layoutManager.numberOfGlyphs
        if glyphCount > 0 {
            var index = 0
            while index < glyphCount {
                var lineRange = NSRange()
                layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange)
                let lineBounds = layoutManager.boundingRect(forGlyphRange: lineRange, in: textContainer)
                maxLineWidth = max(maxLineWidth, lineBounds.width)
                index = NSMaxRange(lineRange)
            }
        }

        let minWidth: CGFloat = 200
        let minHeight = lineHeight + padding * 2
        let backdropWidth = max(maxLineWidth + padding * 2, minWidth)
        let backdropHeight = max(usedRect.height + padding * 2, minHeight)

        // Convert text position to contentView coordinates
        // The text starts at (0,0) in textView, which is at (0,0) in containerView
        // containerView.frame.origin gives us the offset in contentView
        let textOriginInContent = CGPoint(
            x: containerView.frame.origin.x + usedRect.origin.x,
            y: containerView.frame.origin.y + (containerView.frame.height - usedRect.origin.y - usedRect.height)
        )

        textBackdrop.frame = NSRect(
            x: textOriginInContent.x - padding,
            y: textOriginInContent.y - padding,
            width: backdropWidth,
            height: backdropHeight
        )
        textInnerShadow.frame = textBackdrop.bounds
        updateInnerShadowFrames(textInnerShadow)
    }

    // MARK: - Buffer Operations

    func createNewBuffer() {
        // Save current buffer
        bufferManager.updateCurrentBuffer(
            content: textView.string,
            cursorPosition: textView.selectedRange().location
        )
        // Create new buffer and switch to it
        bufferManager.createBuffer()
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        repositionTextView()
        updateBufferIndicator()
    }

    func closeCurrentBuffer() {
        guard bufferManager.bufferCount > 1 else { return }

        bufferManager.closeCurrentBuffer()
        // Load the new active buffer
        textView.string = bufferManager.activeBuffer?.content ?? ""
        let cursorPos = bufferManager.activeBuffer?.cursorPosition ?? 0
        textView.setSelectedRange(NSRange(location: min(cursorPos, textView.string.count), length: 0))
        repositionTextView()
        updateBufferIndicator()
    }

    func switchToNextBuffer() {
        guard bufferManager.bufferCount > 1 else { return }

        // Save current buffer
        bufferManager.updateCurrentBuffer(
            content: textView.string,
            cursorPosition: textView.selectedRange().location
        )
        // Switch to next buffer
        bufferManager.switchToNextBuffer()
        // Load the new active buffer
        textView.string = bufferManager.activeBuffer?.content ?? ""
        let cursorPos = bufferManager.activeBuffer?.cursorPosition ?? 0
        textView.setSelectedRange(NSRange(location: min(cursorPos, textView.string.count), length: 0))
        repositionTextView()
        updateBufferIndicator()
    }

    func switchToBuffer(at index: Int) {
        guard index < bufferManager.bufferCount else { return }
        guard index != bufferManager.currentIndex else { return }

        // Save current buffer
        bufferManager.updateCurrentBuffer(
            content: textView.string,
            cursorPosition: textView.selectedRange().location
        )
        // Switch to specific buffer
        bufferManager.switchToBuffer(at: index)
        // Load the new active buffer
        textView.string = bufferManager.activeBuffer?.content ?? ""
        let cursorPos = bufferManager.activeBuffer?.cursorPosition ?? 0
        textView.setSelectedRange(NSRange(location: min(cursorPos, textView.string.count), length: 0))
        repositionTextView()
        updateBufferIndicator()
    }

    func dismiss(insertText: Bool) {
        appLog("dismiss() called, insertText: \(insertText)")
        stopInterceptingKeys()

        // Save current buffer state
        bufferManager.updateCurrentBuffer(
            content: textView.string,
            cursorPosition: textView.selectedRange().location
        )

        if insertText {
            let text = textView.string
            window?.orderOut(nil)
            onDismiss?(text) { [weak self] success in
                if success {
                    // Copy to clipboard as backup before clearing
                    if !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    // Only clear buffer if insertion target was valid
                    self?.bufferManager.updateCurrentBuffer(content: "", cursorPosition: 0)
                    appLog("Buffer cleared after successful insert validation")
                } else {
                    appLog("Buffer kept - no valid text input target")
                }
            }
        } else {
            // Escape - buffer already saved above
            window?.orderOut(nil)
            onDismiss?("") { _ in }
        }
        appLog("dismiss() completed")
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        // Strip emojis to prevent CoreText crashes
        let text = textView.string
        let stripped = text.unicodeScalars.filter { scalar in
            // Keep basic ASCII, extended Latin, and common symbols
            // Exclude emoji ranges
            !(scalar.value >= 0x1F600 && scalar.value <= 0x1F64F) && // Emoticons
            !(scalar.value >= 0x1F300 && scalar.value <= 0x1F5FF) && // Misc Symbols and Pictographs
            !(scalar.value >= 0x1F680 && scalar.value <= 0x1F6FF) && // Transport and Map
            !(scalar.value >= 0x1F1E0 && scalar.value <= 0x1F1FF) && // Flags
            !(scalar.value >= 0x2600 && scalar.value <= 0x26FF) &&   // Misc symbols
            !(scalar.value >= 0x2700 && scalar.value <= 0x27BF) &&   // Dingbats
            !(scalar.value >= 0x1F900 && scalar.value <= 0x1F9FF) && // Supplemental Symbols
            !(scalar.value >= 0x1FA00 && scalar.value <= 0x1FA6F) && // Chess Symbols
            !(scalar.value >= 0x1FA70 && scalar.value <= 0x1FAFF) && // Symbols Extended-A
            !(scalar.value >= 0xFE00 && scalar.value <= 0xFE0F) &&   // Variation Selectors
            !(scalar.value >= 0x200D && scalar.value <= 0x200D)      // Zero Width Joiner
        }
        let newText = String(String.UnicodeScalarView(stripped))

        if newText != text {
            let cursorPos = textView.selectedRange().location
            textView.string = newText
            let newPos = min(cursorPos, newText.count)
            textView.setSelectedRange(NSRange(location: newPos, length: 0))
        }

        repositionTextView()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        repositionTextView()
    }

    func focusTextInput() {
        guard let window = window, window.isVisible, NSApp.isActive else { return }
        window.makeKeyAndOrderFront(nil)
        let focused = window.makeFirstResponder(textView)
        appLog("Input focus: active=\(NSApp.isActive), key=\(window.isKeyWindow), textResponder=\(focused)")
    }

    // MARK: - App-local keyboard handling

    private func startInterceptingKeys() {
        stopInterceptingKeys()
        // The overlay owns keyboard focus. A global CGEventTap can stop receiving
        // keys under Secure Event Input, even when tap creation succeeds.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.window,
                  window.isVisible, event.window === window else { return event }
            return self.handleKeyDown(event)
        }
        appLog("Started local keyboard monitor")
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags
        switch event.keyCode {
        case 53:
            appLog("Local input: Escape, dismissing")
            dismiss(insertText: false)
            return nil
        case 48 where modifiers.contains(.control):
            dismiss(insertText: false)
            return nil
        case 17 where modifiers.contains(.control):
            createNewBuffer()
            return nil
        case 13 where modifiers.contains(.control):
            closeCurrentBuffer()
            return nil
        case 36 where modifiers.contains(.command), 76 where modifiers.contains(.command):
            appLog("Local input: Command+Enter, submitting")
            dismiss(insertText: true)
            return nil
        default:
            break
        }

        if modifiers.contains(.control) {
            let numberKeyCodes: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
            if let bufferIndex = numberKeyCodes[event.keyCode] {
                switchToBuffer(at: bufferIndex)
                return nil
            }
        }

        if event.keyCode == 48 && modifiers.intersection([.control, .command, .option]).isEmpty {
            switchToNextBuffer()
            return nil
        }

        // Standard Cmd shortcuts are applied directly to the editor. This is an
        // LSUIElement app, so the Edit menu never becomes the active menu bar and
        // its key equivalents are dropped before anything can act on them.
        if modifiers.intersection([.command, .control, .option]) == [.command],
           let key = event.charactersIgnoringModifiers?.lowercased() {
            let shift = modifiers.contains(.shift)
            switch key {
            case "a" where !shift:
                textView.selectAll(nil)
                return nil
            case "c" where !shift:
                textView.copy(nil)
                return nil
            case "x" where !shift:
                textView.cut(nil)
                return nil
            case "v":
                textView.paste(nil)
                return nil
            case "z":
                if shift {
                    textView.undoManager?.redo()
                } else {
                    textView.undoManager?.undo()
                }
                return nil
            default:
                break
            }
        }

        // Keep native text input, composition, and the Edit menu in the responder
        // chain. Restore the editor if clicking the overlay moved focus away.
        if window?.firstResponder !== textView {
            window?.makeFirstResponder(textView)
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            appLog("Local input: Enter, passing to text view")
        }
        return event
    }

    private func stopInterceptingKeys() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
            appLog("Stopped local keyboard monitor")
        }
    }

}

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
