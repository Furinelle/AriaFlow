import Foundation
import Testing
@testable import AriaFlow

@Suite("Telegram Downloads")
struct TelegramDownloadServiceTests {
    @Test("accepts Telegram message links and preserves thread parameters")
    func parsesTelegramMessageLinks() throws {
        let publicLink = try TelegramMessageLink(parsing: "https://t.me/telegram/193")
        let privateLink = try TelegramMessageLink(parsing: "https://t.me/c/1697797156/151")
        let threadLink = try TelegramMessageLink(parsing: "https://t.me/opencfdchannel/4434?comment=360409")

        #expect(publicLink.absoluteString == "https://t.me/telegram/193")
        #expect(privateLink.absoluteString == "https://t.me/c/1697797156/151")
        #expect(threadLink.absoluteString == "https://t.me/opencfdchannel/4434?comment=360409")
        #expect(publicLink.displayName == "Telegram 消息 193")
    }

    @Test("rejects non-message and non-Telegram links")
    func rejectsUnsupportedLinks() {
        for value in [
            "https://example.com/channel/193",
            "https://t.me/telegram",
            "https://t.me/+invite-token",
            "magnet:?xt=urn:btih:123"
        ] {
            #expect(throws: TelegramDownloadError.self) {
                try TelegramMessageLink(parsing: value)
            }
        }
    }

    @Test("builds a direct tdl download command")
    func buildsTDLCommand() throws {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/tdl")
        let link = try TelegramMessageLink(parsing: "https://t.me/telegram/193")
        let command = try TDLCommandBuilder.make(
            executableURL: executable,
            links: [link],
            downloadDirectory: "~/Downloads/Telegram"
        )

        #expect(command.executableURL == executable)
        #expect(command.arguments == [
            "dl",
            "-u", "https://t.me/telegram/193",
            "-d", ("~/Downloads/Telegram" as NSString).expandingTildeInPath,
            "--continue",
            "--group",
            "--skip-same"
        ])
        #expect(command.workingDirectoryURL.path == ("~/Downloads/Telegram" as NSString).expandingTildeInPath)
    }

    @Test("discovers an executable supplied through the environment")
    func findsEnvironmentOverride() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appending(path: "tdl")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let found = TDLExecutableLocator.find(
            environment: ["ARIAFLOW_TDL_PATH": executable.path],
            pathCandidates: []
        )
        #expect(found?.standardizedFileURL == executable.standardizedFileURL)
    }

    @Test("sanitizes terminal control sequences from tdl errors")
    func sanitizesTDLError() {
        let value = TDLOutputSanitizer.errorMessage(
            from: Data("\u{001B}[31mnot logged in\u{001B}[0m\n".utf8)
        )
        #expect(value == "not logged in")
    }
}
