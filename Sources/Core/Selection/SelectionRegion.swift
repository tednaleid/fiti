// ABOUTME: Region of an oriented selection box that a point falls in, plus
// ABOUTME: the pure cursor policy. Drives both hit-routing and hover cursors.

import Foundation

public enum Corner: Equatable, Sendable {
    case topLeft, topRight, bottomRight, bottomLeft
}

public enum SelectionRegion: Equatable, Sendable {
    case rotateHandle
    case corner(Corner)
    case body
    case outside
}
