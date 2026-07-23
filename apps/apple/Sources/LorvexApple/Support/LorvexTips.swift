import TipKit

/// Tip shown in the Settings MCP section, explaining AI-first design.
struct MCPAssistantTip: Tip {
    var title: Text {
        Text(LocalizedStringResource("tips.mcp_assistant.title", defaultValue: "AI-First Design", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    var message: Text? {
        Text(
            LocalizedStringResource(
                "tips.mcp_assistant.message",
                defaultValue: "Lorvex is built for AI assistants to do most of the work. Connect your MCP-capable client to get started.",
                table: "Localizable",
                bundle: LorvexL10n.bundle
            )
        )
    }
    var image: Image? { Image(systemName: "brain") }
}

/// Tip shown the first time the Reviews workspace opens.
struct DailyReviewTip: Tip {
    var title: Text {
        Text(LocalizedStringResource("tips.daily_review.title", defaultValue: "Daily Review", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    var message: Text? {
        Text(
            LocalizedStringResource(
                "tips.daily_review.message",
                defaultValue: "Wrap up your day with a quick reflection. Lorvex can sync it across devices.",
                table: "Localizable",
                bundle: LorvexL10n.bundle
            )
        )
    }
    var image: Image? { Image(systemName: "checkmark.seal") }
}
