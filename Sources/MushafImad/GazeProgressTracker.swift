//
//  GazeProgressTracker.swift
//  MushafImad
//
//  Tracks reading progress by mapping gaze position to page regions,
//  measuring dwell time, and optionally auto-advancing pages.
//
//  Uses a fallback heuristic (scroll position + dwell time) when
//  ARKit face tracking is unavailable.
//

import SwiftUI
import Combine

/// Represents which region of the page the user's gaze is focused on.
public enum PageRegion: String, Sendable {
    case top        // Upper third of the page
    case middle     // Middle third
    case bottom     // Lower third
    case offScreen  // Not looking at the page
}

/// Tracks which verse/page the user is reading based on gaze data.
@MainActor
public final class GazeProgressTracker: ObservableObject {

    // MARK: - Published State

    /// The region of the page where the user is currently looking
    @Published public private(set) var currentRegion: PageRegion = .offScreen

    /// How long the user has been looking at the bottom region (seconds)
    @Published public private(set) var bottomDwellTime: TimeInterval = 0

    /// Whether the auto-page threshold has been reached
    @Published public private(set) var shouldAdvancePage = false

    /// Estimated line number (0–14) the user is reading on the current page
    @Published public private(set) var estimatedLine: Int = 0

    /// Progress through current page (0.0 to 1.0)
    @Published public private(set) var pageProgress: CGFloat = 0

    /// The last page number that was auto-saved as read
    @Published public private(set) var lastSavedPage: Int?

    // MARK: - Configuration

    /// Minimum confidence level required to register a gaze reading
    public var minimumConfidence: CGFloat = 0.25

    /// Seconds of bottom-region dwell before triggering auto-page
    public var autoPageDwellThreshold: TimeInterval = 3.0

    /// Whether to use the fallback scroll-position heuristic
    @Published public var useFallbackMode = false

    // MARK: - Private

    private var bottomDwellStart: Date?
    private var lastGazeRegion: PageRegion = .offScreen
    private var progressSaveTimer: Timer?
    private var currentPageNumber: Int = 1

    /// Called when auto-advance should happen
    public var onAutoAdvance: (() -> Void)?

    /// Called when a page is considered fully read
    public var onPageRead: ((Int) -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Gaze Processing

    /// Process an incoming gaze point and update reading progress.
    public func processGaze(_ gaze: GazePoint, pageNumber: Int) {
        currentPageNumber = pageNumber

        guard gaze.confidence >= minimumConfidence else {
            updateRegion(.offScreen)
            return
        }

        // Map Y coordinate to page region
        let region: PageRegion
        if gaze.y < 0.33 {
            region = .top
        } else if gaze.y < 0.67 {
            region = .middle
        } else {
            region = .bottom
        }

        updateRegion(region)

        // Estimate which line (0–14) the user is reading
        // Quran pages have 15 lines
        estimatedLine = min(14, max(0, Int(gaze.y * 15)))

        // Update page progress based on gaze position
        pageProgress = max(pageProgress, gaze.y)

        // Track bottom dwell for auto-page
        trackBottomDwell(region: region)
    }

    /// Fallback: estimate reading progress from scroll position and time spent.
    public func processScrollFallback(
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        pageNumber: Int
    ) {
        guard useFallbackMode else { return }
        currentPageNumber = pageNumber

        let scrollProgress = contentHeight > viewportHeight
            ? scrollOffset / (contentHeight - viewportHeight)
            : 0

        let normalizedProgress = max(0, min(1, scrollProgress))

        let region: PageRegion
        if normalizedProgress < 0.33 {
            region = .top
        } else if normalizedProgress < 0.67 {
            region = .middle
        } else {
            region = .bottom
        }

        updateRegion(region)
        estimatedLine = min(14, max(0, Int(normalizedProgress * 15)))
        pageProgress = max(pageProgress, normalizedProgress)
        trackBottomDwell(region: region)
    }

    // MARK: - Region & Dwell Tracking

    private func updateRegion(_ newRegion: PageRegion) {
        if currentRegion != newRegion {
            currentRegion = newRegion
            lastGazeRegion = newRegion
        }
    }

    private func trackBottomDwell(region: PageRegion) {
        if region == .bottom {
            if bottomDwellStart == nil {
                bottomDwellStart = Date()
            }

            let elapsed = Date().timeIntervalSince(bottomDwellStart ?? Date())
            bottomDwellTime = elapsed

            if elapsed >= autoPageDwellThreshold && !shouldAdvancePage {
                shouldAdvancePage = true
                onAutoAdvance?()

                // Mark page as read
                markPageAsRead(currentPageNumber)
            }
        } else {
            bottomDwellStart = nil
            bottomDwellTime = 0
            shouldAdvancePage = false
        }
    }

    // MARK: - Progress Saving

    /// Mark a page as read and notify listeners.
    public func markPageAsRead(_ pageNumber: Int) {
        lastSavedPage = pageNumber
        onPageRead?(pageNumber)
    }

    /// Reset progress tracking for a new page.
    public func resetForNewPage() {
        pageProgress = 0
        estimatedLine = 0
        bottomDwellTime = 0
        bottomDwellStart = nil
        shouldAdvancePage = false
        currentRegion = .offScreen
    }

    /// Call when the page changes to save previous page progress and reset.
    public func handlePageChange(from oldPage: Int, to newPage: Int) {
        // If user progressed past 80% of the old page, mark it as read
        if pageProgress > 0.8 {
            markPageAsRead(oldPage)
        }
        resetForNewPage()
    }
}
