import SwiftUI

/// Eight draggable band bars plus save/delete for named custom profiles.
struct EqualizerEditor: View {
    let bands: [Int]
    let customProfile: String?
    let isBusy: Bool
    let onCommit: ([Int]) -> Void
    let onSave: (String) -> Void
    let onDelete: (String) -> Void

    @State private var draft: [Int] = []
    @State private var draggingBand: Int?
    @State private var newName = ""

    private static let range = EarbudsModel.eqRange
    private static let step = 10 // 1 dB

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(EarbudsModel.eqBandHz.indices, id: \.self) { index in
                    bandColumn(index)
                }
            }
            HStack(spacing: 8) {
                if let customProfile {
                    Label(customProfile, systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Button("Delete", role: .destructive) { onDelete(customProfile) }
                } else {
                    TextField("Name this EQ", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Flat") { commit(Array(repeating: 0, count: draft.count)) }
            }
            .controlSize(.small)
            .disabled(isBusy)
        }
        .onAppear { draft = bands }
        .onChange(of: bands) { if draggingBand == nil { draft = bands } }
    }

    private func bandColumn(_ index: Int) -> some View {
        let value = draft.indices.contains(index) ? draft[index] : 0
        return VStack(spacing: 4) {
            Text(Self.gainLabel(value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(draggingBand == index ? .primary : .secondary)
            BandBar(value: value, range: Self.range)
                .frame(width: 24, height: 96)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            draggingBand = index
                            draft[index] = Self.value(at: drag.location.y, height: 96)
                        }
                        .onEnded { _ in
                            draggingBand = nil
                            commit(draft)
                        }
                )
                .accessibilityElement()
                .accessibilityLabel("\(Self.frequencyLabel(EarbudsModel.eqBandHz[index])) hertz")
                .accessibilityValue(Self.gainLabel(value) + " decibels")
                .accessibilityAdjustableAction { direction in
                    let delta = direction == .increment ? Self.step : -Self.step
                    var next = draft
                    next[index] = min(max(value + delta, Self.range.lowerBound), Self.range.upperBound)
                    commit(next)
                }
            Text(Self.frequencyLabel(EarbudsModel.eqBandHz[index]))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func commit(_ bands: [Int]) {
        draft = bands
        onCommit(bands)
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onSave(name)
        newName = ""
    }

    private static func value(at y: CGFloat, height: CGFloat) -> Int {
        let fraction = 1 - min(max(y / height, 0), 1)
        let raw = Double(range.lowerBound) + fraction * Double(range.upperBound - range.lowerBound)
        let stepped = Int((raw / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    private static func gainLabel(_ value: Int) -> String {
        let db = Double(value) / 10
        let text = db == db.rounded() ? String(Int(db)) : String(format: "%.1f", db)
        return value > 0 ? "+" + text : text
    }

    private static func frequencyLabel(_ hz: Int) -> String {
        hz < 1000 ? String(hz) : String(format: "%gk", Double(hz) / 1000)
    }
}

/// Track with a fill growing up or down from the 0 dB line.
private struct BandBar: View {
    let value: Int
    let range: ClosedRange<Int>

    var body: some View {
        GeometryReader { geo in
            let span = CGFloat(range.upperBound - range.lowerBound)
            let zeroY = geo.size.height * CGFloat(range.upperBound) / span
            let valueY = geo.size.height * CGFloat(range.upperBound - value) / span
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
                Rectangle()
                    .fill(.tertiary)
                    .frame(height: 1)
                    .offset(y: zeroY)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(height: max(abs(zeroY - valueY), 2))
                    .offset(y: min(zeroY, valueY))
                    .padding(.horizontal, 3)
            }
        }
        .contentShape(Rectangle())
    }
}
