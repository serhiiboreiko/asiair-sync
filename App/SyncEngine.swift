import Foundation
import Darwin

private struct RsyncBinary {
    let path: String
    let supportsProgress2: Bool
}

final class SyncEngine {
    var onStatus: ((SyncRuntimeStatus) -> Void)?

    private let lock = NSLock()
    private let workerQueue = DispatchQueue(label: "asiair.sync.engine", qos: .utility)
    private let logWriter = LogWriter(fileName: "asiair-sync-app.log")
    private let rsyncBinary: RsyncBinary
    private let mountPoint: String

    private var settings: SyncSettings
    private var runtimeStatus: SyncRuntimeStatus = .initial
    private var paused = true
    private var shouldStop = false
    private var loopRunning = false
    private var currentProcess: Process?

    private let percentRegex = try! NSRegularExpression(pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)%"#)
    private let speedRegex = try! NSRegularExpression(
        pattern: #"([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?\s*(?:[kmgtpe]?i?b/s|bytes/sec))"#,
        options: [.caseInsensitive]
    )
    private let filesRemainingRegex = try! NSRegularExpression(
        pattern: #"(?:to|ir)-chk=([0-9,]+)(?:/([0-9,]+))?"#,
        options: [.caseInsensitive]
    )
    private let ansiEscapeRegex = try! NSRegularExpression(pattern: #"\x{1B}\[[0-9;?]*[ -/]*[@-~]"#)

    init(initialSettings: SyncSettings) {
        self.settings = initialSettings.normalized
        self.mountPoint = SyncEngine.makeDefaultMountPoint()
        self.rsyncBinary = SyncEngine.detectRsyncBinary()

        if initialSettings.isConfigured {
            runtimeStatus = SyncRuntimeStatus(phase: .paused, message: "Paused", progressPercent: 0, transferSpeed: nil, filesLeftToDownload: 0, localFitsCount: 0, lastSyncedAt: nil, currentFile: nil)
        } else {
            runtimeStatus = .initial
        }

        log("Detected rsync binary at \(rsyncBinary.path), progress2 support: \(rsyncBinary.supportsProgress2)")
        startLoopIfNeeded()
    }

    deinit {
        stop()
    }

    func updateSettings(_ newSettings: SyncSettings) {
        let normalized = newSettings.normalized
        lock.withLock {
            settings = normalized
        }

        log("Updated settings host=\(normalized.host) share=\(normalized.shareName) interval=\(normalized.syncIntervalSeconds)s delete=\(normalized.deleteRemovedFiles)")

        if !normalized.isConfigured {
            setPaused(true)
            updateRuntimeStatus {
                $0.phase = .notConfigured
                $0.message = "Complete setup to start syncing"
                $0.progressPercent = 0
                $0.transferSpeed = nil
                $0.filesLeftToDownload = 0
                $0.localFitsCount = 0
                $0.currentFile = nil
            }
            return
        }

        let localCount = countFitsFiles(in: normalized.destinationPath)
        updateRuntimeStatus {
            $0.localFitsCount = localCount
        }
    }

    func setPaused(_ shouldPause: Bool) {
        let processToTerminate: Process? = lock.withLock {
            paused = shouldPause
            return shouldPause ? currentProcess : nil
        }

        if shouldPause {
            terminateProcess(processToTerminate, context: "pause")
            updateRuntimeStatus {
                if settings.isConfigured {
                    $0.phase = .paused
                    $0.message = "Paused"
                    $0.transferSpeed = nil
                } else {
                    $0.phase = .notConfigured
                    $0.message = "Complete setup to start syncing"
                    $0.transferSpeed = nil
                }
            }
            log("Paused sync")
        } else {
            updateRuntimeStatus {
                if settings.isConfigured {
                    if $0.phase != .syncing {
                        $0.phase = .idle
                        $0.message = "Waiting for next sync cycle"
                        $0.transferSpeed = nil
                    }
                } else {
                    $0.phase = .notConfigured
                    $0.message = "Complete setup to start syncing"
                    $0.transferSpeed = nil
                }
            }
            log("Resumed sync")
        }
    }

    func stop() {
        let processToTerminate: Process? = lock.withLock {
            shouldStop = true
            return currentProcess
        }
        terminateProcess(processToTerminate, context: "stop")
    }

    private func startLoopIfNeeded() {
        let shouldStart: Bool = lock.withLock {
            if loopRunning {
                return false
            }
            loopRunning = true
            return true
        }

        guard shouldStart else { return }

        workerQueue.async { [weak self] in
            self?.runLoop()
        }
    }

    private func runLoop() {
        log("Sync loop started")

        while true {
            let snapshot: (shouldStop: Bool, paused: Bool, settings: SyncSettings) = lock.withLock {
                (shouldStop, paused, settings)
            }

            if snapshot.shouldStop {
                break
            }

            if !snapshot.settings.isConfigured {
                updateRuntimeStatus {
                    $0.phase = .notConfigured
                    $0.message = "Complete setup to start syncing"
                    $0.progressPercent = 0
                    $0.transferSpeed = nil
                    $0.filesLeftToDownload = 0
                    $0.localFitsCount = 0
                    $0.currentFile = nil
                }
                sleepInterruptible(seconds: 1)
                continue
            }

            if snapshot.paused {
                updateRuntimeStatus {
                    $0.phase = .paused
                    $0.message = "Paused"
                    $0.transferSpeed = nil
                }
                sleepInterruptible(seconds: 0.5)
                continue
            }

            runSyncCycle(using: snapshot.settings)
            sleepInterruptible(seconds: Double(max(snapshot.settings.syncIntervalSeconds, 1)))
        }

        lock.withLock {
            loopRunning = false
            currentProcess = nil
        }

        log("Sync loop stopped")
    }

    private func runSyncCycle(using settings: SyncSettings) {
        updateRuntimeStatus {
            $0.phase = .syncing
            $0.message = "Mounting SMB share..."
            $0.progressPercent = 0
            $0.transferSpeed = nil
            $0.filesLeftToDownload = 0
            $0.currentFile = nil
        }

        do {
            try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: settings.destinationPath, withIntermediateDirectories: true)
        } catch {
            setError("Failed to prepare folders: \(error.localizedDescription)")
            return
        }
        if shouldAbortCurrentCycle() {
            log("Aborting cycle before mount due to pause/stop")
            return
        }

        guard let sourceMountPath = resolveMountedSourcePath(using: settings) else {
            setError("Could not mount \(settings.host)/\(settings.shareName)")
            return
        }
        if shouldAbortCurrentCycle() {
            log("Aborting cycle after mount due to pause/stop")
            return
        }

        guard isMounted(at: sourceMountPath) else {
            setError("SMB share is not mounted")
            return
        }

        let localCountBeforeSync = countFitsFiles(in: settings.destinationPath)
        let filesLeftToDownload = countFilesLeftToDownload(using: settings, sourceMountPath: sourceMountPath)
        if shouldAbortCurrentCycle() {
            log("Aborting cycle after preflight count due to pause/stop")
            return
        }

        updateRuntimeStatus {
            $0.phase = .syncing
            $0.message = "Syncing FITS files..."
            $0.localFitsCount = localCountBeforeSync
            $0.filesLeftToDownload = filesLeftToDownload
        }

        let rc = runRsync(using: settings, sourceMountPath: sourceMountPath)

        let runtimeSnapshot: (paused: Bool, stopped: Bool) = lock.withLock {
            (paused, shouldStop)
        }
        if runtimeSnapshot.paused || runtimeSnapshot.stopped {
            return
        }

        switch rc {
        case 0, 23, 24, 35:
            let localCount = countFitsFiles(in: settings.destinationPath)
            updateRuntimeStatus {
                $0.phase = .idle
                $0.message = "Sync cycle done (rc=\(rc))"
                $0.progressPercent = 100
                $0.transferSpeed = nil
                $0.filesLeftToDownload = 0
                $0.localFitsCount = localCount
                $0.lastSyncedAt = Date()
                $0.currentFile = nil
            }
            log("Sync cycle finished successfully with rc=\(rc), local FITS files=\(localCount)")
        case 30:
            _ = forceUnmount()
            setError("Timeout (rc=30), unmounted SMB share and will retry")
        default:
            setError("rsync failed with rc=\(rc)")
        }
    }

    private func resolveMountedSourcePath(using settings: SyncSettings) -> String? {
        let remoteIdentity = remoteShareIdentity(using: settings)

        if let existingPath = mountedPathForRemote(remoteIdentity: remoteIdentity) {
            if existingPath != mountPoint {
                log("Reusing existing mounted share at \(existingPath)")
            }
            return existingPath
        }

        _ = forceUnmount()

        let remote = "//guest:@\(settings.host)/\(percentEncodedShareName(from: settings.shareName))"
        let result = runCommandCapture(executable: "/sbin/mount_smbfs", arguments: [remote, mountPoint])

        if result.status != 0 {
            log("mount_smbfs failed with rc=\(result.status): \(result.output)")

            if let existingPath = mountedPathForRemote(remoteIdentity: remoteIdentity) {
                log("mount_smbfs reported an error, but found existing mounted share at \(existingPath)")
                return existingPath
            }
            return nil
        }

        if isMounted(at: mountPoint) {
            return mountPoint
        }

        return mountedPathForRemote(remoteIdentity: remoteIdentity)
    }

    private func isMounted(at mountPath: String) -> Bool {
        let result = runCommandCapture(executable: "/sbin/mount", arguments: [])
        guard result.status == 0 else {
            return false
        }

        for rawLine in result.output.split(separator: "\n") {
            let line = String(rawLine)
            if line.contains(" on \(mountPath) (") && line.contains("smbfs") {
                return true
            }
        }

        return false
    }

    @discardableResult
    private func forceUnmount() -> Bool {
        let result = runCommandCapture(executable: "/usr/sbin/diskutil", arguments: ["unmount", "force", mountPoint])
        if result.status != 0 {
            log("diskutil unmount force returned rc=\(result.status): \(result.output)")
        }
        return result.status == 0
    }

    private func runRsync(using settings: SyncSettings, sourceMountPath: String) -> Int32 {
        var arguments: [String] = [
            "-a",
            "--stats",
            "--partial",
            "--inplace",
            "--append-verify",
            "--timeout=60",
            "--prune-empty-dirs",
            "--out-format=FILE:%n"
        ]

        arguments.append(contentsOf: fitsFilterArguments())

        if settings.deleteRemovedFiles {
            arguments.append("--delete-delay")
            arguments.append("--max-delete=5000")
        }

        if rsyncBinary.supportsProgress2 {
            arguments.append("--info=progress2")
        } else {
            arguments.append("--progress")
        }

        let source = sourceMountPath.hasSuffix("/") ? sourceMountPath : sourceMountPath + "/"
        let destination = settings.destinationPath.hasSuffix("/") ? settings.destinationPath : settings.destinationPath + "/"
        arguments.append(contentsOf: [source, destination])

        log("Running rsync from \(source) to \(destination)")

        return runProcessStreaming(executable: rsyncBinary.path, arguments: arguments) { [weak self] line in
            self?.handleRsyncOutputLine(line)
        }
    }

    private func countFilesLeftToDownload(using settings: SyncSettings, sourceMountPath: String) -> Int {
        var arguments: [String] = [
            "-a",
            "--dry-run",
            "--prune-empty-dirs",
            "--out-format=FILE:%n"
        ]

        arguments.append(contentsOf: fitsFilterArguments())

        let source = sourceMountPath.hasSuffix("/") ? sourceMountPath : sourceMountPath + "/"
        let destination = settings.destinationPath.hasSuffix("/") ? settings.destinationPath : settings.destinationPath + "/"
        arguments.append(contentsOf: [source, destination])

        let result = runCommandCapture(executable: rsyncBinary.path, arguments: arguments, trackAsCurrentProcess: true)
        guard result.status == 0 || result.status == 23 || result.status == 24 else {
            log("Could not calculate files left to download (rc=\(result.status)): \(result.output)")
            return 0
        }

        var count = 0
        for rawLine in result.output.split(separator: "\n") {
            guard rawLine.hasPrefix("FILE:") else {
                continue
            }

            let path = String(rawLine.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if isFitsFilePath(path) {
                count += 1
            }
        }

        log("Files left to download estimate: \(count)")
        return count
    }

    private func fitsFilterArguments() -> [String] {
        [
            "--include=*/",
            "--include=*.fit",
            "--include=*.fits",
            "--include=*.fz",
            "--include=*.FIT",
            "--include=*.FITS",
            "--include=*.FZ",
            "--exclude=*"
        ]
    }

    private func isFitsFilePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".fit") || lower.hasSuffix(".fits") || lower.hasSuffix(".fz")
    }

    private func mountedPathForRemote(remoteIdentity: String) -> String? {
        let result = runCommandCapture(executable: "/sbin/mount", arguments: [])
        guard result.status == 0 else {
            return nil
        }

        let prefix = "\(remoteIdentity) on "

        for rawLine in result.output.split(separator: "\n") {
            let line = String(rawLine)
            guard line.hasPrefix(prefix), line.contains(" (smbfs") else {
                continue
            }

            let start = line.index(line.startIndex, offsetBy: prefix.count)
            guard let end = line.range(of: " (", range: start..<line.endIndex)?.lowerBound else {
                continue
            }

            let path = String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }

        return nil
    }

    private func remoteShareIdentity(using settings: SyncSettings) -> String {
        "//guest:@\(settings.host)/\(percentEncodedShareName(from: settings.shareName))"
    }

    private func percentEncodedShareName(from shareName: String) -> String {
        shareName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? shareName
    }

    private func handleRsyncOutputLine(_ line: String) {
        let sanitizedLine = strippingANSIEscapeSequences(from: line)
        guard !sanitizedLine.isEmpty else {
            return
        }

        if sanitizedLine.hasPrefix("FILE:") {
            let file = String(sanitizedLine.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            updateRuntimeStatus {
                if isFitsFilePath(file), $0.filesLeftToDownload > 0 {
                    $0.filesLeftToDownload -= 1
                }
                $0.currentFile = file
            }
            return
        }

        if let percent = firstDoubleMatch(in: sanitizedLine, regex: percentRegex) {
            let bounded = min(max(percent, 0), 100)
            updateRuntimeStatus {
                $0.progressPercent = bounded
            }
        }

        if let speed = firstStringMatch(in: sanitizedLine, regex: speedRegex) {
            let normalizedSpeed = speed.replacingOccurrences(of: " ", with: "")
            updateRuntimeStatus {
                $0.transferSpeed = normalizedSpeed
            }
        }

        if let filesRemaining = firstIntMatch(in: sanitizedLine, regex: filesRemainingRegex) {
            let bounded = max(filesRemaining, 0)
            updateRuntimeStatus {
                if $0.filesLeftToDownload == 0 || bounded < $0.filesLeftToDownload {
                    $0.filesLeftToDownload = bounded
                }
            }
        }
    }

    private func runProcessStreaming(executable: String, arguments: [String], onLine: @escaping (String) -> Void) -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            log("Executable not found: \(executable)")
            return -1
        }

        let process = Process()
        let pipe = Pipe()
        let parser = StreamLineParser(onLine: onLine)
        let semaphore = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = SyncEngine.commandEnvironment()
        process.standardOutput = pipe
        process.standardError = pipe

        let fileHandle = pipe.fileHandleForReading

        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                return
            }
            parser.ingest(data)
        }

        process.terminationHandler = { [weak self] proc in
            fileHandle.readabilityHandler = nil
            parser.finish()
            self?.clearCurrentProcessIfMatching(process)
            self?.log("Process \(executable) finished with rc=\(proc.terminationStatus)")
            semaphore.signal()
        }

        do {
            try process.run()
            setCurrentProcess(process)
        } catch {
            fileHandle.readabilityHandler = nil
            parser.finish()
            clearCurrentProcessIfMatching(process)
            log("Failed to start process \(executable): \(error.localizedDescription)")
            return -1
        }

        semaphore.wait()
        return process.terminationStatus
    }

    private func runCommandCapture(executable: String, arguments: [String], trackAsCurrentProcess: Bool = false) -> (status: Int32, output: String) {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return (-1, "Executable not found: \(executable)")
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = SyncEngine.commandEnvironment()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            if trackAsCurrentProcess {
                setCurrentProcess(process)
            }
        } catch {
            if trackAsCurrentProcess {
                clearCurrentProcessIfMatching(process)
            }
            return (-1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if trackAsCurrentProcess {
            clearCurrentProcessIfMatching(process)
        }
        let text = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, text)
    }

    private func countFitsFiles(in destinationPath: String) -> Int {
        let url = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let extensions: Set<String> = ["fit", "fits", "fz"]

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()
            if extensions.contains(ext) {
                count += 1
            }
        }

        return count
    }

    private func firstIntMatch(in text: String, regex: NSRegularExpression) -> Int? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let value = text[valueRange].replacingOccurrences(of: ",", with: "")
        return Int(value)
    }

    private func firstDoubleMatch(in text: String, regex: NSRegularExpression) -> Double? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Double(text[valueRange])
    }

    private func firstStringMatch(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[valueRange])
    }

    private func setError(_ message: String) {
        updateRuntimeStatus {
            $0.phase = .error
            $0.message = message
            $0.transferSpeed = nil
            $0.filesLeftToDownload = 0
            $0.currentFile = nil
        }
        log(message)
    }

    private func setCurrentProcess(_ process: Process?) {
        lock.withLock {
            currentProcess = process
        }
    }

    private func clearCurrentProcessIfMatching(_ process: Process) {
        lock.withLock {
            if currentProcess === process {
                currentProcess = nil
            }
        }
    }

    private func shouldAbortCurrentCycle() -> Bool {
        lock.withLock {
            paused || shouldStop
        }
    }

    private func terminateProcess(_ process: Process?, context: String) {
        guard let process else { return }
        guard process.isRunning else { return }

        let pid = process.processIdentifier
        log("Terminating process pid=\(pid) for \(context)")
        process.terminate()

        let deadline = Date().addingTimeInterval(1.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            log("Process pid=\(pid) did not exit after SIGTERM, sending SIGKILL")
            _ = kill(pid, SIGKILL)
        }
    }

    private func strippingANSIEscapeSequences(from text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return ansiEscapeRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateRuntimeStatus(_ mutate: (inout SyncRuntimeStatus) -> Void) {
        let snapshot: SyncRuntimeStatus = lock.withLock {
            mutate(&runtimeStatus)
            return runtimeStatus
        }

        onStatus?(snapshot)
    }

    private func sleepInterruptible(seconds: Double) {
        var remaining = max(seconds, 0)

        while remaining > 0 {
            let chunk = min(0.5, remaining)
            Thread.sleep(forTimeInterval: chunk)
            remaining -= chunk

            let shouldBreak: Bool = lock.withLock {
                shouldStop || paused
            }

            if shouldBreak {
                break
            }
        }
    }

    private func log(_ message: String) {
        logWriter.write(message)
    }

    private static func makeDefaultMountPoint() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("ASIAIRSync/mnt", isDirectory: true).path
    }

    private static func detectRsyncBinary() -> RsyncBinary {
        let candidates = ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync", "/usr/bin/rsync"]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = commandEnvironment()

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self)

                let supportsProgress2 = output.contains("version 3.") || output.contains("version 4.")
                return RsyncBinary(path: path, supportsProgress2: supportsProgress2)
            } catch {
                continue
            }
        }

        return RsyncBinary(path: "/usr/bin/rsync", supportsProgress2: false)
    }

    private static func commandEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return env
    }
}

private final class StreamLineParser {
    private let lock = NSLock()
    private var buffer = ""
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func ingest(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")

        var completedLines: [String] = []

        lock.withLock {
            buffer.append(normalized)

            while let range = buffer.range(of: "\n") {
                let raw = String(buffer[..<range.lowerBound])
                buffer = String(buffer[range.upperBound...])

                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    completedLines.append(line)
                }
            }
        }

        for line in completedLines {
            onLine(line)
        }
    }

    func finish() {
        var finalLine: String?

        lock.withLock {
            let line = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                finalLine = line
            }
            buffer.removeAll(keepingCapacity: false)
        }

        if let finalLine {
            onLine(finalLine)
        }
    }
}

private final class LogWriter {
    private let lock = NSLock()
    private let fileURL: URL

    init(fileName: String) {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(fileName)
    }

    func write(_ message: String) {
        let timestamp = Self.formatter.string(from: Date())
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        lock.withLock {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                return
            }

            defer { try? handle.close() }

            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                return
            }
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension NSLock {
    func withLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
