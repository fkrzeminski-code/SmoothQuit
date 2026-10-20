import AppKit

// One geometry for the menu bar, app icon and documentation. No animation or timer.
enum Brand {
    static let orbit: CGPath = {
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: 50, y: 50), radius: 32,
                    startAngle: -.pi / 36, endAngle: .pi * 1.5, clockwise: false)
        return path.copy(strokingWithWidth: 11, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }()
    static let dot = CGPath(ellipseIn: CGRect(x: 66.13, y: 20.87, width: 13, height: 13), transform: nil)

    static func draw(in context: CGContext, size: CGFloat, color: NSColor = .white) {
        context.saveGState()
        context.scaleBy(x: size / 100, y: size / 100)
        context.setFillColor(color.cgColor)
        context.addPath(orbit); context.addPath(dot); context.fillPath()
        context.restoreGState()
    }
    static func image(size: CGFloat = 18, state: MonitoringState = .active) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: rect.width / 100, y: rect.height / 100)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(orbit)
            switch state {
            case .active: context.addPath(dot)
            case .paused:
                context.addRect(CGRect(x: 65, y: 20, width: 5, height: 15))
                context.addRect(CGRect(x: 74, y: 20, width: 5, height: 15))
            case .disabled:
                // A hollow marker distinguishes Off from Pause without lowering contrast.
                context.addPath(dot.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 1))
            case .needsAccess:
                context.addRect(CGRect(x: 70, y: 27, width: 5, height: 12))
                context.addEllipse(in: CGRect(x: 70, y: 19, width: 5, height: 5))
            case .needsApps:
                context.addRect(CGRect(x: 65, y: 26, width: 17, height: 5))
                context.addRect(CGRect(x: 71, y: 20, width: 5, height: 17))
            }
            context.fillPath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SmoothQuit"
        return image
    }
}
