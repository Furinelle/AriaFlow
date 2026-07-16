import Foundation

enum TelegramDownloadError: Error, LocalizedError {
    case invalidMessageLink(String)
    case executableNotFound
    case emptyDownloadDirectory
    case noLinks
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMessageLink:
            "仅支持复制自 Telegram 的消息链接，例如 https://t.me/channel/123。"
        case .executableNotFound:
            "找不到 tdl。请先运行 brew install telegram-downloader，并使用 tdl login -T qr 登录。"
        case .emptyDownloadDirectory:
            "Telegram 下载目录不能为空。"
        case .noLinks:
            "请至少添加一个 Telegram 消息链接。"
        case .processFailed(let message):
            message.isEmpty ? "tdl 下载失败。" : "tdl 下载失败：\(message)"
        }
    }
}

struct TelegramMessageLink: Hashable, Sendable {
    let absoluteString: String
    let messageID: String

    init(parsing rawValue: String) throws {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(),
              ["t.me", "www.t.me"].contains(host) else {
            throw TelegramDownloadError.invalidMessageLink(trimmedValue)
        }

        let pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard pathComponents.count >= 2,
              let messageID = pathComponents.last,
              Int64(messageID).map({ $0 > 0 }) == true else {
            throw TelegramDownloadError.invalidMessageLink(trimmedValue)
        }

        components.scheme = "https"
        components.host = "t.me"
        components.fragment = nil
        guard let canonicalURL = components.url else {
            throw TelegramDownloadError.invalidMessageLink(trimmedValue)
        }

        absoluteString = canonicalURL.absoluteString
        self.messageID = messageID
    }

    var displayName: String {
        "Telegram 消息 \(messageID)"
    }
}

struct TDLCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL
}

enum TDLExecutableLocator {
    private static let defaultPathCandidates = [
        "/opt/homebrew/bin/tdl",
        "/usr/local/bin/tdl",
        "/opt/homebrew/opt/telegram-downloader/bin/tdl",
        "/usr/local/opt/telegram-downloader/bin/tdl"
    ]

    static func find(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        pathCandidates: [String]? = nil
    ) -> URL? {
        var candidates: [String] = []
        if let overridePath = environment["ARIAFLOW_TDL_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            candidates.append(overridePath)
        }

        candidates.append(contentsOf: pathCandidates ?? defaultPathCandidates)
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/tdl" })
        }

        var seen = Set<String>()
        return candidates.lazy
            .map { ($0 as NSString).expandingTildeInPath }
            .filter { seen.insert($0).inserted }
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

enum TDLCommandBuilder {
    static func make(
        executableURL: URL,
        links: [TelegramMessageLink],
        downloadDirectory: String
    ) throws -> TDLCommand {
        guard !links.isEmpty else {
            throw TelegramDownloadError.noLinks
        }

        let trimmedDirectory = downloadDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDirectory.isEmpty else {
            throw TelegramDownloadError.emptyDownloadDirectory
        }

        let expandedDirectory = (trimmedDirectory as NSString).expandingTildeInPath
        let workingDirectoryURL = URL(fileURLWithPath: expandedDirectory, isDirectory: true)
        var arguments = ["dl"]
        for link in links {
            arguments.append(contentsOf: ["-u", link.absoluteString])
        }
        arguments.append(contentsOf: [
            "-d", expandedDirectory,
            "--continue",
            "--group",
            "--skip-same",
            "--disable-progress-ps"
        ])

        return TDLCommand(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL
        )
    }
}

enum DownloadDirectoryResolver {
    static func selectedPath(from url: URL) -> String? {
        guard url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func resolve(preferred: String?, fallback: String) -> String {
        let trimmedPreferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = trimmedPreferred?.isEmpty == false ? trimmedPreferred! : fallback
        let expanded = (selected as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }
}

enum TDLOutputSanitizer {
    private static let ansiExpression = try? NSRegularExpression(
        pattern: #"\u001B\[[0-?]*[ -/]*[@-~]"#
    )

    static func strippingControlSequences(from value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return ansiExpression?.stringByReplacingMatches(in: value, range: range, withTemplate: "") ?? value
    }

    static func errorMessage(from data: Data) -> String {
        guard let rawValue = String(data: data, encoding: .utf8) else { return "" }
        let value = strippingControlSequences(from: rawValue)

        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let summary = lines.suffix(3).joined(separator: " ")
        return String(summary.prefix(600))
    }
}

struct TDLProgressSnapshot: Equatable, Sendable {
    let fractionCompleted: Double
    let downloadedBytes: Int64
    let totalBytes: Int64?
    let bytesPerSecond: Int64
    let estimatedTimeRemaining: String?
}

struct TDLProgressParser {
    private struct TrackerProgress {
        let fractionCompleted: Double
        let downloadedBytes: Int64
        let totalBytes: Int64?
        let bytesPerSecond: Int64
        let estimatedTimeRemaining: String?
    }

    private static let progressExpression = try? NSRegularExpression(
        pattern: #"^(.*?)\s+([0-9]+(?:\.[0-9]+)?)%\s+\[[^\]]*\]\s+\[\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB|TB)\s+in\s+[^;\]]+(?:;\s*~?ETA:\s*([^;\]]+))?;\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB|TB)/s\]"#
    )

    private var pendingData = Data()
    private var trackers: [String: TrackerProgress] = [:]

    mutating func consume(_ data: Data) -> TDLProgressSnapshot? {
        guard !data.isEmpty else { return nil }
        pendingData.append(data)

        var latestSnapshot: TDLProgressSnapshot?
        while let newlineIndex = pendingData.firstIndex(of: 0x0A) {
            let lineData = pendingData[pendingData.startIndex..<newlineIndex]
            pendingData.removeSubrange(pendingData.startIndex...newlineIndex)
            let line = String(decoding: lineData, as: UTF8.self)
            if let snapshot = parse(line: line) {
                latestSnapshot = snapshot
            }
        }
        return latestSnapshot
    }

    private mutating func parse(line rawLine: String) -> TDLProgressSnapshot? {
        let line = TDLOutputSanitizer.strippingControlSequences(from: rawLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty,
              let expression = Self.progressExpression else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let key = capture(1, match: match, in: line)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              let percentText = capture(2, match: match, in: line),
              let percent = Double(percentText),
              let downloadedText = capture(3, match: match, in: line),
              let downloadedUnit = capture(4, match: match, in: line),
              let downloadedBytes = Self.bytes(value: downloadedText, unit: downloadedUnit),
              let speedText = capture(6, match: match, in: line),
              let speedUnit = capture(7, match: match, in: line),
              let bytesPerSecond = Self.bytes(value: speedText, unit: speedUnit) else {
            return nil
        }

        let fractionCompleted = min(max(percent / 100, 0), 1)
        let totalBytes = fractionCompleted > 0
            ? Int64((Double(downloadedBytes) / fractionCompleted).rounded())
            : nil
        let eta = capture(5, match: match, in: line)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        trackers[key] = TrackerProgress(
            fractionCompleted: fractionCompleted,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            bytesPerSecond: bytesPerSecond,
            estimatedTimeRemaining: eta?.isEmpty == false ? eta : nil
        )

        let values = Array(trackers.values)
        let downloadedTotal = values.reduce(Int64(0)) { $0 + $1.downloadedBytes }
        let speedTotal = values.reduce(Int64(0)) { $0 + $1.bytesPerSecond }
        let estimatedTotals = values.compactMap(\.totalBytes)
        let estimatedTotal = estimatedTotals.count == values.count
            ? estimatedTotals.reduce(Int64(0), +)
            : nil
        let aggregateFraction: Double
        if values.count == 1, let first = values.first {
            aggregateFraction = first.fractionCompleted
        } else if let estimatedTotal, estimatedTotal > 0 {
            aggregateFraction = Double(downloadedTotal) / Double(estimatedTotal)
        } else {
            aggregateFraction = values.isEmpty
                ? 0
                : values.reduce(0) { $0 + $1.fractionCompleted } / Double(values.count)
        }

        return TDLProgressSnapshot(
            fractionCompleted: min(max(aggregateFraction, 0), 1),
            downloadedBytes: downloadedTotal,
            totalBytes: estimatedTotal,
            bytesPerSecond: speedTotal,
            estimatedTimeRemaining: values.compactMap(\.estimatedTimeRemaining).last
        )
    }

    private func capture(_ index: Int, match: NSTextCheckingResult, in value: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let stringRange = Range(range, in: value) else {
            return nil
        }
        return String(value[stringRange])
    }

    private static func bytes(value: String, unit: String) -> Int64? {
        guard let number = Double(value) else { return nil }
        let multiplier: Double = switch unit {
        case "KB": 1_024
        case "MB": 1_024 * 1_024
        case "GB": 1_024 * 1_024 * 1_024
        case "TB": 1_024 * 1_024 * 1_024 * 1_024
        default: 1
        }
        return Int64((number * multiplier).rounded())
    }
}

enum TDLRunResult: Equatable, Sendable {
    case completed
    case cancelled
    case failed(String)
}

private final class TDLRunContext: @unchecked Sendable {
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    private let lock = NSLock()
    private var parser = TDLProgressParser()
    private var errorData = Data()
    private var lastProgressEmission = 0.0

    func consumeOutput(_ data: Data) -> TDLProgressSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let snapshot = parser.consume(data) else { return nil }

        let now = ProcessInfo.processInfo.systemUptime
        guard snapshot.fractionCompleted >= 1 || now - lastProgressEmission >= 0.2 else {
            return nil
        }
        lastProgressEmission = now
        return snapshot
    }

    func appendError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        errorData.append(data)
        if errorData.count > 64 * 1_024 {
            errorData.removeFirst(errorData.count - 64 * 1_024)
        }
        lock.unlock()
    }

    func capturedError() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return errorData
    }

    func stopReading() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
    }
}

@MainActor
final class TelegramDownloadService {
    private var processes: [String: Process] = [:]
    private var intentionallyTerminated = Set<String>()

    var isAvailable: Bool {
        TDLExecutableLocator.find() != nil
    }

    var executablePath: String? {
        TDLExecutableLocator.find()?.path
    }

    var hasRunningProcesses: Bool {
        processes.values.contains(where: \.isRunning)
    }

    func start(
        id: String,
        links: [TelegramMessageLink],
        downloadDirectory: String,
        progress: @escaping @MainActor @Sendable (TDLProgressSnapshot) -> Void = { _ in },
        completion: @escaping @MainActor @Sendable (TDLRunResult) -> Void
    ) throws {
        guard processes[id]?.isRunning != true else { return }
        guard let executableURL = TDLExecutableLocator.find() else {
            throw TelegramDownloadError.executableNotFound
        }

        let command = try TDLCommandBuilder.make(
            executableURL: executableURL,
            links: links,
            downloadDirectory: downloadDirectory
        )
        try FileManager.default.createDirectory(at: command.workingDirectoryURL, withIntermediateDirectories: true)

        let context = TDLRunContext()
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectoryURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = context.outputPipe
        process.standardError = context.errorPipe
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        context.outputPipe.fileHandleForReading.readabilityHandler = { [context] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let snapshot = context.consumeOutput(data) else { return }
            Task { @MainActor in
                progress(snapshot)
            }
        }
        context.errorPipe.fileHandleForReading.readabilityHandler = { [context] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            context.appendError(data)
        }
        process.terminationHandler = { [weak self, context] finishedProcess in
            context.stopReading()
            context.appendError(context.errorPipe.fileHandleForReading.readDataToEndOfFile())
            let errorData = context.capturedError()
            let status = finishedProcess.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processes[id] = nil
                let wasTerminated = self.intentionallyTerminated.remove(id) != nil
                if wasTerminated {
                    completion(.cancelled)
                } else if status == 0 {
                    completion(.completed)
                } else {
                    completion(.failed(TDLOutputSanitizer.errorMessage(from: errorData)))
                }
            }
        }

        do {
            try process.run()
            processes[id] = process
        } catch {
            context.stopReading()
            throw error
        }
    }

    func terminate(id: String) {
        guard let process = processes[id], process.isRunning else { return }
        intentionallyTerminated.insert(id)
        process.terminate()
    }

    func stopAll() {
        for (id, process) in processes where process.isRunning {
            intentionallyTerminated.insert(id)
            process.terminate()
        }
    }
}
