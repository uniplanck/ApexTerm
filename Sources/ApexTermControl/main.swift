import ApexTermCore
import Foundation

@main
enum ApexTermControl {
    static func main() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let socketURL = extractSocketURL(from: &arguments)
        guard let command = arguments.first else {
            usageAndExit()
        }

        let action: AutomationAction
        switch command {
        case "status":
            action = .readStatus

        case "focus":
            guard arguments.count == 2,
                  let sessionID = UUID(uuidString: arguments[1]) else {
                usageAndExit("focus requires a session UUID")
            }
            action = .focusSession(sessionID: sessionID)

        case "workspace":
            guard arguments.count == 2,
                  let workspaceID = UUID(uuidString: arguments[1]) else {
                usageAndExit("workspace requires a workspace UUID")
            }
            action = .openWorkspace(workspaceID: workspaceID)

        case "split":
            guard arguments.count == 3,
                  let sessionID = UUID(uuidString: arguments[1]) else {
                usageAndExit("split requires a session UUID and horizontal|vertical")
            }
            let axis: SplitNode.SplitAxis
            switch arguments[2] {
            case "horizontal": axis = .horizontal
            case "vertical": axis = .vertical
            default: usageAndExit("split axis must be horizontal or vertical")
            }
            action = .createSplit(sessionID: sessionID, axis: axis)

        case "attach":
            guard arguments.count >= 2 else {
                usageAndExit("attach requires HOST [TMUX_SESSION|-]")
            }
            let tmuxSession: String?
            if arguments.count >= 3, arguments[2] != "-" {
                tmuxSession = arguments[2]
            } else {
                tmuxSession = nil
            }
            action = .attachRemote(
                hostAlias: arguments[1],
                tmuxSession: tmuxSession
            )

        case "exec":
            guard arguments.count >= 3,
                  let sessionID = UUID(uuidString: arguments[1]) else {
                usageAndExit("exec requires SESSION_UUID COMMAND")
            }
            action = .runCommand(
                sessionID: sessionID,
                command: arguments.dropFirst(2).joined(separator: " ")
            )

        case "remote":
            guard arguments.count == 3 else {
                usageAndExit("remote requires hide|restore|delete ALIAS")
            }
            switch arguments[1] {
            case "hide": action = .hideRemoteHost(alias: arguments[2])
            case "restore": action = .restoreRemoteHost(alias: arguments[2])
            case "delete": action = .deleteRemoteHost(alias: arguments[2])
            default: usageAndExit("remote action must be hide, restore, or delete")
            }

        case "agent":
            guard arguments.count >= 6,
                  let runID = UUID(uuidString: arguments[1]),
                  let state = AgentRunState(rawValue: arguments[2]) else {
                usageAndExit(
                    "agent requires RUN_UUID STATE PROVIDER LABEL WORKDIR [PROGRESS|-] [MESSAGE]"
                )
            }
            let progress: Double?
            if arguments.count >= 7, arguments[6] != "-" {
                guard let parsed = Double(arguments[6]) else {
                    usageAndExit("agent progress must be 0...1 or -")
                }
                progress = parsed
            } else {
                progress = nil
            }
            let message = arguments.count >= 8 ? arguments[7] : nil
            action = .reportAgentRun(
                report: AgentRunReport(
                    runID: runID,
                    provider: arguments[3],
                    label: arguments[4],
                    workingDirectory: arguments[5],
                    state: state,
                    progress: progress,
                    message: message
                )
            )

        default:
            usageAndExit("unknown command: \(command)")
        }

        let request = AutomationRequest(clientID: "gag", action: action)
        let response = try UnixAutomationClient.send(request, to: socketURL)

        if let payload = response.payload, command == "status" {
            printPrettyJSON(payload)
        } else if let payload = response.payload, command == "exec" {
            printCommandResult(payload)
        } else {
            print("\(response.status.rawValue): \(response.message)")
        }

        guard response.status == .accepted else {
            Foundation.exit(2)
        }
    }

    private static func extractSocketURL(from arguments: inout [String]) -> URL {
        if let index = arguments.firstIndex(of: "--socket"),
           arguments.indices.contains(index + 1) {
            let path = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }

        return ApexTermPaths.automationSocketURL()
    }

    private static func printCommandResult(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let result = try? JSONDecoder().decode(TmuxCommandResult.self, from: data) else {
            print(payload)
            return
        }
        if !result.output.isEmpty {
            print(result.output)
        }
        print("[apexterm exit=\(result.exitCode)]")
    }

    private static func printPrettyJSON(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: pretty, encoding: .utf8) else {
            print(payload)
            return
        }
        print(text)
    }

    private static func usageAndExit(_ error: String? = nil) -> Never {
        if let error {
            fputs("error: \(error)\n", stderr)
        }
        fputs(
            """
            Usage:
              apextermctl [--socket PATH] status
              apextermctl [--socket PATH] focus SESSION_UUID
              apextermctl [--socket PATH] workspace WORKSPACE_UUID
              apextermctl [--socket PATH] split SESSION_UUID horizontal|vertical
              apextermctl [--socket PATH] attach HOST [TMUX_SESSION|-]
              apextermctl [--socket PATH] exec SESSION_UUID COMMAND
              apextermctl [--socket PATH] remote hide|restore|delete ALIAS
              apextermctl [--socket PATH] agent RUN_UUID STATE PROVIDER LABEL WORKDIR [PROGRESS|-] [MESSAGE]
            \n
            """,
            stderr
        )
        Foundation.exit(64)
    }
}
