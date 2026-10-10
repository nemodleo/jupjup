import AppKit
import QuartzCore

// 고른 자리 표시(디자인 캔버스 4번 D안). 눈이 머문 곳에서 진행과 끝을 보여 준다.
// 읽는 중: 주홍 괄호가 남고 선이 위아래로 훑음 → 다 됨: 괄호가 조여들며 테두리로, 모서리에 낙관 → 사라짐.

@MainActor
final class SelectionMarker {
    private var panel: NSPanel?
    private var root: CALayer?
    private var brackets: CAShapeLayer?
    private var scan: CALayer?
    private let pad: CGFloat = 20 // 괄호·낙관이 들어갈 바깥 여백

    /// rect: 화면 좌표(왼쪽 아래 원점)
    func show(_ rect: CGRect) {
        dismiss(animated: false)
        let frame = rect.insetBy(dx: -pad, dy: -pad)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        p.contentView = view
        guard let layer = view.layer else { return }
        root = layer

        let inner = CGRect(x: pad, y: pad, width: rect.width, height: rect.height)

        // 훑는 선
        let clip = CALayer()
        clip.frame = inner.insetBy(dx: 2, dy: 2)
        clip.masksToBounds = true
        let line = CALayer()
        line.backgroundColor = Ink.seal.withAlphaComponent(0.55).cgColor
        line.frame = CGRect(x: 0, y: 0, width: clip.bounds.width, height: 2)
        clip.addSublayer(line)
        layer.addSublayer(clip)
        let sweep = CABasicAnimation(keyPath: "position.y")
        sweep.fromValue = clip.bounds.height - 1
        sweep.toValue = 1
        sweep.duration = 0.9
        sweep.autoreverses = true
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        line.add(sweep, forKey: "sweep")
        scan = clip

        // 괄호 (고르기 화면과 같은 자리·굵기)
        let b = CAShapeLayer()
        b.path = Self.bracketPath(inner.insetBy(dx: -6, dy: -6))
        b.strokeColor = Ink.seal.cgColor
        b.fillColor = nil
        b.lineWidth = 2.5
        b.lineCap = .square
        layer.addSublayer(b)
        brackets = b

        panel = p
        p.orderFrontRegardless()
    }

    /// 다 됨. ok=false(글자 없음)이면 낙관 없이 옅어지며 사라진다.
    func finish(ok: Bool) {
        guard let root, let brackets else { return }
        scan?.removeFromSuperlayer()
        scan = nil
        let inner = root.bounds.insetBy(dx: pad, dy: pad)

        if !ok {
            brackets.strokeColor = Ink.faint.cgColor
            dismiss(animated: true, after: 0.25)
            return
        }

        // 괄호 → 글을 감싸는 테두리로 조여듦
        let ring = CAShapeLayer()
        ring.path = CGPath(roundedRect: inner.insetBy(dx: -2, dy: -2), cornerWidth: 4, cornerHeight: 4, transform: nil)
        ring.strokeColor = Ink.seal.cgColor
        ring.fillColor = nil
        ring.lineWidth = 2.5
        ring.opacity = 0
        root.addSublayer(ring)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.22)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        brackets.path = Self.bracketPath(inner.insetBy(dx: -2, dy: -2))
        brackets.opacity = 0
        ring.opacity = 1
        CATransaction.commit()

        // 오른쪽 위 모서리에 낙관 쾅
        let size: CGFloat = 24
        let stamp = CALayer()
        stamp.frame = CGRect(x: inner.maxX - size / 2 + 2, y: inner.maxY - size / 2 + 2, width: size, height: size)
        stamp.backgroundColor = Ink.seal.cgColor
        stamp.cornerRadius = 3
        stamp.shadowColor = Ink.seal.cgColor
        stamp.shadowOpacity = 0.4
        stamp.shadowRadius = 5
        stamp.shadowOffset = CGSize(width: 0, height: -3)
        let check = CAShapeLayer()
        let c = CGMutablePath()
        c.move(to: CGPoint(x: 6.5, y: 12.5))
        c.addLine(to: CGPoint(x: 10.5, y: 8.2))
        c.addLine(to: CGPoint(x: 18, y: 16.5))
        check.path = c
        check.strokeColor = Ink.hanjiLight.cgColor
        check.fillColor = nil
        check.lineWidth = 2.4
        check.lineCap = .round
        check.lineJoin = .round
        stamp.addSublayer(check)
        root.addSublayer(stamp)
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1.6, 0.92, 1.04, 1]
        pop.keyTimes = [0, 0.5, 0.75, 1]
        pop.duration = 0.32
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = 0.12
        stamp.add(pop, forKey: "pop")
        stamp.add(fadeIn, forKey: "in")

        dismiss(animated: true, after: 0.9)
    }

    func dismiss(animated: Bool, after delay: Double = 0) {
        guard let p = panel else { return }
        panel = nil
        root = nil
        brackets = nil
        scan = nil
        guard animated else { p.orderOut(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; p.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated { p.orderOut(nil) }
            }
        }
    }

    private static func bracketPath(_ o: CGRect) -> CGPath {
        let len = min(24, o.width / 3, o.height / 3)
        let p = CGMutablePath()
        for (c, dx, dy) in [(CGPoint(x: o.minX, y: o.minY), 1.0, 1.0), (CGPoint(x: o.maxX, y: o.minY), -1.0, 1.0),
                            (CGPoint(x: o.maxX, y: o.maxY), -1.0, -1.0), (CGPoint(x: o.minX, y: o.maxY), 1.0, -1.0)] {
            p.move(to: CGPoint(x: c.x, y: c.y + dy * len))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x + dx * len, y: c.y))
        }
        return p
    }
}
