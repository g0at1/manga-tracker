import SwiftUI
import Vision
import VisionKit

/// The camera, reading the EAN-13 barcode on the back of a volume and, from
/// the text around it, the printed price ("CENA: 25,20zł"). Calls `onScan`
/// once per book: as soon as both are read, or shortly after the barcode
/// when no price shows up.
struct ISBNScannerView: UIViewControllerRepresentable {
    /// Stops the camera while false (the confirmation screen is up).
    var isActive: Bool
    let onScan: (_ isbn: String, _ price: Double?) -> Void

    /// Whether this device has a camera scanner the user allowed.
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13]), .text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if isActive {
            if !scanner.isScanning {
                context.coordinator.reset()
                try? scanner.startScanning()
            }
        } else if scanner.isScanning {
            scanner.stopScanning()
            context.coordinator.reset()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        coordinator.reset()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String, Double?) -> Void

        /// How long to keep looking for the price once the barcode is read.
        private let priceGrace: Duration = .seconds(1.5)

        private var isbn: String?
        private var price: Double?
        private var pending: Task<Void, Never>?
        /// The book last handed over, ignored while it stays in view so it
        /// isn't reported again right after being saved.
        private var lastDelivered: (isbn: String, at: Date)?

        init(onScan: @escaping (String, Double?) -> Void) {
            self.onScan = onScan
        }

        func reset() {
            pending?.cancel()
            pending = nil
            isbn = nil
            price = nil
        }

        func dataScanner(_: DataScannerViewController, didAdd _: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        func dataScanner(_: DataScannerViewController, didUpdate _: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        func dataScanner(_: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            for item in items {
                switch item {
                case let .barcode(barcode):
                    guard let payload = barcode.payloadStringValue,
                          let found = ISBN.normalized(payload)
                    else { continue }
                    if let last = lastDelivered, last.isbn == found, Date().timeIntervalSince(last.at) < 6 {
                        continue
                    }
                    if isbn != found {
                        // A different book came into view: start over.
                        reset()
                        isbn = found
                    }
                case let .text(text):
                    if price == nil, let found = PrintedPrice.parse(text.transcript) {
                        price = found
                    }
                @unknown default:
                    continue
                }
            }

            guard isbn != nil else { return }
            if price != nil {
                deliver()
            } else if pending == nil {
                pending = Task { [weak self, priceGrace] in
                    try? await Task.sleep(for: priceGrace)
                    guard !Task.isCancelled else { return }
                    self?.deliver()
                }
            }
        }

        private func deliver() {
            guard let isbn else { return }
            let price = price
            reset()
            lastDelivered = (isbn, Date())
            onScan(isbn, price)
        }
    }
}
