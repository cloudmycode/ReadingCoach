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

    /// 将任意四边形（UIKit 像素坐标，原点左上）透视矫正为正矩形。
    /// 角点顺序：左上 → 右上 → 右下 → 左下。
    func perspectiveCorrected(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) -> UIImage? {
        guard let cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 1, height > 1 else { return nil }

        let uiPoints = [topLeft, topRight, bottomRight, bottomLeft].map {
            CGPoint(
                x: min(max($0.x, 0), width),
                y: min(max($0.y, 0), height)
            )
        }
        guard Self.isConvexQuadrilateral(uiPoints) else { return nil }

        // CIImage 坐标系原点在左下，Y 轴向上；UIKit 原点在左上。
        let toCI: (CGPoint) -> CGPoint = { CGPoint(x: $0.x, y: height - $0.y) }
        let ciTL = toCI(uiPoints[0])
        let ciTR = toCI(uiPoints[1])
        let ciBR = toCI(uiPoints[2])
        let ciBL = toCI(uiPoints[3])

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: ciTL), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: ciTR), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: ciBR), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: ciBL), forKey: "inputBottomLeft")

        guard let output = filter.outputImage else { return nil }
        return render(output)
    }

    /// 四点是否为凸四边形且面积足够（防止交叉/退化）。
    private static func isConvexQuadrilateral(_ points: [CGPoint]) -> Bool {
        guard points.count == 4 else { return false }
        // 叉积符号应一致
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = points[i]
            let b = points[(i + 1) % 4]
            let c = points[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-3 { return false }
            if sign == 0 {
                sign = cross > 0 ? 1 : -1
            } else if cross * sign < 0 {
                return false
            }
        }
        // 面积（鞋带公式）不能太小
        var area: CGFloat = 0
        for i in 0..<4 {
            let p = points[i]
            let q = points[(i + 1) % 4]
            area += p.x * q.y - q.x * p.y
        }
        return abs(area) > 100
    }

    private func render(_ source: CIImage) -> UIImage? {
        let extent = source.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
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
