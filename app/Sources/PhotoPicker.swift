import SwiftUI
import PhotosUI

/// 相册选图 → 回调 JPEG Data
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let r = results.first,
                  r.itemProvider.canLoadObject(ofClass: UIImage.self) else { return }

            r.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                guard let img = obj as? UIImage else { return }
                let scaled = Self.downscale(img, maxSide: 1280)
                guard let data = scaled.jpegData(compressionQuality: 0.82) else { return }
                DispatchQueue.main.async { self.parent.onPick(data) }
            }
        }

        static func downscale(_ img: UIImage, maxSide: CGFloat) -> UIImage {
            let w = img.size.width, h = img.size.height
            let m = max(w, h)
            guard m > maxSide else { return img }
            let r = maxSide / m
            let sz = CGSize(width: w * r, height: h * r)
            let f = UIGraphicsImageRenderer(size: sz)
            return f.image { _ in img.draw(in: CGRect(origin: .zero, size: sz)) }
        }
    }
}

/// 拍照 → 回调 JPEG Data
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let img = info[.originalImage] as? UIImage else { return }
            let scaled = PhotoPicker.Coordinator.downscale(img, maxSide: 1280)
            guard let data = scaled.jpegData(compressionQuality: 0.82) else { return }
            parent.onPick(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
