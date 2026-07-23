import Foundation
import Markdown

/// A parsed markdown document reduced to the block kinds Lorvex renders.
///
/// Built from a markdown source string via swift-markdown's AST. Supports
/// headings, paragraphs, unordered/ordered lists, GFM task lists, fenced code
/// blocks, block quotes, GFM tables, and thematic breaks.
///
/// Inline-bearing blocks (headings, paragraphs, list items, quotes, table
/// cells) carry their inline markdown *source* — bold/italic/inline-code/link
/// markup and `~~strikethrough~~` are preserved so the renderer can style them.
/// `~~` survives even though `Markup.format()` collapses it to a single tilde:
/// inline source is reconstructed via ``inlineSource(_:)`` rather than
/// `format()`.
///
/// Markdown image syntax is preserved as inline markdown source inside the
/// surrounding text block. Lorvex no longer exposes app-owned note images.
public struct MarkdownNote: Equatable, Sendable {
    /// One row of a GFM task list: a checkbox state plus its inline markdown.
    public struct TaskItem: Equatable, Sendable {
        public var isChecked: Bool
        public var text: String

        public init(isChecked: Bool, text: String) {
            self.isChecked = isChecked
            self.text = text
        }
    }

    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList(start: Int, items: [String])
        /// GFM task list (`- [ ]` / `- [x]`) — checkbox rows.
        case taskList([TaskItem])
        case code(language: String?, text: String)
        case quote(String)
        /// GFM table: column header cells and body rows of inline markdown.
        case table(headers: [String], rows: [[String]])
        case divider
    }

    struct RenderedTaskItem: Equatable, Sendable {
        var isChecked: Bool
        var source: String
        var text: AttributedString
    }

    enum RenderedBlock: Equatable, Sendable {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        case unorderedList([AttributedString])
        case orderedList(start: Int, items: [AttributedString])
        case taskList([RenderedTaskItem])
        case code(language: String?, text: String)
        case quote(AttributedString)
        case table(headers: [AttributedString], rows: [[AttributedString]])
        case divider
    }

    public var blocks: [Block]
    var renderedBlocks: [RenderedBlock]

    public init(_ source: String) {
        let document = Document(parsing: source)
        blocks = document.children.compactMap(Self.block(from:))
        if blocks.isEmpty {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            blocks = trimmed.isEmpty ? [] : [.paragraph(trimmed)]
        }
        renderedBlocks = blocks.map(Self.renderedBlock(from:))
    }

    private static func block(from markup: Markup) -> Block? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, text: inlineSource(heading))
        case let paragraph as Paragraph:
            return .paragraph(inlineSource(paragraph))
        case let list as UnorderedList:
            return listBlock(items: Array(list.listItems))
        case let list as OrderedList:
            if Self.hasCheckboxes(list.listItems) {
                return .taskList(list.listItems.map(Self.taskItem(from:)))
            }
            return .orderedList(start: Int(list.startIndex), items: list.listItems.map(Self.itemText))
        case let code as CodeBlock:
            return .code(language: code.language, text: code.code)
        case let quote as BlockQuote:
            return .quote(quote.children.map(Self.plainText).joined(separator: "\n"))
        case let table as Table:
            return tableBlock(table)
        case _ as ThematicBreak:
            return .divider
        default:
            let text = plainText(markup).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : .paragraph(text)
        }
    }

    /// An unordered list renders as a GFM task list when any item carries a
    /// checkbox, otherwise as a plain bulleted list.
    private static func listBlock(items: [ListItem]) -> Block {
        if hasCheckboxes(items) {
            return .taskList(items.map(taskItem(from:)))
        }
        return .unorderedList(items.map(itemText))
    }

    private static func hasCheckboxes(_ items: some Sequence<ListItem>) -> Bool {
        items.contains { $0.checkbox != nil }
    }

    private static func taskItem(from item: ListItem) -> TaskItem {
        TaskItem(isChecked: item.checkbox == .checked, text: itemText(item))
    }

    /// The inline markdown source of a list item's first paragraph (the common
    /// shape), falling back to the joined inline source of every child block.
    private static func itemText(_ item: ListItem) -> String {
        if let paragraph = item.children.first(where: { $0 is Paragraph }) as? Paragraph {
            return inlineSource(paragraph)
        }
        return item.children.map(inlineSource).joined(separator: " ")
    }

    private static func tableBlock(_ table: Table) -> Block {
        let headers = Array(table.head.cells).map(inlineSource)
        let rows = table.body.rows.map { row in Array(row.cells).map(inlineSource) }
        return .table(headers: headers, rows: Array(rows))
    }

    private static func renderedBlock(from block: Block) -> RenderedBlock {
        switch block {
        case let .heading(level, text):
            return .heading(level: level, text: MarkdownInline.attributedString(text))
        case let .paragraph(text):
            return .paragraph(MarkdownInline.attributedString(text))
        case let .unorderedList(items):
            return .unorderedList(items.map(MarkdownInline.attributedString))
        case let .orderedList(start, items):
            return .orderedList(start: start, items: items.map(MarkdownInline.attributedString))
        case let .taskList(items):
            return .taskList(items.map { item in
                RenderedTaskItem(
                    isChecked: item.isChecked,
                    source: item.text,
                    text: MarkdownInline.attributedString(item.text)
                )
            })
        case let .code(language, text):
            return .code(language: language, text: text)
        case let .quote(text):
            return .quote(MarkdownInline.attributedString(text))
        case let .table(headers, rows):
            return .table(
                headers: headers.map(MarkdownInline.attributedString),
                rows: rows.map { $0.map(MarkdownInline.attributedString) }
            )
        case .divider:
            return .divider
        }
    }

    /// Reconstructs the inline markdown source of `markup`, preserving emphasis,
    /// strong, inline code, links, and — unlike `Markup.format()` — GFM
    /// `~~strikethrough~~` with both tildes intact so `AttributedString(markdown:)`
    /// and the renderer's manual strikethrough pass can recover it.
    static func inlineSource(_ markup: Markup) -> String {
        switch markup {
        case let text as Markdown.Text:
            return text.string
        case let code as InlineCode:
            return "`\(code.code)`"
        case let strong as Strong:
            return "**\(childInlineSource(strong))**"
        case let emphasis as Emphasis:
            return "_\(childInlineSource(emphasis))_"
        case let strike as Strikethrough:
            return "~~\(childInlineSource(strike))~~"
        case let link as Link:
            let destination = link.destination ?? ""
            return "[\(childInlineSource(link))](\(destination))"
        case let image as Image:
            let destination = image.source ?? ""
            return "![\(image.plainText)](\(destination))"
        case _ as SoftBreak:
            return " "
        case _ as LineBreak:
            return "\n"
        default:
            return childInlineSource(markup)
        }
    }

    private static func childInlineSource(_ markup: Markup) -> String {
        markup.children.map(inlineSource).joined()
    }

    private static func plainText(_ markup: Markup) -> String {
        if let convertible = markup as? PlainTextConvertibleMarkup {
            return convertible.plainText
        }
        if let code = markup as? CodeBlock {
            return code.code
        }
        return markup.children
            .map(plainText)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
