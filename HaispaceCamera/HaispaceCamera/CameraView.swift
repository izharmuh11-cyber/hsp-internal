import SwiftUI
import AVFoundation

// MARK: - Camera View Model
class CameraViewModel: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var permissionGranted = false
    @Published var capturedImage: UIImage?
    @Published var countdown: Int? = nil
    @Published var isCapturing = false

    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var countdownTimer: Timer?

    override init() {
        super.init()
        checkPermission()
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted { self?.setupSession() }
                }
            }
        default:
            permissionGranted = false
        }
    }

    func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Gunakan kamera belakang (kualitas terbaik untuk photobooth)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = true
            }
        }
    }

    // MARK: - Countdown & Capture
    func startCountdown() {
        guard !isCapturing else { return }
        isCapturing = true
        countdown = 3

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if let current = self.countdown {
                if current <= 1 {
                    timer.invalidate()
                    self.countdown = nil
                    self.capturePhoto()
                } else {
                    self.countdown = current - 1
                }
            }
        }
    }

    private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func resetCapture() {
        capturedImage = nil
        isCapturing = false
        countdown = nil
    }
}

// MARK: - Photo Capture Delegate
extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            self.capturedImage = image
            self.isCapturing = false
        }
    }
}

// MARK: - Camera Preview Layer
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Camera View UI
struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            // Background hitam
            Color.black.ignoresSafeArea()

            if viewModel.permissionGranted {
                // Live Preview
                CameraPreview(session: viewModel.session)
                    .ignoresSafeArea()

                // Overlay UI
                VStack {
                    // Header
                    HStack {
                        Text("HAISPACE")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(6)
                        Spacer()
                        Text("CAMERA")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .tracking(4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)

                    Spacer()

                    // Countdown
                    if let count = viewModel.countdown {
                        Text("\(count)")
                            .font(.system(size: 120, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 20)
                            .transition(.scale)
                            .animation(.spring(response: 0.3), value: count)
                    }

                    Spacer()

                    // Captured Photo Preview
                    if let image = viewModel.capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .padding(.bottom, 8)
                    }

                    // Bottom Controls
                    HStack(spacing: 40) {
                        // Retake Button
                        if viewModel.capturedImage != nil {
                            Button {
                                viewModel.resetCapture()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }

                        // Shutter Button
                        Button {
                            if viewModel.capturedImage == nil {
                                viewModel.startCountdown()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 80, height: 80)
                                Circle()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 3)
                                    .frame(width: 92, height: 92)
                            }
                        }
                        .disabled(viewModel.isCapturing || viewModel.capturedImage != nil)
                        .opacity(viewModel.isCapturing ? 0.5 : 1.0)
                    }
                    .padding(.bottom, 50)
                }

            } else {
                // Permission Denied State
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Izin Kamera Diperlukan")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text("Buka Settings → Privacy → Camera\ndan izinkan Haispace Camera")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.6))
                        .font(.body)
                    Button("Buka Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }
}
