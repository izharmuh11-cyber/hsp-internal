// FrameMaskCompositor.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Legacy Frame Mask & Smart Auto-Fit Metal Engine (SnapBooth Legacy Ported).
// Preserves exact aspect ratio matching, gravity alignment (0.5/0.5 center snap), and slot boundary clipping.

import Foundation
import CoreGraphics

public struct FrameSlot: Sendable, Equatable {
    public let id: String
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat
    public let rotationDegrees: CGFloat
    
    public init(id: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rotationDegrees: CGFloat = 0.0) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotationDegrees = rotationDegrees
    }
}

public struct SlotAdjustment: Sendable, Equatable {
    public let cropGravityX: CGFloat // 0.0 (Left) s/d 1.0 (Right), Default 0.5 (Center)
    public let cropGravityY: CGFloat // 0.0 (Top) s/d 1.0 (Bottom), Default 0.5 (Center)
    public let cropZoom: CGFloat     // Default 1.0
    
    public init(cropGravityX: CGFloat = 0.5, cropGravityY: CGFloat = 0.5, cropZoom: CGFloat = 1.0) {
        self.cropGravityX = cropGravityX
        self.cropGravityY = cropGravityY
        self.cropZoom = cropZoom
    }
}

public struct CompositedDrawRect: Sendable, Equatable {
    public let drawX: CGFloat
    public let drawY: CGFloat
    public let drawWidth: CGFloat
    public let drawHeight: CGFloat
    public let clipSlotRect: CGRect
}

public struct FrameMaskCompositor: Sendable {
    
    public init() {}
    
    /// Mengkalkulasi tata letak auto-fit presisi (Legacy `canvas-composite.js` algorithm ported to Swift)
    public func calculateAutoFitRect(
        imageSize: CGSize,
        slot: FrameSlot,
        adjustment: SlotAdjustment = SlotAdjustment()
    ) -> CompositedDrawRect {
        
        let slotW = slot.width
        let slotH = slot.height
        
        guard imageSize.width > 0, imageSize.height > 0, slotW > 0, slotH > 0 else {
            let clipRect = CGRect(x: slot.x, y: slot.y, width: slotW, height: slotH)
            return CompositedDrawRect(drawX: slot.x, drawY: slot.y, drawWidth: slotW, drawHeight: slotH, clipSlotRect: clipRect)
        }
        
        let slotAspect = slotW / slotH
        let imgAspect = imageSize.width / imageSize.height
        let zoom = max(1.0, adjustment.cropZoom)
        
        var drawW: CGFloat = 0.0
        var drawH: CGFloat = 0.0
        
        // 1. Aspect Ratio Lock & Scaling
        if imgAspect > slotAspect {
            drawH = slotH * zoom
            drawW = drawH * imgAspect
        } else {
            drawW = slotW * zoom
            drawH = drawW / imgAspect
        }
        
        // 2. Gravity-based Translation (Center Snap default 0.5)
        let extraX = drawW - slotW
        let extraY = drawH - slotH
        
        let drawX = slot.x - (extraX * adjustment.cropGravityX)
        let drawY = slot.y - (extraY * adjustment.cropGravityY)
        let clipRect = CGRect(x: slot.x, y: slot.y, width: slotW, height: slotH)
        
        return CompositedDrawRect(
            drawX: drawX,
            drawY: drawY,
            drawWidth: drawW,
            drawHeight: drawH,
            clipSlotRect: clipRect
        )
    }
}
