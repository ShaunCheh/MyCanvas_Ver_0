import CoreGraphics
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

struct CanvasMarkdownLayoutResult {
    let attributedText: NSAttributedString
    let contentSize: CGSize

    var contentHeight: CGFloat {
        contentSize.height
    }
}

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
    private static let quotePrefix = "▌ "
    private static let unorderedListPrefix = "• "

    static func layout(
        markdownSource: String,
        style: CanvasTextStyle,
        maxLayoutWidth: CGFloat,
        scale: CGFloat = 1
    ) -> CanvasMarkdownLayoutResult {
        let resolvedLayoutWidth = max(maxLayoutWidth, 1)
        let attributedText = makeAttributedText(
            markdownSource: markdownSource,
            style: style,
            scale: scale
        )
        let measuredRect = attributedText.boundingRect(
            with: CGSize(
                width: resolvedLayoutWidth,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [
                .usesLineFragmentOrigin,
                .usesFontLeading
            ],
            context: nil
        )
        return CanvasMarkdownLayoutResult(
            attributedText: attributedText,
            contentSize: CGSize(
                width: resolvedLayoutWidth,
                height: ceil(max(measuredRect.height, minimumContentHeight(
                    style: style,
                    scale: scale
                )))
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

    private static func makeAttributedText(
        markdownSource: String,
        style: CanvasTextStyle,
        scale: CGFloat
    ) -> NSAttributedString {
        let blocks = parseBlocks(from: markdownSource)
        let resolvedBlocks = blocks.isEmpty
            ? [.paragraph(text: markdownSource)]
            : blocks
        let renderedBlocks = resolvedBlocks.map { block in
            makeAttributedBlock(
                for: block,
                style: style,
                scale: scale
            )
        }
        let composed = NSMutableAttributedString(string: "")
        for (index, block) in renderedBlocks.enumerated() {
            if index > 0 {
                composed.append(NSAttributedString(string: "\n\n"))
            }
            composed.append(block)
        }
        return composed
    }

    private static func makeAttributedBlock(
        for block: Block,
        style: CanvasTextStyle,
        scale: CGFloat
    ) -> NSAttributedString {
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
            return attributed

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
            return attributed

        case let .unorderedList(items):
            return makeListBlock(
                items: items.enumerated().map { _, item in
                    (prefix: unorderedListPrefix, text: item)
                },
                style: style,
                fontSize: baseFontSize
            )

        case let .orderedList(items):
            return makeListBlock(
                items: items.map { item in
                    (prefix: "\(item.number). ", text: item.text)
                },
                style: style,
                fontSize: baseFontSize
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
            return attributed

        case let .codeBlock(text):
            let attributed = makeLeafAttributedText(
                from: text.isEmpty ? " " : text,
                style: style,
                fontSize: baseFontSize * 0.95,
                traits: .plain.merging(isCode: true),
                color: platformColor(for: style.color)
            )
            attributed.addAttribute(
                .backgroundColor,
                value: codeBackgroundColor(),
                range: NSRange(location: 0, length: attributed.length)
            )
            applyParagraphStyle(
                to: attributed,
                fontSize: baseFontSize,
                firstLineHeadIndent: baseFontSize * codeBlockInsetFactor,
                headIndent: baseFontSize * codeBlockInsetFactor,
                paragraphSpacing: baseFontSize * blockSpacingFactor
            )
            return attributed
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
        color: CanvasMarkdownPlatformColor
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
        if traits.isCode {
            attributed.addAttribute(
                .backgroundColor,
                value: codeBackgroundColor(),
                range: NSRange(location: 0, length: attributed.length)
            )
        }
        return attributed
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

    private static func codeBackgroundColor() -> CanvasMarkdownPlatformColor {
        #if os(macOS)
        return CanvasMarkdownPlatformColor(
            calibratedWhite: 0,
            alpha: 0.08
        )
        #else
        return CanvasMarkdownPlatformColor(
            white: 0,
            alpha: 0.08
        )
        #endif
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
