import Foundation
import AppKit
import SwiftUI

enum CompositorError: Error, LocalizedError {
    case renderFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: return "Failed to render plate."
        case .writeFailed:  return "Failed to write plate PNG."
        }
    }
}

// Rasterises the SwiftUI PlateFrameView to a PNG. The plate composition
// (typography, borders, layout) lives in SwiftUI; this just bakes that
// view into a high-resolution image for export.
enum PlateCompositor {
    // A4 portrait at 300dpi
    private static let exportSize = CGSize(width: 620, height: 877)
    private static let exportScale: CGFloat = 4.0 // → 2480 × 3508

    @MainActor
    static func renderPNG(entry: Entry, to destination: URL) throws {
        // ImageRenderer rasterises immediately and won't wait for the
        // async LocalImage loader inside PlateFrameView, so we read the
        // illustration off disk here and pass it in preloaded.
        let illustration: NSImage? = {
            guard let name = entry.illustrationFilename else { return nil }
            let url = AppPaths.illustrations.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }()

        let view = PlateFrameView(entry: entry, preloadedIllustration: illustration)
            .frame(width: exportSize.width, height: exportSize.height)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = exportScale
        renderer.proposedSize = ProposedViewSize(exportSize)

        guard let cgImage = renderer.cgImage else {
            throw CompositorError.renderFailed
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CompositorError.writeFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try pngData.write(to: destination)
    }
}
