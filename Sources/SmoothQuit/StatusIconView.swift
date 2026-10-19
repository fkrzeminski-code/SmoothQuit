import AppKit
import QuartzCore

// Keep the native status button and menu. Only its artwork animates, once per state change.
final class StatusIconView: NSImageView {
    private(set) var active: Bool?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(active: Bool, animated: Bool, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard self.active != active else { return }
        let hadState = self.active != nil
        self.active = active
        image = Brand.image(active: active)
        setAccessibilityElement(false)
        wantsLayer = true
        let previous = layer?.animation(forKey: "stateChange") == nil ? nil
            : layer?.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat
        layer?.removeAllAnimations()
        guard hadState, animated, !reduceMotion else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = previous ?? (active ? -.pi / 5 : .pi / 5)
        turn.toValue = 0
        turn.duration = 0.24
        turn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(turn, forKey: "stateChange")
    }
}
