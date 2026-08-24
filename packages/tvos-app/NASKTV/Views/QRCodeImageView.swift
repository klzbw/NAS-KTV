import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - QRCodeImageView
struct QRCodeImageView: View {
    let content: String
    var size: CGFloat = 200

    private var qrImage: UIImage? {
        guard !content.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaleX = size / outputImage.extent.width
        let scaleY = size / outputImage.extent.height
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        if let image = qrImage {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(Color.white)
                .cornerRadius(4)
        } else {
            ProgressView()
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
        }
    }
}
