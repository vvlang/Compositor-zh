import AppKit
import SwiftUI
import Testing
@testable import Compositor

/// The tab strip sits in the title bar. Empty space beside the tabs has to stay a window drag, on macOS 26
/// where a view that claims more room than it draws into keeps the mouse-down across its whole frame.
@MainActor
@Suite(.serialized)
struct TitleBarDragTests {
    @Test func emptySpaceBesideOneTabIsOutsideTheDragArea() async throws {
        let workspace = ProjectWorkspace()
        let (window, hosting) = try await host(workspace, width: 800)
        defer { window.orderOut(nil) }
        let dragArea = try #require(find(TitleBarDragView.self, in: hosting))
        let frame = dragArea.convert(dragArea.bounds, to: hosting)
        #expect(frame.width > 500, "one tab still leaves only \(frame.width) of drag area in \(hosting.bounds)")
        try sendClick(at: NSPoint(x: frame.midX, y: frame.midY), in: hosting, window: window)
        #expect(window.dragCount == 1)

        window.dragCount = 0
        try sendClick(at: NSPoint(x: 12, y: hosting.bounds.midY), in: hosting, window: window)
        #expect(window.dragCount == 0, "a tab click dragged the window")
    }

    @Test func overflowingTabsStillLeaveTheRestOfTheTitleBarDraggable() async throws {
        let workspace = ProjectWorkspace()
        for _ in 0..<12 { workspace.newCanvas() }
        let (window, hosting) = try await host(workspace, width: 280)
        defer { window.orderOut(nil) }
        // Far too many tabs to fit 280pt: they collapse behind the overflow pill instead of scrolling, and
        // still only claim the width they draw into — there's no NSScrollView left to swallow the rest.
        #expect(find(NSScrollView.self, in: hosting) == nil)
        let dragArea = try #require(find(TitleBarDragView.self, in: hosting))
        let frame = dragArea.convert(dragArea.bounds, to: hosting)
        // The point of the test is that the tabs left *some* of the bar alone — a fixed number of
        // points would be a language bug: 「未命名 2」 is a different width from "Untitled 2", so
        // whatever threshold the label widths happen to clear would differ per language. Assert
        // against the bar instead: a strip that is actually there, and still sizeable, is the claim.
        let remaining = hosting.bounds.width - dragArea.frame.maxX
        #expect(frame.width > 0, "the tabs swallowed the bar completely: drag area is \(frame)")
        #expect(remaining >= 0, "the drag area ran past the end of the bar: \(frame) in \(hosting.bounds)")
        try sendClick(at: NSPoint(x: frame.midX, y: frame.midY), in: hosting, window: window)
        #expect(window.dragCount == 1)
    }

    private func host(_ workspace: ProjectWorkspace, width: CGFloat) async throws -> (DragRecordingWindow, NSView) {
        let hosting = NSHostingView(rootView: ProjectTabStrip(workspace: workspace)
            .frame(width: width, height: 34, alignment: .leading))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: 34)
        let window = DragRecordingWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        return (window, hosting)
    }

    private func sendClick(at point: NSPoint, in view: NSView, window: NSWindow) throws {
        let location = view.convert(point, to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        window.sendEvent(down)
    }

    private final class DragRecordingWindow: NSWindow {
        var dragCount = 0
        override func performDrag(with event: NSEvent) { dragCount += 1 }
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }
}
