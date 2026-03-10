//
//  GazeProgressTrackerTests.swift
//  MushafImadTests
//
//  Tests for GazeProgressTracker reading progress tracking logic.
//

import XCTest
@testable import MushafImad

@MainActor
final class GazeProgressTrackerTests: XCTestCase {

    private var tracker: GazeProgressTracker!

    override func setUp() {
        super.setUp()
        tracker = GazeProgressTracker()
    }

    override func tearDown() {
        tracker = nil
        super.tearDown()
    }

    // MARK: - Region Detection

    func testGazeInTopRegion() {
        let gaze = GazePoint(x: 0.5, y: 0.1, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)
        XCTAssertEqual(tracker.currentRegion, .top)
    }

    func testGazeInMiddleRegion() {
        let gaze = GazePoint(x: 0.5, y: 0.5, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)
        XCTAssertEqual(tracker.currentRegion, .middle)
    }

    func testGazeInBottomRegion() {
        let gaze = GazePoint(x: 0.5, y: 0.8, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)
        XCTAssertEqual(tracker.currentRegion, .bottom)
    }

    func testLowConfidenceGazeIgnored() {
        let gaze = GazePoint(x: 0.5, y: 0.5, confidence: 0.1, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)
        XCTAssertEqual(tracker.currentRegion, .offScreen)
    }

    // MARK: - Line Estimation

    func testEstimatedLineForTopGaze() {
        let gaze = GazePoint(x: 0.5, y: 0.0, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)
        XCTAssertEqual(tracker.estimatedLine, 0)
    }

    func testEstimatedLineForBottomGaze() {
        let gaze = GazePoint(x: 0.5, y: 0.99, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)
        XCTAssertEqual(tracker.estimatedLine, 14)
    }

    func testEstimatedLineForMiddleGaze() {
        let gaze = GazePoint(x: 0.5, y: 0.5, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)
        XCTAssertEqual(tracker.estimatedLine, 7)
    }

    // MARK: - Page Progress

    func testPageProgressIncreases() {
        let gaze1 = GazePoint(x: 0.5, y: 0.3, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze1, pageNumber: 1)
        XCTAssertEqual(tracker.pageProgress, 0.3, accuracy: 0.01)

        let gaze2 = GazePoint(x: 0.5, y: 0.7, confidence: 0.8, timestamp: 1)
        tracker.processGaze(gaze2, pageNumber: 1)
        XCTAssertEqual(tracker.pageProgress, 0.7, accuracy: 0.01)
    }

    func testPageProgressDoesNotDecrease() {
        let gaze1 = GazePoint(x: 0.5, y: 0.8, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze1, pageNumber: 1)

        let gaze2 = GazePoint(x: 0.5, y: 0.2, confidence: 0.8, timestamp: 1)
        tracker.processGaze(gaze2, pageNumber: 1)

        // Progress should stay at 0.8, not drop to 0.2
        XCTAssertEqual(tracker.pageProgress, 0.8, accuracy: 0.01)
    }

    // MARK: - Page Change

    func testResetForNewPage() {
        let gaze = GazePoint(x: 0.5, y: 0.9, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 1)

        tracker.resetForNewPage()

        XCTAssertEqual(tracker.pageProgress, 0)
        XCTAssertEqual(tracker.estimatedLine, 0)
        XCTAssertEqual(tracker.bottomDwellTime, 0)
        XCTAssertFalse(tracker.shouldAdvancePage)
        XCTAssertEqual(tracker.currentRegion, .offScreen)
    }

    func testHandlePageChangeMarksReadWhenProgressHigh() {
        var readPages: [Int] = []
        tracker.onPageRead = { page in readPages.append(page) }

        // Simulate reading most of page 5
        let gaze = GazePoint(x: 0.5, y: 0.85, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 5)

        tracker.handlePageChange(from: 5, to: 6)

        XCTAssertEqual(readPages, [5])
    }

    func testHandlePageChangeDoesNotMarkReadWhenProgressLow() {
        var readPages: [Int] = []
        tracker.onPageRead = { page in readPages.append(page) }

        // Only read top portion
        let gaze = GazePoint(x: 0.5, y: 0.3, confidence: 0.8, timestamp: 0)
        tracker.processGaze(gaze, pageNumber: 5)

        tracker.handlePageChange(from: 5, to: 6)

        XCTAssertTrue(readPages.isEmpty)
    }

    // MARK: - Fallback Mode

    func testScrollFallbackIgnoredWhenDisabled() {
        tracker.useFallbackMode = false
        tracker.processScrollFallback(scrollOffset: 500, viewportHeight: 800, contentHeight: 2000, pageNumber: 1)
        XCTAssertEqual(tracker.currentRegion, .offScreen)
    }

    func testScrollFallbackWorksWhenEnabled() {
        tracker.useFallbackMode = true
        tracker.processScrollFallback(scrollOffset: 500, viewportHeight: 800, contentHeight: 2000, pageNumber: 1)
        XCTAssertNotEqual(tracker.currentRegion, .offScreen)
    }
}
