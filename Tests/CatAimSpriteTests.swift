import Foundation
import CoreGraphics
import ImageIO

@main
private struct CatAimSpriteTests {
    static func main() {
        let path = CommandLine.arguments.dropFirst().first ?? "SumibiKeyboard/PersianCatAim.png"
        let url = URL(fileURLWithPath: path)
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let full = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(full.width == full.height && full.width % 3 == 0)
        // Validate the same small decode used by the keyboard, not just the original sheet.
        let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 192,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)!
        precondition(small.width == 192 && small.height == 192)
        for sheet in [full, small] {
            let w = sheet.width, h = sheet.height, cell = w / 3
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            rgba.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(sheet, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            var frames = Set<Data>()
            let cropped = CatHuntSpriteSheet.frames(from: sheet)
            precondition(cropped.count == 9)
            for index in 0..<9 {
                let x0 = index % 3 * cell, y0 = index / 3 * cell
                var data = Data(), visible = 0
                for y in 0..<cell { for x in 0..<cell {
                    let offset = ((y0 + y) * w + x0 + x) * 4
                    let alpha = rgba[offset + 3]
                    if alpha > 50 { visible += 1 }
                    if x == 0 || y == 0 || x == cell - 1 || y == cell - 1 {
                        precondition(alpha <= 2, "Visible pixels must not cross cell boundaries")
                    }
                    data.append(contentsOf: rgba[offset..<offset + 4])
                } }
                precondition(visible > cell * cell / 10, "Every pose must contain a cat")
                // Exercise the production cropper: asymmetric padding must not clip face/tail.
                precondition(visiblePixelCount(cropped[index]) == visible,
                             "Cropping must preserve every visible cat pixel")
                frames.insert(data)
            }
            precondition(frames.count == 9, "All nine drawn frames must be distinct")
        }
        print("Cat sprite checks passed: square 3x3 sheet, nine distinct poses, transparent gutters, 192px runtime decode, no clipped face/tail pixels")
    }

    static func visiblePixelCount(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return stride(from: 3, to: rgba.count, by: 4).reduce(0) { $0 + (rgba[$1] > 50 ? 1 : 0) }
    }
}
