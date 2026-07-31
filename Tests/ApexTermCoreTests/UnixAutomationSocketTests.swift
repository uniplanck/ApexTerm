import Foundation
import XCTest
@testable import ApexTermCore

final class UnixAutomationSocketTests: XCTestCase {
    func testWireCodecRoundTripsAssociatedValueAction() throws {
        let request = AutomationRequest(
            clientID: "gag",
            action: .runCommand(
                sessionID: UUID(),
                command: "swift test"
            )
        )

        let encoded = try AutomationWireCodec.encodeRequest(request)
        let decoded = try AutomationWireCodec.decodeRequest(encoded)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(encoded.last, 0x0A)
    }

    func testAuthorizerSeparatesCapabilitiesAndRiskApproval() {
        let authorizer = AutomationRequestAuthorizer(
            grants: [
                AutomationGrant(
                    clientID: "gag",
                    capabilities: [.readStatus, .runCommand]
                )
            ]
        )

        let allowed = authorizer.authorize(
            AutomationRequest(
                clientID: "gag",
                action: .runCommand(sessionID: UUID(), command: "swift test")
            )
        )
        let requiresApproval = authorizer.authorize(
            AutomationRequest(
                clientID: "gag",
                action: .runCommand(sessionID: UUID(), command: "sudo rm -rf /")
            )
        )
        let wrongClient = authorizer.authorize(
            AutomationRequest(clientID: "unknown", action: .readStatus)
        )

        XCTAssertEqual(allowed.status, .accepted)
        XCTAssertEqual(requiresApproval.status, .denied)
        XCTAssertTrue(requiresApproval.message.contains("approval"))
        XCTAssertEqual(wrongClient.status, .denied)
    }

    func testUnixSocketServerRoundTripAndPrivatePermissions() throws {
        let socketURL = URL(
            fileURLWithPath: "/tmp/apexterm-\(UUID().uuidString.prefix(8)).sock"
        )
        let authorizer = AutomationRequestAuthorizer(
            grants: [
                AutomationGrant(clientID: "gag", capabilities: [.readStatus])
            ]
        )
        let server = UnixAutomationServer(socketURL: socketURL) { request in
            authorizer.authorize(request)
        }
        defer { server.stop() }

        try server.start()

        let attributes = try FileManager.default.attributesOfItem(
            atPath: socketURL.path
        )
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

        let request = AutomationRequest(clientID: "gag", action: .readStatus)
        let response = try UnixAutomationClient.send(request, to: socketURL)

        XCTAssertEqual(response.requestID, request.id)
        XCTAssertEqual(response.status, .accepted)
        XCTAssertEqual(response.message, "Authorized")
    }

    func testUnixSocketRejectsUnauthorizedMutation() throws {
        let socketURL = URL(
            fileURLWithPath: "/tmp/apexterm-\(UUID().uuidString.prefix(8)).sock"
        )
        let authorizer = AutomationRequestAuthorizer(
            grants: [
                AutomationGrant(clientID: "gag", capabilities: [.readStatus])
            ]
        )
        let server = UnixAutomationServer(socketURL: socketURL) { request in
            authorizer.authorize(request)
        }
        defer { server.stop() }
        try server.start()

        let request = AutomationRequest(
            clientID: "gag",
            action: .runCommand(sessionID: UUID(), command: "git status")
        )
        let response = try UnixAutomationClient.send(request, to: socketURL)

        XCTAssertEqual(response.requestID, request.id)
        XCTAssertEqual(response.status, .denied)
    }

    func testSocketPathLengthIsBounded() {
        let longPath = "/tmp/" + String(repeating: "a", count: 200) + ".sock"
        let server = UnixAutomationServer(
            socketURL: URL(fileURLWithPath: longPath)
        ) { request in
            AutomationResponse(
                requestID: request.id,
                status: .accepted,
                message: "ok"
            )
        }

        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? UnixAutomationSocketError, .pathTooLong)
        }
    }
}
