import AVFoundation
import UIKit
import HaishinKit

class BackgroundFrameGenerator {
    private var timer: Timer?
    private var pixelBuffer: CVPixelBuffer?
    private weak var stream: RTMPStream?
    
    init(stream: RTMPStream) {
        self.stream = stream
        createPausedPixelBuffer()
    }
    
    private func createPausedPixelBuffer() {
        let size = CGSize(width: 1280, height: 720)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            
            let colors = [UIColor.darkGray.cgColor, UIColor.black.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width/2, y: size.height/2),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width/2, y: size.height/2),
                    endRadius: size.width/2,
                    options: .drawsBeforeStartLocation
                )
            }
            
            let text = "STREAM PAUSED\n(Audio is Live)"
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 100, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attrs)
        }
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs, &buffer)
        
        guard let pb = buffer, let cgImage = image.cgImage else { return }
        
        CVPixelBufferLockBaseAddress(pb, [])
        let cgContext = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        if let ctx = cgContext {
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        self.pixelBuffer = pb
    }
    
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self = self, let pb = self.pixelBuffer, let stream = self.stream else { return }
            
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            var sampleTime = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 15),
                presentationTimeStamp: now,
                decodeTimeStamp: .invalid
            )
            
            var formatDesc: CMFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &formatDesc)
            
            var sampleBuffer: CMSampleBuffer?
            guard let fd = formatDesc else { return }
            
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pb,
                formatDescription: fd,
                sampleTiming: &sampleTime,
                sampleBufferOut: &sampleBuffer
            )
            
            if let sb = sampleBuffer {
                stream.append(sb)
            }
        }
        
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
