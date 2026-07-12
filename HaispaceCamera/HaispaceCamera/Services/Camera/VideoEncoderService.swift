// VideoEncoderService.swift
// HaispaceCamera — Services/Camera
//
// Menggunakan VideoToolbox untuk melakukan kompresi hardware-accelerated 
// dari raw CVPixelBuffer menjadi NAL Units (H.264 bitstream).
// Bitstream dikirim via P2P ke iPad.

import Foundation
import VideoToolbox
import CoreMedia

actor VideoEncoderService {
    static let shared = VideoEncoderService()
    
    private var compressionSession: VTCompressionSession?
    private var isConfigured = false
    
    // Callback saat NAL Unit siap dikirim
    var onNALUReady: ((Data) -> Void)?
    
    private init() {}
    
    func configure(width: Int32, height: Int32) {
        guard !isConfigured else { return }
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            HaispaceLogger.error("Gagal membuat VTCompressionSession: \(status)", category: "camera")
            return
        }
        
        // Optimasi untuk real-time streaming berlatensi rendah
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        // Bitrate: 2.5 Mbps cukup untuk preview 720p/1080p yang jernih
        let bitrateLimit: Int32 = 2_500_000
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrateLimit))
        
        // Keyframe interval tiap 30 frame (~1 detik pada 30fps)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 30))
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        isConfigured = true
        HaispaceLogger.info("VideoEncoderService configured: \(width)x\(height)", category: "camera")
    }
    
    func encode(sampleBuffer: CMSampleBuffer) {
        guard isConfigured, let session = compressionSession,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        var flags: VTEncodeInfoFlags = []
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
    }
    
    // Dipanggil oleh outputCallback C-function
    nonisolated func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        Task {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
                  let attachment = attachments.first else { return }
            
            let isKeyframe = attachment[kCMSampleAttachmentKey_NotSync] == nil
            
            // Ekstrak SPS & PPS jika ini keyframe
            if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var spsSize: Int = 0
                var spsCount: Int = 0
                var ppsSize: Int = 0
                var ppsCount: Int = 0
                
                var spsPointer: UnsafePointer<UInt8>?
                var ppsPointer: UnsafePointer<UInt8>?
                
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil) == noErr,
                   CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: nil) == noErr {
                    
                    if let spsPtr = spsPointer, let ppsPtr = ppsPointer {
                        let spsData = Data(bytes: spsPtr, count: spsSize)
                        let ppsData = Data(bytes: ppsPtr, count: ppsSize)
                        
                        await dispatchNALU(data: spsData, isSPS: true)
                        await dispatchNALU(data: ppsData, isPPS: true)
                    }
                }
            }
            
            // Ekstrak NALU
            guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            
            if CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr {
                if let ptr = dataPointer {
                    var bufferOffset = 0
                    let startCode = Data([0x00, 0x00, 0x00, 0x01])
                    
                    while bufferOffset < length - 4 {
                        var naluLength: UInt32 = 0
                        memcpy(&naluLength, ptr + bufferOffset, 4)
                        naluLength = CFSwapInt32BigToHost(naluLength)
                        
                        var naluData = Data(startCode)
                        naluData.append(Data(bytes: ptr + bufferOffset + 4, count: Int(naluLength)))
                        
                        await dispatchNALU(data: naluData, isSPS: false, isPPS: false)
                        bufferOffset += Int(4 + naluLength)
                    }
                }
            }
        }
    }
    
    private func dispatchNALU(data: Data, isSPS: Bool = false, isPPS: Bool = false) {
        var finalData = data
        if isSPS || isPPS {
            let startCode = Data([0x00, 0x00, 0x00, 0x01])
            finalData = startCode + data
        }
        onNALUReady?(finalData)
    }
}

// C-function callback untuk VTCompressionSession
private func compressionOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
    let encoder = Unmanaged<VideoEncoderService>.fromOpaque(refCon).takeUnretainedValue()
    encoder.handleEncodedSampleBuffer(sampleBuffer)
}
