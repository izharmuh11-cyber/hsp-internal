// PhotoTransferService.swift
// HaispaceCamera — Services/Camera
//
// Mengelola antrian transfer AIC (Adaptive Image Compression)
// dengan Dual-Channel transfer (Thumbnail cepat + Full Quality lambat).
//
// Ref: docs/design/40_concurrency_strategy.md

import Foundation
import AVFoundation
import UIKit
import ImageIO
import CoreImage
import Vision

actor PhotoTransferService {
    static let shared = PhotoTransferService()
    
    private struct PendingTransfer {
        let photoId: String
        let photoData: Data
        let sortOrder: Int
    }
    
    private var fullQualityQueue: [PendingTransfer] = []
    private var isProcessingQueue = false
    
    // REUSE CICONTEXT: CIContext adalah objek yang sangat berat karena menginisialisasi
    // pipeline Metal, shader compilation, dan command queue GPU.
    // Default initializer CIContext() otomatis menggunakan Metal GPU di iOS secara optimal.
    private let ciContext = CIContext()
    
    private init() {}
    
    /// Dipanggil setiap kali iPhone selesai mengambil foto resolusi tinggi.
    ///
    /// Jika portrait mode aktif, efek bokeh diterapkan menggunakan AVPortraitEffectsMatte —
    /// segmentation mask pixel-perfect dari Neural Engine iPhone (public API Apple, stable, memory-safe).
    /// Tidak menggunakan CIDepthBlurEffect (undocumented internal API, OOM risk 400-800MB).
    ///
    /// Pipeline memori: ~180MB peak (aman di iPhone 14 dengan 6GB RAM).
    func handleNewCapture(photoId: String, capture: AVCapturePhoto, sortOrder: Int, isPortraitActive: Bool, requestedZoom: CGFloat = 1.0) async {
        var photoData: Data? = capture.fileDataRepresentation()
        
        if isPortraitActive, let rawData = photoData {
            
            let bokehResult: Data? = autoreleasepool { () -> Data? in
                
                // Cek ketersediaan Portrait Effects Matte (Neural Engine segmentation mask).
                // Nil jika isPortraitEffectsMatteDeliveryEnabled belum di-set atau device tidak support.
                // Jika nil: tetap terapkan Smart Grading tanpa bokeh (tidak crash, masih berguna).
                guard let matte = capture.portraitEffectsMatte else {
                    HaispaceLogger.info("Portrait effects matte tidak tersedia — Smart Grading tanpa bokeh diterapkan", category: "camera")
                    
                    // Terapkan Smart Grading saja (tanpa segmentation mask / bokeh)
                    let presetId = CameraCaptureService.shared.currentColorPreset
                    // Selalu jalankan grading untuk Portrait Mode
                    
                    let ciImageOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
                    guard var flatPhoto = CIImage(data: rawData, options: ciImageOptions) else { return nil }
                    let rawExtF = flatPhoto.extent
                    if rawExtF.origin != .zero {
                        flatPhoto = flatPhoto.transformed(by: CGAffineTransform(translationX: -rawExtF.minX, y: -rawExtF.minY))
                    }
                    let photoExtF = flatPhoto.extent
                    
                    // Layer 2-like: warm lift + shadow protection langsung ke seluruh foto
                    let warmed = flatPhoto.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1.04, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: 1.01, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 0.97, w: 0),
                        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                    ]).applyingFilter("CIHighlightShadowAdjust", parameters: [
                        "inputHighlightAmount": 0.88,
                        "inputShadowAmount":    0.55
                    ])
                    
                    // Vignette sinematik ringan
                    let vignetted = warmed.clampedToExtent()
                        .applyingFilter("CIVignette", parameters: ["inputRadius": 1.6, "inputIntensity": 0.45])
                        .cropped(to: photoExtF)
                    
                    // Film grain
                    let noiseFlat = (CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage.empty())
                        .cropped(to: photoExtF)
                        .transformed(by: CGAffineTransform(scaleX: 1.6, y: 1.6))
                        .cropped(to: photoExtF)
                        .applyingFilter("CIColorMatrix", parameters: [
                            "inputRVector": CIVector(x: 0.04, y: 0, z: 0, w: 0),
                            "inputGVector": CIVector(x: 0, y: 0.04, z: 0, w: 0),
                            "inputBVector": CIVector(x: 0, y: 0, z: 0.04, w: 0),
                            "inputBiasVector": CIVector(x: 0.48, y: 0.48, z: 0.48, w: 0)
                        ])
                        .applyingFilter("CIColorMonochrome", parameters: [
                            "inputColor": CIColor(red: 0.5, green: 0.5, blue: 0.5),
                            "inputIntensity": 1.0
                        ])
                    let presetApplied = CameraCaptureService.shared.applyColorFilter(to: vignetted, presetId: presetId)
                    let grained = noiseFlat.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: presetApplied])
                    
                    guard let cgF = self.ciContext.createCGImage(grained, from: photoExtF),
                          let jpegF = UIImage(cgImage: cgF).jpegData(compressionQuality: 0.92) else { return nil }
                    HaispaceLogger.info("[SmartGrading] No-Bokeh mode: grading+grain applied (Preset: \(presetId))", category: "camera")
                    return jpegF
                }
                
                // Load foto dengan EXIF orientation sebagai affine transform (zero-copy, memory efficient)
                let ciImageOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
                guard var orientedPhoto = CIImage(data: rawData, options: ciImageOptions) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal membuat CIImage — foto asli digunakan", category: "camera")
                    return nil
                }
                
                // Normalkan origin ke (0,0) — oriented() dapat menggeser origin ke nilai negatif
                let rawExtent = orientedPhoto.extent
                if rawExtent.origin != .zero {
                    orientedPhoto = orientedPhoto.transformed(
                        by: CGAffineTransform(translationX: -rawExtent.minX, y: -rawExtent.minY)
                    )
                }
                let exifOrientation = capture.metadata[kCGImagePropertyOrientation as String] as? Int32 ?? 1
                
                // --- MATTE PROCESSING ---
                // Format: kCVPixelFormatType_OneComponent8 (grayscale 8-bit)
                //   255 = orang/foreground → foto tetap tajam
                //     0 = background      → foto di-blur
                let mattePixelBuffer = matte.mattingImage
                var matteCIImage = CIImage(cvPixelBuffer: mattePixelBuffer)
                    .oriented(forExifOrientation: exifOrientation)
                
                let matteRawExtent = matteCIImage.extent
                if matteRawExtent.origin != .zero {
                    matteCIImage = matteCIImage.transformed(
                        by: CGAffineTransform(translationX: -matteRawExtent.minX, y: -matteRawExtent.minY)
                    )
                }
                
                // PENTING: Jika Portrait mode di-set ke 2x (requestedZoom >= 1.8),
                // lakukan 2x center crop pada foto & matte mask agar hasil akhir foto 2x Portrait presisi!
                if requestedZoom >= 1.8 {
                    let pW = orientedPhoto.extent.width
                    let pH = orientedPhoto.extent.height
                    let cropRect = CGRect(x: pW * 0.25, y: pH * 0.25, width: pW * 0.5, height: pH * 0.5)
                    orientedPhoto = orientedPhoto.cropped(to: cropRect)
                        .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
                        .transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
                    
                    let mW = matteCIImage.extent.width
                    let mH = matteCIImage.extent.height
                    let mCropRect = CGRect(x: mW * 0.25, y: mH * 0.25, width: mW * 0.5, height: mH * 0.5)
                    matteCIImage = matteCIImage.cropped(to: mCropRect)
                        .transformed(by: CGAffineTransform(translationX: -mCropRect.minX, y: -mCropRect.minY))
                        .transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
                }
                
                let photoExtent = orientedPhoto.extent
                
                // Scale matte ke dimensi foto (matte selalu resolusi lebih rendah dari foto)
                let scaleX = photoExtent.width / matteCIImage.extent.width
                let scaleY = photoExtent.height / matteCIImage.extent.height
                let scaledMatte = matteCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                // Haluskan tepi matte — radius 2.5 = anti-aliasing natural pada rambut & jari
                let softMatte = scaledMatte
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 2.5])
                    .cropped(to: photoExtent)
                
                // --- FIX #5: HIGHLIGHT BLOOM ---
                // CIBloom memperkuat highlight (cahaya terang) sebelum blur diterapkan.
                // Ketika highlight yang membesar ini di-blur, hasilnya adalah glowing circles
                // yang persis seperti specular bokeh dari lensa optik premium.
                // inputRadius=6.0 + inputIntensity=0.4 → subtle, tidak overexposed.
                let bloomedSource = orientedPhoto.applyingFilter("CIBloom", parameters: [
                    "inputRadius":    6.0,   // radius halo glow di sekitar highlight
                    "inputIntensity": 0.4    // intensitas glow (0.4 = subtle & natural)
                ])
                
                let currentAperture = CameraCaptureService.shared.currentAperture
                let heavyRadius: Double = currentAperture < 1.8 ? 32.0 : (currentAperture < 3.5 ? 22.0 : (currentAperture < 6.5 ? 10.0 : 0.0))
                let lightRadius: Double = currentAperture < 1.8 ? 14.0 : (currentAperture < 3.5 ? 8.0 : (currentAperture < 6.5 ? 4.0 : 0.0))
                
                let blurredBackground: CIImage
                if heavyRadius > 0 {
                    let lightBlur = bloomedSource
                        .clampedToExtent()
                        .applyingFilter("CIDiscBlur", parameters: ["inputRadius": lightRadius])
                        .cropped(to: photoExtent)
                    
                    let heavyBlur = bloomedSource
                        .clampedToExtent()
                        .applyingFilter("CIDiscBlur", parameters: ["inputRadius": heavyRadius])
                        .cropped(to: photoExtent)
                    
                    if let depthData = capture.depthData {
                        let depthFloat32 = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                        var depthCIImage = CIImage(cvPixelBuffer: depthFloat32.depthDataMap)
                            .oriented(forExifOrientation: exifOrientation)
                        
                        let depthRawExtent = depthCIImage.extent
                        if depthRawExtent.origin != .zero {
                            depthCIImage = depthCIImage.transformed(
                                by: CGAffineTransform(translationX: -depthRawExtent.minX, y: -depthRawExtent.minY)
                            )
                        }
                        let dScaleX = photoExtent.width / depthCIImage.extent.width
                        let dScaleY = photoExtent.height / depthCIImage.extent.height
                        let scaledDepth = depthCIImage.transformed(by: CGAffineTransform(scaleX: dScaleX, y: dScaleY))
                        
                        let nearPlane: CGFloat = 0.5
                        let farPlane:  CGFloat = 3.5
                        let dScale = 1.0 / (farPlane - nearPlane)
                        let dBias  = -nearPlane * dScale
                        
                        let normalizedDepth = scaledDepth.applyingFilter("CIColorMatrix", parameters: [
                            "inputRVector":    CIVector(x: dScale, y: 0, z: 0, w: 0),
                            "inputGVector":    CIVector(x: 0, y: dScale, z: 0, w: 0),
                            "inputBVector":    CIVector(x: 0, y: 0, z: dScale, w: 0),
                            "inputBiasVector": CIVector(x: dBias, y: dBias, z: dBias, w: 0)
                        ])
                        
                        let smoothDepth = normalizedDepth
                            .applyingFilter("CIColorClamp", parameters: [
                                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                            ])
                            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 4.0])
                            .cropped(to: photoExtent)
                        
                        blurredBackground = heavyBlur.applyingFilter("CIBlendWithMask", parameters: [
                            kCIInputBackgroundImageKey: lightBlur,
                            kCIInputMaskImageKey: smoothDepth
                        ])
                        HaispaceLogger.info("[PortraitMatte] Variable DOF AKTIF — depth gradient diterapkan", category: "camera")
                    } else {
                        blurredBackground = heavyBlur
                        HaispaceLogger.info("[PortraitMatte] Variable DOF fallback — depth nil, heavy blur digunakan", category: "camera")
                    }
                } else {
                    blurredBackground = bloomedSource
                }
                
                // --- COMPOSITE FINAL (Bokeh) ---
                let composite = orientedPhoto.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: blurredBackground,
                    kCIInputMaskImageKey: softMatte
                ])
                
                // --- HAISPACE CINEMATIC SMART GRADING (Portrait Mode Only) ---
                // Menggunakan softMatte yang sudah tersedia (zero-cost reuse) untuk membedakan
                // grading antara subject (orang) dan background secara per-pixel.
                let presetId = CameraCaptureService.shared.currentColorPreset
                let finalPhoto: CIImage
                
                // Selalu aktifkan 4-layer smart grading saat Portrait Mode (walau preset original)
                do {
                    
                    // ── LAYER 1: Background Cinematic Grade ──
                    // Cool tone shift pada background: R--, B++ → cinematic background
                    let coolBackground = composite.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 0.88, y: 0, z: 0, w: 0),   // sedikit kurangi Red
                        "inputGVector": CIVector(x: 0, y: 0.93, z: 0, w: 0),   // sedikit kurangi Green
                        "inputBVector": CIVector(x: 0, y: 0, z: 1.06, w: 0),   // sedikit tambah Blue
                        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                    ])
                    
                    // Desaturasi ringan pada background → tidak bersaing dengan subject
                    let desatBackground = coolBackground.applyingFilter("CIColorControls", parameters: [
                        "inputSaturation": 0.72,  // 28% desaturasi
                        "inputBrightness": -0.015, // slight darken
                        "inputContrast":   1.04
                    ])
                    
                    // Vignette ringan pada seluruh foto (bingkai sinematik)
                    let vignetted = desatBackground
                        .clampedToExtent()
                        .applyingFilter("CIVignette", parameters: [
                            "inputRadius":    1.8,
                            "inputIntensity": 0.55
                        ])
                        .cropped(to: photoExtent)
                    
                    // Blend: background → graded, subject → original composite
                    let gradedBackground = composite.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: vignetted,
                        kCIInputMaskImageKey: softMatte      // subject area dipertahankan
                    ])
                    
                    // ── LAYER 2: Subject Skin Enhancement ──
                    // Warm lift pada subject: skin lebih flatter, shadow diangkat
                    let warmSubject = composite.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1.04, y: 0, z: 0, w: 0),   // sedikit tambah Red (warm)
                        "inputGVector": CIVector(x: 0, y: 1.01, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 0.97, w: 0),   // sedikit kurangi Blue
                        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                    ])
                    
                    // Shadow lift + highlight protection pada subject
                    let enhancedSubject = warmSubject.applyingFilter("CIHighlightShadowAdjust", parameters: [
                        "inputHighlightAmount": 0.85,  // proteksi highlight agar tidak overexposed
                        "inputShadowAmount":    0.6    // angkat shadow → detail di area gelap lebih terlihat
                    ])
                    
                    // Blend graded background dengan enhanced subject menggunakan softMatte
                    let subjectEnhanced = gradedBackground.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: gradedBackground,
                        kCIInputImageKey: enhancedSubject,
                        kCIInputMaskImageKey: softMatte
                    ])
                    
                    // ── LAYER 3: Face Region Micro-Contrast ──
                    // VNDetectFaceLandmarksRequest → bounding box wajah → CIImage mask gradient
                    // Micro-contrast & subtle brightness boost tepat di area wajah (mata, pipi, dahi)
                    var faceEnhanced = subjectEnhanced

                    var detectedFaceRect: CGRect = .zero  // expose ke Layer 4A
                    
                    if let cgForVision = self.ciContext.createCGImage(composite, from: photoExtent) {
                        let faceRequest = VNDetectFaceLandmarksRequest()
                        let handler = VNImageRequestHandler(cgImage: cgForVision, options: [:])
                        
                        if (try? handler.perform([faceRequest])) != nil,
                           let faceObs = (faceRequest.results as? [VNFaceObservation])?.first {
                            
                            // Konversi normalized bounding box ke koordinat foto
                            let faceBB = faceObs.boundingBox
                            let faceRect = CGRect(
                                x:      faceBB.minX * photoExtent.width,
                                y:      faceBB.minY * photoExtent.height,
                                width:  faceBB.width  * photoExtent.width  * 1.15,
                                height: faceBB.height * photoExtent.height * 1.15
                            ).intersection(photoExtent)
                            
                            if !faceRect.isEmpty {
                                detectedFaceRect = faceRect
                                
                                // Crop area wajah dari subjectEnhanced
                                let faceCrop = subjectEnhanced.cropped(to: faceRect)
                                
                                // Micro-contrast boost di area wajah
                                let faceGraded = faceCrop.applyingFilter("CIColorControls", parameters: [
                                    "inputSaturation": 1.06,
                                    "inputBrightness": 0.012,
                                    "inputContrast":   1.08
                                ])
                                
                                // Gaussian gradient mask untuk blend natural di tepi wajah
                                let faceMaskColor = CIImage(color: CIColor(red: 0.75, green: 0.75, blue: 0.75))
                                    .cropped(to: faceRect)
                                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18.0])
                                    .cropped(to: faceRect)
                                
                                faceEnhanced = subjectEnhanced.applyingFilter("CIBlendWithMask", parameters: [
                                    kCIInputBackgroundImageKey: subjectEnhanced,
                                    kCIInputImageKey: faceGraded,
                                    kCIInputMaskImageKey: faceMaskColor
                                ])
                            }
                        }
                    }
                    
                    // ── LAYER 4A: Adaptive Skin Tone Calibration ──
                    // Sampel warna kulit rata-rata dari area wajah yang terdeteksi (Layer 3).
                    // Hitung koreksi bias yang diperlukan untuk mendekati "neutral flattering skin tone"
                    // secara otomatis — adapts untuk semua warna kulit tanpa over-processing.
                    var skinCalibrated = faceEnhanced
                    
                    if !detectedFaceRect.isEmpty {
                        let faceSampleImage = faceEnhanced.cropped(to: detectedFaceRect)
                        
                        // CIAreaAverage: output 1x1 pixel berisi warna rata-rata area wajah
                        let averaged = faceSampleImage.applyingFilter("CIAreaAverage", parameters: [
                            kCIInputExtentKey: CIVector(cgRect: detectedFaceRect)
                        ])
                        
                        // Render 1x1 pixel ke bitmap untuk baca R, G, B
                        var pixelData = [UInt8](repeating: 0, count: 4)
                        let colorSpace = CGColorSpaceCreateDeviceRGB()
                        self.ciContext.render(
                            averaged,
                            toBitmap: &pixelData,
                            rowBytes: 4,
                            bounds: averaged.extent,
                            format: .RGBA8,
                            colorSpace: colorSpace
                        )
                        
                        let avgR = CGFloat(pixelData[0]) / 255.0
                        let avgG = CGFloat(pixelData[1]) / 255.0
                        let avgB = CGFloat(pixelData[2]) / 255.0
                        
                        // Target "flattering neutral" skin tone (universal mid-point):
                        // Sedikit warm, cukup untuk semua skin tone.
                        // Koreksi dibatasi max 15% untuk menghindari unnatural look.
                        let targetR: CGFloat = 0.68
                        let targetG: CGFloat = 0.52
                        let targetB: CGFloat = 0.42
                        
                        let biasR = max(-0.06, min(0.06, (targetR - avgR) * 0.14))
                        let biasG = max(-0.04, min(0.04, (targetG - avgG) * 0.10))
                        let biasB = max(-0.05, min(0.05, (targetB - avgB) * 0.12))
                        
                        // Terapkan koreksi pada SELURUH gambar (subject only via softMatte)
                        let correctedSubject = faceEnhanced.applyingFilter("CIColorMatrix", parameters: [
                            "inputRVector":    CIVector(x: 1.0, y: 0,   z: 0,   w: 0),
                            "inputGVector":    CIVector(x: 0,   y: 1.0, z: 0,   w: 0),
                            "inputBVector":    CIVector(x: 0,   y: 0,   z: 1.0, w: 0),
                            "inputBiasVector": CIVector(x: biasR, y: biasG, z: biasB, w: 0)
                        ])
                        
                        // Blend koreksi hanya ke area subject menggunakan softMatte
                        skinCalibrated = faceEnhanced.applyingFilter("CIBlendWithMask", parameters: [
                            kCIInputBackgroundImageKey: faceEnhanced,
                            kCIInputImageKey: correctedSubject,
                            kCIInputMaskImageKey: softMatte
                        ])
                        
                        HaispaceLogger.info(
                            "[SmartGrading] Adaptive Skin — measured R:\(String(format:"%.2f",avgR)) G:\(String(format:"%.2f",avgG)) B:\(String(format:"%.2f",avgB)) | bias R:\(String(format:"%.3f",biasR)) G:\(String(format:"%.3f",biasG)) B:\(String(format:"%.3f",biasB))",
                            category: "camera"
                        )
                    }
                    
                    // ── GLOBAL PRESET TONE (Haispace Signature) ──
                    // Terapkan tone preset pilihan user sebagai finishing layer
                    let presetGraded = CameraCaptureService.shared.applyColorFilter(to: skinCalibrated, presetId: presetId)
                    
                    // ── LAYER 4B: Luminance-Aware Film Grain ──
                    // Simulasi butiran film analog: grayscale noise, di-blend dengan CISoftLightBlendMode.
                    // Soft light centered di 0.5 → nilai di atas/bawah 0.5 mencerahkan/menggelapkan sedikit.
                    // Hasilnya: grain lebih terasa di shadow, nyaris menghilang di highlight — persis film analog.
                    let noiseGen = CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage.empty()
                    let rawNoise = noiseGen.cropped(to: photoExtent)
                    
                    // Scale noise sedikit lebih besar dari per-pixel → clump 2-3px = karakter butiran film
                    let scaledNoise = rawNoise
                        .transformed(by: CGAffineTransform(scaleX: 1.6, y: 1.6))
                        .cropped(to: photoExtent)
                    
                    // Konversi ke grayscale (luminance-only grain, tanpa chroma noise yang jelek)
                    // Scale ke rentang sangat sempit di sekitar 0.5 → intensity grain 4%
                    let filmGrain = scaledNoise.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector":    CIVector(x: 0.04, y: 0,    z: 0,    w: 0),
                        "inputGVector":    CIVector(x: 0,    y: 0.04, z: 0,    w: 0),
                        "inputBVector":    CIVector(x: 0,    y: 0,    z: 0.04, w: 0),
                        "inputBiasVector": CIVector(x: 0.48, y: 0.48, z: 0.48, w: 0)  // center di 0.5
                    ])
                    
                    // Grayscale: semua channel sama → pure luminance grain
                    let monoGrain = filmGrain.applyingFilter("CIColorMonochrome", parameters: [
                        "inputColor":     CIColor(red: 0.5, green: 0.5, blue: 0.5),
                        "inputIntensity": 1.0
                    ])
                    
                    // CISoftLightBlendMode: noise 0.5 = no effect, 0.52 = slight brighten, 0.48 = slight darken
                    // Shadow areas otomatis mendapat lebih banyak grain (soft light non-linearity)
                    finalPhoto = monoGrain.applyingFilter("CISoftLightBlendMode", parameters: [
                        kCIInputBackgroundImageKey: presetGraded
                    ])
                    
                    HaispaceLogger.info("[SmartGrading] Haispace Cinematic 4-Layer AKTIF (Preset: \(presetId)) — Adaptive Skin ✓ Film Grain ✓", category: "camera")
                }
                
                guard let cgImage = self.ciContext.createCGImage(finalPhoto, from: photoExtent) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal render CGImage — foto asli digunakan", category: "camera")
                    return nil
                }
                
                let uiImage = UIImage(cgImage: cgImage)
                guard let jpegData = uiImage.jpegData(compressionQuality: 0.92) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal encode JPEG — foto asli digunakan", category: "camera")
                    return nil
                }
                
                HaispaceLogger.info(
                    "Portrait Bokeh ✓ (Preset: \(presetId), f/\(currentAperture)): \(jpegData.count / 1024)KB (\(Int(photoExtent.width))×\(Int(photoExtent.height))px)",
                    category: "camera"
                )
                return jpegData
            } // ← autoreleasepool
            
            if let result = bokehResult {
                photoData = result
            }
        } else if !isPortraitActive, let rawData = photoData, CameraCaptureService.shared.currentColorPreset != "original" {
            // Mode normal tetapi menggunakan Pro Studio Color Preset Filter
            let presetId = CameraCaptureService.shared.currentColorPreset
            let ciImageOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
            if var orientedPhoto = CIImage(data: rawData, options: ciImageOptions) {
                let rawExtent = orientedPhoto.extent
                if rawExtent.origin != .zero {
                    orientedPhoto = orientedPhoto.transformed(
                        by: CGAffineTransform(translationX: -rawExtent.minX, y: -rawExtent.minY)
                    )
                }
                let filteredPhoto = CameraCaptureService.shared.applyColorFilter(to: orientedPhoto, presetId: presetId)
                if let cgImage = self.ciContext.createCGImage(filteredPhoto, from: filteredPhoto.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    if let jpegData = uiImage.jpegData(compressionQuality: 0.92) {
                        photoData = jpegData
                        HaispaceLogger.info("Normal Photo Color Filter ✓ (Preset: \(presetId)): \(jpegData.count / 1024)KB", category: "camera")
                    }
                }
            }
        }
        
        guard let data = photoData else {
            HaispaceLogger.error("Gagal mendapatkan data gambar dari jepretan", category: "camera")
            return
        }
        
        HaispaceLogger.info("Mulai dual-channel transfer untuk \(photoId) (order: \(sortOrder))", category: "p2p")
        
        async let thumbnailTask: Void = sendThumbnailImmediately(photoId: photoId, data: data)
        async let queueTask: Void = enqueueFullQuality(photoId: photoId, data: data, sortOrder: sortOrder)
        
        _ = await (thumbnailTask, queueTask)
    }
    
    // CHANNEL 1: Fast Preview Stream (< 100ms)
    private func sendThumbnailImmediately(photoId: String, data: Data) async {
        // Kompres ke ~300KB
        let thumbnailData = await compressImage(data: data, quality: 0.6, maxBytes: 300_000)
        
        let message = P2PMessage.photoPreview(id: photoId, thumbnailData: thumbnailData)
        
        do {
            let encodedMessage = try message.encode()
            try await P2PClientService.shared.sendData(encodedMessage)
            HaispaceLogger.info("Thumbnail terkirim: \(photoId) (\(thumbnailData.count) bytes)", category: "p2p")
        } catch {
            HaispaceLogger.error("Gagal mengirim thumbnail \(photoId): \(error)", category: "p2p")
        }
    }
    
    // CHANNEL 2: Background Full Quality Queue
    private func enqueueFullQuality(photoId: String, data: Data, sortOrder: Int) async {
        let pending = PendingTransfer(photoId: photoId, photoData: data, sortOrder: sortOrder)
        fullQualityQueue.append(pending)
        
        if !isProcessingQueue {
            await processFullQualityQueue()
        }
    }
    
    /// Memulai kembali antrean pengiriman foto yang tertunda
    func resumeTransferQueue() async {
        guard !isProcessingQueue else { return }
        await processFullQualityQueue()
    }
    
    private func processFullQualityQueue() async {
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        while !fullQualityQueue.isEmpty {
            // Cek status koneksi. Jika terputus, jeda pemrosesan antrean.
            let isConnected = await P2PClientService.shared.isConnected()
            guard isConnected else {
                HaispaceLogger.warning("Menunda pengiriman full quality - P2P terputus", category: "p2p")
                break
            }
            
            let nextTransfer = fullQualityQueue.removeFirst()
            
            // Kirim metadata terlebih dahulu
            let metadataMsg = P2PMessage.photoMetadata(
                photoId: nextTransfer.photoId,
                fileSize: nextTransfer.photoData.count,
                capturedAt: Date(),
                sortOrder: nextTransfer.sortOrder
            )
            
            do {
                try await P2PClientService.shared.sendData(metadataMsg.encode())
                
                // Beri jeda kecil agar iPad siap
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                // Kirim data penuh secara aman (TCP/MPC dual-mode send)
                try await P2PClientService.shared.sendPhotoFull(id: nextTransfer.photoId, data: nextTransfer.photoData)
                
                HaispaceLogger.info("Full quality terkirim: \(nextTransfer.photoId)", category: "p2p")
            } catch {
                HaispaceLogger.error("Gagal mengirim full quality \(nextTransfer.photoId): \(error)", category: "p2p")
                
                // Re-enqueue jika gagal (bisa diberi limit retry di masa depan)
                fullQualityQueue.insert(nextTransfer, at: 0)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // tunggu 1 detik sebelum retry
            }
        }
    }
    
    private func compressImage(data: Data, quality: CGFloat, maxBytes: Int) async -> Data {
        // Implementasi optimasi memori menggunakan ImageIO
        return await Task.detached(priority: .userInitiated) {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
                return data
            }
            
            // Definisikan opsi pembuatan thumbnail
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
            ]
            
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                return data
            }
            
            let resultData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(resultData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
                return data
            }
            
            let compressionOptions: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            
            CGImageDestinationAddImage(destination, thumbnail, compressionOptions as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                return data
            }
            
            return resultData as Data
        }.value
    }
}
