// ABOUTME: Active tool in the selection / drawing surface. Lives parallel to
// ABOUTME: AppController.Mode — orthogonal: any active mode can host any tool.

import Foundation

public enum Tool: Equatable, Hashable, Sendable {
    case pen
    case selection
}
