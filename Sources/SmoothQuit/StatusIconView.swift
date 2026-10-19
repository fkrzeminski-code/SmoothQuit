import AppKit
import QuartzCore

// Keep the native button. Coalesce rapid state changes into one centered turn.
final class StatusIconView: NSImageView {
    private(set) var active: Bool?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        // AppKit's backing layer defaults to a corner pivot, not the image center.
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
    }
    func update(active: Bool, animated: Bool, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard self.active != active else { return }
        let hadState = self.active != nil
        self.active = active
        image = Brand.image(active: active)
        setAccessibilityElement(false)
        wantsLayer = true
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard hadState, animated, !reduceMotion else {
            layer?.removeAnimation(forKey: "stateChange")
            return
        }
        // Changing direction mid-turn creates a shake. The latest state is applied
        // immediately, while an existing turn finishes without restarting.
        guard layer?.animation(forKey: "stateChange") == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = active ? 2 * CGFloat.pi : -2 * CGFloat.pi
        turn.duration = 0.6
        turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(turn, forKey: "stateChange")
    }
}
