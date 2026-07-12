// QRScannerView.swift
// HaispaceCamera
//
// Scanner QR Code berbasis AVFoundation untuk membaca payload pairing.
// Di-wrap dengan UIViewControllerRepresentable agar bisa dipakai di SwiftUI.

import SwiftUI
import AVFoundation
import AudioToolbox

struct QRScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        // No update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        var parent: QRScannerView

        init(_ parent: QRScannerView) {
            self.parent = parent
        }

        func qrScanningDidFail() {
            print("QR Scanner Failed")
        }

        func qrScanningSucceededWithCode(_ str: String?) {
            if let str = str {
                parent.onResult(str)
            }
        }

        func qrScanningDidStop() {
            parent.onCancel()
        }
    }
}

// MARK: - View Controller

protocol QRScannerViewControllerDelegate: AnyObject {
    func qrScanningDidFail()
    func qrScanningSucceededWithCode(_ str: String?)
    func qrScanningDidStop()
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    weak var delegate: QRScannerViewControllerDelegate?
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Custom Close Button
        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("Batal", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeBtn.layer.cornerRadius = 16
        closeBtn.frame = CGRect(x: 20, y: 50, width: 80, height: 40)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)
        
        // Add framing rect for scanning UI
        let scanRect = UIView()
        scanRect.layer.borderColor = UIColor.green.cgColor
        scanRect.layer.borderWidth = 3
        scanRect.layer.cornerRadius = 12
        let size: CGFloat = 250
        scanRect.frame = CGRect(x: (view.bounds.width - size)/2, y: (view.bounds.height - size)/2, width: size, height: size)
        view.addSubview(scanRect)
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }
    
    @objc func closeTapped() {
        delegate?.qrScanningDidStop()
    }
    
    func failed() {
        delegate?.qrScanningDidFail()
        captureSession = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if (captureSession?.isRunning == false) {
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            
            delegate?.qrScanningSucceededWithCode(stringValue)
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
