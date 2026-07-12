// StreamingDecoderService.swift
// HaispaceBooths — Services/Camera
//
// Menerima NAL Units H.264 dari iPhone via P2P dan me-render-nya 
// secara hardware-accelerated ke layar iPad dengan latensi sangat rendah.
//
// Ref: docs/design/20_haicamera_iphone.md

import Foundation
import AVFoundation
import CoreMedia
import OSLog

@MainActor
final class StreamingDecoderService {
    
    static let shared = StreamingDecoderService()
    
    // CoreMedia format description untuk H.264
    private var formatDescription: CMVideoFormatDescription?
    
    // Layer tampilan yang ditempel ke SwiftUI View
    let displayLayer = AVSampleBufferDisplayLayer()
    
    // SPS & PPS dari stream
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    
    private init() {
        displayLayer.videoGravity = .resizeAspectFill
        
        // Memastikan decode dilakukan as soon as possible tanpa delay sinkronisasi waktu
        displayLayer.controlTimebase = CMTimebase(pointer: CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: nil) as! CMTimebase)
        displayLayer.controlTimebase?.rate = 1.0
    }
    
    /// Mengelola paket raw NALU dari network.
    /// Untuk Fase 1, menerima stream NAL Unit (termasuk SPS/PPS di awal stream).
    func enqueue(nalu: Data) {
        // Implementasi dekode raw H.264 (Annex-B) ke CMSampleBuffer
        // Proses ini mem-parsing byte stream 0x00 00 00 01
        
        guard nalu.count > 4 else { return }
        
        // Baca tipe NALU dari header byte ke-4
        let naluType = nalu[4] & 0x1F
        
        switch naluType {
        case 7: // Sequence Parameter Set (SPS)
            sps = [UInt8](nalu.dropFirst(4))
            updateFormatDescription()
        case 8: // Picture Parameter Set (PPS)
            pps = [UInt8](nalu.dropFirst(4))
            updateFormatDescription()
        case 5, 1: // IDR (Keyframe) atau P-Frame/B-Frame (Non-IDR)
            if let formatDesc = formatDescription {
                decodeFrame(nalu: nalu, formatDescription: formatDesc)
            }
        default:
            break // Ignore other NAL types for now
        }
    }
    
    private func updateFormatDescription() {
        guard let sps = sps, let pps = pps else { return }
        
        let spsPointer = UnsafePointer(sps)
        let ppsPointer = UnsafePointer(pps)
        let parameterSetPointers = [spsPointer, ppsPointer]
        let parameterSetSizes = [sps.count, pps.count]
        
        var formatDesc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDesc
        )
        
        if status == noErr {
            self.formatDescription = formatDesc
            HaispaceLogger.debug("VideoFormatDescription berhasil diperbarui", category: "camera")
        } else {
            HaispaceLogger.error("Gagal membuat VideoFormatDescription: \(status)", category: "camera")
        }
    }
    
    private func decodeFrame(nalu: Data, formatDescription: CMVideoFormatDescription) {
        // Mengubah format panjang NALU dari Annex B (0x00000001) ke format AVCC (panjang 4-byte big endian)
        var length = CFSwapInt32HostToBig(UInt32(nalu.count - 4))
        var avccNalu = Data(bytes: &length, count: 4)
        avccNalu.append(nalu.dropFirst(4))
        
        var blockBuffer: CMBlockBuffer?
        let status = avccNalu.withUnsafeBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return kCMBlockBufferNoErr }
            return CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: UnsafeMutableRawPointer(mutating: baseAddress),
                blockLength: avccNalu.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccNalu.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        
        guard status == kCMBlockBufferNoErr, let blockBuf = blockBuffer else { return }
        
        var sampleSizeArray = [avccNalu.count]
        var sampleBuffer: CMSampleBuffer?
        
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuf,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        
        if sampleStatus == noErr, let sampleBuf = sampleBuffer {
            // Pastikan buffer siap dirender as soon as possible
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuf, createIfNecessary: true) as? [[CFString: Any]]
            attachments?.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
            
            // Push ke layer
            if displayLayer.isReadyForMoreMediaData {
                displayLayer.enqueue(sampleBuf)
            }
        }
    }
}
