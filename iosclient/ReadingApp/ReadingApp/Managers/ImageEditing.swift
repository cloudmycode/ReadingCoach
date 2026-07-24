import CoreImage
import UIKit

extension UIImage {
    var normalizedForEditing: UIImage? {
        guard let cgImage else { return nil }
        guard imageOrientation != .up else {
            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }

        return render(
            CIImage(cgImage: cgImage)
                .oriented(forExifOrientation: imageOrientation.exifOrientation)
        )
    }

    func rotatedLeft() -> UIImage? {
        guard let cgImage else { return nil }
        return render(CIImage(cgImage: cgImage).oriented(.left))
    }

    /// 将图片等比缩放到最长边不超过 maxDimension（像素）。
    /// 用于上传前降采样：过高分辨率会显著拖慢云端 OCR，且文档识别并不需要原始像素。
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let pixelWidth = CGFloat(cgImage?.width ?? Int(size.width))
        let pixelHeight = CGFloat(cgImage?.height ?? Int(size.height))
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > maxDimension, longestSide > 0 else { return self }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(
            width: (pixelWidth * scale).rounded(),
            height: (pixelHeight * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func render(_ source: CIImage) -> UIImage? {
        let extent = source.extent.integral
        let normalized = source.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        guard let output = CIContext().createCGImage(normalized, from: normalized.extent) else {
            return nil
        }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }
}

private extension UIImage.Orientation {
    var exifOrientation: Int32 {
        switch self {
        case .up: 1
        case .upMirrored: 2
        case .down: 3
        case .downMirrored: 4
        case .leftMirrored: 5
        case .right: 6
        case .rightMirrored: 7
        case .left: 8
        @unknown default: 1
        }
    }
}
