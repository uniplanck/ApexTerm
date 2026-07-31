import XCTest
@testable import ApexTermCore

final class GagIntegrationTests: XCTestCase {
    func testStartedJobIDAndReferencesAreParsedSafely() {
        XCTAssertEqual(
            GagJobCodec.parseStartedJobID(
                "job_abc123 running      15% chatgpt-task Test — Opening"
            ),
            "job_abc123"
        )
        XCTAssertEqual(
            GagJobReference.parse("gae/job_def456"),
            GagJobReference(target: .gae, jobID: "job_def456")
        )
        XCTAssertEqual(
            GagJobReference.parse("gag:job_local123"),
            GagJobReference(target: .local, jobID: "job_local123")
        )
        XCTAssertNil(GagJobReference.parse("gae/not-a-job"))
    }

    func testShellQuoteKeepsPromptAsOneRemoteArgument() {
        XCTAssertEqual(GagJobCodec.shellQuote(""), "''")
        XCTAssertEqual(GagJobCodec.shellQuote("plain words"), "'plain words'")
        XCTAssertEqual(
            GagJobCodec.shellQuote("don't $(expand)"),
            "'don'\"'\"'t $(expand)'"
        )
    }

    func testJobJSONDecodesResponseAndConversationURL() throws {
        let data = Data(
            """
            {
              "job": {
                "id": "job_123abc",
                "workspaceRoot": "/tmp/work",
                "title": "ApexTerm CLI smoke",
                "preset": "chatgpt-task",
                "status": "succeeded",
                "progress": 100,
                "currentStep": "Completed without planner LLM",
                "exitCode": 0,
                "input": {
                  "prompt": "短く回答して",
                  "timeoutMs": 600000
                },
                "state": {
                  "phase": "completed",
                  "responseText": "GAG_CLI_OK",
                  "conversationUrl": "https://chatgpt.com/c/example",
                  "selectedModelLabel": "GPT-5.6 Thinking"
                },
                "createdAt": "2026-07-19T00:00:00.000Z",
                "finishedAt": "2026-07-19T00:00:01.000Z",
                "updatedAt": "2026-07-19T00:00:01.000Z"
              },
              "events": []
            }
            """.utf8
        )
        let envelope = try GagJobCodec.decodeJobEnvelope(data)
        XCTAssertEqual(envelope.job.status, .succeeded)
        XCTAssertEqual(envelope.job.input?.prompt, "短く回答して")
        XCTAssertNil(envelope.job.input?.performance)
        XCTAssertEqual(envelope.job.state?.responseText, "GAG_CLI_OK")
        XCTAssertEqual(envelope.job.state?.selectedModelLabel, "GPT-5.6 Thinking")
        XCTAssertEqual(
            GagRuntimeMetrics.calculate(target: .local, job: envelope.job).requestedPerformance,
            .high
        )
    }

    func testJobJSONDecodesPerformanceActualModelAndPricing() throws {
        let data = Data(
            """
            {
              "job": {
                "id": "job_perf123",
                "workspaceRoot": "/tmp/work",
                "title": "Fastest task",
                "preset": "chatgpt-task",
                "status": "succeeded",
                "progress": 100,
                "currentStep": "Completed",
                "input": {
                  "prompt": "FASTEST_OK",
                  "timeoutMs": 600000,
                  "performance": "fastest"
                },
                "state": {
                  "phase": "completed",
                  "requestedPerformance": "fastest",
                  "selectedModel": "gpt-5-5-instant",
                  "selectedModelLabel": "最速 5.5",
                  "modelSelectionStatus": "selected",
                  "apiCostEstimate": {
                    "status": "registered",
                    "requestedModel": "gpt-5-5-instant",
                    "selectedModel": "gpt-5-5-instant",
                    "selectedModelLabel": "最速 5.5",
                    "pricingModel": "gpt-5.5",
                    "pricingLabel": "GPT-5.5",
                    "inputTokens": 12,
                    "outputTokens": 5,
                    "usdJpyRate": 160,
                    "usd": 0.00021,
                    "jpy": 0.0336,
                    "maxUsd": 0.000345,
                    "maxJpy": 0.0552,
                    "note": "API換算"
                  }
                },
                "createdAt": "2026-07-19T00:00:00.000Z",
                "finishedAt": "2026-07-19T00:00:01.000Z",
                "updatedAt": "2026-07-19T00:00:01.000Z"
              }
            }
            """.utf8
        )
        let envelope = try GagJobCodec.decodeJobEnvelope(data)
        let metrics = GagRuntimeMetrics.calculate(target: .local, job: envelope.job)
        XCTAssertEqual(envelope.job.input?.performance, .fastest)
        XCTAssertEqual(metrics.requestedPerformance, .fastest)
        XCTAssertEqual(metrics.selectedModel, "gpt-5-5-instant")
        XCTAssertEqual(metrics.selectedModelLabel, "最速 5.5")
        XCTAssertEqual(metrics.apiCostEstimate?.pricingModel, "gpt-5.5")
        XCTAssertEqual(metrics.apiCostEstimate?.jpy, 0.0336)
    }

    func testRuntimeMetricsEstimateTokensAndRemainingTime() {
        let now = ISO8601DateFormatter().date(from: "2026-07-19T00:01:00Z")!
        let job = GagJobRecord(
            id: "job_metrics123",
            workspaceRoot: "/tmp/work",
            title: "Metrics",
            status: .running,
            progress: 50,
            currentStep: "Waiting",
            input: GagJobInput(prompt: "日本語の入力と English input", timeoutMs: 600_000),
            state: GagJobState(responseText: "途中回答"),
            createdAt: "2026-07-19T00:00:00.000Z",
            startedAt: "2026-07-19T00:00:00.000Z",
            updatedAt: "2026-07-19T00:01:00.000Z"
        )
        let metrics = GagRuntimeMetrics.calculate(target: .local, job: job, now: now)
        XCTAssertEqual(metrics.reference, "local/job_metrics123")
        XCTAssertEqual(metrics.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(metrics.elapsedSeconds, 60, accuracy: 0.01)
        XCTAssertEqual(metrics.estimatedRemainingSeconds ?? -1, 60, accuracy: 0.01)
        XCTAssertGreaterThan(metrics.tokens.input, 0)
        XCTAssertGreaterThan(metrics.tokens.output, 0)
        XCTAssertEqual(metrics.tokens.total, metrics.tokens.input + metrics.tokens.output)
    }

    func testCompletedRuntimeHasZeroRemainingTime() {
        let job = GagJobRecord(
            id: "job_done123",
            workspaceRoot: "/tmp/work",
            title: "Done",
            status: .succeeded,
            progress: 100,
            currentStep: "Completed",
            createdAt: "2026-07-19T00:00:00.000Z",
            finishedAt: "2026-07-19T00:00:10.000Z",
            updatedAt: "2026-07-19T00:00:10.000Z"
        )
        let metrics = GagRuntimeMetrics.calculate(target: .gae, job: job)
        XCTAssertEqual(metrics.estimatedRemainingSeconds, 0)
        XCTAssertEqual(metrics.progress, 1)
    }

    func testTokenEstimateHandlesJapaneseAndASCII() {
        XCTAssertGreaterThan(GagTokenEstimate.estimateText("日本語テスト"), 0)
        XCTAssertGreaterThan(GagTokenEstimate.estimateText("simple ascii text"), 0)
        XCTAssertEqual(GagTokenEstimate.estimateText(""), 0)
    }

    func testStableRunIDAndStatusMapping() {
        let first = GagJobCodec.stableRunID(target: .local, jobID: "job_abc123")
        let second = GagJobCodec.stableRunID(target: .local, jobID: "job_abc123")
        let remote = GagJobCodec.stableRunID(target: .gae, jobID: "job_abc123")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, remote)
        XCTAssertEqual(GagJobStatus.waitingApproval.agentRunState, .waitingApproval)
        XCTAssertEqual(GagJobStatus.interrupted.agentRunState, .disconnected)
        XCTAssertTrue(GagJobStatus.succeeded.isTerminal)
        XCTAssertFalse(GagJobStatus.running.isTerminal)
    }
}
