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
            "--skip-same"
        ])

        return TDLCommand(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL
        )
    }
}

enum TDLOutputSanitizer {
    private static let ansiExpression = try? NSRegularExpression(
        pattern: #"\u001B\[[0-?]*[ -/]*[@-~]"#
    )

    static func errorMessage(from data: Data) -> String {
        guard var value = String(data: data, encoding: .utf8) else { return "" }
        let range = NSRange(value.startIndex..., in: value)
        value = ansiExpression?.stringByReplacingMatches(in: value, range: range, withTemplate: "") ?? value

        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let summary = lines.suffix(3).joined(separator: " ")
        return String(summary.prefix(600))
    }
}

enum TDLRunResult: Equatable, Sendable {
    case completed
    case cancelled
    case failed(String)
}

private final class TDLRunContext: @unchecked Sendable {
    let errorPipe = Pipe()
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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = context.errorPipe
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        process.terminationHandler = { [weak self, context] finishedProcess in
            let errorData = context.errorPipe.fileHandleForReading.readDataToEndOfFile()
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

        try process.run()
        processes[id] = process
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
