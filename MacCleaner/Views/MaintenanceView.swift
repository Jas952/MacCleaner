import AppKit
import SwiftUI

// MARK: - Blueprint color tokens
private let bpStroke  = Color(red: 0.55, green: 0.60, blue: 0.70)
private let bpFill    = Color(red: 0.93, green: 0.95, blue: 0.98)
private let bpAccent  = Color(red: 0.35, green: 0.48, blue: 0.78)
private let bpDimFill = Color(red: 0.20, green: 0.25, blue: 0.38)

// Shared layout constants
// kSchematicW/H — uniform schematic column for all three cards
// kLeading       — gap from card left edge to schematic
// kGap           — equal gap: schematic→divider, divider→button, button→divider
private let kSchematicW:   CGFloat = 170   // fixed render width  — same for all 3 cards
private let kSchematicH:   CGFloat = 110   // fixed column height — same for all 3 cards
private let kSchematicVisualH: CGFloat = 96
private let kLeading:      CGFloat = 20
private let kGap:          CGFloat = 14
private let kButtonW:      CGFloat = 52
private let kMacBookBodyRatio: CGFloat = 1.414

private func schematicScale(naturalW: CGFloat, naturalH: CGFloat) -> CGFloat {
    kSchematicVisualH / naturalH
}

private func macBookWidth(forHeight height: CGFloat) -> CGFloat {
    height * kMacBookBodyRatio
}

// MARK: - Screen Blueprint Schematic

struct ScreenBlueprintSchematic: View {
    var dimmed: Bool = false
    @State private var dimProgress: Double = 0

    static let naturalW: CGFloat = 150
    static let naturalH: CGFloat = 86
    private let W = ScreenBlueprintSchematic.naturalW
    private let H = ScreenBlueprintSchematic.naturalH
    private var deviceW: CGFloat { macBookWidth(forHeight: H) }
    private var lidH: CGFloat { H * 0.80 }
    private var baseH: CGFloat { H - lidH - 1.4 }
    private var displayW: CGFloat { deviceW * 0.80 }
    private var displayH: CGFloat { displayW / 1.6 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(bpFill)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(bpStroke, lineWidth: 1.1))

                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(dimmed
                              ? bpDimFill.opacity(0.36 + 0.58 * dimProgress)
                              : bpStroke.opacity(0.09))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(bpStroke.opacity(0.28), lineWidth: 0.4))
                        .frame(width: displayW, height: displayH)
                    if !dimmed {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(bpAccent.opacity(0.28))
                                .frame(height: 2.5)
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(bpAccent.opacity(0.13))
                                    .frame(width: 18)
                                VStack(spacing: 2) {
                                    ForEach(0..<4, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 0.8)
                                            .fill(bpAccent.opacity(0.16))
                                            .frame(height: 2)
                                    }
                                }.frame(maxWidth: .infinity)
                            }
                        }
                        .frame(width: displayW - 10, height: displayH - 8)
                    } else {
                        Text("=)")
                            .font(.system(size: 11, weight: .light, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55 * dimProgress))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 7)

                Circle().fill(bpStroke).frame(width: 2.5, height: 2.5)
                    .offset(y: -(lidH / 2) + 4)
            }
            .frame(width: deviceW, height: lidH)

            Capsule()
                .fill(bpStroke.opacity(0.86))
                .frame(width: deviceW, height: 1.4)

            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(bpFill)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(bpStroke.opacity(0.84), lineWidth: 0.9))
                Capsule()
                    .fill(bpStroke.opacity(0.22))
                    .frame(width: deviceW * 0.18, height: 1.5)
                    .offset(y: baseH * 0.35)
            }
            .frame(width: deviceW, height: baseH)
        }
        .frame(width: W, height: H)
        .onChange(of: dimmed) { d in
            withAnimation(.easeIn(duration: 0.45)) { dimProgress = d ? 1 : 0 }
        }
        .onAppear { dimProgress = dimmed ? 1 : 0 }
    }
}

// MARK: - Shared MacBook top case schematic

private struct MacBookTopCaseBlueprint: View {
    let width: CGFloat
    let height: CGFloat
    let locked: Bool
    let lockOpacity: Double
    let lockScale: CGFloat
    let showsLockGlyph: Bool

    private var keyGap: CGFloat { max(0.7, width * 0.008) }
    private var keyboardW: CGFloat { width * 0.84 }
    private var keyboardH: CGFloat { height * 0.34 }
    private var keyH: CGFloat { max(1.8, keyboardH * 0.155) }
    private var commandKeyW: CGFloat { keyboardW * 0.082 }
    private var spaceKeyW: CGFloat { keyboardW * 0.34 }
    private var touchBarW: CGFloat { commandKeyW * 2 + spaceKeyW + keyGap * 2 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.035, style: .continuous)
                .fill(bpFill)
                .overlay(
                    RoundedRectangle(cornerRadius: width * 0.035, style: .continuous)
                        .strokeBorder(bpStroke, lineWidth: 1.0)
                )

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(bpStroke.opacity(0.16))
                .frame(width: width * 0.18, height: max(1, height * 0.018))
                .offset(y: height * 0.43)

            touchBar
                .offset(y: -height * 0.32)

            keyboard
                .offset(y: -height * 0.10)

            trackpad
                .offset(y: height * 0.24)

            if showsLockGlyph && locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: width * 0.12, weight: .semibold))
                    .foregroundStyle(Color.accentRed.opacity(lockOpacity))
                    .scaleEffect(lockScale)
            }
        }
        .frame(width: width, height: height)
    }

    private var touchBar: some View {
        RoundedRectangle(cornerRadius: max(1, width * 0.012), style: .continuous)
            .fill(locked ? Color.accentRed.opacity(0.18) : bpDimFill.opacity(0.78))
            .overlay(
                HStack(spacing: width * 0.012) {
                    ForEach(0..<8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 0.7, style: .continuous)
                            .fill((locked ? Color.accentRed : bpAccent).opacity(index == 3 ? 0.45 : 0.20))
                            .frame(width: touchBarW * (index == 3 ? 0.14 : 0.075))
                    }
                }
                .padding(.horizontal, touchBarW * 0.06)
            )
            .frame(width: touchBarW, height: max(4.2, height * 0.072))
            .overlay(
                RoundedRectangle(cornerRadius: max(1, width * 0.012), style: .continuous)
                    .strokeBorder(bpStroke.opacity(0.30), lineWidth: 0.45)
            )
    }

    private var keyboard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(1.5, width * 0.012), style: .continuous)
                .strokeBorder(bpStroke.opacity(0.16), lineWidth: 0.45)

            VStack(spacing: keyGap) {
                keyRow(count: 13)
                keyRow(count: 13)
                keyRow(count: 13)
                keyRow(count: 13)
                spaceRow
            }
            .padding(.horizontal, keyboardW * 0.025)
            .padding(.vertical, keyboardH * 0.06)
        }
        .frame(width: keyboardW, height: keyboardH)
    }

    private var trackpad: some View {
        RoundedRectangle(cornerRadius: width * 0.025, style: .continuous)
            .fill(bpFill)
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.025, style: .continuous)
                    .strokeBorder(bpStroke.opacity(0.58), lineWidth: 0.75)
            )
            .frame(width: width * 0.42, height: height * 0.22)
    }

    @ViewBuilder
    private func keyRow(count: Int) -> some View {
        let availW = keyboardW * 0.95
        let keyW = (availW - keyGap * CGFloat(count - 1)) / CGFloat(count)
        HStack(spacing: keyGap) {
            ForEach(0..<count, id: \.self) { _ in
                keyCell(width: keyW)
            }
        }
        .frame(width: availW)
    }

    private var spaceRow: some View {
        HStack(spacing: keyGap) {
            keyCell(width: keyboardW * 0.062)
            keyCell(width: commandKeyW)
            keyCell(width: keyboardW * 0.062)
            keyCell(width: spaceKeyW)
            keyCell(width: keyboardW * 0.062)
            keyCell(width: commandKeyW)
            keyCell(width: keyboardW * 0.062)
            HStack(spacing: keyGap * 0.70) {
                keyCell(width: keyboardW * 0.035)
                VStack(spacing: keyGap * 0.60) {
                    keyCell(width: keyboardW * 0.035, height: keyH * 0.43)
                    keyCell(width: keyboardW * 0.035, height: keyH * 0.43)
                }
                keyCell(width: keyboardW * 0.035)
            }
        }
        .frame(width: keyboardW * 0.95)
    }

    @ViewBuilder
    private func keyCell(width: CGFloat, height: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: max(0.8, width * 0.14), style: .continuous)
            .fill(locked ? Color.accentRed.opacity(0.07) : bpStroke.opacity(0.075))
            .overlay(
                RoundedRectangle(cornerRadius: max(0.8, width * 0.14), style: .continuous)
                    .strokeBorder(
                        locked ? Color.accentRed.opacity(0.26) : bpStroke.opacity(0.42),
                        lineWidth: 0.38
                    )
            )
            .frame(width: max(1, width), height: max(1, height ?? keyH))
    }
}

// MARK: - Keyboard Blueprint Schematic

struct KeyboardBlueprintSchematic: View {
    var locked: Bool = false
    @State private var lockOpacity: Double = 0
    @State private var lockScale: CGFloat  = 0.7

    static let naturalW: CGFloat = 150
    static let naturalH: CGFloat = 86
    private let W = KeyboardBlueprintSchematic.naturalW
    private let H = KeyboardBlueprintSchematic.naturalH

    var body: some View {
        MacBookTopCaseBlueprint(
            width: macBookWidth(forHeight: H),
            height: H,
            locked: locked,
            lockOpacity: lockOpacity,
            lockScale: lockScale,
            showsLockGlyph: true
        )
        .frame(width: W, height: H)
        .onChange(of: locked) { isLocked in
            if isLocked {
                lockOpacity = 0; lockScale = 0.5
                withAnimation(.spring(response: 0.28, dampingFraction: 0.60)) {
                    lockOpacity = 0.88; lockScale = 1.0
                }
            } else {
                withAnimation(.easeOut(duration: 0.16)) { lockOpacity = 0; lockScale = 0.7 }
            }
        }
        .onAppear { lockOpacity = locked ? 0.88 : 0; lockScale = 1.0 }
    }
}

// MARK: - Full MacBook Blueprint

struct FullBlueprintSchematic: View {
    var screenDimmed: Bool = false
    var keyboardLocked: Bool = false

    static let naturalW: CGFloat = 150
    static let naturalH: CGFloat = 86
    private let W = FullBlueprintSchematic.naturalW
    private let H = FullBlueprintSchematic.naturalH
    private var deviceW: CGFloat { macBookWidth(forHeight: H) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bpFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(bpStroke, lineWidth: 1.05)
                )

            Image(systemName: "apple.logo")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(bpStroke.opacity(0.58))
        }
        .frame(width: deviceW, height: H)
        .frame(width: W, height: H)
    }
}

// MARK: - Schematic column
// Uniform column width for all cards so the action button always starts at the same X.
// The schematic is scaled to fill the column height (minus design padding).

// SchematicColumn: scales every schematic to the same visual height.
// Width = kLeading + scaledW + kGap (then a full-height divider, then the button).
private struct SchematicColumn<S: View>: View {
    let cardHeight: CGFloat
    let naturalW: CGFloat
    let naturalH: CGFloat
    let schematic: S

    init(cardHeight: CGFloat, naturalW: CGFloat, naturalH: CGFloat,
         @ViewBuilder schematic: () -> S) {
        self.cardHeight = cardHeight
        self.naturalW = naturalW
        self.naturalH = naturalH
        self.schematic = schematic()
    }

    var body: some View {
        let scale = schematicScale(naturalW: naturalW, naturalH: naturalH)
        let colW = kLeading + kSchematicW + kGap

        schematic
            .scaleEffect(scale, anchor: .center)
            .frame(width: kSchematicW, height: kSchematicVisualH)
            .padding(.leading, kLeading)
            .frame(width: colW, height: cardHeight, alignment: .center)
    }
}

// MARK: - Inline picker (always visible chip)

private struct InlinePicker<T: Hashable & CaseIterable & Identifiable>: View
    where T: CustomStringConvertible, T.AllCases: RandomAccessCollection {
    let label: String
    @Binding var selection: T
    let options: [T]
    let display: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)

            // Segmented-style chips
            HStack(spacing: 3) {
                ForEach(options, id: \.hashValue) { option in
                    let selected = option == selection
                    Button(action: { selection = option }) {
                        Text(display(option))
                            .font(.system(size: 10, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : Color.textSecondaryLight)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selected ? Color.accentBlue : Color.black.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(selected
                                                  ? Color.clear
                                                  : Color(red: 0.76, green: 0.78, blue: 0.82),
                                                  lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Duration picker (inline chips)

private struct DurationPicker: View {
    @Binding var selection: MaintenanceDuration
    var body: some View {
        HStack(spacing: 0) {
            Text("Duration")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(MaintenanceDuration.allCases) { d in
                    chipButton(label: d.label, selected: selection == d) { selection = d }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OpacityPicker: View {
    @Binding var selection: DimOpacity
    var body: some View {
        HStack(spacing: 0) {
            Text("Opacity")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(DimOpacity.allCases) { op in
                    chipButton(label: op.label, selected: selection == op) { selection = op }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@ViewBuilder
private func chipButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 10, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.white : Color.textSecondaryLight)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(minWidth: 28)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? Color.accentBlue : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(selected
                                  ? Color.clear
                                  : Color(red: 0.76, green: 0.78, blue: 0.82),
                                  lineWidth: 0.8)
            )
    }
    .buttonStyle(.plain)
}

// MARK: - Timer badge

private struct TimerBadge: View {
    let seconds: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "timer").font(.system(size: 9))
            Text(fmt(seconds)).font(.system(size: 10, design: .monospaced).weight(.semibold))
        }
        .foregroundStyle(Color.accentAmber)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(Color.accentAmber.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentAmber.opacity(0.25), lineWidth: 0.8))
        )
    }
    private func fmt(_ s: Int) -> String {
        String(format: "%d:%02d", max(0,s)/60, max(0,s)%60)
    }
}

// MARK: - Countdown overlay (light)

private struct CountdownOverlay: View {
    let count: Int
    var body: some View {
        ZStack {
            Color.white.opacity(0.72)
            Text("\(count)")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimaryLight)
        }
        .transition(.opacity)
    }
}

// MARK: - Cancel button

private struct CancelButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                Text("Cancel").font(.system(size: 10))
            }
            .foregroundStyle(Color.textSecondaryLight)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(red: 0.78, green: 0.80, blue: 0.84), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action button
// Width = kGap + kButtonW + kGap, then a full-height right divider.
// Coloured fill matches the shared schematic visual height, centred vertically.

private struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let disabled: Bool
    let cardHeight: CGFloat
    let buttonHeight: CGFloat
    let action: () -> Void

    var body: some View {
        let totalW = kGap + kButtonW + kGap
        let iconSize: CGFloat = buttonHeight < 92 ? 14 : 15
        let labelSize: CGFloat = buttonHeight < 92 ? 9.5 : 10
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(disabled ? Color(red: 0.74, green: 0.75, blue: 0.78) : color)
                .frame(width: kButtonW, height: buttonHeight)

            Button(action: action) {
                VStack(spacing: buttonHeight < 92 ? 4 : 5) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                    Text(label)
                        .font(.system(size: labelSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundStyle(.white)
                .frame(width: kButtonW, height: buttonHeight)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
        .frame(width: totalW, height: cardHeight, alignment: .center)
    }
}

// MARK: - Card shell

private struct CardShell<Content: View>: View {
    let activeColor: Color?
    let countdownView: AnyView?
    let content: Content

    init(activeColor: Color? = nil,
         countdown: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.activeColor = activeColor
        self.countdownView = countdown
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surfaceCardLight)
                        .shadow(color: Color.shadowMedium, radius: 5, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(activeColor.map { $0.opacity(0.32) } ?? Color.borderLight,
                                      lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let cd = countdownView {
                cd.clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Info panel (right side of divider)

private struct InfoPanel<Pickers: View>: View {
    let title: String
    let subtitle: String
    let badge: String?
    let badgeColor: Color
    let timer: (active: Bool, seconds: Int)?
    let showCancel: Bool
    let cancelAction: () -> Void
    let pickers: Pickers

    init(title: String,
         subtitle: String,
         badge: String? = nil,
         badgeColor: Color = .accentGreen,
         timer: (active: Bool, seconds: Int)? = nil,
         showCancel: Bool = false,
         cancelAction: @escaping () -> Void = {},
         @ViewBuilder pickers: () -> Pickers) {
        self.title = title; self.subtitle = subtitle
        self.badge = badge; self.badgeColor = badgeColor
        self.timer = timer; self.showCancel = showCancel
        self.cancelAction = cancelAction
        self.pickers = pickers()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title row
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .layoutPriority(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(badgeColor)
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(badgeColor.opacity(0.10)))
                }
                if let t = timer, t.active {
                    TimerBadge(seconds: t.seconds)
                }
                Spacer()
                if showCancel { CancelButton(action: cancelAction) }
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondaryLight)
                .lineLimit(2)
                .minimumScaleFactor(0.92)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Divider between text and pickers
            Rectangle()
                .fill(Color.borderLight)
                .frame(height: 1)
                .padding(.top, 9)
                .padding(.bottom, 7)

            // Pickers
            pickers
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Card 1: Screen Dim

private struct ScreenDimCard: View {
    @ObservedObject var svc: MaintenanceService
    let cardHeight: CGFloat

    var body: some View {
        CardShell(
            activeColor: svc.isScreenDimmed ? Color.accentBlue : nil,
            countdown: svc.screenDimCountdownActive
                ? AnyView(CountdownOverlay(count: svc.screenDimCountdown)) : nil
        ) {
            HStack(spacing: 0) {
                // Schematic — scales to fill card height
                SchematicColumn(
                    cardHeight: cardHeight,
                    naturalW: ScreenBlueprintSchematic.naturalW,
                    naturalH: ScreenBlueprintSchematic.naturalH
                ) {
                    ScreenBlueprintSchematic(dimmed: svc.isScreenDimmed)
                }

                ActionButton(
                    icon: svc.isScreenDimmed ? "eye" : "moon.fill",
                    label: svc.isScreenDimmed ? "Stop" : "Dim",
                    color: svc.isScreenDimmed ? Color.accentRed : Color.accentBlue,
                    disabled: svc.screenDimCountdownActive && !svc.isScreenDimmed,
                    cardHeight: cardHeight,
                    buttonHeight: kSchematicVisualH
                ) {
                    svc.isScreenDimmed ? svc.deactivateScreenDim() : svc.startScreenDimCountdown()
                }

                InfoPanel(
                    title: "Screen Blackout",
                    subtitle: "Darken the screen to clean the display.",
                    timer: (active: svc.isScreenDimmed, seconds: svc.screenDimTimeRemaining),
                    showCancel: svc.isScreenDimmed || svc.screenDimCountdownActive,
                    cancelAction: { svc.deactivateScreenDim() }
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        OpacityPicker(selection: $svc.dimOpacity)
                        DurationPicker(selection: $svc.screenDimDuration)
                    }
                }
            }
            .frame(height: cardHeight)
        }
        .animation(.easeInOut(duration: 0.18), value: svc.isScreenDimmed)
        .animation(.easeInOut(duration: 0.18), value: svc.screenDimCountdownActive)
    }
}

// MARK: - Card 2: Keyboard Lock

private struct KeyboardLockCard: View {
    @ObservedObject var svc: MaintenanceService
    let cardHeight: CGFloat

    var body: some View {
        CardShell(activeColor: svc.isKeyboardLocked ? Color.accentRed : nil) {
            HStack(spacing: 0) {
                SchematicColumn(
                    cardHeight: cardHeight,
                    naturalW: KeyboardBlueprintSchematic.naturalW,
                    naturalH: KeyboardBlueprintSchematic.naturalH
                ) {
                    KeyboardBlueprintSchematic(locked: svc.isKeyboardLocked)
                }

                ActionButton(
                    icon: svc.isKeyboardLocked ? "lock.open.fill" : "lock.fill",
                    label: svc.isKeyboardLocked ? "Unlock" : "Lock",
                    color: svc.isKeyboardLocked ? Color.accentRed : Color.accentBlue,
                    disabled: false,
                    cardHeight: cardHeight,
                    buttonHeight: kSchematicVisualH
                ) {
                    svc.isKeyboardLocked ? svc.deactivateKeyboardLock() : svc.activateKeyboardLock()
                }

                InfoPanel(
                    title: "Keyboard Lock",
                    subtitle: "Disable keypresses while cleaning.",
                    timer: (active: svc.isKeyboardLocked, seconds: svc.keyboardLockTimeRemaining),
                    showCancel: svc.isKeyboardLocked,
                    cancelAction: { svc.deactivateKeyboardLock() }
                ) {
                    DurationPicker(selection: $svc.keyboardLockDuration)
                }
            }
            .frame(height: cardHeight)
        }
        .animation(.easeInOut(duration: 0.18), value: svc.isKeyboardLocked)
    }
}

// MARK: - Card 3: Both

private struct BothCard: View {
    @ObservedObject var svc: MaintenanceService
    let cardHeight: CGFloat

    var body: some View {
        CardShell(
            activeColor: svc.isBothActive ? Color.accentGreen : nil,
            countdown: svc.bothCountdownActive
                ? AnyView(CountdownOverlay(count: svc.bothCountdown)) : nil
        ) {
            HStack(spacing: 0) {
                SchematicColumn(
                    cardHeight: cardHeight,
                    naturalW: FullBlueprintSchematic.naturalW,
                    naturalH: FullBlueprintSchematic.naturalH
                ) {
                    FullBlueprintSchematic(
                        screenDimmed: svc.isBothActive,
                        keyboardLocked: svc.isBothActive
                    )
                }

                ActionButton(
                    icon: svc.isBothActive ? "power" : "play.fill",
                    label: svc.isBothActive ? "Exit" : "Start",
                    color: svc.isBothActive ? Color.accentRed : Color.accentGreen,
                    disabled: svc.bothCountdownActive && !svc.isBothActive,
                    cardHeight: cardHeight,
                    buttonHeight: kSchematicVisualH
                ) {
                    svc.isBothActive ? svc.deactivateBoth() : svc.startBothCountdown()
                }

                InfoPanel(
                    title: "Full Maintenance Mode",
                    subtitle: "Screen blackout + keyboard lock simultaneously.",
                    badge: "recommended",
                    badgeColor: Color.accentGreen,
                    timer: (active: svc.isBothActive, seconds: svc.bothTimeRemaining),
                    showCancel: svc.isBothActive || svc.bothCountdownActive,
                    cancelAction: { svc.deactivateBoth() }
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        OpacityPicker(selection: $svc.dimOpacity)
                        DurationPicker(selection: $svc.bothDuration)
                    }
                }
            }
            .frame(height: cardHeight)
        }
        .animation(.easeInOut(duration: 0.18), value: svc.isBothActive)
        .animation(.easeInOut(duration: 0.18), value: svc.bothCountdownActive)
    }
}

// MARK: - MaintenanceView

private enum ToolsPane: CaseIterable, Identifiable {
    case physical
    case keyboard
    case speaker
    case storage
    case network

    var id: Self { self }

    var title: String {
        switch self {
        case .physical: return "Physical Maintenance"
        case .keyboard: return "Input Test"
        case .speaker: return "Speaker Test"
        case .storage: return "Device Health"
        case .network: return "Network Test"
        }
    }

    var subtitle: String {
        switch self {
        case .physical: return "Screen blackout and keyboard lock"
        case .keyboard: return "Keyboard, trackpad and mouse"
        case .speaker: return "Left/right channel check"
        case .storage: return "SSD, APFS and battery"
        case .network: return "Reachability and latency"
        }
    }

    var icon: String {
        switch self {
        case .physical: return "wrench.and.screwdriver"
        case .keyboard: return "keyboard"
        case .speaker: return "speaker.wave.3"
        case .storage: return "stethoscope"
        case .network: return "network"
        }
    }
}

struct MaintenanceView: View {
    @StateObject private var svc = MaintenanceService.shared
    @StateObject private var keyboardDiagnosticService = KeyboardDiagnosticService()
    @StateObject private var speakerTestService = SpeakerTestService()
    @StateObject private var storageHealthService = StorageHealthService()
    @StateObject private var diskIntegrityService = DiskIntegrityService()
    @StateObject private var advancedSSDService = AdvancedSSDService()
    @StateObject private var thermalPowerService = ThermalPowerService()
    @StateObject private var networkDiagnosticService = NetworkDiagnosticService()
    @State private var selectedPane: ToolsPane = .physical
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator
    @State private var reportLanguage: ToolsReportLanguage = .russian

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentBlue.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tools")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                    Text("Physical maintenance and hardware diagnostics")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 12)

                Button {
                    modalCoordinator.present(title: "Final Report", subtitle: "Hardware and maintenance diagnostics") {
                        ToolsDiagnosticReportSheet(
                            language: $reportLanguage,
                            report: diagnosticReport
                        )
                    }
                } label: {
                    Label("Final Report", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.surfaceCardLight)
                                .shadow(color: Color.shadowLight, radius: 4, x: 0, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentBlue.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Rectangle().fill(Color.borderLight).frame(height: 1)
                .padding(.horizontal, 28)

            VStack(spacing: 0) {
                paneSwitcher
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Group {
                    switch selectedPane {
                    case .physical:
                        physicalMaintenancePane
                    case .keyboard:
                        keyboardTestPane
                    case .speaker:
                        compactPane { SpeakerTestPanel(service: speakerTestService) }
                    case .storage:
                        compactPane {
                            DeviceHealthPanel(
                                storageService: storageHealthService,
                                diskService: diskIntegrityService,
                                advancedSSDService: advancedSSDService,
                                thermalService: thermalPowerService
                            )
                        }
                    case .network:
                        networkTestPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.surfaceLight)
        .onChange(of: selectedPane) { pane in
            stopInactiveDiagnostics(activePane: pane)
        }
        .onDisappear {
            stopAllDiagnostics()
        }
    }

    private var diagnosticReport: ToolsDiagnosticReport {
        ToolsDiagnosticReportBuilder.build(
            language: reportLanguage,
            keyboardService: keyboardDiagnosticService,
            pointerSnapshot: PointerInputSnapshot.load(),
            speakerService: speakerTestService,
            storageService: storageHealthService,
            diskService: diskIntegrityService,
            advancedSSDService: advancedSSDService,
            thermalService: thermalPowerService,
            networkService: networkDiagnosticService
        )
    }

    private var paneSwitcher: some View {
        VStack(spacing: 8) {
            toolPaneRow([.physical, .keyboard, .speaker])
            toolPaneRow([.storage, .network])
        }
    }

    private func toolPaneRow(_ panes: [ToolsPane]) -> some View {
        HStack(spacing: 8) {
            ForEach(panes) { pane in
                paneButton(pane)
            }
        }
    }

    private func paneButton(_ pane: ToolsPane) -> some View {
        Button {
            selectedPane = pane
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .font(.system(size: 12, weight: .medium))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pane.title)
                        .font(.system(size: 12, weight: selectedPane == pane ? .semibold : .medium))
                    Text(pane.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(selectedPane == pane ? Color.textSecondaryLight : Color.textTertiaryLight)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selectedPane == pane ? Color.textPrimaryLight : Color.textSecondaryLight)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selectedPane == pane ? Color.surfaceCardLight : Color.black.opacity(0.025))
                    .shadow(color: selectedPane == pane ? Color.shadowMedium : .clear, radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selectedPane == pane ? Color.accentBlue.opacity(0.22) : Color.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var physicalMaintenancePane: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let totalSpacing = spacing * 4
            let cardH = max(112, (geo.size.height - totalSpacing) / 3)

            VStack(spacing: spacing) {
                ScreenDimCard(svc: svc, cardHeight: cardH)
                KeyboardLockCard(svc: svc, cardHeight: cardH)
                BothCard(svc: svc, cardHeight: cardH)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, spacing)
        }
    }

    private var keyboardTestPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                KeyboardDiagnosticSection(service: keyboardDiagnosticService)
                PointerInputTestPanel()
            }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
        }
    }

    private func compactPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            content()
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
        }
    }

    private var networkTestPane: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                NetworkTestPanel(
                    service: networkDiagnosticService,
                    minimumContentHeight: max(400, geo.size.height - 98)
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }
        }
    }

    private func stopInactiveDiagnostics(activePane: ToolsPane) {
        if activePane != .keyboard {
            keyboardDiagnosticService.stop()
        }
        if activePane != .speaker {
            speakerTestService.stop()
        }
        if activePane != .storage {
            storageHealthService.cancel()
            diskIntegrityService.cancel()
            advancedSSDService.cancel()
            thermalPowerService.cancel()
        }
        if activePane != .network {
            networkDiagnosticService.cancel()
        }
    }

    private func stopAllDiagnostics() {
        keyboardDiagnosticService.stop()
        speakerTestService.stop()
        storageHealthService.cancel()
        diskIntegrityService.cancel()
        advancedSSDService.cancel()
        thermalPowerService.cancel()
        networkDiagnosticService.cancel()
    }
}

private enum ToolsReportLanguage: String, CaseIterable, Identifiable {
    case russian
    case english

    var id: Self { self }

    var shortTitle: String {
        switch self {
        case .russian: return "RU"
        case .english: return "EN"
        }
    }
}

private enum ToolsReportSeverity: Equatable {
    case good
    case notice
    case warning

    var color: Color {
        switch self {
        case .good: return .accentGreen
        case .notice: return .accentAmber
        case .warning: return .accentRed
        }
    }

    var icon: String {
        switch self {
        case .good: return "checkmark.seal"
        case .notice: return "exclamationmark.triangle"
        case .warning: return "xmark.octagon"
        }
    }
}

private struct ToolsDiagnosticReportSection: Identifiable {
    let id = UUID()
    let title: String
    let status: String
    let summary: String
    let details: [String]
    let recommendation: String
    let lastUsedAt: Date
    let severity: ToolsReportSeverity
}

private struct ToolsDiagnosticReport {
    let title: String
    let generatedAt: String
    let emptyMessage: String?
    let sections: [ToolsDiagnosticReportSection]
    let copyButtonTitle: String
    let closeButtonTitle: String
    let copiedTitle: String
    let copyText: String
}

private struct ToolsReportMetricRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let score: Double?
    let health: ToolsReportSeverity?
}

private struct ToolsDiagnosticReportSheet: View {
    @Binding var language: ToolsReportLanguage
    let report: ToolsDiagnosticReport
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(report.generatedAt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                }

                Spacer()

                languageSwitch

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.045)))
                }
                .buttonStyle(.plain)
                .help(report.closeButtonTitle)
            }
            .padding(20)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let emptyMessage = report.emptyMessage {
                        reportNoticeCard(emptyMessage)
                    }

                    ForEach(report.sections) { section in
                        reportSectionCard(section)
                    }
                }
                .padding(20)
            }

            Rectangle().fill(Color.borderLight).frame(height: 1)

            HStack(spacing: 10) {
                Spacer()
                Button {
                    copyReport()
                } label: {
                    Label(didCopy ? report.copiedTitle : report.copyButtonTitle, systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentBlue))
                }
                .buttonStyle(.plain)

                Button(report.closeButtonTitle) {
                    dismiss()
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondaryLight)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.045)))
            }
            .padding(20)
        }
        .frame(width: 720, height: 640)
        .background(Color.surfaceLight)
    }

    private var languageSwitch: some View {
        HStack(spacing: 4) {
            ForEach(ToolsReportLanguage.allCases) { option in
                let selected = option == language

                Button {
                    language = option
                } label: {
                    Text(option.shortTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.textPrimaryLight)
                        .frame(width: 42, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Color.accentBlue : Color.black.opacity(0.075))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selected ? Color.accentBlue.opacity(0.25) : Color.black.opacity(0.13), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
        )
        .accessibilityLabel("Report language")
    }

    private func reportNoticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentAmber)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentAmber.opacity(0.10)))

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondaryLight)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentAmber.opacity(0.065))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentAmber.opacity(0.18), lineWidth: 1))
        )
    }

    private func reportSectionCard(_ section: ToolsDiagnosticReportSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: section.severity.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(section.severity.color)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(section.severity.color.opacity(0.10)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(section.status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(section.severity.color)
                }

                Spacer()

                Text(ToolsDiagnosticReportBuilder.shortDate(section.lastUsedAt, language: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
            }

            Text(section.summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondaryLight)
                .fixedSize(horizontal: false, vertical: true)

            let rows = metricRows(for: section)
            if !rows.isEmpty {
                metricTable(rows)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.surfaceCardLight)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.borderLight, lineWidth: 1))
        )
    }

    private var reportOverviewTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(language == .russian ? "Сводная таблица" : "Summary Table")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                tableHeader(language == .russian ? "Раздел" : "Area", width: 190)
                tableHeader(language == .russian ? "Статус" : "Status", width: 120)
                tableHeader(language == .russian ? "Метрик" : "Metrics", width: 70)
                tableHeader(language == .russian ? "Время" : "Time", width: 120)
                tableHeader(language == .russian ? "Индикатор" : "Indicator", width: nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.035))

            ForEach(report.sections) { section in
                HStack(spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                        .frame(width: 190, alignment: .leading)
                    statusPill(section.status, color: section.severity.color)
                        .frame(width: 120, alignment: .leading)
                    Text("\(metricRows(for: section).count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(width: 70, alignment: .leading)
                    Text(ToolsDiagnosticReportBuilder.shortDate(section.lastUsedAt, language: language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    sectionIndicator(section)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                if section.id != report.sections.last?.id {
                    Rectangle().fill(Color.borderLight).frame(height: 1)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.surfaceCardLight)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.borderLight, lineWidth: 1))
        )
    }

    private func tableHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.textTertiaryLight)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private func statusPill(_ status: String, color: Color) -> some View {
        Text(status)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.10)))
    }

    private func sectionIndicator(_ section: ToolsDiagnosticReportSection) -> some View {
        let rows = metricRows(for: section)
        let scores = rows.compactMap(\.score)
        return HStack(spacing: 3) {
            if scores.isEmpty {
                Capsule()
                    .fill(section.severity.color.opacity(0.28))
                    .frame(height: 8)
            } else {
                ForEach(Array(scores.prefix(12).enumerated()), id: \.offset) { _, score in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(section.severity.color.opacity(0.25 + 0.65 * score))
                        .frame(width: 9, height: max(4, CGFloat(18 * score)))
                        .frame(height: 18, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricTable(_ rows: [ToolsReportMetricRow]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                metricTableHeader(language == .russian ? "Метрика" : "Metric")
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                metricTableHeader(language == .russian ? "Значение" : "Value")
                    .frame(width: 150, alignment: .leading)
                metricTableHeader(language == .russian ? "Здоровье" : "Health")
                    .frame(width: 82, alignment: .leading)
                metricTableHeader(language == .russian ? "График" : "Graph")
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.030))

            ForEach(rows) { row in
                let health = row.health ?? .notice
                HStack(spacing: 8) {
                    Text(row.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 150, alignment: .leading)
                    healthBadge(health)
                        .frame(width: 82, alignment: .leading)
                    metricBar(row.score, color: health.color)
                        .frame(minWidth: 150, maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if row.id != rows.last?.id {
                    Rectangle().fill(Color.borderLight).frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight, lineWidth: 1))
    }

    private func metricTableHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.textTertiaryLight)
            .lineLimit(1)
    }

    private func healthBadge(_ health: ToolsReportSeverity) -> some View {
        Text(healthLabel(health))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(health.color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(health.color.opacity(0.10)))
    }

    private func healthLabel(_ health: ToolsReportSeverity) -> String {
        switch health {
        case .good: return language == .russian ? "Хорошо" : "Good"
        case .notice: return language == .russian ? "Средне" : "Check"
        case .warning: return language == .russian ? "Плохо" : "Bad"
        }
    }

    private func metricBar(_ score: Double?, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.055))
                Capsule()
                    .fill(color.opacity(score == nil ? 0.18 : 0.78))
                    .frame(width: geo.size.width * CGFloat(max(0.05, min(1, score ?? 0.16))))
            }
        }
        .frame(height: 7)
        .frame(maxWidth: .infinity)
    }

    private func metricRows(for section: ToolsDiagnosticReportSection) -> [ToolsReportMetricRow] {
        section.details.map { detail in
            let parts = detail.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let label = parts.count == 2 ? parts[0] : (language == .russian ? "Деталь" : "Detail")
            let value = parts.count == 2 ? parts[1] : detail
            return ToolsReportMetricRow(
                label: label,
                value: value,
                score: metricScore(label: label, value: value),
                health: metricHealth(label: label, value: value)
            )
        }
    }

    private func metricScore(label: String, value: String) -> Double? {
        guard let number = firstNumber(in: value) else { return nil }
        let lower = "\(label) \(value)".lowercased()
        if lower.contains("%") { return max(0, min(1, abs(number) / 100)) }
        if lower.contains("mbps") { return max(0, min(1, number / 100)) }
        if lower.contains("ms") { return max(0, min(1, number / 200)) }
        if lower.contains("px") { return max(0, min(1, number / 2_000)) }
        if lower.contains("click") || lower.contains("клик") { return max(0, min(1, number / 10)) }
        if lower.contains("press") || lower.contains("нажат") { return max(0, min(1, number / 80)) }
        return max(0, min(1, abs(number) / 100))
    }

    private func firstNumber(in text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: #"-?\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(normalized[range])
    }

    private func metricHealth(label: String, value: String) -> ToolsReportSeverity? {
        let combined = "\(label) \(value)".lowercased()
        let valueLower = value.lowercased()
        let number = firstNumber(in: value)

        if value == "-" || valueLower.contains("unknown") || valueLower.contains("неизвест") {
            return .notice
        }
        if valueLower.contains("verified") || valueLower.contains("passed") || valueLower.contains("healthy") || valueLower.contains("center") {
            return .good
        }
        if valueLower.contains("muted") || valueLower.contains("permission denied") || valueLower.contains("warning") || valueLower.contains("critical") {
            return .warning
        }
        if valueLower.contains("not installed") || valueLower.contains("partial") || valueLower.contains("review") {
            return .notice
        }

        if combined.contains("ошиб") || combined.contains("errors") || combined.contains("error") || combined.contains("loss") || combined.contains("потер") {
            guard let number else { return .notice }
            if number == 0 { return .good }
            if number > 5 { return .warning }
            return .notice
        }

        if combined.contains("wear") || combined.contains("used") || combined.contains("износ") {
            guard let number else { return .notice }
            if number >= 80 { return .warning }
            if number >= 50 { return .notice }
            return .good
        }

        if combined.contains("spare") || combined.contains("запас") {
            guard let number else { return .notice }
            if number < 10 { return .warning }
            if number < 25 { return .notice }
            return .good
        }

        if combined.contains("volume") || combined.contains("громк") {
            guard let number else { return .notice }
            if number < 5 { return .warning }
            if number < 20 { return .notice }
            return .good
        }

        if combined.contains("ping") || combined.contains("пинг") || combined.contains("latency") {
            guard let number else { return .notice }
            if number > 200 { return .warning }
            if number > 120 { return .notice }
            return .good
        }

        if combined.contains("jitter") || combined.contains("дрож") {
            guard let number else { return .notice }
            if number > 50 { return .warning }
            if number > 20 { return .notice }
            return .good
        }

        if combined.contains("download") || combined.contains("скачив") {
            guard let number else { return .notice }
            if number < 5 { return .warning }
            if number < 20 { return .notice }
            return .good
        }

        if combined.contains("upload") || combined.contains("отправ") {
            guard let number else { return .notice }
            if number < 1 { return .warning }
            if number < 5 { return .notice }
            return .good
        }

        if combined.contains("click") || combined.contains("клик") || combined.contains("press") || combined.contains("нажат") || combined.contains("движ") || combined.contains("movement") {
            guard let number else { return .notice }
            return number > 0 ? .good : .notice
        }

        return number == nil ? nil : .good
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.copyText, forType: .string)
        didCopy = true
    }
}

@MainActor
private enum ToolsDiagnosticReportBuilder {
    private static let maxResultAge: TimeInterval = 24 * 60 * 60

    static func build(
        language: ToolsReportLanguage,
        keyboardService: KeyboardDiagnosticService,
        pointerSnapshot: PointerInputSnapshot?,
        speakerService: SpeakerTestService,
        storageService: StorageHealthService,
        diskService: DiskIntegrityService,
        advancedSSDService: AdvancedSSDService,
        thermalService: ThermalPowerService,
        networkService: NetworkDiagnosticService,
        now: Date = Date()
    ) -> ToolsDiagnosticReport {
        var sections: [ToolsDiagnosticReportSection] = []
        var staleNames: [String] = []

        addSection(
            makeKeyboardSection(keyboardService, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )
        addSection(
            makePointerSection(pointerSnapshot, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )
        addSection(
            makeSpeakerSection(speakerService, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )
        addSection(
            makeStorageSection(storageService, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )
        addSection(
            makeDiskSection(diskService, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )
        addSection(
            makeAdvancedSSDSection(advancedSSDService, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )
        addSection(
            makeThermalSection(thermalService, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )
        addSection(
            makeNetworkSection(networkService, language: language),
            to: &sections,
            staleNames: &staleNames,
            now: now
        )

        let emptyMessage = sections.isEmpty ? emptyMessage(language: language, hasStaleResults: !staleNames.isEmpty) : nil
        let copyText = makeCopyText(
            sections: sections,
            emptyMessage: emptyMessage,
            generatedAt: fullDate(now, language: .english),
            language: language
        )

        return ToolsDiagnosticReport(
            title: "Tools Final Report",
            generatedAt: "Generated: \(fullDate(now, language: .english))",
            emptyMessage: emptyMessage,
            sections: sections,
            copyButtonTitle: "Copy report",
            closeButtonTitle: "Close",
            copiedTitle: "Copied",
            copyText: copyText
        )
    }

    static func shortDate(_ date: Date, language: ToolsReportLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .russian ? "ru_RU" : "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func fullDate(_ date: Date, language: ToolsReportLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .russian ? "ru_RU" : "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func addSection(
        _ section: ToolsDiagnosticReportSection?,
        to sections: inout [ToolsDiagnosticReportSection],
        staleNames: inout [String],
        now: Date
    ) {
        guard let section else { return }
        if now.timeIntervalSince(section.lastUsedAt) <= maxResultAge {
            sections.append(section)
        } else {
            staleNames.append(section.title)
        }
    }

    private static func makeKeyboardSection(
        _ service: KeyboardDiagnosticService,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let lastUsedAt = service.lastUsedAt else { return nil }
        let testedCount = service.testedCount
        let labels = service.testedKeyCodes
            .sorted()
            .map { service.label(for: $0) }
        let shownLabels = labels.prefix(10).joined(separator: ", ")
        let extraCount = max(0, labels.count - 10)
        let keysDetail = extraCount > 0 ? "\(shownLabels) +\(extraCount)" : shownLabels
        let hasKeys = testedCount > 0

        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "Клавиатура",
                status: hasKeys ? "Клавиши отвечают" : "Нажатия не записаны",
                summary: hasKeys
                    ? "Метод анализа: запись системных событий клавиатуры, включая нажатия, отпускания и повторы при удержании. Последний тест записал \(testedCount) разных клавиш; эти клавиши передали ввод корректно."
                    : "Анализ опирается на запись системных событий клавиатуры: нажатий, отпусканий и повторов при удержании. Последний тест не содержит нажатий, поэтому покрытие пока пустое.",
                details: [
                    "Всего нажатий: \(service.pressCount)",
                    "Повторов при удержании: \(service.repeatCount)",
                    keysDetail.isEmpty ? "Список клавиш пуст" : "Проверенные клавиши: \(keysDetail)"
                ],
                recommendation: hasKeys
                    ? "Норма. Для полноты нажать все важные клавиши."
                    : "Повторить тест: нужны нажатия.",
                lastUsedAt: lastUsedAt,
                severity: hasKeys ? .good : .notice
            )
        }

        return ToolsDiagnosticReportSection(
            title: "Keyboard",
            status: hasKeys ? "Keys respond" : "No key presses recorded",
            summary: hasKeys
                ? "Method: record keyboard events, including presses, releases and held-key repeats. The latest test captured \(testedCount) different keys; those keys sent input correctly."
                : "The analysis records keyboard events: presses, releases and held-key repeats. The latest test has no recorded presses, so coverage is still empty.",
            details: [
                "Total presses: \(service.pressCount)",
                "Held-key repeats: \(service.repeatCount)",
                keysDetail.isEmpty ? "Key list is empty" : "Checked keys: \(keysDetail)"
            ],
            recommendation: hasKeys
                ? "OK. Press every important key for full coverage."
                : "Repeat test: key presses needed.",
            lastUsedAt: lastUsedAt,
            severity: hasKeys ? .good : .notice
        )
    }

    private static func makePointerSection(
        _ snapshot: PointerInputSnapshot?,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let snapshot else { return nil }
        let moved = snapshot.movement > 0
        let clicked = snapshot.clicks > 0
        let scrolled = abs(snapshot.scrollAmount) > 0
        let checkedCount = [moved, clicked, scrolled].filter { $0 }.count
        let severity: ToolsReportSeverity = checkedCount >= 2 ? .good : .notice

        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "Трекпад / мышь",
                status: checkedCount >= 2 ? "Ввод виден" : "Проверено частично",
                summary: checkedCount >= 2
                    ? "Для трекпада и мыши использовалась область ввода, которая считает движение курсора, клики и прокрутку. Последний тест записал несколько типов действий; устройство ввода передает события в систему."
                    : "Для трекпада и мыши использовалась область ввода, которая считает движение курсора, клики и прокрутку. Последний тест записал только часть действий, поэтому результат показывает неполное покрытие.",
                details: [
                    "Движение: \(Int(snapshot.movement)) px",
                    "Клики: \(snapshot.clicks)",
                    "Прокрутка: \(Int(snapshot.scrollAmount))",
                    "Последнее действие: \(snapshot.lastAction)"
                ],
                recommendation: checkedCount >= 2
                    ? "Норма по записанным действиям."
                    : "Повторить: движение + клик + прокрутка.",
                lastUsedAt: snapshot.lastUsedAt,
                severity: severity
            )
        }

        return ToolsDiagnosticReportSection(
            title: "Trackpad / mouse",
            status: checkedCount >= 2 ? "Input detected" : "Partly checked",
            summary: checkedCount >= 2
                ? "The pointer test uses an input pad that counts cursor movement, clicks and scrolling. The latest test recorded several action types; the input device is sending events to the system."
                : "The pointer test uses an input pad that counts cursor movement, clicks and scrolling. The latest test recorded only part of the actions, so coverage is incomplete.",
            details: [
                "Movement: \(Int(snapshot.movement)) px",
                "Clicks: \(snapshot.clicks)",
                "Scroll: \(Int(snapshot.scrollAmount))",
                "Last action: \(snapshot.lastAction)"
            ],
            recommendation: checkedCount >= 2
                ? "OK for recorded actions."
                : "Repeat: movement + click + scroll.",
            lastUsedAt: snapshot.lastUsedAt,
            severity: severity
        )
    }

    private static func makeSpeakerSection(
        _ service: SpeakerTestService,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let lastUsedAt = service.lastUsedAt else { return nil }
        let issue = service.outputInfo.issueLevel
        let severity: ToolsReportSeverity
        switch issue {
        case .good: severity = service.lastCompletedMode == nil ? .notice : .good
        case .notice: severity = .notice
        case .warning: severity = .warning
        }
        let mode = service.lastCompletedMode.map { speakerModeTitle($0, language: language) }
        let route = "\(service.outputInfo.name) (\(service.outputInfo.routeSummary))"

        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "Звук и динамики",
                status: service.healthStatus,
                summary: mode.map { "Метод звукового теста: тестовый сигнал отправляется в выбранный аудиовыход macOS, затем сверяются маршрут, формат, громкость и баланс. Последний тест завершен в режиме «\($0)», маршрут вывода: \(route)." }
                    ?? "Метод звукового теста: тестовый сигнал отправляется в выбранный аудиовыход macOS, затем сверяются маршрут, формат, громкость и баланс. Завершенный звуковой тест в последнем анализе пока не найден.",
                details: [
                    "Формат: \(service.outputInfo.formatSummary)",
                    "Громкость: \(service.outputInfo.volumeSummary)",
                    "Баланс: \(service.outputInfo.balance)",
                    "Подсказка системы: \(service.resultSummary)"
                ],
                recommendation: speakerRecommendation(issue: issue, hasCompletedMode: service.lastCompletedMode != nil, language: language),
                lastUsedAt: lastUsedAt,
                severity: severity
            )
        }

        return ToolsDiagnosticReportSection(
            title: "Sound and speakers",
            status: service.healthStatus,
            summary: mode.map { "The sound test sends a generated signal through the selected macOS audio output, then checks route, format, volume and balance. The latest test completed \($0) with output route \(route)." }
                ?? "The sound test sends a generated signal through the selected macOS audio output, then checks route, format, volume and balance. The latest analysis does not contain a completed sound test yet.",
            details: [
                "Format: \(service.outputInfo.formatSummary)",
                "Volume: \(service.outputInfo.volumeSummary)",
                "Balance: \(service.outputInfo.balance)",
                "System hint: \(service.resultSummary)"
            ],
            recommendation: speakerRecommendation(issue: issue, hasCompletedMode: service.lastCompletedMode != nil, language: language),
            lastUsedAt: lastUsedAt,
            severity: severity
        )
    }

    private static func makeStorageSection(
        _ service: StorageHealthService,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let lastUsedAt = service.lastUsedAt else { return nil }
        guard let snapshot = service.snapshot else {
            return unavailableSection(
                title: language == .russian ? "SSD / накопитель" : "SSD / storage",
                status: language == .russian ? "Не удалось прочитать" : "Could not read",
                summary: language == .russian
                    ? "Базовый анализ SSD берет сведения macOS и доступные SMART-поля: статус, износ, резерв и ошибки. Последний запуск не вернул понятный ответ о диске."
                    : "The basic SSD analysis reads macOS data and available SMART fields: status, wear, spare reserve and errors. The latest run did not return a clear drive answer.",
                recommendation: language == .russian
                    ? "Повторите проверку. Если снова пусто, проверьте диск через Disk Utility."
                    : "Run the check again. If it stays empty, check the disk in Disk Utility.",
                lastUsedAt: lastUsedAt
            )
        }

        let lowSpare = snapshot.availableSpareThreshold.map { threshold in
            (snapshot.availableSpare ?? 100) <= threshold
        } ?? ((snapshot.availableSpare ?? 100) < 25)

        let severity: ToolsReportSeverity
        if snapshot.smartStatus != "Verified" || (snapshot.mediaErrors ?? 0) > 0 || lowSpare || (snapshot.percentageUsed ?? 0) >= 80 {
            severity = .warning
        } else if (snapshot.percentageUsed ?? 0) >= 50 {
            severity = .notice
        } else {
            severity = .good
        }

        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "SSD / накопитель",
                status: snapshot.healthLabel,
                summary: "Базовый анализ SSD берет сведения macOS и доступные SMART-поля: статус, износ, резерв и ошибки носителя. Последний запуск для \(snapshot.deviceName) вернул SMART-статус: \(snapshot.smartStatus).",
                details: [
                    "Износ: \(snapshot.wearLabel)",
                    "Запасные ячейки: \(snapshot.spareLabel)",
                    "Порог запаса: \(snapshot.availableSpareThreshold.map { "\($0)%" } ?? "-")",
                    "Ошибки носителя: \(snapshot.errorLabel)",
                    snapshot.detailLabel
                ],
                recommendation: severity == .good
                    ? "Норма."
                    : "Резервная копия + повторная проверка.",
                lastUsedAt: lastUsedAt,
                severity: severity
            )
        }

        return ToolsDiagnosticReportSection(
            title: "SSD / storage",
            status: snapshot.healthLabel,
            summary: "The basic SSD analysis reads macOS data and available SMART fields: status, wear, spare reserve and media errors. The latest run returned SMART status \(snapshot.smartStatus) for drive \(snapshot.deviceName).",
            details: [
                "Wear: \(snapshot.wearLabel)",
                "Spare cells: \(snapshot.spareLabel)",
                "Spare threshold: \(snapshot.availableSpareThreshold.map { "\($0)%" } ?? "-")",
                "Media errors: \(snapshot.errorLabel)",
                snapshot.detailLabel
            ],
            recommendation: severity == .good
                ? "OK."
                : "Back up + repeat check.",
            lastUsedAt: lastUsedAt,
            severity: severity
        )
    }

    private static func makeDiskSection(
        _ service: DiskIntegrityService,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let lastUsedAt = service.lastUsedAt else { return nil }
        guard let snapshot = service.snapshot else {
            return unavailableSection(
                title: language == .russian ? "APFS файловая система" : "APFS file system",
                status: language == .russian ? "Нет результата" : "No result",
                summary: language == .russian
                    ? "Для APFS используется команда diskutil verifyVolume: она читает карту файлов и структуру основного тома без записи изменений. Последний запуск не сохранил итог проверки."
                    : "For APFS, the report uses diskutil verifyVolume on the boot volume in read-only mode. The latest run did not save a final verification result.",
                recommendation: language == .russian
                    ? "Запустите проверку APFS еще раз."
                    : "Run the APFS check again.",
                lastUsedAt: lastUsedAt
            )
        }

        let isVerified = snapshot.statusLabel == "Verified"
        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "APFS файловая система",
                status: snapshot.statusLabel,
                summary: isVerified
                    ? "Для APFS используется команда diskutil verifyVolume: она сверяет карту файлов и структуру основного тома. Последний запуск вернул Verified; критичных ошибок структуры не найдено."
                    : "Для APFS используется команда diskutil verifyVolume: она сверяет карту файлов и структуру основного тома. Последний запуск вернул статус, требующий внимания.",
                details: [
                    "Код выхода: \(snapshot.exitCode)",
                    "Ответ: \(snapshot.summary)"
                ],
                recommendation: isVerified
                    ? "Норма."
                    : "Повторить; при повторе открыть Disk Utility.",
                lastUsedAt: lastUsedAt,
                severity: isVerified ? .good : .warning
            )
        }

        return ToolsDiagnosticReportSection(
            title: "APFS file system",
            status: snapshot.statusLabel,
            summary: isVerified
                ? "For APFS, diskutil verifyVolume inspects the file map and structure of the boot volume. The latest run returned Verified; no critical structure errors were found."
                : "For APFS, diskutil verifyVolume inspects the file map and structure of the boot volume. The latest run returned a status that needs attention.",
            details: [
                "Exit code: \(snapshot.exitCode)",
                "Reply: \(snapshot.summary)"
            ],
            recommendation: isVerified
                ? "OK."
                : "Repeat; open Disk Utility if it returns.",
            lastUsedAt: lastUsedAt,
            severity: isVerified ? .good : .warning
        )
    }

    private static func makeAdvancedSSDSection(
        _ service: AdvancedSSDService,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let lastUsedAt = service.lastUsedAt else { return nil }
        guard let snapshot = service.snapshot else { return nil }
        let hasErrors = (Int(snapshot.mediaErrors ?? "0") ?? 0) > 0
        let hasWarning = snapshot.criticalWarning.map { $0 != "0x00" } ?? false
        let hasHighWear = (snapshot.usedPercent ?? 0) >= 80
        let hasLowSpare = snapshot.availableSpareThresholdPercent.map { threshold in
            (snapshot.availableSparePercent ?? 100) <= threshold
        } ?? false
        let hasModerateWear = (snapshot.usedPercent ?? 0) >= 50
        let severity: ToolsReportSeverity = !snapshot.isAvailable
            ? .notice
            : (hasErrors || hasWarning || hasHighWear || hasLowSpare ? .warning : (hasModerateWear ? .notice : .good))

        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "Глубокий SMART SSD",
                status: snapshot.statusLabel,
                summary: snapshot.isAvailable
                    ? "Глубокий SMART-анализ запускает smartctl и читает данные прошивки SSD: NVMe warning, износ, резерв и ошибки. Последний запуск получил эти данные."
                    : "Глубокий SMART-анализ запускает smartctl и читает данные прошивки SSD. Последний запуск недоступен, потому что smartmontools не установлен.",
                details: [
                    "Предупреждение: \(snapshot.criticalWarning ?? "-")",
                    "Износ: \(snapshot.percentageUsed ?? "-")",
                    "Запас: \(snapshot.availableSpare ?? "-")",
                    "Порог запаса: \(snapshot.availableSpareThreshold ?? "-")",
                    "Температура: \(snapshot.temperature ?? "-")",
                    "Ошибки: \(snapshot.mediaErrors ?? "-")",
                    snapshot.detail
                ],
                recommendation: severity == .good
                    ? "Норма."
                    : "Резервная копия + повтор SMART.",
                lastUsedAt: lastUsedAt,
                severity: severity
            )
        }

        return ToolsDiagnosticReportSection(
            title: "Deep SSD SMART",
            status: snapshot.statusLabel,
            summary: snapshot.isAvailable
                ? "The deep SMART analysis runs smartctl and reads SSD firmware data: NVMe warning, wear, spare reserve and errors. The latest run collected that data."
                : "The deep SMART analysis runs smartctl and reads SSD firmware data. The latest run is unavailable because smartmontools is not installed.",
            details: [
                "Warning: \(snapshot.criticalWarning ?? "-")",
                "Wear: \(snapshot.percentageUsed ?? "-")",
                "Spare: \(snapshot.availableSpare ?? "-")",
                "Spare threshold: \(snapshot.availableSpareThreshold ?? "-")",
                "Temperature: \(snapshot.temperature ?? "-")",
                "Errors: \(snapshot.mediaErrors ?? "-")",
                snapshot.detail
            ],
            recommendation: severity == .good
                ? "OK."
                : "Back up + repeat SMART.",
            lastUsedAt: lastUsedAt,
            severity: severity
        )
    }

    private static func makeThermalSection(
        _ service: ThermalPowerService,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let lastUsedAt = service.lastUsedAt else { return nil }
        guard let snapshot = service.snapshot else {
            return unavailableSection(
                title: language == .russian ? "Температура и питание" : "Thermal and power",
                status: language == .russian ? "Нет данных" : "No data",
                summary: language == .russian
                    ? "Тепловой снимок снимается через powermetrics: считываются thermal pressure, мощность CPU, GPU и общий пакет. Последний запуск не сохранил данные снимка."
                    : "The thermal and power snapshot uses powermetrics to read thermal pressure, CPU, GPU and package power. The latest run did not save snapshot data.",
                recommendation: language == .russian
                    ? "Запустите снимок еще раз и подтвердите права администратора."
                    : "Run the snapshot again and approve administrator access.",
                lastUsedAt: lastUsedAt
            )
        }

        let hotStatuses = ["Critical", "Heavy", "Serious"]
        let severity: ToolsReportSeverity = snapshot.statusLabel == "Review" || hotStatuses.contains(snapshot.statusLabel) ? .warning : .good

        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "Температура и питание",
                status: snapshot.statusLabel,
                summary: "Тепловой снимок снимается через powermetrics: считываются thermal pressure, мощность CPU, GPU и общий пакет. Последний запуск сохранил короткий замер текущей нагрузки.",
                details: [
                    "Нагрузка по температуре: \(snapshot.thermalPressure ?? "-")",
                    "CPU: \(snapshot.cpuPower ?? "-")",
                    "GPU: \(snapshot.gpuPower ?? "-")",
                    "Весь пакет: \(snapshot.packagePower ?? "-")"
                ],
                recommendation: severity == .good
                    ? "Норма по снимку."
                    : "Охладить Mac + повторить.",
                lastUsedAt: lastUsedAt,
                severity: severity
            )
        }

        return ToolsDiagnosticReportSection(
            title: "Thermal and power",
            status: snapshot.statusLabel,
            summary: "The thermal and power snapshot uses powermetrics to read thermal pressure, CPU, GPU and package power. The latest run saved a short sample of current load.",
            details: [
                "Thermal pressure: \(snapshot.thermalPressure ?? "-")",
                "CPU: \(snapshot.cpuPower ?? "-")",
                "GPU: \(snapshot.gpuPower ?? "-")",
                "Package: \(snapshot.packagePower ?? "-")"
            ],
            recommendation: severity == .good
                ? "OK for this snapshot."
                : "Cool down + repeat.",
            lastUsedAt: lastUsedAt,
            severity: severity
        )
    }

    private static func makeNetworkSection(
        _ service: NetworkDiagnosticService,
        language: ToolsReportLanguage
    ) -> ToolsDiagnosticReportSection? {
        guard let lastUsedAt = service.lastUsedAt else { return nil }
        guard let snapshot = service.snapshot else { return nil }
        let unstable = (snapshot.packetLossPercent ?? 0) > 5 || (snapshot.jitterMS ?? 0) > 50
        let slowLatency = (snapshot.latencyMS ?? 0) > 120
        let severity: ToolsReportSeverity = !snapshot.internetReachable || unstable ? .warning : (slowLatency ? .notice : .good)

        if language == .russian {
            return ToolsDiagnosticReportSection(
                title: "Интернет",
                status: snapshot.statusLabel,
                summary: snapshot.internetReachable
                    ? "Сетевой анализ состоит из Cloudflare trace, IP lookup и нескольких HTTP download/upload/latency замеров. Последний запуск собрал скорость, задержку, jitter и процент неуспешных HTTP-проб."
                    : "Сетевой анализ состоит из Cloudflare trace, IP lookup и нескольких HTTP download/upload/latency замеров. Последний запуск не собрал полный набор измерений.",
                details: [
                    "Скачивание: \(mbpsLabel(snapshot.downloadMbps))",
                    "Отправка: \(mbpsLabel(snapshot.uploadMbps))",
                    "Пинг: \(msLabel(snapshot.latencyMS))",
                    "Дрожание: \(msLabel(snapshot.jitterMS))",
                    "HTTP-пробы без ответа: \(percentLabel(snapshot.packetLossPercent))"
                ],
                recommendation: severity == .good
                    ? "Норма."
                    : "Повтор рядом с роутером / другая сеть.",
                lastUsedAt: lastUsedAt,
                severity: severity
            )
        }

        return ToolsDiagnosticReportSection(
            title: "Internet",
            status: snapshot.statusLabel,
            summary: snapshot.internetReachable
                ? "The network analysis consists of Cloudflare trace, IP lookup and several HTTP download/upload/latency samples. The latest run collected speed, latency, jitter and failed HTTP probe measurements."
                : "The network analysis consists of Cloudflare trace, IP lookup and several HTTP download/upload/latency samples. The latest run did not collect a complete measurement set.",
            details: [
                "Download: \(mbpsLabel(snapshot.downloadMbps))",
                "Upload: \(mbpsLabel(snapshot.uploadMbps))",
                "Ping: \(msLabel(snapshot.latencyMS))",
                "Jitter: \(msLabel(snapshot.jitterMS))",
                "Failed HTTP probes: \(percentLabel(snapshot.packetLossPercent))"
            ],
            recommendation: severity == .good
                ? "OK."
                : "Repeat near router / try another network.",
            lastUsedAt: lastUsedAt,
            severity: severity
        )
    }

    private static func unavailableSection(
        title: String,
        status: String,
        summary: String,
        recommendation: String,
        lastUsedAt: Date
    ) -> ToolsDiagnosticReportSection {
        ToolsDiagnosticReportSection(
            title: title,
            status: status,
            summary: summary,
            details: [],
            recommendation: recommendation,
            lastUsedAt: lastUsedAt,
            severity: .notice
        )
    }

    private static func emptyMessage(language: ToolsReportLanguage, hasStaleResults: Bool) -> String {
        if language == .russian {
            return hasStaleResults
                ? "Свежих данных: 0. Повторите нужные проверки."
                : "Свежих данных: 0. Запустите хотя бы один тест."
        }
        return hasStaleResults
            ? "Fresh data: 0. Repeat the needed checks."
            : "Fresh data: 0. Run at least one test."
    }

    private static func makeCopyText(
        sections: [ToolsDiagnosticReportSection],
        emptyMessage: String?,
        generatedAt: String,
        language: ToolsReportLanguage
    ) -> String {
        let title = "Tools Final Report"
        let generated = "Generated: \(generatedAt)"
        let metric = language == .russian ? "Метрика" : "Metric"
        let value = language == .russian ? "Значение" : "Value"
        let health = language == .russian ? "Здоровье" : "Health"
        let status = language == .russian ? "Вывод" : "Conclusion"
        let fresh = sections.count

        var lines: [String] = [
            title,
            generated,
            "",
            "| \(language == .russian ? "Показатель" : "Item") | \(value) |",
            "|---|---:|",
            "| \(language == .russian ? "Свежие блоки" : "Fresh areas") | \(fresh) |",
            "| \(language == .russian ? "Период" : "Period") | \(language == .russian ? "последние 24 часа" : "last 24 hours") |"
        ]

        if let emptyMessage {
            lines.append("")
            lines.append(emptyMessage)
        }

        for section in sections {
            lines.append("")
            lines.append("### \(section.title)")
            lines.append(section.summary)
            lines.append("")
            lines.append("| \(metric) | \(value) | \(health) |")
            lines.append("|---|---:|---|")
            for detail in section.details {
                let parts = detail.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.count == 2 {
                    lines.append("| \(parts[0]) | \(parts[1]) | \(metricHealthText(label: parts[0], value: parts[1], language: language)) |")
                } else {
                    let label = language == .russian ? "Деталь" : "Detail"
                    lines.append("| \(label) | \(detail) | \(metricHealthText(label: label, value: detail, language: language)) |")
                }
            }
            lines.append("")
            lines.append("**\(status):** \(section.status)")
        }

        return lines.joined(separator: "\n")
    }

    private static func metricHealthText(label: String, value: String, language: ToolsReportLanguage) -> String {
        let severity = metricHealth(label: label, value: value) ?? .notice
        switch severity {
        case .good: return language == .russian ? "Хорошо" : "Good"
        case .notice: return language == .russian ? "Средне" : "Check"
        case .warning: return language == .russian ? "Плохо" : "Bad"
        }
    }

    private static func metricHealth(label: String, value: String) -> ToolsReportSeverity? {
        let combined = "\(label) \(value)".lowercased()
        let valueLower = value.lowercased()
        let number = firstNumber(in: value)

        if value == "-" || valueLower.contains("unknown") || valueLower.contains("неизвест") { return .notice }
        if valueLower.contains("verified") || valueLower.contains("passed") || valueLower.contains("healthy") || valueLower.contains("center") { return .good }
        if valueLower.contains("muted") || valueLower.contains("permission denied") || valueLower.contains("warning") || valueLower.contains("critical") { return .warning }
        if valueLower.contains("not installed") || valueLower.contains("partial") || valueLower.contains("review") { return .notice }

        if combined.contains("ошиб") || combined.contains("errors") || combined.contains("error") || combined.contains("loss") || combined.contains("потер") {
            guard let number else { return .notice }
            if number == 0 { return .good }
            if number > 5 { return .warning }
            return .notice
        }
        if combined.contains("wear") || combined.contains("used") || combined.contains("износ") {
            guard let number else { return .notice }
            if number >= 80 { return .warning }
            if number >= 50 { return .notice }
            return .good
        }
        if combined.contains("spare") || combined.contains("запас") {
            guard let number else { return .notice }
            if number < 10 { return .warning }
            if number < 25 { return .notice }
            return .good
        }
        if combined.contains("volume") || combined.contains("громк") {
            guard let number else { return .notice }
            if number < 5 { return .warning }
            if number < 20 { return .notice }
            return .good
        }
        if combined.contains("ping") || combined.contains("пинг") || combined.contains("latency") {
            guard let number else { return .notice }
            if number > 200 { return .warning }
            if number > 120 { return .notice }
            return .good
        }
        if combined.contains("jitter") || combined.contains("дрож") {
            guard let number else { return .notice }
            if number > 50 { return .warning }
            if number > 20 { return .notice }
            return .good
        }
        if combined.contains("download") || combined.contains("скачив") {
            guard let number else { return .notice }
            if number < 5 { return .warning }
            if number < 20 { return .notice }
            return .good
        }
        if combined.contains("upload") || combined.contains("отправ") {
            guard let number else { return .notice }
            if number < 1 { return .warning }
            if number < 5 { return .notice }
            return .good
        }
        if combined.contains("click") || combined.contains("клик") || combined.contains("press") || combined.contains("нажат") || combined.contains("движ") || combined.contains("movement") {
            guard let number else { return .notice }
            return number > 0 ? .good : .notice
        }

        return number == nil ? nil : .good
    }

    private static func firstNumber(in text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: #"-?\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(normalized[range])
    }

    private static func speakerModeTitle(_ mode: SpeakerTestMode, language: ToolsReportLanguage) -> String {
        guard language == .russian else { return mode.title }
        switch mode {
        case .left: return "левый канал"
        case .stereo: return "стерео"
        case .right: return "правый канал"
        case .sweep: return "частотная проверка"
        case .rattle: return "проверка дребезга"
        case .pinkNoise: return "розовый шум"
        case .impulse: return "короткие щелчки"
        }
    }

    private static func speakerRecommendation(
        issue: SpeakerOutputIssue,
        hasCompletedMode: Bool,
        language: ToolsReportLanguage
    ) -> String {
        if language == .russian {
            switch issue {
            case .good:
                return hasCompletedMode
                    ? "Норма по завершенному тесту."
                    : "Нужен завершенный тест L/R/стерео."
            case .notice:
                return "Проверить громкость/баланс/выход."
            case .warning:
                return "Исправить звук + повторить."
            }
        }

        switch issue {
        case .good:
            return hasCompletedMode
                ? "OK for completed test."
                : "Needs completed L/R/stereo test."
        case .notice:
            return "Check volume/balance/output."
        case .warning:
            return "Fix sound + repeat."
        }
    }

    private static func mbpsLabel(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f Mbps", value)
    }

    private static func msLabel(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.0f ms", value)
    }

    private static func percentLabel(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f%%", value)
    }
}
