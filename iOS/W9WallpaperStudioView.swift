// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct W9WallpaperStudioView: View {
    @State private var inputLayer = W9WallpaperStudio.Layer.background
    @State private var isChoosing = false
    @State private var request: FileRequest?
    @State private var background: LayerImage?
    @State private var foreground: LayerImage?
    @State private var shift = 0.0
    @State private var preview: CGImage?
    @State private var isRendering = false
    @State private var isExporting = false
    @State private var document: PNGDocument?
    @State private var status: String?

    private struct LayerImage: Identifiable {
        let id = UUID()
        let value: CGImage
    }

    private struct FileRequest: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let layer: W9WallpaperStudio.Layer
    }

    private struct PreviewKey: Equatable {
        let background: UUID?
        let foreground: UUID?
        let shift: Double
    }

    private struct PNGDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.png] }
        let bytes: Data

        init(_ bytes: Data) { self.bytes = bytes }

        init(configuration: ReadConfiguration) throws {
            guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            self.bytes = bytes
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: bytes)
        }
    }

    static var title: String { String(localized: "Parallax Wallpaper Studio", table: "W9Studio") }

    var body: some View {
        List {
            Section {
                Button { choose(.background) } label: { Label(label("Choose Background"), systemImage: "photo") }
                Button { choose(.foreground) } label: { Label(label("Choose PNG Foreground"), systemImage: "square.stack") }
                    .disabled(background == nil)
                if foreground != nil {
                    Button(label("Remove Foreground")) {
                        foreground = nil
                        shift = 0
                    }
                }
            } footer: {
                Text("Use a JPG, PNG, or HEIC background and an optional PNG with transparency. Images stay on this device.", tableName: "W9Studio")
            }
            .disabled(isRendering || request != nil)

            if let preview {
                Section {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    if foreground != nil {
                        Slider(value: $shift, in: -1...1, step: 0.02) {
                            Text("Horizontal Framing", tableName: "W9Studio")
                        }
                        if shift != 0 {
                            Button(label("Center Layers")) { shift = 0 }
                        }
                    }
                }
            }

            Section {
                if request != nil || isRendering { ProgressView() }
                Button { exportPNG() } label: {
                    Label(label("Save PNG to Files"), systemImage: "square.and.arrow.up")
                }
                .disabled(background == nil || request != nil || isRendering)
                if let status { Text(status).foregroundStyle(.secondary) }
            } footer: {
                Text("Exports a static 1080 × 1920 PNG. It does not set your wallpaper or create a Live Photo.", tableName: "W9Studio")
            }
        }
        .navigationTitle(Self.title)
        .fileImporter(
            isPresented: $isChoosing,
            allowedContentTypes: inputLayer == .foreground ? [.png] : [.jpeg, .png, .heic]
        ) { result in
            switch result {
            case .success(let url):
                request = .init(url: url, layer: inputLayer)
                status = nil
            case .failure:
                status = label("Could not open this image.")
            }
        }
        .task(id: request?.id) {
            guard let selected = request else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try W9WallpaperStudio.loadImage(at: selected.url, for: selected.layer) }
            }.value
            guard !Task.isCancelled, request?.id == selected.id else { return }
            request = nil
            switch result {
            case .success(let image):
                if selected.layer == .background { background = .init(value: image) }
                else { foreground = .init(value: image) }
            case .failure(let error):
                status = message(error as? W9WallpaperStudio.Failure)
            }
        }
        .task(id: PreviewKey(background: background?.id, foreground: foreground?.id, shift: shift)) {
            guard let background else { return }
            preview = try? W9WallpaperStudio.render(
                background: background.value, foreground: foreground?.value, shift: shift, exporting: false
            )
        }
        .fileExporter(
            isPresented: $isExporting, document: document, contentType: .png, defaultFilename: "LilaShift-Wallpaper"
        ) { result in
            document = nil
            switch result {
            case .success: status = label("PNG saved.")
            case .failure: status = label("Could not save PNG.")
            }
        }
    }

    private func choose(_ layer: W9WallpaperStudio.Layer) {
        inputLayer = layer
        isChoosing = true
    }

    private func exportPNG() {
        guard let background = background?.value else { return }
        let overlay = foreground?.value
        let framing = shift
        isRendering = true
        status = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try W9WallpaperStudio.png(background: background, foreground: overlay, shift: framing) }
            }.value
            isRendering = false
            switch result {
            case .success(let data):
                document = PNGDocument(data)
                isExporting = true
            case .failure:
                status = label("Could not render PNG.")
            }
        }
    }

    private func label(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "W9Studio")
    }

    private func message(_ issue: W9WallpaperStudio.Failure?) -> String {
        switch issue {
        case .tooLarge: label("This image exceeds 20 MiB.")
        case .unsupportedImage: label("The image format, dimensions, or foreground alpha channel are not supported.")
        case .renderFailed: label("Could not render PNG.")
        case .unreadable, nil: label("Could not open this image.")
        }
    }
}
