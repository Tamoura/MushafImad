//
//  EyeTrackingOverlayView.swift
//  MushafImad
//
//  A subtle overlay that shows the estimated gaze position and
//  reading progress indicators when eye tracking is active.
//

import SwiftUI

/// Overlay view showing the user's estimated gaze position on the page.
public struct EyeTrackingOverlayView: View {
    @ObservedObject var eyeTrackingManager: EyeTrackingManager
    @ObservedObject var gazeTracker: GazeProgressTracker

    @AppStorage("eye_tracking_show_indicator") private var showIndicator: Bool = false
    @AppStorage("eye_tracking_auto_page") private var autoPage: Bool = false

    public init(eyeTrackingManager: EyeTrackingManager, gazeTracker: GazeProgressTracker) {
        self.eyeTrackingManager = eyeTrackingManager
        self.gazeTracker = gazeTracker
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Gaze indicator dot
                if showIndicator && eyeTrackingManager.isTracking && eyeTrackingManager.isLookingAtScreen {
                    gazeIndicator(in: geometry.size)
                }

                // Auto-page progress indicator at bottom
                if autoPage && gazeTracker.currentRegion == .bottom && gazeTracker.bottomDwellTime > 0 {
                    autoPageIndicator(in: geometry.size)
                }

                // Reading progress bar on the side
                if eyeTrackingManager.isTracking {
                    readingProgressBar(in: geometry.size)
                }

                // Status badge (top-right corner)
                if eyeTrackingManager.isEnabled {
                    statusBadge
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Gaze Indicator

    @ViewBuilder
    private func gazeIndicator(in size: CGSize) -> some View {
        let x = eyeTrackingManager.currentGaze.x * size.width
        let y = eyeTrackingManager.currentGaze.y * size.height
        let confidence = eyeTrackingManager.currentGaze.confidence

        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(0.4 * confidence),
                        Color.accentColor.opacity(0.1 * confidence),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 24
                )
            )
            .frame(width: 48, height: 48)
            .position(x: x, y: y)
            .animation(.easeOut(duration: 0.1), value: eyeTrackingManager.currentGaze.x)
            .animation(.easeOut(duration: 0.1), value: eyeTrackingManager.currentGaze.y)
    }

    // MARK: - Auto Page Indicator

    @ViewBuilder
    private func autoPageIndicator(in size: CGSize) -> some View {
        let progress = min(1.0, gazeTracker.bottomDwellTime / gazeTracker.autoPageDwellThreshold)

        VStack(spacing: 4) {
            Spacer()

            // Progress arc
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.accentColor)
            }
            .frame(width: 32, height: 32)

            Text(String(localized: "Auto-page"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 60)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Reading Progress Bar

    @ViewBuilder
    private func readingProgressBar(in size: CGSize) -> some View {
        VStack {
            Spacer()

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 3, height: size.height * 0.6)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 3, height: size.height * 0.6 * gazeTracker.pageProgress)
                        .animation(.easeInOut(duration: 0.3), value: gazeTracker.pageProgress)
                }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        VStack {
            HStack {
                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.top, 8)
            .padding(.trailing, 8)

            Spacer()
        }
    }

    private var statusColor: Color {
        if !eyeTrackingManager.isTracking {
            return .red
        } else if !eyeTrackingManager.isFaceDetected {
            return .orange
        } else if eyeTrackingManager.isLookingAtScreen {
            return .green
        } else {
            return .yellow
        }
    }
}
