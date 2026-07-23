import Foundation
import Markdown

/// Inline markdown → `AttributedString` rendering for Lorvex note surfaces.
///
/// Built directly from the swift-markdown inline AST rather than
/// `AttributedString(markdown:)`, which drops GFM strikethrough (`~~…~~`).
/// Walking the AST applies each span's `inlinePresentationIntent` to exactly
/// its own characters, so a struck word that also appears as plain text is no
/// longer struck everywhere — the failure mode of patching the rendered string
/// by text search.
public enum MarkdownInline {
    public static func attributedString(_ source: String) -> AttributedString {
        var result = AttributedString()
        append(Document(parsing: source), into: &result, intent: [], link: nil)
        return result
    }

    /// Recursively appends `markup`'s inline content to `out`, carrying the
    /// accumulated presentation intent and enclosing link down to leaf text.
    private static func append(
        _ markup: Markup,
        into out: inout AttributedString,
        intent: InlinePresentationIntent,
        link: URL?
    ) {
        switch markup {
        case let text as Markdown.Text:
            out.append(run(text.string, intent: intent, link: link))
        case let code as InlineCode:
            out.append(run(code.code, intent: intent.union(.code), link: link))
        case is SoftBreak:
            out.append(run(" ", intent: intent, link: link))
        case is LineBreak:
            out.append(run("\n", intent: intent, link: link))
        case let html as InlineHTML:
            out.append(run(html.rawHTML, intent: intent, link: link))
        case let emphasis as Emphasis:
            descend(emphasis, into: &out, intent: intent.union(.emphasized), link: link)
        case let strong as Strong:
            descend(strong, into: &out, intent: intent.union(.stronglyEmphasized), link: link)
        case let strike as Strikethrough:
            descend(strike, into: &out, intent: intent.union(.strikethrough), link: link)
        case let anchor as Markdown.Link:
            let destination = anchor.destination.flatMap(URL.init(string:))
            descend(anchor, into: &out, intent: intent, link: destination ?? link)
        default:
            // Block containers (Document, Paragraph) and any unhandled inline:
            // render their children with the current context.
            descend(markup, into: &out, intent: intent, link: link)
        }
    }

    private static func descend(
        _ markup: Markup,
        into out: inout AttributedString,
        intent: InlinePresentationIntent,
        link: URL?
    ) {
        for child in markup.children {
            append(child, into: &out, intent: intent, link: link)
        }
    }

    private static func run(
        _ string: String,
        intent: InlinePresentationIntent,
        link: URL?
    ) -> AttributedString {
        var run = AttributedString(string)
        if !intent.isEmpty { run.inlinePresentationIntent = intent }
        if let link { run.link = link }
        return run
    }
}
