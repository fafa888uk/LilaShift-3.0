import SwiftUI

@main struct LilaReadOnlyApp: App {
    var body: some Scene {
        WindowGroup { NavigationStack { ReadOnlyToolsView() } }
    }
}

extension Color {
    static let gestaltAccent = Color(red: 0.52, green: 0.33, blue: 0.83)
}

enum GlassTokens { static let cardRadius: CGFloat = 22 }

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding().glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding().glassEffect(.regular.interactive()).opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct CustomizationFailure: LocalizedError {
    let key: String
    init(_ key: String) { self.key = key }
    var errorDescription: String? { L(key) }
}

enum CustomizationFiles {
    static func relative(_ path: String) throws -> String {
        let parts = path.components(separatedBy: "/")
        guard !path.contains("\\"), !path.utf8.contains(0),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CustomizationFailure("The archive contains unsafe paths or links.")
        }
        return path
    }
}
