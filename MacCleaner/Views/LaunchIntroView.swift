import SwiftUI

struct LaunchIntroView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tileVisible = false
    @State private var tileSettled = false
    @State private var capsuleProgress: CGFloat = 0
    @State private var signalProgress: CGFloat = 0
    @State private var heartbeatProgress: CGFloat = 0
    @State private var snowflakeVisible = false
    @State private var sloganVisible = false
    @State private var isLeaving = false

    var body: some View {
        ZStack {
            Color.surfaceLight
                .ignoresSafeArea()

            VStack(spacing: 18) {
                logoMark
                    .frame(width: 214, height: 214)
                    .scaleEffect(isLeaving ? 0.94 : (tileSettled ? 1.0 : 0.9))
                    .opacity(isLeaving ? 0 : 1)

                Text("Device Health Matters")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Color.textSecondaryLight)
                    .opacity(sloganVisible && !isLeaving ? 1 : 0)
                    .offset(y: sloganVisible ? 0 : 8)
            }
            .offset(y: -4)
        }
        .opacity(isLeaving ? 0 : 1)
        .task {
            await playSequence()
        }
    }

    private var logoMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 47, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.95, green: 0.96, blue: 0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 47, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.74), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 30, x: 0, y: 18)
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                .opacity(tileVisible ? 1 : 0)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(red: 0.035, green: 0.04, blue: 0.045))
                .frame(width: 174 * capsuleProgress, height: 66)
                .shadow(color: Color.black.opacity(0.13), radius: 6, x: 0, y: 3)
                .opacity(tileVisible ? 1 : 0)

            ZStack {
                LogoSignalGlyph(progress: signalProgress)
                    .frame(width: 34, height: 34)
                    .position(x: 35, y: 33)
                    .opacity(signalProgress > 0 ? 1 : 0)

                LogoHeartbeatGlyph(progress: heartbeatProgress)
                    .stroke(
                        Color(red: 0.38, green: 1.0, blue: 0.48),
                        style: StrokeStyle(lineWidth: 4.8, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 48, height: 34)
                    .position(x: 88, y: 33)
                    .shadow(color: Color(red: 0.38, green: 1.0, blue: 0.48).opacity(0.55), radius: 7)

                Image(systemName: "snowflake")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.72, blue: 1.0))
                    .rotationEffect(.degrees(snowflakeVisible ? 0 : -72))
                    .scaleEffect(snowflakeVisible ? 1 : 0.62)
                    .frame(width: 34, height: 34)
                    .position(x: 138, y: 33)
                    .opacity(snowflakeVisible ? 1 : 0)
                    .shadow(color: Color(red: 0.35, green: 0.72, blue: 1.0).opacity(0.55), radius: 7)
            }
            .frame(width: 174, height: 66)
            .mask(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .frame(width: 174 * capsuleProgress, height: 66)
            )
        }
    }

    @MainActor
    private func playSequence() async {
        if reduceMotion {
            tileVisible = true
            tileSettled = true
            capsuleProgress = 1
            signalProgress = 1
            heartbeatProgress = 1
            snowflakeVisible = true
            withAnimation(.easeOut(duration: 0.18)) {
                sloganVisible = true
            }
            await wait(0.55)
            withAnimation(.easeInOut(duration: 0.24)) {
                isLeaving = true
            }
            await wait(0.26)
            onFinished()
            return
        }

        await wait(0.12)
        withAnimation(.interpolatingSpring(stiffness: 104, damping: 13)) {
            tileVisible = true
            tileSettled = true
        }

        await wait(0.28)
        withAnimation(.easeInOut(duration: 0.38)) {
            capsuleProgress = 1
        }

        await wait(0.22)
        withAnimation(.easeOut(duration: 0.28)) {
            signalProgress = 1
        }

        await wait(0.18)
        withAnimation(.easeInOut(duration: 0.42)) {
            heartbeatProgress = 1
        }

        await wait(0.24)
        withAnimation(.interpolatingSpring(stiffness: 150, damping: 10)) {
            snowflakeVisible = true
        }

        await wait(0.12)
        withAnimation(.easeOut(duration: 0.34)) {
            sloganVisible = true
        }

        await wait(0.84)
        withAnimation(.easeInOut(duration: 0.38)) {
            isLeaving = true
        }

        await wait(0.42)
        onFinished()
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

private struct LogoSignalGlyph: View {
    let progress: CGFloat
    private let color = Color(red: 1.0, green: 0.84, blue: 0.24)

    var body: some View {
        ZStack {
            SignalArc(index: 0)
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 4.2, lineCap: .round)
                )

            SignalArc(index: 1)
                .trim(from: 0, to: max(0, progress - 0.18) / 0.82)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 4.2, lineCap: .round)
                )

            SignalArc(index: 2)
                .trim(from: 0, to: max(0, progress - 0.34) / 0.66)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 4.2, lineCap: .round)
                )
        }
        .shadow(color: color.opacity(0.5), radius: 7)
    }
}

private struct SignalArc: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = min(rect.width, rect.height)
        let radius: CGFloat
        switch index {
        case 0: radius = size * 0.20
        case 1: radius = size * 0.34
        default: radius = size * 0.48
        }
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.2)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(216),
            endAngle: .degrees(324),
            clockwise: false
        )
        return path
    }
}

private struct LogoHeartbeatGlyph: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.minX + rect.width * 0.26, y: rect.midY),
            CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.54),
            CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.18),
            CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY - rect.height * 0.18),
            CGPoint(x: rect.minX + rect.width * 0.70, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY)
        ]

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        let clamped = max(0, min(1, progress))
        let segmentProgress = clamped * CGFloat(points.count - 1)
        let wholeSegments = Int(segmentProgress)
        let partial = segmentProgress - CGFloat(wholeSegments)

        if wholeSegments > 0 {
            for index in 1...min(wholeSegments, points.count - 1) {
                path.addLine(to: points[index])
            }
        }

        if wholeSegments < points.count - 1 {
            let start = points[wholeSegments]
            let end = points[wholeSegments + 1]
            path.addLine(
                to: CGPoint(
                    x: start.x + (end.x - start.x) * partial,
                    y: start.y + (end.y - start.y) * partial
                )
            )
        }

        return path
    }
}
