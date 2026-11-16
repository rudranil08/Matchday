import SwiftUI
import CoreMotion

/// Interactive background for the sign-in screens: a floodlit pitch in chalk lines.
/// Flick the ball with your finger; tilt the phone and the pitch (and ball) respond.
/// Score in either goal for a "GOAL" flash and a haptic.
struct PitchBackground: View {
    var tint: Color = Color(hex: "0f1320")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sim = BallSim()
    @State private var motion = TiltReader()
    @State private var goals = 0
    @State private var goalFlash: Date?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let now = timeline.date
                Canvas { ctx, size in
                    let tilt = reduceMotion ? .zero : motion.tilt
                    if sim.step(now: now, size: size, gravity: tilt) { DispatchQueue.main.async { scored() } }
                    drawPitch(&ctx, size: size, tilt: tilt)
                    drawBall(&ctx)
                }
                .overlay {
                    if let flash = goalFlash, now.timeIntervalSince(flash) < 1.2 {
                        let t = now.timeIntervalSince(flash) / 1.2
                        Text("GOAL")
                            .font(AppFont.displayBlack(64))
                            .foregroundStyle(.white.opacity(0.9 * (1 - t)))
                            .scaleEffect(0.8 + 0.4 * t)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(tint)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { sim.drag(to: $0.location, at: Date()) }
                    .onEnded { v in sim.release(velocity: CGVector(dx: v.velocity.width, dy: v.velocity.height)) }
            )
            .onAppear { sim.reset(in: geo.size); if !reduceMotion { motion.start() } }
            .onDisappear { motion.stop() }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .heavy), trigger: goals)
        .accessibilityHidden(true)
    }

    private func scored() {
        goals += 1
        goalFlash = Date()
    }

    private func drawPitch(_ ctx: inout GraphicsContext, size: CGSize, tilt: CGVector) {
        // Parallax: the lines drift a few points with the tilt.
        let shift = CGSize(width: tilt.dx * 10, height: tilt.dy * 10)
        let inset: CGFloat = 22
        let rect = CGRect(x: inset + shift.width, y: inset + 40 + shift.height, width: size.width - inset * 2, height: size.height - inset * 2 - 80)
        let chalk = GraphicsContext.Shading.color(.white.opacity(0.13))
        let style = StrokeStyle(lineWidth: 2)

        var p = Path(roundedRect: rect, cornerRadius: 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        let r = rect.width * 0.18
        p.addEllipse(in: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2))
        p.addEllipse(in: CGRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6))
        for top in [true, false] {
            let boxW = rect.width * 0.6, boxH = rect.height * 0.14
            let sixW = rect.width * 0.28, sixH = rect.height * 0.05
            let y = top ? rect.minY : rect.maxY
            let dir: CGFloat = top ? 1 : -1
            p.addRect(CGRect(x: rect.midX - boxW / 2, y: top ? y : y - boxH, width: boxW, height: boxH))
            p.addRect(CGRect(x: rect.midX - sixW / 2, y: top ? y : y - sixH, width: sixW, height: sixH))
            p.addEllipse(in: CGRect(x: rect.midX - 2, y: y + dir * boxH * 0.72 - 2, width: 4, height: 4))
        }
        ctx.stroke(p, with: chalk, style: style)

        // Goals (where the ball scores).
        for g in sim.goals(in: size) {
            ctx.stroke(Path(roundedRect: g, cornerRadius: 2), with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 3))
        }
    }

    private func drawBall(_ ctx: inout GraphicsContext) {
        // Chalk trail.
        for (i, pt) in sim.trail.enumerated() {
            let a = Double(i) / Double(max(sim.trail.count, 1)) * 0.25
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)), with: .color(.white.opacity(a)))
        }
        let b = sim.ball, r = BallSim.radius
        // Soft floodlight under the ball.
        ctx.fill(Path(ellipseIn: CGRect(x: b.x - r * 3, y: b.y - r * 3, width: r * 6, height: r * 6)), with: .color(.white.opacity(0.05)))
        ctx.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)), with: .color(.white))
        // Simple panel pattern that rotates as it rolls.
        var panel = Path()
        for k in 0..<5 {
            let angle = sim.spin + Double(k) * 2 * .pi / 5
            let pt = CGPoint(x: b.x + cos(angle) * r * 0.42, y: b.y + sin(angle) * r * 0.42)
            k == 0 ? panel.move(to: pt) : panel.addLine(to: pt)
        }
        panel.closeSubpath()
        ctx.fill(panel, with: .color(Color(hex: "121726")))
        ctx.stroke(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: "121726").opacity(0.4)), lineWidth: 1)
    }
}

/// Tiny physics for the ball: friction, wall bounces, tilt gravity, goal detection.
final class BallSim {
    static let radius: CGFloat = 14
    var ball = CGPoint(x: 200, y: 400)
    var velocity = CGVector(dx: 120, dy: -260)
    var spin: Double = 0
    var trail: [CGPoint] = []
    private var last: Date?
    private var dragging = false
    private var dragSamples: [(CGPoint, Date)] = []
    private var cooldown: Date = .distantPast

    func reset(in size: CGSize) {
        ball = CGPoint(x: size.width / 2, y: size.height * 0.62)
        velocity = CGVector(dx: 90, dy: -220)
    }

    func goals(in size: CGSize) -> [CGRect] {
        let w = size.width * 0.22
        let top = CGRect(x: size.width / 2 - w / 2, y: 22 + 40 - 10, width: w, height: 12)
        let bottom = CGRect(x: size.width / 2 - w / 2, y: size.height - 22 - 40 - 2, width: w, height: 12)
        return [top, bottom]
    }

    func drag(to p: CGPoint, at t: Date) {
        dragging = true
        ball = p
        velocity = .zero
        dragSamples.append((p, t))
        if dragSamples.count > 4 { dragSamples.removeFirst() }
    }

    func release(velocity v: CGVector) {
        dragging = false
        dragSamples.removeAll()
        // Cap the flick so the ball stays on screen-ish.
        let speed = hypot(v.dx, v.dy), cap: CGFloat = 2200
        velocity = speed > cap ? CGVector(dx: v.dx / speed * cap, dy: v.dy / speed * cap) : v
    }

    /// Advances the sim; returns true when a goal was scored this frame.
    func step(now: Date, size: CGSize, gravity: CGVector) -> Bool {
        defer { last = now }
        guard let last else { return false }
        let dt = min(now.timeIntervalSince(last), 1 / 30)
        guard !dragging else { return false }

        velocity.dx += gravity.dx * 900 * dt
        velocity.dy += gravity.dy * 900 * dt
        let friction = pow(0.55, dt)
        velocity.dx *= friction
        velocity.dy *= friction
        ball.x += velocity.dx * dt
        ball.y += velocity.dy * dt

        let r = Self.radius, bounce: CGFloat = 0.72
        if ball.x < r { ball.x = r; velocity.dx = abs(velocity.dx) * bounce }
        if ball.x > size.width - r { ball.x = size.width - r; velocity.dx = -abs(velocity.dx) * bounce }
        if ball.y < r + 40 { ball.y = r + 40; velocity.dy = abs(velocity.dy) * bounce }
        if ball.y > size.height - r - 40 { ball.y = size.height - r - 40; velocity.dy = -abs(velocity.dy) * bounce }

        let speed = hypot(velocity.dx, velocity.dy)
        spin += Double(speed) * dt / Double(r) * (velocity.dx >= 0 ? 1 : -1)
        if speed > 60 { trail.append(ball) }
        if trail.count > 18 || (speed < 60 && !trail.isEmpty) { trail.removeFirst() }

        if now > cooldown, goals(in: size).contains(where: { $0.insetBy(dx: 0, dy: -r).contains(ball) }), speed > 150 {
            cooldown = now.addingTimeInterval(1.5)
            // Back to the centre spot for kick-off.
            ball = CGPoint(x: size.width / 2, y: size.height / 2)
            velocity = .zero
            trail.removeAll()
            return true
        }
        return false
    }
}

/// Reads device tilt (no permission needed for motion data on iPhone).
final class TiltReader {
    private let manager = CMMotionManager()
    private(set) var tilt = CGVector.zero

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let g = m?.gravity else { return }
            self?.tilt = CGVector(dx: g.x, dy: -g.y - 0.6) // phone held upright ≈ no pull
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
