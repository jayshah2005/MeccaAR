import SwiftUI
import UIKit

struct FaceCameraCaptureView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        var parent: FaceCameraCaptureView

        init(_ parent: FaceCameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            parent.isPresented = false
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage)
                ?? (info[.originalImage] as? UIImage)

            if let image {
                parent.onCapture(image.squareTexture())
            }
            parent.isPresented = false
        }
    }
}

private extension UIImage {
    func squareTexture(sideLength: CGFloat = 512) -> UIImage {
        let targetSize = CGSize(width: sideLength, height: sideLength)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            let widthScale = sideLength / size.width
            let heightScale = sideLength / size.height
            let scale = max(widthScale, heightScale)
            let drawSize = CGSize(
                width: size.width * scale,
                height: size.height * scale
            )
            let origin = CGPoint(
                x: (sideLength - drawSize.width) / 2,
                y: (sideLength - drawSize.height) / 2
            )
            draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
