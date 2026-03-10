//
//  EyeTrackingSettingsView.swift
//  MushafImad
//
//  Privacy-first settings for the eye-tracking reading progress feature.
//  All data is processed locally on-device. Camera access requires explicit opt-in.
//

import SwiftUI

public struct EyeTrackingSettingsView: View {
    @StateObject private var eyeTrackingManager = EyeTrackingManager()

    @AppStorage("eye_tracking_enabled") private var isEnabled: Bool = false
    @AppStorage("eye_tracking_show_indicator") private var showIndicator: Bool = false
    @AppStorage("eye_tracking_auto_page") private var autoPage: Bool = false
    @AppStorage("eye_tracking_dwell_seconds") private var dwellSeconds: Double = 3.0
    @AppStorage("eye_tracking_smoothing") private var smoothing: Double = 0.15
    @AppStorage("eye_tracking_consent_given") private var consentGiven: Bool = false

    @State private var showConsentAlert = false
    @State private var showPrivacyInfo = false

    public init() {}

    public var body: some View {
        Form {
            // MARK: - Privacy Notice
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy First")
                            .font(.headline)
                        Text("Eye tracking uses the front camera locally on your device. No images or gaze data are stored or transmitted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    showPrivacyInfo = true
                } label: {
                    Label("Learn More About Privacy", systemImage: "lock.shield")
                }
            }

            // MARK: - Enable Toggle
            Section(header: Text("Eye Tracking")) {
                if !eyeTrackingManager.isSupported {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Eye tracking requires a device with TrueDepth camera (iPhone X or later).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Toggle("Enable Eye Tracking", isOn: Binding(
                        get: { isEnabled },
                        set: { newValue in
                            if newValue && !consentGiven {
                                showConsentAlert = true
                            } else {
                                isEnabled = newValue
                            }
                        }
                    ))

                    if isEnabled {
                        // Status indicator
                        HStack {
                            Circle()
                                .fill(eyeTrackingManager.isTracking ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(eyeTrackingManager.isTracking
                                 ? String(localized: "Tracking Active")
                                 : String(localized: "Not Tracking"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: - Reading Progress
            if isEnabled && eyeTrackingManager.isSupported {
                Section(header: Text("Reading Progress")) {
                    Toggle("Show Gaze Indicator", isOn: $showIndicator)

                    Text("Displays a subtle dot showing where your gaze is estimated on the page. Useful for calibration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("Auto Page Advance")) {
                    Toggle("Auto-Advance Pages", isOn: $autoPage)

                    if autoPage {
                        VStack(alignment: .leading) {
                            Text("Dwell Time: \(String(format: "%.1f", dwellSeconds))s")
                                .font(.subheadline)
                            Slider(value: $dwellSeconds, in: 1.5...8.0, step: 0.5) {
                                Text("Dwell Time")
                            } minimumValueLabel: {
                                Text("1.5s")
                                    .font(.caption2)
                            } maximumValueLabel: {
                                Text("8s")
                                    .font(.caption2)
                            }
                        }

                        Text("When your gaze dwells at the bottom of the page for this duration, the next page loads automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Accuracy")) {
                    VStack(alignment: .leading) {
                        Text("Smoothing: \(Int(smoothing * 100))%")
                            .font(.subheadline)
                        Slider(value: $smoothing, in: 0.05...0.5, step: 0.05) {
                            Text("Smoothing")
                        } minimumValueLabel: {
                            Text("Smooth")
                                .font(.caption2)
                        } maximumValueLabel: {
                            Text("Responsive")
                                .font(.caption2)
                        }
                    }

                    Text("Higher smoothing reduces jitter but adds slight delay. Lower smoothing is more responsive but may be jumpy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Fallback Mode
            Section(header: Text("Fallback Mode")) {
                Text("On devices without TrueDepth camera, reading progress is estimated using scroll position and time spent on each page.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Eye Tracking")
        .alert("Camera Access Required", isPresented: $showConsentAlert) {
            Button("Enable") {
                consentGiven = true
                isEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Eye tracking uses your device's front camera to estimate where you're reading. All processing happens locally on your device. No images or data leave your device.")
        }
        .sheet(isPresented: $showPrivacyInfo) {
            NavigationStack {
                privacyInfoView
                    .navigationTitle("Privacy Information")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPrivacyInfo = false }
                        }
                    }
            }
        }
    }

    // MARK: - Privacy Info Sheet

    @ViewBuilder
    private var privacyInfoView: some View {
        List {
            Section("How It Works") {
                privacyRow(icon: "camera", title: "Front Camera",
                           detail: "Uses the TrueDepth camera to track facial landmarks and eye direction in real-time.")

                privacyRow(icon: "cpu", title: "On-Device Processing",
                           detail: "All face and gaze analysis runs entirely on your device using Apple's ARKit framework.")

                privacyRow(icon: "eye", title: "Gaze Estimation",
                           detail: "Eye direction is mapped to screen coordinates to estimate which verse you're reading.")
            }

            Section("What We Don't Do") {
                privacyRow(icon: "icloud.slash", title: "No Cloud Upload",
                           detail: "Camera frames and gaze data never leave your device.")

                privacyRow(icon: "externaldrive.badge.xmark", title: "No Storage",
                           detail: "No photos, videos, or facial data are saved. Only your reading page progress is stored.")

                privacyRow(icon: "person.crop.circle.badge.xmark", title: "No Identification",
                           detail: "We don't perform face recognition or store any biometric data.")
            }

            Section("Your Control") {
                privacyRow(icon: "power", title: "Opt-In Only",
                           detail: "Eye tracking is disabled by default and requires your explicit permission to start.")

                privacyRow(icon: "xmark.circle", title: "Instant Stop",
                           detail: "Toggle off at any time to immediately stop camera access and gaze tracking.")
            }
        }
    }

    @ViewBuilder
    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        EyeTrackingSettingsView()
    }
}
