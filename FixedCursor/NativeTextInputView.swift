import Cocoa
import Carbon

// MARK: - Native Text Input View using NSTextInputClient

class NativeTextInputView: NSView, NSTextInputClient {

    // Text storage
    private var textStorage = NSTextStorage()
    private var selectedRange_ = NSRange(location: 0, length: 0)
    private var markedRange_ = NSRange(location: NSNotFound, length: 0)

    // Callbacks
    var onTextChange: ((String, Int) -> Void)?  // (text, cursorPosition)
    var onEscape: (() -> Void)?
    var onSubmit: (() -> Void)?

    // For cursor position calculation
    var cursorIndex: Int {
        return selectedRange_.location
    }

    var text: String {
        return textStorage.string
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextStorage()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextStorage()
    }

    private func setupTextStorage() {
        textStorage = NSTextStorage(string: "")
    }

    func clear() {
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: "")
        selectedRange_ = NSRange(location: 0, length: 0)
        markedRange_ = NSRange(location: NSNotFound, length: 0)
        notifyTextChange()
    }

    private func notifyTextChange() {
        onTextChange?(textStorage.string, selectedRange_.location)
    }

    // MARK: - NSResponder

    override func keyDown(with event: NSEvent) {
        // Check for Escape
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        // Check for Cmd+Enter
        if event.modifierFlags.contains(.command) && event.keyCode == 36 {
            onSubmit?()
            return
        }

        // Let the input context handle everything else natively
        if inputContext?.handleEvent(event) != true {
            // If input context didn't handle it, pass to super
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        inputContext?.handleEvent(event)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let insertString: String
        if let str = string as? String {
            insertString = str
        } else if let attrStr = string as? NSAttributedString {
            insertString = attrStr.string
        } else {
            return
        }

        // Clear marked text
        if markedRange_.location != NSNotFound {
            textStorage.replaceCharacters(in: markedRange_, with: "")
            selectedRange_.location = markedRange_.location
            markedRange_ = NSRange(location: NSNotFound, length: 0)
        }

        // Determine replacement range
        var actualRange = replacementRange
        if actualRange.location == NSNotFound {
            actualRange = selectedRange_
        }

        // Insert the text
        textStorage.replaceCharacters(in: actualRange, with: insertString)
        selectedRange_ = NSRange(location: actualRange.location + insertString.count, length: 0)

        notifyTextChange()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let markedString: String
        if let str = string as? String {
            markedString = str
        } else if let attrStr = string as? NSAttributedString {
            markedString = attrStr.string
        } else {
            return
        }

        var actualRange = replacementRange
        if actualRange.location == NSNotFound {
            if markedRange_.location != NSNotFound {
                actualRange = markedRange_
            } else {
                actualRange = selectedRange_
            }
        }

        textStorage.replaceCharacters(in: actualRange, with: markedString)
        markedRange_ = NSRange(location: actualRange.location, length: markedString.count)
        selectedRange_ = NSRange(location: markedRange_.location + selectedRange.location, length: selectedRange.length)

        notifyTextChange()
    }

    func unmarkText() {
        markedRange_ = NSRange(location: NSNotFound, length: 0)
        notifyTextChange()
    }

    func selectedRange() -> NSRange {
        return selectedRange_
    }

    func markedRange() -> NSRange {
        return markedRange_
    }

    func hasMarkedText() -> Bool {
        return markedRange_.location != NSNotFound && markedRange_.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        if clampedRange.length == 0 {
            return nil
        }
        actualRange?.pointee = clampedRange
        return textStorage.attributedSubstring(from: clampedRange)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.underlineStyle, .foregroundColor, .backgroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window = self.window, let screen = window.screen else {
            return .zero
        }

        let screenCenter = NSPoint(
            x: screen.frame.midX,
            y: screen.frame.midY
        )

        return NSRect(x: screenCenter.x, y: screenCenter.y - 20, width: 1, height: 20)
    }

    func characterIndex(for point: NSPoint) -> Int {
        return selectedRange_.location
    }

    func attributedString() -> NSAttributedString {
        return NSAttributedString(attributedString: textStorage)
    }

    // MARK: - Standard Edit Actions

    override func doCommand(by selector: Selector) {
        if responds(to: selector) {
            perform(selector, with: nil)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        if selectedRange_.length > 0 {
            textStorage.replaceCharacters(in: selectedRange_, with: "")
            selectedRange_ = NSRange(location: selectedRange_.location, length: 0)
        } else if selectedRange_.location > 0 {
            let deleteRange = NSRange(location: selectedRange_.location - 1, length: 1)
            textStorage.replaceCharacters(in: deleteRange, with: "")
            selectedRange_.location -= 1
        }
        notifyTextChange()
    }

    override func deleteForward(_ sender: Any?) {
        if selectedRange_.length > 0 {
            textStorage.replaceCharacters(in: selectedRange_, with: "")
            selectedRange_ = NSRange(location: selectedRange_.location, length: 0)
        } else if selectedRange_.location < textStorage.length {
            let deleteRange = NSRange(location: selectedRange_.location, length: 1)
            textStorage.replaceCharacters(in: deleteRange, with: "")
        }
        notifyTextChange()
    }

    override func deleteWordBackward(_ sender: Any?) {
        if selectedRange_.location == 0 { return }

        let text = textStorage.string as NSString
        var wordStart = selectedRange_.location

        while wordStart > 0 {
            let char = text.character(at: wordStart - 1)
            if !CharacterSet.whitespaces.contains(UnicodeScalar(char)!) {
                break
            }
            wordStart -= 1
        }

        while wordStart > 0 {
            let char = text.character(at: wordStart - 1)
            if CharacterSet.whitespaces.contains(UnicodeScalar(char)!) ||
               CharacterSet.punctuationCharacters.contains(UnicodeScalar(char)!) {
                break
            }
            wordStart -= 1
        }

        let deleteRange = NSRange(location: wordStart, length: selectedRange_.location - wordStart)
        textStorage.replaceCharacters(in: deleteRange, with: "")
        selectedRange_ = NSRange(location: wordStart, length: 0)
        notifyTextChange()
    }

    override func deleteWordForward(_ sender: Any?) {
        if selectedRange_.location >= textStorage.length { return }

        let text = textStorage.string as NSString
        var wordEnd = selectedRange_.location

        while wordEnd < textStorage.length {
            let char = text.character(at: wordEnd)
            if CharacterSet.whitespaces.contains(UnicodeScalar(char)!) ||
               CharacterSet.punctuationCharacters.contains(UnicodeScalar(char)!) {
                break
            }
            wordEnd += 1
        }

        while wordEnd < textStorage.length {
            let char = text.character(at: wordEnd)
            if !CharacterSet.whitespaces.contains(UnicodeScalar(char)!) {
                break
            }
            wordEnd += 1
        }

        let deleteRange = NSRange(location: selectedRange_.location, length: wordEnd - selectedRange_.location)
        textStorage.replaceCharacters(in: deleteRange, with: "")
        notifyTextChange()
    }

    override func deleteToBeginningOfLine(_ sender: Any?) {
        let text = textStorage.string as NSString
        var lineStart = selectedRange_.location

        while lineStart > 0 && text.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }

        let deleteRange = NSRange(location: lineStart, length: selectedRange_.location - lineStart)
        textStorage.replaceCharacters(in: deleteRange, with: "")
        selectedRange_ = NSRange(location: lineStart, length: 0)
        notifyTextChange()
    }

    override func deleteToEndOfLine(_ sender: Any?) {
        let text = textStorage.string as NSString
        var lineEnd = selectedRange_.location

        while lineEnd < textStorage.length && text.character(at: lineEnd) != 0x0A {
            lineEnd += 1
        }

        let deleteRange = NSRange(location: selectedRange_.location, length: lineEnd - selectedRange_.location)
        textStorage.replaceCharacters(in: deleteRange, with: "")
        notifyTextChange()
    }

    override func moveLeft(_ sender: Any?) {
        if selectedRange_.length > 0 {
            selectedRange_ = NSRange(location: selectedRange_.location, length: 0)
        } else if selectedRange_.location > 0 {
            selectedRange_.location -= 1
        }
        notifyTextChange()
    }

    override func moveRight(_ sender: Any?) {
        if selectedRange_.length > 0 {
            selectedRange_ = NSRange(location: selectedRange_.location + selectedRange_.length, length: 0)
        } else if selectedRange_.location < textStorage.length {
            selectedRange_.location += 1
        }
        notifyTextChange()
    }

    override func moveUp(_ sender: Any?) {
        let (row, col) = rowColFromIndex(selectedRange_.location)
        if row > 0 {
            let newIndex = indexFromRowCol(row: row - 1, col: col)
            selectedRange_ = NSRange(location: newIndex, length: 0)
        }
        notifyTextChange()
    }

    override func moveDown(_ sender: Any?) {
        let lines = textStorage.string.components(separatedBy: "\n")
        let (row, col) = rowColFromIndex(selectedRange_.location)
        if row < lines.count - 1 {
            let newIndex = indexFromRowCol(row: row + 1, col: col)
            selectedRange_ = NSRange(location: newIndex, length: 0)
        }
        notifyTextChange()
    }

    override func moveWordLeft(_ sender: Any?) {
        selectedRange_.location = wordBoundaryBackward(from: selectedRange_.location)
        selectedRange_.length = 0
        notifyTextChange()
    }

    override func moveWordRight(_ sender: Any?) {
        selectedRange_.location = wordBoundaryForward(from: selectedRange_.location)
        selectedRange_.length = 0
        notifyTextChange()
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        let text = textStorage.string as NSString
        var lineStart = selectedRange_.location

        while lineStart > 0 && text.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }

        selectedRange_ = NSRange(location: lineStart, length: 0)
        notifyTextChange()
    }

    override func moveToEndOfLine(_ sender: Any?) {
        let text = textStorage.string as NSString
        var lineEnd = selectedRange_.location

        while lineEnd < textStorage.length && text.character(at: lineEnd) != 0x0A {
            lineEnd += 1
        }

        selectedRange_ = NSRange(location: lineEnd, length: 0)
        notifyTextChange()
    }

    override func moveToBeginningOfDocument(_ sender: Any?) {
        selectedRange_ = NSRange(location: 0, length: 0)
        notifyTextChange()
    }

    override func moveToEndOfDocument(_ sender: Any?) {
        selectedRange_ = NSRange(location: textStorage.length, length: 0)
        notifyTextChange()
    }

    // MARK: - Selection Movement

    override func moveLeftAndModifySelection(_ sender: Any?) {
        if selectedRange_.location > 0 {
            selectedRange_.location -= 1
            selectedRange_.length += 1
        }
        notifyTextChange()
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
        if selectedRange_.location + selectedRange_.length < textStorage.length {
            selectedRange_.length += 1
        }
        notifyTextChange()
    }

    override func moveWordLeftAndModifySelection(_ sender: Any?) {
        let newLoc = wordBoundaryBackward(from: selectedRange_.location)
        let diff = selectedRange_.location - newLoc
        selectedRange_.location = newLoc
        selectedRange_.length += diff
        notifyTextChange()
    }

    override func moveWordRightAndModifySelection(_ sender: Any?) {
        let endPos = selectedRange_.location + selectedRange_.length
        let newEnd = wordBoundaryForward(from: endPos)
        selectedRange_.length = newEnd - selectedRange_.location
        notifyTextChange()
    }

    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        let text = textStorage.string as NSString
        var lineStart = selectedRange_.location

        while lineStart > 0 && text.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }

        selectedRange_.length += selectedRange_.location - lineStart
        selectedRange_.location = lineStart
        notifyTextChange()
    }

    override func moveToEndOfLineAndModifySelection(_ sender: Any?) {
        let text = textStorage.string as NSString
        var lineEnd = selectedRange_.location + selectedRange_.length

        while lineEnd < textStorage.length && text.character(at: lineEnd) != 0x0A {
            lineEnd += 1
        }

        selectedRange_.length = lineEnd - selectedRange_.location
        notifyTextChange()
    }

    override func selectAll(_ sender: Any?) {
        selectedRange_ = NSRange(location: 0, length: textStorage.length)
        notifyTextChange()
    }

    // MARK: - Edit Commands

    override func insertNewline(_ sender: Any?) {
        insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    override func insertTab(_ sender: Any?) {
        insertText("\t", replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    @objc func copy(_ sender: Any?) {
        if selectedRange_.length > 0 {
            let selectedText = (textStorage.string as NSString).substring(with: selectedRange_)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
        }
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        if selectedRange_.length > 0 {
            textStorage.replaceCharacters(in: selectedRange_, with: "")
            selectedRange_ = NSRange(location: selectedRange_.location, length: 0)
            notifyTextChange()
        }
    }

    @objc func paste(_ sender: Any?) {
        if let str = NSPasteboard.general.string(forType: .string) {
            insertText(str, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    // MARK: - Helper Methods

    private func wordBoundaryBackward(from index: Int) -> Int {
        if index == 0 { return 0 }

        let text = textStorage.string as NSString
        var pos = index

        while pos > 0 && CharacterSet.whitespaces.contains(UnicodeScalar(text.character(at: pos - 1))!) {
            pos -= 1
        }

        while pos > 0 {
            let char = text.character(at: pos - 1)
            if CharacterSet.whitespaces.contains(UnicodeScalar(char)!) ||
               CharacterSet.punctuationCharacters.contains(UnicodeScalar(char)!) {
                break
            }
            pos -= 1
        }

        return pos
    }

    private func wordBoundaryForward(from index: Int) -> Int {
        if index >= textStorage.length { return textStorage.length }

        let text = textStorage.string as NSString
        var pos = index

        while pos < textStorage.length {
            let char = text.character(at: pos)
            if CharacterSet.whitespaces.contains(UnicodeScalar(char)!) ||
               CharacterSet.punctuationCharacters.contains(UnicodeScalar(char)!) {
                break
            }
            pos += 1
        }

        while pos < textStorage.length && CharacterSet.whitespaces.contains(UnicodeScalar(text.character(at: pos))!) {
            pos += 1
        }

        return pos
    }

    private func rowColFromIndex(_ index: Int) -> (row: Int, col: Int) {
        let lines = textStorage.string.components(separatedBy: "\n")
        var remaining = index
        for (row, line) in lines.enumerated() {
            if remaining <= line.count {
                return (row, remaining)
            }
            remaining -= line.count + 1
        }
        return (lines.count - 1, lines.last?.count ?? 0)
    }

    private func indexFromRowCol(row: Int, col: Int) -> Int {
        let lines = textStorage.string.components(separatedBy: "\n")
        var index = 0
        for r in 0..<min(row, lines.count) {
            index += lines[r].count + 1
        }
        if row < lines.count {
            index += min(col, lines[row].count)
        }
        return min(index, textStorage.length)
    }
}
