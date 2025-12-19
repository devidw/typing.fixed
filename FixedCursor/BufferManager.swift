import Foundation

struct Buffer: Identifiable {
    let id: UUID
    var content: String
    var cursorPosition: Int

    init(content: String = "", cursorPosition: Int = 0) {
        self.id = UUID()
        self.content = content
        self.cursorPosition = cursorPosition
    }
}

class BufferManager {
    private(set) var buffers: [Buffer] = []
    private(set) var currentIndex: Int = 0

    var activeBuffer: Buffer? {
        guard !buffers.isEmpty else { return nil }
        return buffers[currentIndex]
    }

    var bufferCount: Int {
        buffers.count
    }

    init() {
        // Start with one empty buffer
        buffers.append(Buffer())
    }

    func createBuffer() {
        guard buffers.count < 9 else { return }
        buffers.append(Buffer())
        currentIndex = buffers.count - 1
    }

    func switchToBuffer(at index: Int) {
        guard index >= 0 && index < buffers.count else { return }
        currentIndex = index
    }

    func closeCurrentBuffer() {
        guard buffers.count > 1 else { return }

        buffers.remove(at: currentIndex)
        if currentIndex >= buffers.count {
            currentIndex = buffers.count - 1
        }
    }

    func switchToNextBuffer() {
        guard buffers.count > 1 else { return }
        currentIndex = (currentIndex + 1) % buffers.count
    }

    func updateCurrentBuffer(content: String, cursorPosition: Int) {
        guard !buffers.isEmpty else { return }
        buffers[currentIndex].content = content
        buffers[currentIndex].cursorPosition = cursorPosition
    }
}
