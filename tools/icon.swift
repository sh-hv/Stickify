import CoreGraphics
import ImageIO
import Foundation

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: -0.12)
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 36, color: CGColor(gray: 0, alpha: 0.25))
ctx.setFillColor(CGColor(red: 0.16, green: 0.82, blue: 0.56, alpha: 1))
ctx.addPath(CGPath(roundedRect: CGRect(x: -300, y: -300, width: 600, height: 600), cornerWidth: 150, cornerHeight: 150, transform: nil))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
let face = CGColor(gray: 1, alpha: 1)
ctx.setFillColor(face)
ctx.fillEllipse(in: CGRect(x: -130, y: 40, width: 70, height: 110))
ctx.fillEllipse(in: CGRect(x: 60, y: 40, width: 70, height: 110))
ctx.setStrokeColor(face)
ctx.setLineWidth(40)
ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: 0, y: -10), radius: 150, startAngle: CGFloat.pi * 1.15, endAngle: CGFloat.pi * 1.85, clockwise: false)
ctx.strokePath()
ctx.restoreGState()
let img = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
