import Foundation

public enum RemoteTool: String, Codable {
    case pen
    case highlighter
    case eraser
}

public struct RemoteStrokePoint: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var pressure: Double?
    public var t: Double?

    public init(x: Double, y: Double, pressure: Double? = nil, t: Double? = nil) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.t = t
    }
}

public struct RemoteStartStroke: Codable, Equatable {
    public var strokeId: String
    public var tool: RemoteTool
    public var color: String?
    public var width: Double?
    public var point: RemoteStrokePoint
}

public struct RemoteAppendPoints: Codable, Equatable {
    public var strokeId: String
    public var points: [RemoteStrokePoint]
}

public enum RemoteAction: Equatable {
    case startStroke(RemoteStartStroke)
    case appendPoints(RemoteAppendPoints)
    case endStroke(strokeId: String)
    case undo
    case redo
    case pairing(clientId: String, pin: String, remember: Bool)

    // Codable helpers when needed in the future may be added.
}

public enum RemoteParseError: Error, Equatable {
    case invalidJSON
    case missingType
    case unknownType(String)
    case invalidPayload(String)
}

/// Parse a single JSON message (Data) into a RemoteAction.
/// The transport layer is responsible for calling this when a text message arrives.
public func parseRemoteAction(from data: Data) throws -> RemoteAction {
    let any = try JSONSerialization.jsonObject(with: data, options: [])
    guard let dict = any as? [String: Any] else {
        throw RemoteParseError.invalidJSON
    }
    guard let typeAny = dict["type"] else { throw RemoteParseError.missingType }
    guard let type = typeAny as? String else { throw RemoteParseError.missingType }

    switch type {
    case "startStroke":
        do {
            let json = try JSONSerialization.data(withJSONObject: dict, options: [])
            let s = try JSONDecoder().decode(RemoteStartStroke.self, from: json)
            return .startStroke(s)
        } catch {
            throw RemoteParseError.invalidPayload("startStroke: \(error)")
        }
    case "appendPoints":
        do {
            let json = try JSONSerialization.data(withJSONObject: dict, options: [])
            let s = try JSONDecoder().decode(RemoteAppendPoints.self, from: json)
            return .appendPoints(s)
        } catch {
            throw RemoteParseError.invalidPayload("appendPoints: \(error)")
        }
    case "endStroke":
        if let sid = dict["strokeId"] as? String {
            return .endStroke(strokeId: sid)
        } else {
            throw RemoteParseError.invalidPayload("endStroke missing strokeId")
        }
    case "undo":
        return .undo
    case "redo":
        return .redo
    default:
        throw RemoteParseError.unknownType(type)
    }
}

// MARK: - Port protocol

public protocol RemoteControlPort: AnyObject {
    /// Called when a remote stroke starts. The coordinates are normalized (0..1).
    func remote_startStroke(_ s: RemoteStartStroke)
    /// Called to append points to an in-progress stroke.
    func remote_appendPoints(_ a: RemoteAppendPoints)
    /// Called when a remote stroke ends.
    func remote_endStroke(strokeId: String)
    /// Undo / redo commands
    func remote_undo()
    func remote_redo()
    /// Convenience method to dispatch a parsed RemoteAction.
    func remote_handleAction(_ action: RemoteAction)
}

// A small test double useful in tests (kept public for tests in other modules)
public final class RecordingRemoteControlPort: RemoteControlPort {
    public private(set) var started: [RemoteStartStroke] = []
    public private(set) var appended: [RemoteAppendPoints] = []
    public private(set) var ended: [String] = []
    public private(set) var undoCount = 0
    public private(set) var redoCount = 0

    public init() {}

    public func remote_startStroke(_ s: RemoteStartStroke) {
        started.append(s)
    }
    public func remote_appendPoints(_ a: RemoteAppendPoints) {
        appended.append(a)
    }
    public func remote_endStroke(strokeId: String) {
        ended.append(strokeId)
    }
    public func remote_undo() { undoCount += 1 }
    public func remote_redo() { redoCount += 1 }
    public func remote_handleAction(_ action: RemoteAction) {
        switch action {
        case .startStroke(let s):
            remote_startStroke(s)
        case .appendPoints(let a):
            remote_appendPoints(a)
        case .endStroke(let id):
            remote_endStroke(strokeId: id)
        case .undo:
            remote_undo()
        case .redo:
            remote_redo()
        case .pairing:
            break // Pairing is handled by PairingManager, not forwarded to port
        }
    }
}
