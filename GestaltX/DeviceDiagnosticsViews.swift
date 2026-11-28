// SPDX-License-Identifier: GPL-3.0-only
// Device Diagnostics views (W1, LilaShift 5.0.0) — read-only
// SwiftUI display for the five DeviceKit diagnostics in
// `DeviceDiagnostics.swift`: screen physical metrics, biometric
// hardware, Low Power Mode, screen brightness and available disk
// capacity.
//
// The card never writes anything. A value that could not be read
// is shown as "Unavailable" with its reason, never as a guessed
// value. The card is standalone: it is not wired into ContentView
// or FeatureCatalog here — the W1 coordinator wires it in (see
// `W1DeviceDiagnosticsRegistration`).
import SwiftUI

struct DeviceDiagnosticsCard: View {
    @State private var reader = DeviceDiagnosticsReader()
    @State private var report: DeviceDiagnosticsReport?

    private var byteFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }

    private func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes else { return L("Unknown") }
        return byteFormatter.string(fromByteCount: bytes)
    }

    private func formatScale(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: GlassTokens.heroTint) {
            VStack(alignment: .leading, spacing: GlassTokens.cardSpacing) {
                HStack(spacing: GlassTokens.rowSpacing) {
                    GlassIconPedestal(systemImage: "iphone", tint: .gestaltAccent, size: GlassTokens.iconSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Device Diagnostics"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Screen, biometrics, Low Power Mode, brightness and disk space — read-only, from public iOS APIs."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let report {
                    screenSection(report.screenMetrics)
                    Divider()
                    biometricsSection(report.biometrics)
                    Divider()
                    lowPowerSection(isEnabled: report.isLowPowerModeEnabled)
                    Divider()
                    brightnessSection(report.brightness)
                    Divider()
                    diskSection(report.diskCapacity)
                    Text(L("Measured") + ": " + report.measuredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("Unknown"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(L("Refresh")) {
                    refresh()
                }
                .font(.subheadline)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        report = reader.read()
    }

    // MARK: - Rows

    private func row(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func unavailableRow(label: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label + ":")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(L("Unavailable"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Screen

    private func screenSection(_ metrics: DeviceScreenMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Screen"))
                .font(.headline)
                .foregroundStyle(.primary)
            if let modelName = metrics.modelName {
                row(label: L("Model"), value: modelName)
            } else if let reason = metrics.unmappedIdentifierReason {
                unavailableRow(label: L("Model"), reason: reason)
            }
            if let diagonal = metrics.diagonalInches {
                row(label: L("Screen size"), value: String(format: "%.1f", diagonal) + "″")
            } else {
                unavailableRow(label: L("Screen size"), reason: L("PPI and screen size come from the model table, which does not cover this model."))
            }
            if let ppi = metrics.pixelsPerInch {
                row(label: "PPI", value: "\(ppi)")
            } else {
                unavailableRow(label: "PPI", reason: L("PPI and screen size come from the model table, which does not cover this model."))
            }
            if let ratio = metrics.aspectRatioText {
                row(label: L("Aspect ratio"), value: ratio)
            }
            row(label: L("Resolution"), value: "\(metrics.pixelWidth) × \(metrics.pixelHeight)")
            row(label: L("Points"), value: "\(Int(metrics.pointsWidth)) × \(Int(metrics.pointsHeight))")
            row(label: L("Scale"), value: formatScale(metrics.scale) + " / " + formatScale(metrics.nativeScale))
            row(label: L("Display Zoom"), value: metrics.isZoomed ? L("Zoomed") : L("Standard"))
            Text(L("Display Zoom is derived from the native scale exceeding the scale; verify it by toggling Display Zoom on the device."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Biometrics

    private func biometricsSection(_ status: BiometricStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Biometrics"))
                .font(.headline)
                .foregroundStyle(.primary)
            row(label: L("Sensor"), value: status.kind.title)
            row(label: L("Available"), value: status.canEvaluate ? L("Available") : L("Unavailable"))
            if let detail = status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Low Power Mode

    private func lowPowerSection(isEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Low Power Mode"))
                .font(.headline)
                .foregroundStyle(.primary)
            row(label: L("Low Power Mode"), value: isEnabled ? L("On") : L("Off"))
        }
    }

    // MARK: - Brightness

    private func brightnessSection(_ brightness: ScreenBrightness) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Screen Brightness"))
                .font(.headline)
                .foregroundStyle(.primary)
            row(label: L("Brightness"), value: "\(brightness.percent)%")
        }
    }

    // MARK: - Disk

    private func diskSection(_ capacity: DiskCapacity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Disk Space"))
                .font(.headline)
                .foregroundStyle(.primary)
            if let reason = capacity.unavailableReason {
                unavailableRow(label: L("Available disk space"), reason: reason)
            } else {
                row(label: L("Available (opportunistic)"), value: formatBytes(capacity.opportunisticBytes))
                row(label: L("Available (important)"), value: formatBytes(capacity.importantBytes))
                row(label: L("Total capacity"), value: formatBytes(capacity.totalBytes))
            }
        }
    }
}
