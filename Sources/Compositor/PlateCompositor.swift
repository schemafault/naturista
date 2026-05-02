import Foundation
import AppKit
import CoreGraphics

enum CompositorError: Error, LocalizedError {
    case illustrationNotFound
    case cannotCreateImage
    case cannotCreateDestination
    case writeFailed
    case textureGenerationFailed

    var errorDescription: String? {
        switch self {
        case .illustrationNotFound:
            return "Illustration file not found."
        case .cannotCreateImage:
            return "Cannot create image from illustration file."
        case .cannotCreateDestination:
            return "Cannot create output destination."
        case .writeFailed:
            return "Failed to write composed plate."
        case .textureGenerationFailed:
            return "Failed to generate paper texture."
        }
    }
}

struct PlateCompositor {
    static func compose(
        entryId: UUID,
        commonName: String,
        scientificName: String,
        family: String,
        notes: String,
        illustrationFilename: String
    ) async throws -> String {
        let illustrationURL = AppPaths.illustrations.appendingPathComponent(illustrationFilename)
        guard FileManager.default.fileExists(atPath: illustrationURL.path) else {
            throw CompositorError.illustrationNotFound
        }

        guard let illustrationImage = NSImage(contentsOf: illustrationURL) else {
            throw CompositorError.cannotCreateImage
        }

        let count = try await DatabaseService.shared.getEntryCount()
        let plateNumber = count + 1

        let plateImage = createPlateImage(
            illustration: illustrationImage,
            commonName: commonName,
            scientificName: scientificName,
            family: family,
            notes: notes,
            plateNumber: plateNumber
        )

        let plateFilename = "\(entryId.uuidString)_plate.png"
        let plateURL = AppPaths.plates.appendingPathComponent(plateFilename)

        guard let tiffData = plateImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CompositorError.writeFailed
        }

        try pngData.write(to: plateURL)

        return plateFilename
    }

    private static func createPlateImage(
        illustration: NSImage,
        commonName: String,
        scientificName: String,
        family: String,
        notes: String,
        plateNumber: Int
    ) -> NSImage {
        let width: CGFloat = 2480
        let height: CGFloat = 3508
        let margin: CGFloat = 80
        let borderWidth: CGFloat = 4

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            let paperColor = NSColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1.0)
            context.setFillColor(paperColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            if let noiseTexture = generatePaperTexture(width: Int(width), height: Int(height)) {
                context.setBlendMode(.overlay)
                context.draw(noiseTexture, in: CGRect(x: 0, y: 0, width: width, height: height))
                context.setBlendMode(.normal)
            }

            let borderInset = borderWidth / 2 + 20
            context.setStrokeColor(NSColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 0.8).cgColor)
            context.setLineWidth(borderWidth)
            context.stroke(CGRect(x: borderInset, y: borderInset, width: width - borderInset * 2, height: height - borderInset * 2))

            let innerBorderInset = borderInset + 15
            context.setStrokeColor(NSColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 0.4).cgColor)
            context.setLineWidth(1)
            context.stroke(CGRect(x: innerBorderInset, y: innerBorderInset, width: width - innerBorderInset * 2, height: height - innerBorderInset * 2))

            let titleFont = NSFont.systemFont(ofSize: 120, weight: .bold)
            let italicFont = NSFont.systemFont(ofSize: 72).withTraits(.italic)
            let familyFont = NSFont.systemFont(ofSize: 48, weight: .regular)
            let notesFont = NSFont.systemFont(ofSize: 42, weight: .regular)
            let plateNumberFont = NSFont.systemFont(ofSize: 36, weight: .medium)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1.0)
            ]

            let scientificAttributes: [NSAttributedString.Key: Any] = [
                .font: italicFont,
                .foregroundColor: NSColor(red: 0.25, green: 0.2, blue: 0.15, alpha: 1.0)
            ]

            let familyAttributes: [NSAttributedString.Key: Any] = [
                .font: familyFont,
                .foregroundColor: NSColor(red: 0.4, green: 0.35, blue: 0.3, alpha: 1.0)
            ]

            let titleSize = commonName.size(withAttributes: titleAttributes)
            let availableWidth = width - margin * 2
            let headerY = height - margin - 200

            let titleX = (width - titleSize.width) / 2
            (commonName as NSString).draw(at: CGPoint(x: titleX, y: headerY - titleSize.height), withAttributes: titleAttributes)

            let scientificSize = scientificName.size(withAttributes: scientificAttributes)
            let scientificY = headerY - titleSize.height - 30
            let scientificX = (width - scientificSize.width) / 2
            (scientificName as NSString).draw(at: CGPoint(x: scientificX, y: scientificY - scientificSize.height), withAttributes: scientificAttributes)

            let familySize = family.size(withAttributes: familyAttributes)
            let familyY = scientificY - scientificSize.height - 20
            let familyX = (width - familySize.width) / 2
            ("Family: \(family)" as NSString).draw(at: CGPoint(x: familyX, y: familyY - familySize.height), withAttributes: familyAttributes)

            let illustrationMaxWidth = availableWidth - 100
            let illustrationMaxHeight = familyY - margin - 600

            guard let cgIllustration = illustration.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                image.unlockFocus()
                return image
            }

            let illustrationAspect = CGFloat(cgIllustration.width) / CGFloat(cgIllustration.height)
            var illustrationDrawWidth: CGFloat
            var illustrationDrawHeight: CGFloat

            if illustrationAspect > illustrationMaxWidth / illustrationMaxHeight {
                illustrationDrawWidth = illustrationMaxWidth
                illustrationDrawHeight = illustrationMaxWidth / illustrationAspect
            } else {
                illustrationDrawHeight = illustrationMaxHeight
                illustrationDrawWidth = illustrationMaxHeight * illustrationAspect
            }

            let illustrationX = (width - illustrationDrawWidth) / 2
            let illustrationY = familyY - familySize.height - 80 - illustrationDrawHeight

            context.saveGState()
            context.translateBy(x: illustrationX, y: illustrationY)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgIllustration, in: CGRect(x: 0, y: 0, width: illustrationDrawWidth, height: illustrationDrawHeight))
            context.restoreGState()

            let notesPanelMinY: CGFloat = margin + 150

            if !notes.isEmpty {
                let notesLabelFont = NSFont.systemFont(ofSize: 48, weight: .semibold)
                let notesLabelAttributes: [NSAttributedString.Key: Any] = [
                    .font: notesLabelFont,
                    .foregroundColor: NSColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 1.0)
                ]

                let notesLabel = "Notes"
                let notesLabelSize = notesLabel.size(withAttributes: notesLabelAttributes)
                let notesTextY = notesPanelMinY + 80 + notesLabelSize.height + 60

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                paragraphStyle.lineBreakMode = .byWordWrapping

                let notesBodyAttributes: [NSAttributedString.Key: Any] = [
                    .font: notesFont,
                    .foregroundColor: NSColor(red: 0.25, green: 0.22, blue: 0.18, alpha: 1.0),
                    .paragraphStyle: paragraphStyle
                ]

                let notesTextRect = CGRect(x: margin + 60, y: margin + 60, width: availableWidth - 120, height: notesTextY - margin - 60)
                let boundingRect = notes.boundingRect(
                    with: CGSize(width: notesTextRect.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: notesBodyAttributes,
                    context: nil
                )

                let adjustedHeight = max(notesTextRect.height, boundingRect.height + 40)
                context.setFillColor(NSColor(red: 0.92, green: 0.90, blue: 0.84, alpha: 0.5).cgColor)
                context.fill(CGRect(x: margin + 40, y: margin + 40, width: availableWidth - 80, height: adjustedHeight + 60))

                context.setStrokeColor(NSColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 0.3).cgColor)
                context.setLineWidth(1)
                context.stroke(CGRect(x: margin + 40, y: margin + 40, width: availableWidth - 80, height: adjustedHeight + 60))

                notesLabel.draw(at: CGPoint(x: margin + 60, y: notesTextY), withAttributes: notesLabelAttributes)

                let finalNotesRect = CGRect(x: margin + 60, y: margin + 60, width: availableWidth - 120, height: notesTextY - margin - 60)
                notes.draw(in: finalNotesRect, withAttributes: notesBodyAttributes)
            }

            let plateNumberText = "Plate \(plateNumber)"
            let plateNumberAttributes: [NSAttributedString.Key: Any] = [
                .font: plateNumberFont,
                .foregroundColor: NSColor(red: 0.4, green: 0.35, blue: 0.3, alpha: 0.8)
            ]
            let plateNumberSize = plateNumberText.size(withAttributes: plateNumberAttributes)
            let plateNumberX = width - margin - plateNumberSize.width - 40
            let plateNumberY = margin + 40
            (plateNumberText as NSString).draw(at: CGPoint(x: plateNumberX, y: plateNumberY), withAttributes: plateNumberAttributes)
        }

        image.unlockFocus()
        return image
    }

    private static func generatePaperTexture(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let baseColor = NSColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1.0)
        context.setFillColor(baseColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let noiseData = calloc(width * height, MemoryLayout<UInt8>.size) else {
            return context.makeImage()
        }

        defer { free(noiseData) }

        let noiseTypedPtr = noiseData.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(width * height) {
            noiseTypedPtr[i] = UInt8.random(in: 0...30)
        }

        guard let noiseProvider = CGDataProvider(data: Data(bytes: noiseData, count: width * height) as CFData) else {
            return context.makeImage()
        }

        let noiseImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: noiseProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )

        if let noise = noiseImage {
            context.setBlendMode(.overlay)
            context.draw(noise, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        context.setBlendMode(.normal)

        return context.makeImage()
    }
}

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}