import SwiftUI

/// AirPods-style "connected" card that drops in under the menu bar, then dismisses itself.
@MainActor
final class ConnectedPopup {
    private static let size = CGSize(width: 348, height: 112)
    private static let visibleDuration: Duration = .seconds(5)

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(model: EarbudsModel) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ConnectedCard(model: model) { [weak self] in self?.hide() })

        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.maxX - Self.size.width - 12, y: frame.maxY - Self.size.height - 10)
        panel.setFrame(CGRect(origin: CGPoint(x: origin.x, y: origin.y + 12), size: Self.size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

struct ConnectedCard: View {
    let model: EarbudsModel
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var confirmed = false

    var body: some View {
        HStack(spacing: 12) {
            EarbudsArt(appeared: appeared, animates: !reduceMotion)
                .frame(width: 84, height: 84)
                .background(
                    // Soft wash in the earbuds' own colour so the render sits in light, not on a void.
                    Circle()
                        .fill(RadialGradient(
                            colors: [EarbudsArt.tint.opacity(appeared ? 0.45 : 0), .clear],
                            center: .center, startRadius: 4, endRadius: 38
                        ))
                        .scaleEffect(appeared ? 1.1 : 0.6)
                )
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("R50i NC").font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: confirmed)
                        Text("Connected").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                if let mode = MenuView.modes.first(where: { $0.value == model.ambientSoundMode }) {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : -8)
            .animation(reduceMotion ? nil : .snappy, value: model.ambientSoundMode)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                BatteryRing(label: "L", battery: model.batteryLeft, delay: 0.35)
                BatteryRing(label: "R", battery: model.batteryRight, delay: 0.5)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardBackground()
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.15)) { appeared = true }
            // Bounce the checkmark once the buds have landed.
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                confirmed = true
            }
        }
    }
}

/// Official left/right renders (Resources/DeviceLeft.png, DeviceRight.png) that fly in from the
/// sides, settle as a pair, then bob gently out of phase. Falls back to an SF Symbol without them.
struct EarbudsArt: View {
    /// Sampled from the army green render.
    static let tint = Color(red: 0.42, green: 0.50, blue: 0.42)

    let appeared: Bool
    let animates: Bool
    /// Height of each bud in points; the pair's spacing scales with it.
    var budHeight: CGFloat = 64

    @Environment(\.displayScale) private var displayScale
    @State private var floating = false

    private var unit: CGFloat { budHeight / 64 }

    var body: some View {
        if let left = ProductImage.named("DeviceLeft", height: budHeight, scale: displayScale),
           let right = ProductImage.named("DeviceRight", height: budHeight, scale: displayScale) {
            ZStack {
                bud(left, side: -1)
                bud(right, side: 1)
            }
            .onAppear {
                guard animates else { return }
                floating = true
            }
        } else {
            Image(systemName: "earbuds.case.fill")
                .resizable()
                .scaledToFit()
                .padding(12)
                .foregroundStyle(.secondary)
                .opacity(appeared ? 1 : 0)
        }
    }

    /// `side` is -1 for the left bud, 1 for the right.
    private func bud(_ image: NSImage, side: CGFloat) -> some View {
        // Drawn at its natural size (already resampled for this display), so only the tilt resamples it.
        Image(nsImage: image)
            .interpolation(.high)
            .antialiased(true)
            .rotationEffect(.degrees(side * (appeared ? 8 : 30)))
            .scaleEffect(appeared ? 1 : 0.6)
            .offset(x: side * (appeared ? 16 : 46) * unit, y: (appeared ? side * 5 : 12) * unit)
            .opacity(appeared ? 1 : 0)
            .animation(
                animates ? .spring(response: 0.6, dampingFraction: 0.68).delay(side > 0 ? 0.24 : 0.15) : nil,
                value: appeared
            )
            .offset(y: (floating ? side : -side) * 2.5 * unit)
            .animation(
                animates ? .easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.9) : nil,
                value: floating
            )
    }
}

/// Product renders downsampled once to their on-screen pixel size. Letting the GPU shrink the 480 px
/// source on every frame (then rotate it) skipped source pixels and left the edges jagged.
@MainActor
enum ProductImage {
    private static var cache: [String: NSImage] = [:]

    static func named(_ name: String, height: CGFloat, scale: CGFloat) -> NSImage? {
        let key = "\(name)@\(height)x\(scale)"
        if let cached = cache[key] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        // ImageIO thumbnails area-average the source, unlike a plain bilinear shrink.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int((height * scale * max(sourceWidth, sourceHeight) / sourceHeight).rounded()),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(
            cgImage: thumbnail,
            size: NSSize(width: CGFloat(thumbnail.width) / scale, height: CGFloat(thumbnail.height) / scale)
        )
        cache[key] = image
        return image
    }
}

/// Fills to the battery level once it arrives (the CLI read lands a few seconds after connecting).
private struct BatteryRing: View {
    let label: String
    let battery: EarbudsModel.Battery?
    /// Staggers the left and right fills.
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownLevel = 0.0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: shownLevel)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
            Text(battery.map { "\(Int($0.level * 100))%" } ?? " ")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: sync)
        .onChange(of: battery?.level) { sync() }
        .accessibilityLabel(label == "L" ? "Left" : "Right")
        .accessibilityValue(battery.map { "\(Int($0.level * 100)) percent" } ?? "Unknown")
    }

    private var ringColor: Color {
        guard let battery else { return .secondary }
        return battery.level <= 0.2 ? .red : .green
    }

    private func sync() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85).delay(delay)) {
            shownLevel = battery?.level ?? 0
        }
    }
}

private extension View {
    @ViewBuilder
    func cardBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
