import SwiftUI

@main
struct SoundcoreBarApp: App {
    @State private var model = EarbudsModel(
        cli: OpenSCQ30(binary: Bundle.main.url(forAuxiliaryExecutable: "openscq30")!)
    )
    @AppStorage(MenuBarIcon.storageKey) private var icon = MenuBarIcon.currentMode

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(
                icon.symbol(for: model.ambientSoundMode),
                dimmed: model.isConnected == false
            ))
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuBarIcon: String, CaseIterable {
    static let storageKey = "menuBarIcon"

    case currentMode, earbuds, earbudsCase, headphones, waveform

    var title: String {
        switch self {
        case .currentMode: "Current Mode"
        case .earbuds: "Earbuds"
        case .earbudsCase: "Earbuds Case"
        case .headphones: "Headphones"
        case .waveform: "Waveform"
        }
    }

    /// Template image, so the menu bar still tints it; dimming lowers its alpha like a disabled item.
    static func image(_ symbol: String, dimmed: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.35 : 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = dimmed ? "Earbuds disconnected" : "Earbuds"
        return image
    }

    func symbol(for ambientSoundMode: String?) -> String {
        switch self {
        case .currentMode:
            switch ambientSoundMode {
            case "Transparency": "ear.and.waveform"
            case "Normal": "ear"
            default: "earbuds"
            }
        case .earbuds: "earbuds"
        case .earbudsCase: "earbuds.case.fill"
        case .headphones: "headphones"
        case .waveform: "waveform"
        }
    }
}
