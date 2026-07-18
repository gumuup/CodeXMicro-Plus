import Foundation

enum ProcessOutputReader {
    static func run(executableURL: URL, arguments: [String]) -> (data: Data, status: Int32)? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Drain stdout while the child is running. Waiting first can deadlock once
            // the child fills the pipe buffer with a large query result.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (data, process.terminationStatus)
        } catch {
            return nil
        }
    }
}
