import SwiftUI
import UIKit

/// Спокойная тёплая палитра: кремовый фон, шалфейный акцент, мягкие тексты.
/// Каждый цвет сразу задан и для светлой, и для тёмной темы.
enum Theme {
    static let background = Color(light: 0xF6F1EA, dark: 0x1C1A18)
    static let card = Color(light: 0xFFFCF8, dark: 0x282522)
    static let ink = Color(light: 0x2E2A26, dark: 0xF2ECE4)
    static let muted = Color(light: 0x8A8178, dark: 0xA39A90)
    static let accent = Color(light: 0x6F8F7A, dark: 0x8FB09A)
    static let recording = Color(light: 0xC98B6B, dark: 0xD9A084)

    static let corner: CGFloat = 22
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Мягкая карточка — основной строительный блок интерфейса.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Крупная кнопка с заливкой акцентным цветом.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
