import Foundation
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pulls readable text out of whatever a share sheet hands us. Different apps
/// offer the same content under different type identifiers — ChatGPT and Claude
/// send plain text, Notes sends rich text, Files sends a URL — so each provider
/// is probed in order of preference.
@MainActor
enum SharedTextExtractor {
    private static let textTypes: [UTType] = [.utf8PlainText, .plainText, .text, .rtf, .flatRTFD]

    static func text(from items: [NSExtensionItem]) async -> String? {
        for item in items {
            for provider in item.attachments ?? [] {
                if let text = await self.text(from: provider) { return text }
            }
            // Some apps put the payload on the item itself rather than an attachment.
            if let text = item.attributedContentText?.string, !text.isBlank { return text }
        }
        return nil
    }

    private static func text(from provider: NSItemProvider) async -> String? {
        for type in textTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let text = await loadString(from: provider, typeIdentifier: type.identifier), !text.isBlank {
                return text
            }
        }

        let fileType = UTType.fileURL.identifier
        if provider.hasItemConformingToTypeIdentifier(fileType),
           let text = await loadString(from: provider, typeIdentifier: fileType), !text.isBlank {
            return text
        }

        return nil
    }

    /// The item is converted to a String inside the completion handler so only a
    /// Sendable value ever crosses back to the main actor.
    private static func loadString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: normalize(item))
            }
        }
    }

    nonisolated private static func normalize(_ item: NSSecureCoding?) -> String? {
        switch item {
        case let string as String:
            return string
        case let attributed as NSAttributedString:
            return attributed.string
        case let url as URL where url.isFileURL:
            return try? String(contentsOf: url, encoding: .utf8)
        case let data as Data:
            // Rich-text payloads sometimes arrive as raw bytes rather than an
            // NSAttributedString; decoding keeps RTF control words out of the
            // script instead of reading them aloud.
            if let rich = decodeRichText(data) { return rich }
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    nonisolated private static func decodeRichText(_ data: Data) -> String? {
        for type in [NSAttributedString.DocumentType.rtf, .rtfd] {
            if let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: type],
                documentAttributes: nil
            ) {
                return attributed.string
            }
        }
        return nil
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
