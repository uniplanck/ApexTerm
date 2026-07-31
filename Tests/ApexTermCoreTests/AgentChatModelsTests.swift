import Foundation
import XCTest
@testable import ApexTermCore

final class AgentChatModelsTests: XCTestCase {
    func testAgentChatStoreRoundTripsDraftMessagesAndJob() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("agent-chat-tabs.json")
        let job = GagJobRecord(
            id: "job_chat123",
            workspaceRoot: "/tmp/work",
            title: "Chat task",
            status: .running,
            progress: 55,
            currentStep: "Waiting",
            input: GagJobInput(prompt: "調査して", timeoutMs: 600_000),
            createdAt: "2026-07-19T00:00:00.000Z",
            startedAt: "2026-07-19T00:00:01.000Z",
            updatedAt: "2026-07-19T00:00:02.000Z"
        )
        let cost = GagAPICostEstimate(
            status: "registered",
            selectedModel: "gpt-5-5",
            pricingModel: "gpt-5.5",
            pricingLabel: "GPT-5.5",
            inputTokens: 120,
            outputTokens: 80,
            usdJpyRate: 160,
            jpy: 0.48,
            maxJpy: 0.72,
            note: "API換算"
        )
        let tab = AgentChatTab(
            title: "調査",
            target: .gae,
            performance: .fastest,
            draft: "追記",
            messages: [
                AgentChatMessage(role: .user, text: "調査して", requestedPerformance: .fastest),
                AgentChatMessage(
                    role: .assistant,
                    text: "回答",
                    requestedPerformance: .fastest,
                    selectedModel: "gpt-5-5",
                    selectedModelLabel: "Instant",
                    apiCostEstimate: cost
                )
            ],
            activeJob: GagTargetedJob(target: .gae, job: job),
            metrics: GagRuntimeMetrics.calculate(target: .gae, job: job)
        )

        try AgentChatStore.save([tab], to: fileURL)
        let loaded = try AgentChatStore.load(from: fileURL)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "調査")
        XCTAssertEqual(loaded[0].target, .gae)
        XCTAssertEqual(loaded[0].draft, "追記")
        XCTAssertEqual(loaded[0].selectedPerformance, .fastest)
        XCTAssertEqual(loaded[0].messages.last?.selectedModel, "gpt-5-5")
        XCTAssertEqual(loaded[0].cumulativeAPICostJPY, 0.48...0.72)
        XCTAssertEqual(loaded[0].activeJob?.job.id, "job_chat123")
        XCTAssertTrue(loaded[0].isRunning)
    }

    func testLegacyPerformanceValuesMigrateToHigh() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(GagPerformance.self, from: Data("\"balanced\"".utf8)), .high)
        XCTAssertEqual(try decoder.decode(GagPerformance.self, from: Data("\"sol\"".utf8)), .high)
        XCTAssertEqual(try decoder.decode(GagPerformance.self, from: Data("\"gpt-5-6-sol\"".utf8)), .high)
    }

    func testLegacyAgentChatWithoutPerformanceDefaultsToHigh() throws {
        let data = Data(
            """
            [{
              "id": "00000000-0000-0000-0000-000000000001",
              "title": "Legacy",
              "target": "local",
              "draft": "",
              "messages": [],
              "createdAt": "2026-07-19T00:00:00Z",
              "updatedAt": "2026-07-19T00:00:00Z"
            }]
            """.utf8
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("legacy-agent-chat-tabs.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL)
        let loaded = try AgentChatStore.load(from: fileURL)
        XCTAssertEqual(loaded.first?.selectedPerformance, .high)
    }

    func testTerminalAgentChatIsNotRunning() {
        let job = GagJobRecord(
            id: "job_done456",
            workspaceRoot: "/tmp/work",
            title: "Done",
            status: .succeeded,
            progress: 100,
            currentStep: "Completed",
            createdAt: "2026-07-19T00:00:00.000Z",
            updatedAt: "2026-07-19T00:00:01.000Z"
        )
        let tab = AgentChatTab(
            activeJob: GagTargetedJob(target: .local, job: job)
        )
        XCTAssertFalse(tab.isRunning)
    }
}
