import Foundation

class Logger {
    static let shared = Logger()

    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.fixedcursor.logger", qos: .utility)

    private init() {
        // Log to ~/Library/Logs/FixedCursor.log
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        logFileURL = logsDir.appendingPathComponent("FixedCursor.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Create logs directory if needed
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Log startup
        log("=== FixedCursor Started ===")
    }

    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(fileName):\(line)] \(function): \(message)\n"

        queue.async {
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }

        // Also print to console for Xcode debugging
        print(entry, terminator: "")
    }

    var logPath: String {
        logFileURL.path
    }
}

// Convenience function
func appLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.log(message, file: file, function: function, line: line)
}
