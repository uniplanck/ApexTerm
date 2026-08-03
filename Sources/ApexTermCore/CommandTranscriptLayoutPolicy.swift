import Foundation

public struct CommandTranscriptLayout: Equatable, Sendable {
    public var transcriptHeight: Double
    public var livePaneHeight: Double
    public var showsResizeHandle: Bool

    public init(
        transcriptHeight: Double,
        livePaneHeight: Double,
        showsResizeHandle: Bool
    ) {
        self.transcriptHeight = transcriptHeight
        self.livePaneHeight = livePaneHeight
        self.showsResizeHandle = showsResizeHandle
    }
}

public enum CommandTranscriptLayoutPolicy {
    public static func resolve(
        mode: CommandTranscriptMode,
        showsTranscript: Bool,
        containerHeight: Double,
        measuredContentHeight: Double,
        preferredLivePaneHeight: Double,
        minimumLivePaneHeight: Double,
        maximumLivePaneHeight: Double,
        headerHeight: Double,
        resizeHandleHeight: Double
    ) -> CommandTranscriptLayout {
        let container = max(0, containerHeight)
        let header = min(max(0, headerHeight), container)

        guard showsTranscript else {
            return CommandTranscriptLayout(
                transcriptHeight: 0,
                livePaneHeight: max(0, container - header),
                showsResizeHandle: false
            )
        }

        let usesAutomaticHeight = mode == .ex
        let handle = usesAutomaticHeight
            ? 0
            : min(max(0, resizeHandleHeight), max(0, container - header))
        let available = max(0, container - header - handle)
        let minimumLive = min(max(0, minimumLivePaneHeight), available)
        let maximumLive = min(
            max(minimumLive, maximumLivePaneHeight),
            available
        )

        if usesAutomaticHeight {
            let maximumTranscript = max(0, available - minimumLive)
            let transcript = min(
                max(0, measuredContentHeight),
                maximumTranscript
            )
            return CommandTranscriptLayout(
                transcriptHeight: transcript,
                livePaneHeight: max(minimumLive, available - transcript),
                showsResizeHandle: false
            )
        }

        let livePane = min(
            max(preferredLivePaneHeight, minimumLive),
            maximumLive
        )
        return CommandTranscriptLayout(
            transcriptHeight: max(0, available - livePane),
            livePaneHeight: livePane,
            showsResizeHandle: true
        )
    }
}
