// ABOUTME: Window port. AppKit adapter conforms; tests use a recording double.

import Foundation

@MainActor
public protocol WindowControl: AnyObject {
    func setClickThrough(_ enabled: Bool)
    func focus()
}
