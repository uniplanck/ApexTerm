import Foundation

public struct SSHHostProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String { alias }
    public var alias: String
    public var displayName: String?
    public var hostName: String?
    public var user: String?
    public var port: Int?
    public var identityFile: String?

    public init(
        alias: String,
        displayName: String? = nil,
        hostName: String? = nil,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil
    ) {
        self.alias = alias
        self.displayName = displayName
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
    }

    public var displayTitle: String {
        let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : alias
    }

    public var destination: String {
        let host = hostName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = (host?.isEmpty == false ? host! : alias)
        guard let user = user?.trimmingCharacters(in: .whitespacesAndNewlines),
              !user.isEmpty,
              !resolvedHost.contains("@") else {
            return resolvedHost
        }
        return "\(user)@\(resolvedHost)"
    }

    public var isInteractiveShellCandidate: Bool {
        let host = (hostName ?? alias).lowercased()
        let gitOnlyHosts = [
            "github.com",
            "ssh.github.com",
            "gitlab.com",
            "altssh.gitlab.com",
            "bitbucket.org",
            "ssh.dev.azure.com",
            "vs-ssh.visualstudio.com"
        ]
        return !gitOnlyHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

public enum SSHConfigParser {
    public static func parse(_ text: String) -> [SSHHostProfile] {
        var profiles: [SSHHostProfile] = []
        var aliases: [String] = []
        var options: [String: String] = [:]

        func flush() {
            guard !aliases.isEmpty else { return }
            for alias in aliases where !containsPattern(alias) {
                profiles.append(
                    SSHHostProfile(
                        alias: alias,
                        hostName: options["hostname"],
                        user: options["user"],
                        port: options["port"].flatMap(Int.init),
                        identityFile: options["identityfile"]
                    )
                )
            }
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.split(
                maxSplits: 1,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "host" {
                flush()
                aliases = value.split(whereSeparator: \.isWhitespace).map(String.init)
                options = [:]
            } else if !aliases.isEmpty, options[key] == nil {
                options[key] = value
            }
        }

        flush()
        return deduplicated(profiles)
    }

    private static func containsPattern(_ alias: String) -> Bool {
        alias.contains("*") || alias.contains("?") || alias.contains("!")
    }

    private static func deduplicated(_ profiles: [SSHHostProfile]) -> [SSHHostProfile] {
        var seen: Set<String> = []
        return profiles.filter { profile in
            seen.insert(profile.alias).inserted
        }
    }
}

public enum SSHCommandParser {
    public enum ParseError: Error, Equatable, LocalizedError {
        case empty
        case unsupportedExecutable
        case missingOptionValue(String)
        case invalidPort(String)
        case missingDestination
        case unterminatedQuote

        public var errorDescription: String? {
            switch self {
            case .empty:
                "SSH command is empty"
            case .unsupportedExecutable:
                "Only ssh commands can be imported"
            case let .missingOptionValue(option):
                "Missing value for \(option)"
            case let .invalidPort(value):
                "Invalid SSH port: \(value)"
            case .missingDestination:
                "SSH destination is missing"
            case .unterminatedQuote:
                "SSH command contains an unterminated quote"
            }
        }
    }

    public static func parse(_ command: String, alias preferredAlias: String? = nil) throws -> SSHHostProfile {
        let tokens = try tokenize(command)
        guard !tokens.isEmpty else { throw ParseError.empty }
        guard URL(fileURLWithPath: tokens[0]).lastPathComponent == "ssh" else {
            throw ParseError.unsupportedExecutable
        }

        var identityFile: String?
        var port: Int?
        var explicitUser: String?
        var destination: String?
        var index = 1
        let optionsWithValue: Set<String> = [
            "-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-J", "-L",
            "-m", "-O", "-o", "-Q", "-R", "-S", "-W", "-w"
        ]

        while index < tokens.count {
            let token = tokens[index]
            if token == "--" {
                index += 1
                if index < tokens.count { destination = tokens[index] }
                break
            }
            if token == "-i" || token == "-p" || token == "-l" || optionsWithValue.contains(token) {
                guard index + 1 < tokens.count else {
                    throw ParseError.missingOptionValue(token)
                }
                let value = tokens[index + 1]
                if token == "-i" {
                    identityFile = value
                } else if token == "-p" {
                    guard let parsed = Int(value), (1...65_535).contains(parsed) else {
                        throw ParseError.invalidPort(value)
                    }
                    port = parsed
                } else if token == "-l" {
                    explicitUser = value
                }
                index += 2
                continue
            }
            if token.hasPrefix("-i"), token.count > 2 {
                identityFile = String(token.dropFirst(2))
                index += 1
                continue
            }
            if token.hasPrefix("-p"), token.count > 2 {
                let value = String(token.dropFirst(2))
                guard let parsed = Int(value), (1...65_535).contains(parsed) else {
                    throw ParseError.invalidPort(value)
                }
                port = parsed
                index += 1
                continue
            }
            if token.hasPrefix("-l"), token.count > 2 {
                explicitUser = String(token.dropFirst(2))
                index += 1
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            destination = token
            break
        }

        guard let destination, !destination.isEmpty else {
            throw ParseError.missingDestination
        }
        let components = destination.split(separator: "@", maxSplits: 1).map(String.init)
        let destinationUser = components.count == 2 ? components[0] : nil
        let host = components.count == 2 ? components[1] : components[0]
        let preferred = preferredAlias?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = preferred?.isEmpty == false ? preferred! : host

        return SSHHostProfile(
            alias: alias,
            hostName: host,
            user: explicitUser ?? destinationUser,
            port: port,
            identityFile: identityFile
        )
    }

    private static func tokenize(_ command: String) throws -> [String] {
        enum Quote { case single, double }
        var tokens: [String] = []
        var current = ""
        var quote: Quote?
        var escaping = false

        for character in command {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\", quote != .single {
                escaping = true
                continue
            }
            if character == "'", quote != .double {
                quote = quote == .single ? nil : .single
                continue
            }
            if character == "\"", quote != .single {
                quote = quote == .double ? nil : .double
                continue
            }
            if character.isWhitespace, quote == nil {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if escaping { current.append("\\") }
        guard quote == nil else { throw ParseError.unterminatedQuote }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

public struct ProcessLaunchPlan: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum RemoteLaunchPlanBuilder {
    public static func ssh(
        profile: SSHHostProfile,
        remoteCommand: [String] = [],
        executable: String = "/usr/bin/ssh",
        forceTTY: Bool = true,
        batchMode: Bool = false
    ) -> ProcessLaunchPlan {
        var arguments: [String] = [
            forceTTY ? "-tt" : "-T",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3"
        ]
        if batchMode {
            arguments += [
                "-o", "BatchMode=yes",
                "-o", "NumberOfPasswordPrompts=0",
                "-o", "StrictHostKeyChecking=yes"
            ]
        }
        if let port = profile.port {
            arguments += ["-p", String(port)]
        }
        if let identityFile = profile.identityFile {
            arguments += ["-i", NSString(string: identityFile).expandingTildeInPath]
        }
        arguments.append(profile.destination)
        arguments += remoteCommand
        return ProcessLaunchPlan(executable: executable, arguments: arguments)
    }

    public static func tmuxAttach(
        profile: SSHHostProfile,
        sessionName: String,
        executable: String = "/usr/bin/ssh"
    ) -> ProcessLaunchPlan {
        ssh(
            profile: profile,
            remoteCommand: ["tmux", "new-session", "-A", "-s", sessionName],
            executable: executable
        )
    }
}
