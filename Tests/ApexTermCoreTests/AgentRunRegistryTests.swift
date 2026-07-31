import XCTest
@testable import ApexTermCore

final class AgentRunRegistryTests: XCTestCase {
    func testStructuredAgentLifecycle() async {
        let registry = AgentRunRegistry()
        let run = await registry.register(
            provider: "gag",
            label: "Build ApexTerm",
            workingDirectory: "/tmp/ApexTerm"
        )

        let startedAt = Date(timeIntervalSince1970: 100)
        var updated = await registry.handle(runID: run.id, event: .started(at: startedAt))
        XCTAssertEqual(updated?.state, .running)
        XCTAssertEqual(updated?.startedAt, startedAt)

        updated = await registry.handle(
            runID: run.id,
            event: .progress(value: 0.4, message: "Testing")
        )
        XCTAssertEqual(updated?.progress, 0.4)
        XCTAssertEqual(updated?.lastEvent, "Testing")

        updated = await registry.handle(
            runID: run.id,
            event: .approvalRequested(message: "Approve local action")
        )
        XCTAssertEqual(updated?.state, .waitingApproval)

        updated = await registry.handle(runID: run.id, event: .resumed(message: nil))
        XCTAssertEqual(updated?.state, .running)

        updated = await registry.handle(runID: run.id, event: .succeeded(message: "Done"))
        XCTAssertEqual(updated?.state, .succeeded)
        XCTAssertEqual(updated?.progress, 1)
    }

    func testProgressIsClampedAndIgnoredOutsideRunningState() async {
        let registry = AgentRunRegistry()
        let run = await registry.register(
            provider: "codex",
            label: "Review",
            workingDirectory: "/tmp"
        )

        var updated = await registry.handle(
            runID: run.id,
            event: .progress(value: 2, message: nil)
        )
        XCTAssertEqual(updated?.state, .queued)
        XCTAssertEqual(updated?.progress, 0)

        _ = await registry.handle(runID: run.id, event: .started(at: Date()))
        updated = await registry.handle(
            runID: run.id,
            event: .progress(value: 2, message: nil)
        )
        XCTAssertEqual(updated?.progress, 1)
    }

    func testTerminalRunCannotBeResurrectedByLateEvents() async {
        let registry = AgentRunRegistry()
        let run = await registry.register(
            provider: "gae",
            label: "Deploy",
            workingDirectory: "/tmp"
        )
        _ = await registry.handle(runID: run.id, event: .failed(message: "Failed"))
        let updated = await registry.handle(runID: run.id, event: .started(at: Date()))

        XCTAssertEqual(updated?.state, .failed)
    }

    func testAutomationReportCreatesAndUpdatesStructuredRun() async {
        let registry = AgentRunRegistry()
        let runID = UUID()
        let startedAt = Date(timeIntervalSince1970: 200)

        var run = await registry.apply(
            report: AgentRunReport(
                runID: runID,
                provider: "gag",
                label: "Build ApexTerm",
                workingDirectory: "/tmp/ApexTerm",
                state: .running,
                progress: 0.25,
                message: "Compiling",
                timestamp: startedAt
            )
        )

        XCTAssertEqual(run?.id, runID)
        XCTAssertEqual(run?.state, .running)
        XCTAssertEqual(run?.progress, 0.25)
        XCTAssertEqual(run?.lastEvent, "Compiling")
        XCTAssertEqual(run?.startedAt, startedAt)

        run = await registry.apply(
            report: AgentRunReport(
                runID: runID,
                state: .waitingApproval,
                progress: 0.6,
                message: "Approval required",
                timestamp: Date(timeIntervalSince1970: 201)
            )
        )

        XCTAssertEqual(run?.provider, "gag")
        XCTAssertEqual(run?.state, .waitingApproval)
        XCTAssertEqual(run?.progress, 0.6)
        XCTAssertEqual(run?.lastEvent, "Approval required")
    }

    func testAutomationReportRequiresMetadataForUnknownRun() async {
        let registry = AgentRunRegistry()
        let run = await registry.apply(
            report: AgentRunReport(
                runID: UUID(),
                state: .running
            )
        )

        XCTAssertNil(run)
        let runs = await registry.allRuns()
        XCTAssertEqual(runs, [])
    }

    func testLateReportCannotResurrectCompletedRun() async {
        let registry = AgentRunRegistry()
        let runID = UUID()
        _ = await registry.apply(
            report: AgentRunReport(
                runID: runID,
                provider: "gag",
                label: "Test",
                workingDirectory: "/tmp",
                state: .succeeded
            )
        )

        let run = await registry.apply(
            report: AgentRunReport(
                runID: runID,
                state: .running,
                progress: 0.2
            )
        )

        XCTAssertEqual(run?.state, .succeeded)
        XCTAssertEqual(run?.progress, 1)
    }

    func testRemoveTerminalRunsPreservesActiveRuns() async {
        let registry = AgentRunRegistry()
        let active = await registry.register(
            provider: "gag",
            label: "Active",
            workingDirectory: "/tmp"
        )
        let complete = await registry.register(
            provider: "gag",
            label: "Complete",
            workingDirectory: "/tmp"
        )
        _ = await registry.handle(runID: active.id, event: .started(at: Date()))
        _ = await registry.handle(runID: complete.id, event: .succeeded(message: nil))

        await registry.removeTerminalRuns()
        let all = await registry.allRuns()

        XCTAssertEqual(all.map(\.id), [active.id])
    }
}
