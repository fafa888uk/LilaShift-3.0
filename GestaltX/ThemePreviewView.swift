// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ThemePreviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: Palette = .lavender
    @State private var morphed = false

    private enum Palette: String, CaseIterable, Identifiable {
        case lavender = "Lavender"
        case navy = "Navy"
        case jade = "Jade"

        var id: Self { self }

        var color: Color {
            switch self {
            case .lavender: return .gestaltAccent
            case .navy: return .blue
            case .jade: return .teal
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker(L("Preview Palette"), selection: $palette) {
                    ForEach(Palette.allCases) { option in
                        Text(L(option.rawValue)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("These previews appear inside LilaShift. They do not change Wallet cards or the iOS Lock Screen."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                walletPreview
                keypadPreview
            }
            .padding()
        }
        .navigationTitle(L("Theme Preview"))
        .sensoryFeedback(.selection, trigger: palette)
    }

    private var walletPreview: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: palette.color.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Wallet Card Preview")).font(.headline)
                RoundedRectangle(cornerRadius: 22)
                    .fill(palette.color.gradient)
                    .aspectRatio(1.58, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "wallet.bifold")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .padding(20)
                            .accessibilityHidden(true)
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private var keypadPreview: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: palette.color.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Lock Screen Keypad Preview")).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(1...9, id: \.self) { digit in digitPreview(digit) }
                    Color.clear.frame(height: 1)
                    digitPreview(0)
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(morphed ? palette.color.opacity(0.42) : palette.color.opacity(0.12))
                }
                .accessibilityHidden(true)
                .gesture(DragGesture(minimumDistance: 28).onEnded { gesture in
                    if gesture.translation.height < -28 { toggleTransition() }
                })

                Button(morphed ? L("Reset Preview") : L("Preview Swipe Transition")) {
                    toggleTransition()
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
        }
    }

    private func digitPreview(_ digit: Int) -> some View {
        Text(digit.formatted())
            .font(.title2.monospacedDigit())
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(.thinMaterial, in: Capsule())
    }

    private func toggleTransition() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            morphed.toggle()
        }
    }
}
