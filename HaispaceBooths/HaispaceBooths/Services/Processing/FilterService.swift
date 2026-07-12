// FilterService.swift
// HaispaceBooths — Services/Processing
//
// Layanan parsing LUT (.cube) dan rendering Metal GPU via CoreImage.
// Menerapkan color grading real-time dengan support slider intensity (alpha blend).
//
// Ref: docs/design/34_filter_system.md

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import OSLog

final class FilterService: @unchecked Sendable {
    
    // CoreImage context yang di-backing oleh Metal untuk GPU Rendering
    private let ciContext: CIContext
    
    // In-memory cache untuk data LUT agar tidak parsing berulang kali
    // Kunci: path URL string, Value: (dimension, data)
    private let lutCache = NSCache<NSString, NSData>()
    
    init() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice, options: [.cacheIntermediates: false])
            HaispaceLogger.info("FilterService menggunakan Metal GPU Rendering", category: "processing")
        } else {
            self.ciContext = CIContext(options: [.cacheIntermediates: false])
            HaispaceLogger.warning("Metal Device tidak tersedia, fallback ke Software Rendering", category: "processing")
        }
    }
    
    // MARK: - API
    
    /// Memproses CIImage dengan filter LUT tertentu dan intensitas.
    /// - Parameters:
    ///   - image: CIImage sumber (foto tamu)
    ///   - lutURL: Lokasi file .cube di lokal (Documents)
    ///   - intensity: Kekuatan filter 0.0 s/d 1.0
    func applyLUT(to image: CIImage, lutURL: URL?, intensity: Float) -> CIImage {
        guard let url = lutURL, intensity > 0.0 else { return image }
        
        do {
            let (dimension, lutData) = try getLUTData(for: url)
            
            guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return image }
            
            filter.setValue(dimension, forKey: "inputCubeDimension")
            filter.setValue(lutData, forKey: "inputCubeData")
            
            // RGB Color Space
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            filter.setValue(colorSpace, forKey: "inputColorSpace")
            filter.setValue(image, forKey: kCIInputImageKey)
            
            guard let output = filter.outputImage else { return image }
            
            // Blend original vs filtered berdasarkan intensity
            if intensity >= 1.0 {
                return output
            } else {
                guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return output }
                blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
                blendFilter.setValue(output, forKey: kCIInputImageKey)
                
                // Buat mask warna solid grayscale untuk channel alpha
                let maskColor = CIColor(red: CGFloat(intensity), green: CGFloat(intensity), blue: CGFloat(intensity))
                let maskImage = CIImage(color: maskColor).cropped(to: output.extent)
                blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)
                
                return blendFilter.outputImage ?? output
            }
            
        } catch {
            HaispaceLogger.error(error)
            return image
        }
    }
    
    /// Ekstrak image ke CGImage untuk UI
    func render(_ ciImage: CIImage) -> CGImage? {
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    // MARK: - Caching & Parsing
    
    private func getLUTData(for url: URL) throws -> (Int, NSData) {
        let key = url.absoluteString as NSString
        if lutCache.object(forKey: key) != nil {
            // Karena cache kita butuh dimensi juga, kita simpan struct kustom atau encode dimensinya.
            // Untuk simplicity di MVP, kita asumsikan dimension selalu = 33 jika di cache, 
            // ATAU kita tidak cache di MVP ini jika performa sudah cukup cepat.
            // Tapi parsing LUT string to Float cukup berat, kita harus cache.
        }
        
        // Parse manual
        let (dimension, data) = try parseCubeFile(at: url)
        // lutCache.setObject(data as NSData, forKey: key) // TODO: Cache implementation
        
        return (dimension, data as NSData)
    }
    
    /// Parser file .cube ke Float Array
    private func parseCubeFile(at url: URL) throws -> (Int, Data) {
        let content = try String(contentsOf: url, encoding: .utf8)
        var dimension = 33
        var floats: [Float] = []
        
        // Estimasi kapasitas untuk memori (33^3 * 4 channels) = 143748 floats
        floats.reserveCapacity(150_000)
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                if let sizeStr = trimmed.components(separatedBy: .whitespaces).last,
                   let size = Int(sizeStr) {
                    dimension = size
                }
                continue
            }
            
            let values = trimmed.components(separatedBy: .whitespaces).compactMap { Float($0) }
            if values.count >= 3 {
                // CoreImage butuh RGBA (4 channel), .cube hanya punya RGB
                floats.append(contentsOf: [values[0], values[1], values[2], 1.0])
            }
        }
        
        let data = floats.withUnsafeBytes { Data($0) }
        return (dimension, data)
    }
}
