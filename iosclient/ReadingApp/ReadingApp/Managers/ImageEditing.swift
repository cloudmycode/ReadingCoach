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
