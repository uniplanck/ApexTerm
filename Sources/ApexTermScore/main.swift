import ApexTermCore
import Foundation

@main
enum ApexTermScoreCommand {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--workflow") {
            try runWorkflowScore(arguments: arguments)
        } else {
            try runTechnicalScore(arguments: arguments)
        }
    }

    private static func runTechnicalScore(arguments: [String]) throws {
        let path = arguments.first ?? "scorecard.json"
        let scorecard: Scorecard = try decode(path: path)
        let errors = scorecard.validationErrors()

        print("ApexTerm score: \(scorecard.total)/150")
        for category in ScoreCategory.allCases {
            let points = scorecard.points(for: category)
            let title = category.title.padding(
                toLength: 30,
                withPad: " ",
                startingAt: 0
            )
            print("\(title) \(String(format: "%2d", points))/10")
        }

        try exitIfInvalid(errors)
        if scorecard.passesReleaseGate {
            print("Release gate: PASS")
        } else {
            print("Release gate: NOT MET (requires 136/150)")
            Foundation.exit(1)
        }
    }

    private static func runWorkflowScore(arguments: [String]) throws {
        var path = "workflow-scorecard.json"
        var requiredGate: WorkflowMaturityGate?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--workflow":
                if index + 1 < arguments.count,
                   !arguments[index + 1].hasPrefix("--") {
                    path = arguments[index + 1]
                    index += 2
                } else {
                    index += 1
                }
            case "--require":
                guard index + 1 < arguments.count,
                      let gate = WorkflowMaturityGate(
                          rawValue: arguments[index + 1]
                      ) else {
                    fputs(
                        "ERROR: --require must be dailyDriver, workspaceOS, agentOS, remoteOps, platform, or complete\n",
                        stderr
                    )
                    Foundation.exit(64)
                }
                requiredGate = gate
                index += 2
            default:
                fputs("ERROR: unknown argument: \(arguments[index])\n", stderr)
                Foundation.exit(64)
            }
        }

        let scorecard: UserWorkflowScorecard = try decode(path: path)
        let errors = scorecard.validationErrors()
        let gate = requiredGate ?? scorecard.targetGate

        print("ApexTerm workflow score: \(scorecard.total)/100")
        for category in WorkflowScoreCategory.allCases {
            let points = scorecard.points(for: category)
            let title = category.title.padding(
                toLength: 24,
                withPad: " ",
                startingAt: 0
            )
            print(
                "\(title) \(String(format: "%2d", points))/\(category.maximumPoints)"
            )
        }
        if let reached = scorecard.highestReachedGate {
            print("Highest reached gate: \(reached.title)")
        } else {
            print("Highest reached gate: below Daily Driver")
        }
        if let next = scorecard.nextGate {
            print(
                "Next gate: \(next.title) — \(max(0, next.requiredPoints - scorecard.total)) points remaining"
            )
        }

        try exitIfInvalid(errors)
        if scorecard.passes(gate) {
            print("Workflow gate \(gate.title): PASS")
        } else {
            print(
                "Workflow gate \(gate.title): NOT MET (requires \(gate.requiredPoints)/100 and no critical failure)"
            )
            Foundation.exit(1)
        }
    }

    private static func decode<Value: Decodable>(path: String) throws -> Value {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    private static func exitIfInvalid(_ errors: [String]) throws {
        guard !errors.isEmpty else { return }
        for error in errors {
            fputs("ERROR: \(error)\n", stderr)
        }
        Foundation.exit(2)
    }
}
