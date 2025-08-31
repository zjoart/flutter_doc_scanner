import Flutter
import PDFKit
import UIKit
import Vision
import VisionKit

@available(iOS 13.0, *)
public class SwiftFlutterDocScannerPlugin: NSObject, FlutterPlugin,
    VNDocumentCameraViewControllerDelegate
{
    var resultChannel: FlutterResult?
    var presentingController: VNDocumentCameraViewController?
    var currentMethod: String?
    var page: Int?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_doc_scanner",
            binaryMessenger: registrar.messenger()
        )
        let instance = SwiftFlutterDocScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {

        guard
            [
                "getScanDocuments", "getScannedDocumentAsImages",
                "getScannedDocumentAsPdf",
            ].contains(call.method)
        else {
            result(FlutterMethodNotImplemented)
            return
        }

        let presentedVC: UIViewController? = UIApplication.shared.keyWindow?
            .rootViewController

        self.resultChannel = result
        self.currentMethod = call.method
        if let args = call.arguments as? [String: Any] {
            self.page = args["page"] as? Int ?? 1
        }

        self.presentingController = VNDocumentCameraViewController()
        self.presentingController!.delegate = self

        presentedVC?.present(self.presentingController!, animated: true)
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )
        let documentsDirectory = paths[0]
        return documentsDirectory
    }

    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {

        let scanLimit = page ?? 1

        if scan.pageCount > scanLimit {
            // Show alert instead of dismissing
            let alert = UIAlertController(
                title: "Page Limit Exceeded",
                message:
                    "You scanned \(scan.pageCount) pages, but only \(scanLimit) will be Uploaded.",
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "OK", style: .default) { _ in
                    self.processScannedImages(scan, limit: scanLimit)
                }
            )

            controller.present(alert, animated: true)
        } else {

            processScannedImages(scan, limit: scanLimit)
        }

    }

    private func processScannedImages(_ scan: VNDocumentCameraScan, limit: Int)
    {
        if currentMethod == "getScanDocuments" {
            saveScannedImages(scan: scan)  // Uses existing logic
        } else if currentMethod == "getScannedDocumentAsImages" {
            saveScannedImages(scan: scan)
        } else if currentMethod == "getScannedDocumentAsPdf" {
            saveScannedPdf(scan: scan, limit: limit)
        }

        presentingController?.dismiss(animated: true)
    }

    private func saveScannedImages(scan: VNDocumentCameraScan) {
        let tempDirPath = getDocumentsDirectory()
        let currentDateTime = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let formattedDate = df.string(from: currentDateTime)
        var filenames: [String] = []
        for i in 0..<scan.pageCount {
            let page = scan.imageOfPage(at: i)
            let url = tempDirPath.appendingPathComponent(
                formattedDate + "-\(i).png"
            )
            try? page.pngData()?.write(to: url)
            filenames.append(url.path)
        }
        resultChannel?(filenames)
    }

    private func saveScannedPdf(scan: VNDocumentCameraScan, limit: Int) {
        let tempDirPath = getDocumentsDirectory()
        let currentDateTime = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let formattedDate = df.string(from: currentDateTime)
        let pdfFilePath = tempDirPath.appendingPathComponent(
            "\(formattedDate).pdf"
        )

        let pdfDocument = PDFDocument()
        let pagesToProcess = min(scan.pageCount, limit)

        for i in 0..<pagesToProcess {
            let pageImage = scan.imageOfPage(at: i)
            let compressedPageImage = pageImage.compressed(to: 0.65)

            if let pdfPage = PDFPage(image: compressedPageImage ?? pageImage) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }
        }

        if pdfDocument.write(to: pdfFilePath) {
            resultChannel?(pdfFilePath.path)
        } else {
            resultChannel?(
                FlutterError(
                    code: "PDF_CREATION_ERROR",
                    message: "Failed to create PDF",
                    details: nil
                )
            )
        }

    }

    public func documentCameraViewControllerDidCancel(
        _ controller: VNDocumentCameraViewController
    ) {
        resultChannel?(nil)
        presentingController?.dismiss(animated: true)
    }

    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        resultChannel?(
            FlutterError(
                code: "SCAN_ERROR",
                message: "Failed to scan documents",
                details: error.localizedDescription
            )
        )
        presentingController?.dismiss(animated: true)
    }
}

extension UIImage {
    func compressed(to quality: CGFloat) -> UIImage? {
        // Convert UIImage to JPEG data with compression
        guard let jpegData = self.jpegData(compressionQuality: quality) else {
            return nil
        }
        
        // Convert back to UIImage
        return UIImage(data: jpegData)
    }
}
