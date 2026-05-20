import CoreGraphics
import CoreText
import Foundation
#if os(macOS)
import AppKit
private typealias CanvasMarkdownPlatformColor = NSColor
private typealias CanvasMarkdownPlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias CanvasMarkdownPlatformColor = UIColor
private typealias CanvasMarkdownPlatformFont = UIFont
#endif

enum CanvasMarkdownLayoutMeasurer {
    private struct InlineTraits {
        let isBold: Bool
        let isItalic: Bool
        let isCode: Bool

        static let plain = InlineTraits(
            isBold: false,
            isItalic: false,
            isCode: false
        )

        func merging(
            isBold: Bool = false,
            isItalic: Bool = false,
            isCode: Bool = false
        ) -> InlineTraits {
            InlineTraits(
                isBold: self.isBold || isBold,
                isItalic: self.isItalic || isItalic,
                isCode: self.isCode || isCode
            )
        }
    }

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case unorderedList(items: [String])
        case orderedList(items: [(number: Int, text: String)])
        case quote(text: String)
        case codeBlock(text: String)
    }

    private struct RenderedBlock {
        let block: Block
        let attributedText: NSAttributedString
    }

    private struct AttributedComposition {
        let attributedText: NSAttributedString
        let codeBlockRanges: [NSRange]
        let blocks: [Block]
    }

    private struct CodeBlockDecorationMetrics {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let cornerRadius: CGFloat
    }

    private struct TextLayoutContext {
        let textStorage: NSTextStorage
        let layoutManager: NSLayoutManager
        let textContainer: NSTextContainer
    }

    private static let headingFontMultipliers: [CGFloat] = [
        2.0,
        1.65,
        1.4,
        1.2,
        1.1,
        1.0
    ]
    private static let blockSpacingFactor: CGFloat = 0.45
    private static let lineSpacingFactor: CGFloat = 0.18
    private static let listHeadIndentFactor: CGFloat = 1.8
    private static let quoteHeadIndentFactor: CGFloat = 1.2
    private static let codeBlockInsetFactor: CGFloat = 0.9
    private static let codeBlockPanelHorizontalPaddingFactor: CGFloat = 0.35
    private static let codeBlockPanelVerticalPaddingFactor: CGFloat = 0.18
    private static let codeBlockPanelCornerRadiusFactor: CGFloat = 0.24
    private static let minimumCodeBlockPanelHorizontalPadding: CGFloat = 4
    private static let maximumCodeBlockPanelHorizontalPadding: CGFloat = 12
    private static let minimumCodeBlockPanelVerticalPadding: CGFloat = 2
    private static let maximumCodeBlockPanelVerticalPadding: CGFloat = 6
    private static let minimumCodeBlockPanelCornerRadius: CGFloat = 4
    private static let maximumCodeBlockPanelCornerRadius: CGFloat = 10
    private static let quotePrefix = "▌ "
    private static let unorderedListPrefix = "• "
    private static let isTraceLoggingEnabled = true

    static func layout(
        markdownSource: String,
        style: CanvasTextStyle,
        maxLayoutWidth: CGFloat,
        scale: CGFloat = 1,
        includeCompatibilityCodeBlockBackgrounds: Bool = true
    ) -> CanvasMarkdownLayoutResult {
        let resolvedLayoutWidth = max(maxLayoutWidth, 1)
        let composition = makeAttributedComposition(
            markdownSource: markdownSource,
            style: style,
            scale: scale,
            includeCompatibilityCodeBlockBackgrounds: includeCompatibilityCodeBlockBackgrounds
        )
        let attributedText = composition.attributedText
        let measuredTextHeight = measuredAttributedTextHeight(
            attributedText,
            maxLayoutWidth: resolvedLayoutWidth
        )
        let legacyBoundingRectHeight = isTraceLoggingEnabled
            ? legacyMeasuredTextHeight(
                attributedText,
                maxLayoutWidth: resolvedLayoutWidth
            )
            : nil
        let contentSize = CGSize(
            width: resolvedLayoutWidth,
            height: ceil(max(measuredTextHeight, minimumContentHeight(
                style: style,
                scale: scale
            )))
        )
        let textLayoutContext = makeTextLayoutContext(
            attributedText: attributedText,
            maxLayoutWidth: resolvedLayoutWidth
        )
        let decorations = makeCodeBlockDecorations(
            codeBlockRanges: composition.codeBlockRanges,
            layoutContext: textLayoutContext,
            style: style,
            scale: scale,
            contentSize: contentSize
        )
        logLayoutTrace(
            markdownSource: markdownSource,
            blocks: composition.blocks,
            measuredTextHeight: measuredTextHeight,
            legacyBoundingRectHeight: legacyBoundingRectHeight,
            contentSize: contentSize,
            attributedTextLength: attributedText.length,
            resolvedLayoutWidth: resolvedLayoutWidth
        )
        return CanvasMarkdownLayoutResult(
            attributedText: attributedText,
            contentSize: contentSize,
            decorations: decorations,
            usedContentBounds: measuredUsedContentBounds(
                layoutContext: textLayoutContext,
                contentSize: contentSize,
                decorations: decorations
            )
        )
    }

    static func measuredContentHeight(
        markdownSource: String,
        style: CanvasTextStyle,
        maxLayoutWidth: CGFloat,
        scale: CGFloat = 1
    ) -> CGFloat {
        layout(
            markdownSource: markdownSource,
            style: style,
            maxLayoutWidth: maxLayoutWidth,
            scale: scale
        ).contentHeight
    }

    private static func makeAttributedComposition(
        markdownSource: String,
        style: CanvasTextStyle,
        scale: CGFloat,
        includeCompatibilityCodeBlockBackgrounds: Bool
    ) -> AttributedComposition {
        let blocks = parseBlocks(from: markdownSource)
        let resolvedBlocks = blocks.isEmpty
            ? [.paragraph(text: markdownSource)]
            : blocks
        let renderedBlocks = resolvedBlocks.map { block in
            makeRenderedBlock(
                for: block,
                style: style,
                scale: scale,
                includeCompatibilityCodeBlockBackgrounds: includeCompatibilityCodeBlockBackgrounds
            )
        }
        let composed = NSMutableAttributedString(string: "")
        var codeBlockRanges: [NSRange] = []
        for (index, block) in renderedBlocks.enumerated() {
            if index > 0 {
                composed.append(NSAttributedString(string: "\n\n"))
            }
            let blockRange = NSRange(
                location: composed.length,
                length: block.attributedText.length
            )
            composed.append(block.attributedText)
            if case .codeBlock = block.block {
                codeBlockRanges.append(blockRange)
            }
        }
        return AttributedComposition(
            attributedText: composed,
            codeBlockRanges: codeBlockRanges,
            blocks: resolvedBlocks
        )
    }

    private static func logLayoutTrace(
        markdownSource: String,
        blocks: [Block],
        measuredTextHeight: CGFloat,
        legacyBoundingRectHeight: CGFloat?,
        contentSize: CGSize,
        attributedTextLength: Int,
        resolvedLayoutWidth: CGFloat
    ) {
        guard isTraceLoggingEnabled else {
            return
        }
        print(
            "[Canvas Markdown][Parse] " +
            "width=\(debugScalar(resolvedLayoutWidth)) " +
            "blocks=\(debugBlockSummary(blocks)) " +
            "lastLine=\"\(debugLastNonEmptyLine(in: markdownSource))\" " +
            "tail=\"\(debugTail(markdownSource))\""
        )
        print(
            "[Canvas Markdown][Measure] " +
            "width=\(debugScalar(resolvedLayoutWidth)) " +
            "measuredTextHeight=\(debugScalar(measuredTextHeight)) " +
            "legacyBoundingRectHeight=\(debugOptionalScalar(legacyBoundingRectHeight)) " +
            "committedHeight=\(debugScalar(contentSize.height)) " +
            "attributedLength=\(attributedTextLength)"
        )
    }

    private static func measuredAttributedTextHeight(
        _ attributedText: NSAttributedString,
        maxLayoutWidth: CGFloat
    ) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributedText as CFAttributedString
        )
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(
                width: max(maxLayoutWidth, 1),
                height: CGFloat.greatestFiniteMagnitude
            ),
            nil
        )
        return suggestedSize.height
    }

    private static func legacyMeasuredTextHeight(
        _ attributedText: NSAttributedString,
        maxLayoutWidth: CGFloat
    ) -> CGFloat {
        attributedText.boundingRect(
            with: CGSize(
                width: max(maxLayoutWidth, 1),
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [
                .usesLineFragmentOrigin,
                .usesFontLeading
            ],
            context: nil
        ).height
    }

    private static func debugBlockSummary(_ blocks: [Block]) -> String {
        guard blocks.isEmpty == false else {
            return "[]"
        }
        let parts = blocks.map { block -> String in
            switch block {
            case let .heading(level, text):
                return "h\(level)(\(debugCharacterCount(for: text)))"
            case let .paragraph(text):
                return "p(\(debugCharacterCount(for: text)))"
            case let .unorderedList(items):
                let count = items.count
                let characters = items.reduce(0) { $0 + debugCharacterCount(for: $1) }
                return "ul(items:\(count),chars:\(characters))"
            case let .orderedList(items):
                let count = items.count
                let characters = items.reduce(0) { $0 + debugCharacterCount(for: $1.text) }
                return "ol(items:\(count),chars:\(characters))"
            case let .quote(text):
                return "quote(\(debugCharacterCount(for: text)))"
            case let .codeBlock(text):
                return "code(\(debugCharacterCount(for: text)))"
            }
        }
        return "[" + parts.joined(separator: ",") + "]"
    }

    private static func debugCharacterCount(for text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private static func debugLastNonEmptyLine(in source: String) -> String {
        let line = source
            .components(separatedBy: .newlines)
            .reversed()
            .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            ?? ""
        return debugSingleLine(line)
    }

    private static func debugTail(_ source: String, maxLength: Int = 120) -> String {
        debugSingleLine(String(source.suffix(maxLength)))
    }

    private static func debugSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func debugScalar(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private static func debugOptionalScalar(_ value: CGFloat?) -> String {
        guard let value else {
            return "nil"
        }
        return debugScalar(value)
    }

    private static func makeRenderedBlock(
        for block: Block,
        style: CanvasTextStyle,
        scale: CGFloat,
        includeCompatibilityCodeBlockBackgrounds: Bool
    ) -> RenderedBlock {
        let baseFontSize = CanvasTextLayoutMeasurer.renderFontSize(
            for: style,
            scale: scale
        )
        switch block {
        case let .heading(level, text):
            let multiplier = headingFontSizeMultiplier(for: level)
            let fontSize = max(baseFontSize * multiplier, 1)
            let attributed = makeInlineAttributedText(
                from: text,
                style: style,
                fontSize: fontSize,
                traits: .plain.merging(isBold: true),
                defaultColor: platformColor(for: style.color)
            )
            applyParagraphStyle(
                to: attributed,
                fontSize: fontSize,
                paragraphSpacing: fontSize * blockSpacingFactor
            )
            return RenderedBlock(
                block: block,
                attributedText: attributed
            )

        case let .paragraph(text):
            let attributed = makeInlineAttributedText(
                from: text,
                style: style,
                fontSize: baseFontSize,
                traits: .plain,
                defaultColor: platformColor(for: style.color)
            )
            applyParagraphStyle(
                to: attributed,
                fontSize: baseFontSize,
                paragraphSpacing: baseFontSize * blockSpacingFactor
            )
            return RenderedBlock(
                block: block,
                attributedText: attributed
            )

        case let .unorderedList(items):
            return RenderedBlock(
                block: block,
                attributedText: makeListBlock(
                    items: items.enumerated().map { _, item in
                        (prefix: unorderedListPrefix, text: item)
                    },
                    style: style,
                    fontSize: baseFontSize
                )
            )

        case let .orderedList(items):
            return RenderedBlock(
                block: block,
                attributedText: makeListBlock(
                    items: items.map { item in
                        (prefix: "\(item.number). ", text: item.text)
                    },
                    style: style,
                    fontSize: baseFontSize
                )
            )

        case let .quote(text):
            let quoteText = text
                .components(separatedBy: "\n")
                .map { "\(quotePrefix)\($0)" }
                .joined(separator: "\n")
            let attributed = makeInlineAttributedText(
                from: quoteText,
                style: style,
                fontSize: baseFontSize,
                traits: .plain.merging(isItalic: true),
                defaultColor: platformColor(
                    for: style.color,
                    alphaMultiplier: 0.82
                )
            )
            applyParagraphStyle(
                to: attributed,
                fontSize: baseFontSize,
                headIndent: baseFontSize * quoteHeadIndentFactor,
                paragraphSpacing: baseFontSize * blockSpacingFactor
            )
            return RenderedBlock(
                block: block,
                attributedText: attributed
            )

        case let .codeBlock(text):
            let attributed = makeLeafAttributedText(
                from: text.isEmpty ? " " : text,
                style: style,
                fontSize: baseFontSize * 0.95,
                traits: .plain.merging(isCode: true),
                color: platformColor(for: style.color),
                // Stage 1 moves fenced code block semantics to decorations while
                // keeping an attributed-text fallback for current renderers.
                includesCodeBackground: includeCompatibilityCodeBlockBackgrounds
            )
            applyParagraphStyle(
                to: attributed,
                fontSize: baseFontSize,
                firstLineHeadIndent: baseFontSize * codeBlockInsetFactor,
                headIndent: baseFontSize * codeBlockInsetFactor,
                paragraphSpacing: baseFontSize * blockSpacingFactor
            )
            return RenderedBlock(
                block: block,
                attributedText: attributed
            )
        }
    }

    private static func makeListBlock(
        items: [(prefix: String, text: String)],
        style: CanvasTextStyle,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let composed = NSMutableAttributedString(string: "")
        let bulletIndent = fontSize * listHeadIndentFactor
        for (index, item) in items.enumerated() {
            if index > 0 {
                composed.append(NSAttributedString(string: "\n"))
            }
            let itemAttributed = makeInlineAttributedText(
                from: "\(item.prefix)\(item.text)",
                style: style,
                fontSize: fontSize,
                traits: .plain,
                defaultColor: platformColor(for: style.color)
            )
            applyParagraphStyle(
                to: itemAttributed,
                fontSize: fontSize,
                firstLineHeadIndent: 0,
                headIndent: bulletIndent,
                paragraphSpacing: 0
            )
            composed.append(itemAttributed)
        }
        return composed
    }

    private static func applyParagraphStyle(
        to attributed: NSMutableAttributedString,
        fontSize: CGFloat,
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        paragraphSpacing: CGFloat
    ) {
        guard attributed.length > 0 else {
            return
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = fontSize * lineSpacingFactor
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.firstLineHeadIndent = firstLineHeadIndent
        paragraphStyle.headIndent = headIndent
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
    }

    private static func makeInlineAttributedText(
        from text: String,
        style: CanvasTextStyle,
        fontSize: CGFloat,
        traits: InlineTraits,
        defaultColor: CanvasMarkdownPlatformColor
    ) -> NSMutableAttributedString {
        let composed = NSMutableAttributedString(string: "")
        var cursor = text.startIndex
        var plainBuffer = ""

        func flushPlainBuffer() {
            guard plainBuffer.isEmpty == false else {
                return
            }
            composed.append(
                makeLeafAttributedText(
                    from: plainBuffer,
                    style: style,
                    fontSize: fontSize,
                    traits: traits,
                    color: defaultColor
                )
            )
            plainBuffer = ""
        }

        while cursor < text.endIndex {
            if text[cursor...].hasPrefix("**"),
               let closingRange = text.range(
                of: "**",
                range: text.index(cursor, offsetBy: 2)..<text.endIndex
               )
            {
                flushPlainBuffer()
                let innerStart = text.index(cursor, offsetBy: 2)
                let innerText = String(text[innerStart..<closingRange.lowerBound])
                composed.append(
                    makeInlineAttributedText(
                        from: innerText,
                        style: style,
                        fontSize: fontSize,
                        traits: traits.merging(isBold: true),
                        defaultColor: defaultColor
                    )
                )
                cursor = closingRange.upperBound
                continue
            }

            if text[cursor...].hasPrefix("__"),
               let closingRange = text.range(
                of: "__",
                range: text.index(cursor, offsetBy: 2)..<text.endIndex
               )
            {
                flushPlainBuffer()
                let innerStart = text.index(cursor, offsetBy: 2)
                let innerText = String(text[innerStart..<closingRange.lowerBound])
                composed.append(
                    makeInlineAttributedText(
                        from: innerText,
                        style: style,
                        fontSize: fontSize,
                        traits: traits.merging(isBold: true),
                        defaultColor: defaultColor
                    )
                )
                cursor = closingRange.upperBound
                continue
            }

            if text[cursor] == "`",
               let closingIndex = text[text.index(after: cursor)...].firstIndex(of: "`")
            {
                flushPlainBuffer()
                let innerStart = text.index(after: cursor)
                let innerText = String(text[innerStart..<closingIndex])
                composed.append(
                    makeLeafAttributedText(
                        from: innerText,
                        style: style,
                        fontSize: fontSize,
                        traits: traits.merging(isCode: true),
                        color: defaultColor
                    )
                )
                cursor = text.index(after: closingIndex)
                continue
            }

            if text[cursor] == "*",
               let closingIndex = text[text.index(after: cursor)...].firstIndex(of: "*")
            {
                flushPlainBuffer()
                let innerStart = text.index(after: cursor)
                let innerText = String(text[innerStart..<closingIndex])
                composed.append(
                    makeInlineAttributedText(
                        from: innerText,
                        style: style,
                        fontSize: fontSize,
                        traits: traits.merging(isItalic: true),
                        defaultColor: defaultColor
                    )
                )
                cursor = text.index(after: closingIndex)
                continue
            }

            if text[cursor] == "_",
               let closingIndex = text[text.index(after: cursor)...].firstIndex(of: "_")
            {
                flushPlainBuffer()
                let innerStart = text.index(after: cursor)
                let innerText = String(text[innerStart..<closingIndex])
                composed.append(
                    makeInlineAttributedText(
                        from: innerText,
                        style: style,
                        fontSize: fontSize,
                        traits: traits.merging(isItalic: true),
                        defaultColor: defaultColor
                    )
                )
                cursor = text.index(after: closingIndex)
                continue
            }

            plainBuffer.append(text[cursor])
            cursor = text.index(after: cursor)
        }

        flushPlainBuffer()
        if composed.length == 0 {
            composed.append(
                makeLeafAttributedText(
                    from: " ",
                    style: style,
                    fontSize: fontSize,
                    traits: traits,
                    color: defaultColor
                )
            )
        }
        return composed
    }

    private static func makeLeafAttributedText(
        from text: String,
        style: CanvasTextStyle,
        fontSize: CGFloat,
        traits: InlineTraits,
        color: CanvasMarkdownPlatformColor,
        includesCodeBackground: Bool = true
    ) -> NSMutableAttributedString {
        let resolvedText = text.isEmpty ? " " : text
        let attributed = NSMutableAttributedString(
            string: resolvedText,
            attributes: [
                .font: platformFont(
                    named: style.fontName,
                    size: fontSize,
                    traits: traits
                ),
                .foregroundColor: color
            ]
        )
        if traits.isCode && includesCodeBackground {
            attributed.addAttribute(
                .backgroundColor,
                value: codeBackgroundColor(),
                range: NSRange(location: 0, length: attributed.length)
            )
        }
        return attributed
    }

    private static func makeCodeBlockDecorations(
        codeBlockRanges: [NSRange],
        layoutContext: TextLayoutContext,
        style: CanvasTextStyle,
        scale: CGFloat,
        contentSize: CGSize
    ) -> [CanvasMarkdownDecoration] {
        guard codeBlockRanges.isEmpty == false else {
            return []
        }

        let metrics = codeBlockDecorationMetrics(
            style: style,
            scale: scale
        )
        let contentBounds = CGRect(origin: .zero, size: contentSize)
        return codeBlockRanges.compactMap { characterRange in
            guard let rect = codeBlockDecorationRect(
                for: characterRange,
                layoutContext: layoutContext,
                contentBounds: contentBounds,
                metrics: metrics
            ) else {
                return nil
            }
            return CanvasMarkdownDecoration(
                kind: .codeBlockPanel,
                rect: rect,
                fillColor: codeDecorationFillColor(),
                cornerRadius: metrics.cornerRadius
            )
        }
    }

    private static func measuredUsedContentBounds(
        layoutContext: TextLayoutContext,
        contentSize: CGSize,
        decorations: [CanvasMarkdownDecoration]
    ) -> CGRect {
        let contentBounds = CGRect(origin: .zero, size: contentSize)
        let glyphRange = layoutContext.layoutManager.glyphRange(
            for: layoutContext.textContainer
        )
        var resolvedBounds = standardizedVisibleRect(
            usedRect(
                forGlyphRange: glyphRange,
                layoutContext: layoutContext
            ),
            within: contentBounds
        )
        for decoration in decorations {
            guard let clippedRect = standardizedVisibleRect(
                decoration.rect,
                within: contentBounds
            ) else {
                continue
            }
            resolvedBounds = resolvedBounds.map { $0.union(clippedRect).standardized }
                ?? clippedRect
        }
        return resolvedBounds ?? .zero
    }

    private static func makeTextLayoutContext(
        attributedText: NSAttributedString,
        maxLayoutWidth: CGFloat
    ) -> TextLayoutContext {
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(
                width: max(maxLayoutWidth, 1),
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        _ = layoutManager.glyphRange(for: textContainer)
        return TextLayoutContext(
            textStorage: textStorage,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
    }

    private static func codeBlockDecorationRect(
        for characterRange: NSRange,
        layoutContext: TextLayoutContext,
        contentBounds: CGRect,
        metrics: CodeBlockDecorationMetrics
    ) -> CGRect? {
        let glyphRange = layoutContext.layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else {
            return nil
        }

        guard let blockUsedRect = usedRect(
            forGlyphRange: glyphRange,
            layoutContext: layoutContext
        ) else {
            return nil
        }

        let expandedRect = blockUsedRect.insetBy(
            dx: -metrics.horizontalPadding,
            dy: -metrics.verticalPadding
        )
        return standardizedVisibleRect(
            expandedRect,
            within: contentBounds
        )
    }

    private static func usedRect(
        forGlyphRange glyphRange: NSRange,
        layoutContext: TextLayoutContext
    ) -> CGRect? {
        guard glyphRange.length > 0 else {
            return nil
        }

        var resolvedUsedRect: CGRect?
        layoutContext.layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            _,
            usedRect,
            _,
            lineGlyphRange,
            _
        in
            guard NSIntersectionRange(lineGlyphRange, glyphRange).length > 0 else {
                return
            }
            resolvedUsedRect = resolvedUsedRect.map { $0.union(usedRect) } ?? usedRect
        }
        return resolvedUsedRect
    }

    private static func standardizedVisibleRect(
        _ rect: CGRect?,
        within contentBounds: CGRect
    ) -> CGRect? {
        guard let rect else {
            return nil
        }
        let clippedRect = rect.intersection(contentBounds)
        guard clippedRect.isNull == false, clippedRect.isEmpty == false else {
            return nil
        }
        return CGRect(
            x: floor(clippedRect.minX),
            y: floor(clippedRect.minY),
            width: ceil(clippedRect.width),
            height: ceil(clippedRect.height)
        ).standardized
    }

    private static func parseBlocks(from markdownSource: String) -> [Block] {
        let normalizedSource = markdownSource.replacingOccurrences(
            of: "\r\n",
            with: "\n"
        )
        let lines = normalizedSource.components(separatedBy: "\n")
        var blocks: [Block] = []
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                lineIndex += 1
                continue
            }

            if trimmedLine.hasPrefix("```") {
                lineIndex += 1
                var codeLines: [String] = []
                while lineIndex < lines.count {
                    let codeLine = lines[lineIndex]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        lineIndex += 1
                        break
                    }
                    codeLines.append(codeLine)
                    lineIndex += 1
                }
                blocks.append(.codeBlock(text: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = headingBlock(from: line) {
                blocks.append(heading)
                lineIndex += 1
                continue
            }

            if let unorderedItem = unorderedListItem(from: line) {
                var items = [unorderedItem]
                lineIndex += 1
                while lineIndex < lines.count,
                      let nextItem = unorderedListItem(from: lines[lineIndex])
                {
                    items.append(nextItem)
                    lineIndex += 1
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            if let orderedItem = orderedListItem(from: line) {
                var items = [orderedItem]
                lineIndex += 1
                while lineIndex < lines.count,
                      let nextItem = orderedListItem(from: lines[lineIndex])
                {
                    items.append(nextItem)
                    lineIndex += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            if let initialQuoteLine = quoteLine(from: line) {
                var quoteLines = [initialQuoteLine]
                lineIndex += 1
                while lineIndex < lines.count,
                      let nextQuoteLine = quoteLine(from: lines[lineIndex])
                {
                    quoteLines.append(nextQuoteLine)
                    lineIndex += 1
                }
                blocks.append(.quote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            var paragraphLines = [trimmedLine]
            lineIndex += 1
            while lineIndex < lines.count {
                let nextLine = lines[lineIndex]
                let trimmedNextLine = nextLine.trimmingCharacters(in: .whitespaces)
                if trimmedNextLine.isEmpty ||
                    trimmedNextLine.hasPrefix("```") ||
                    headingBlock(from: nextLine) != nil ||
                    unorderedListItem(from: nextLine) != nil ||
                    orderedListItem(from: nextLine) != nil ||
                    quoteLine(from: nextLine) != nil
                {
                    break
                }
                paragraphLines.append(trimmedNextLine)
                lineIndex += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func headingBlock(from line: String) -> Block? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        var cursor = trimmedLine.startIndex
        while cursor < trimmedLine.endIndex, trimmedLine[cursor] == "#" {
            level += 1
            cursor = trimmedLine.index(after: cursor)
        }
        guard
            level > 0,
            level <= headingFontMultipliers.count,
            cursor < trimmedLine.endIndex,
            trimmedLine[cursor] == " "
        else {
            return nil
        }
        let textStart = trimmedLine.index(after: cursor)
        let text = trimmedLine[textStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            return nil
        }
        return .heading(level: level, text: text)
    }

    private static func unorderedListItem(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard
            trimmedLine.count >= 3,
            ["- ", "* ", "+ "].contains(String(trimmedLine.prefix(2)))
        else {
            return nil
        }
        let content = trimmedLine.dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private static func orderedListItem(from line: String) -> (number: Int, text: String)? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmedLine.firstIndex(of: ".") else {
            return nil
        }
        let numberText = trimmedLine[..<dotIndex]
        guard
            numberText.isEmpty == false,
            numberText.allSatisfy(\.isNumber)
        else {
            return nil
        }
        let contentStart = trimmedLine.index(after: dotIndex)
        guard
            contentStart < trimmedLine.endIndex,
            trimmedLine[contentStart].isWhitespace
        else {
            return nil
        }
        let content = trimmedLine[contentStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            content.isEmpty == false,
            let number = Int(numberText)
        else {
            return nil
        }
        return (number, content)
    }

    private static func quoteLine(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix(">") else {
            return nil
        }
        let quoteBody = trimmedLine.dropFirst()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return quoteBody.isEmpty ? " " : quoteBody
    }

    private static func headingFontSizeMultiplier(for level: Int) -> CGFloat {
        let resolvedIndex = min(max(level - 1, 0), headingFontMultipliers.count - 1)
        return headingFontMultipliers[resolvedIndex]
    }

    private static func minimumContentHeight(
        style: CanvasTextStyle,
        scale: CGFloat
    ) -> CGFloat {
        CanvasTextLayoutMeasurer.renderFontSize(
            for: style,
            scale: scale
        ) * 1.35
    }

    private static func codeBlockDecorationMetrics(
        style: CanvasTextStyle,
        scale: CGFloat
    ) -> CodeBlockDecorationMetrics {
        let baseFontSize = CanvasTextLayoutMeasurer.renderFontSize(
            for: style,
            scale: scale
        )
        return CodeBlockDecorationMetrics(
            horizontalPadding: clamped(
                baseFontSize * codeBlockPanelHorizontalPaddingFactor,
                min: minimumCodeBlockPanelHorizontalPadding,
                max: maximumCodeBlockPanelHorizontalPadding
            ),
            verticalPadding: clamped(
                baseFontSize * codeBlockPanelVerticalPaddingFactor,
                min: minimumCodeBlockPanelVerticalPadding,
                max: maximumCodeBlockPanelVerticalPadding
            ),
            cornerRadius: clamped(
                baseFontSize * codeBlockPanelCornerRadiusFactor,
                min: minimumCodeBlockPanelCornerRadius,
                max: maximumCodeBlockPanelCornerRadius
            )
        )
    }

    private static func clamped(
        _ value: CGFloat,
        min minimumValue: CGFloat,
        max maximumValue: CGFloat
    ) -> CGFloat {
        Swift.min(Swift.max(value, minimumValue), maximumValue)
    }

    private static func platformColor(
        for color: CanvasTextColor,
        alphaMultiplier: CGFloat = 1
    ) -> CanvasMarkdownPlatformColor {
        CanvasMarkdownPlatformColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: min(max(color.alpha * alphaMultiplier, 0), 1)
        )
    }

    private static func codeDecorationFillColor() -> CanvasTextColor {
        CanvasTextColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0.08
        )
    }

    private static func codeBackgroundColor() -> CanvasMarkdownPlatformColor {
        platformColor(for: codeDecorationFillColor())
    }

    private static func platformFont(
        named fontName: String,
        size: CGFloat,
        traits: InlineTraits
    ) -> CanvasMarkdownPlatformFont {
        let resolvedSize = max(size, 1)
        if traits.isCode {
            return codePlatformFont(
                size: resolvedSize,
                bold: traits.isBold,
                italic: traits.isItalic
            )
        }

        let baseFont = basePlatformFont(
            named: fontName,
            size: resolvedSize,
            bold: traits.isBold
        )
        guard traits.isItalic else {
            return baseFont
        }
        return italicPlatformFont(from: baseFont)
    }

    private static func basePlatformFont(
        named fontName: String,
        size: CGFloat,
        bold: Bool
    ) -> CanvasMarkdownPlatformFont {
        #if os(macOS)
        let weight: NSFont.Weight = bold ? .bold : .regular
        if fontName == "System" || fontName.isEmpty {
            return CanvasMarkdownPlatformFont.systemFont(
                ofSize: size,
                weight: weight
            )
        }
        return CanvasMarkdownPlatformFont(name: fontName, size: size) ??
            CanvasMarkdownPlatformFont.systemFont(
                ofSize: size,
                weight: weight
            )
        #else
        let weight: UIFont.Weight = bold ? .bold : .regular
        if fontName == "System" || fontName.isEmpty {
            return CanvasMarkdownPlatformFont.systemFont(
                ofSize: size,
                weight: weight
            )
        }
        return CanvasMarkdownPlatformFont(name: fontName, size: size) ??
            CanvasMarkdownPlatformFont.systemFont(
                ofSize: size,
                weight: weight
            )
        #endif
    }

    private static func codePlatformFont(
        size: CGFloat,
        bold: Bool,
        italic: Bool
    ) -> CanvasMarkdownPlatformFont {
        #if os(macOS)
        let baseFont = CanvasMarkdownPlatformFont.monospacedSystemFont(
            ofSize: size,
            weight: bold ? .bold : .regular
        )
        return italic ? italicPlatformFont(from: baseFont) : baseFont
        #else
        let baseFont = CanvasMarkdownPlatformFont.monospacedSystemFont(
            ofSize: size,
            weight: bold ? .bold : .regular
        )
        return italic ? italicPlatformFont(from: baseFont) : baseFont
        #endif
    }

    private static func italicPlatformFont(
        from font: CanvasMarkdownPlatformFont
    ) -> CanvasMarkdownPlatformFont {
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        let symbolicTraits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(symbolicTraits) else {
            return font
        }
        return CanvasMarkdownPlatformFont(
            descriptor: descriptor,
            size: font.pointSize
        )
        #endif
    }
}
