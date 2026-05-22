// ABOUTME: Shared geometric constants for the selection tool. The rotate-node
// ABOUTME: offset must agree between hit-testing (Core) and chrome drawing (AppKit).

import Foundation

/// Tuning shared by region classification (Core) and chrome rendering (AppKit).
/// Hit radii are grab tolerances, distinct from the handles' visual sizes —
/// the adapter owns how big a handle is drawn, Core owns how close you must be
/// to grab it. The rotate-node offset lives here because the node must be drawn
/// where it is hit-tested.
public enum SelectionMetrics {
    /// Distance the rotate node sits above the box's top edge.
    public static let rotateNodeOffset: Double = 20
    /// Grab radius for corner handles.
    public static let handleHitRadius: Double = 8
    /// Grab radius for the rotate node — a touch larger than corners so the
    /// detached node is easy to catch.
    public static let rotateNodeHitRadius: Double = 10
}
