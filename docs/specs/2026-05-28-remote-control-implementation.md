# Remote Annotation Control - Implementation Plan

## Overview

This document outlines the complete implementation for controlling fiti annotation tools from an iPad over Wi-Fi. The implementation uses a WebSocket-based protocol with JSON messages, supports Apple Pencil pressure (when available in Safari), and provides secure PIN-based pairing.

## Architecture

### Component Structure

```
Sources/Core/Ports/RemoteControl/
  └── RemoteControl.swift          # Core port protocol + types

Sources/AppKit/Adapters/RemoteControl/
  ├── WebSocketServer.swift        # WebSocket server stub (production-ready: use Network.framework)
  ├── WebSocketAdapter.swift       # Maps RemoteAction → RemoteControlPort calls
  └── PairingManager.swift         # PIN generation, token management, device authentication

Sources/AppKit/UI/
  └── RemoteControlStatusView.swift # Toolbar status indicator

dev/remote-client/
  ├── index.html                   # Web client UI
  └── client.js                    # WebSocket client + pointer event capture

Tests/
  ├── CoreTests/RemoteControlTests.swift          # Message parsing tests
  ├── AppKitTests/RemoteControl/WebSocketAdapterTests.swift
  └── AppKitTests/RemoteControl/RemoteControlStatusTests.swift
```

## Protocol Specification

### Message Format

All messages are JSON objects with a `type` field:

**Client → Server:**

```json
{
  "type": "startStroke",
  "strokeId": "uuid",
  "tool": "pen",
  "color": "#FF0000",
  "width": 2.0,
  "point": { "x": 0.12, "y": 0.88, "pressure": 0.75, "t": 1650000000.123 }
}
```

```json
{
  "type": "appendPoints",
  "strokeId": "uuid",
  "points": [
    { "x": 0.13, "y": 0.89, "pressure": 0.72, "t": 1650000000.133 },
    { "x": 0.14, "y": 0.90, "pressure": 0.70, "t": 1650000000.143 }
  ]
}
```

```json
{ "type": "endStroke", "strokeId": "uuid" }
{ "type": "undo" }
{ "type": "redo" }
```

**Pairing Flow:**

```json
// Server sends challenge
{ "type": "pairChallenge", "pin": "1234" }

// Client responds
{ "type": "pairing", "clientId": "iPad Air", "pin": "1234", "remember": true }

// Server confirms
{ "type": "pairResult", "ok": true, "token": "session-token", "controllerName": "iPad Air" }
```

### Coordinate System

- All coordinates are normalized: `x, y ∈ [0.0, 1.0]`
- Origin (0,0) is top-left of the viewport/document
- Pressure is normalized: `pressure ∈ [0.0, 1.0]`
- Timestamp `t` is Unix epoch in milliseconds

## Implementation Details

### 1. Core Port (Sources/Core/Ports/RemoteControl/RemoteControl.swift)

```swift
public protocol RemoteControlPort: AnyObject {
    func remote_startStroke(_ s: RemoteStartStroke)
    func remote_appendPoints(_ a: RemoteAppendPoints)
    func remote_endStroke(strokeId: String)
    func remote_undo()
    func remote_redo()
    func remote_handleAction(_ action: RemoteAction)
}

public enum RemoteAction: Equatable {
    case startStroke(RemoteStartStroke)
    case appendPoints(RemoteAppendPoints)
    case endStroke(strokeId: String)
    case undo
    case redo
    case pairing(clientId: String, pin: String, remember: Bool)
}
```

### 2. WebSocket Server (Sources/AppKit/Adapters/RemoteControl/WebSocketServer.swift)

**Stub implementation** that outlines the architecture. For production:

**Option A (Network.framework):**
```swift
import Network

let parameters = NWParameters(tls: nil)
let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: 9987))
listener.newConnectionHandler = { connection in
    // Handle WebSocket upgrade, then call handleReceivedMessage()
}
listener.start(queue: .global())
```

**Option B (Embedded minimal server):**
Use a lightweight Swift HTTP/WS server like [Vapor](https://vapor.codes) or [Noze.io](http://noze.io) for production.

### 3. Adapter (Sources/AppKit/Adapters/RemoteControl/WebSocketAdapter.swift)

Simple dispatcher that routes `RemoteAction` to `RemoteControlPort` calls:

```swift
public final class WebSocketAdapter {
    public func remote_handleAction(_ action: RemoteAction) {
        switch action {
        case .startStroke(let s):
            port?.remote_startStroke(s)
        case .appendPoints(let a):
            port?.remote_appendPoints(a)
        // ... etc
        }
    }
}
```

### 4. Pairing Manager (Sources/AppKit/Adapters/RemoteControl/PairingManager.swift)

Handles:
- PIN generation (4-digit random)
- Token issuance and validation
- Device "remember" functionality (stores tokens)
- Active session management (single controller)

### 5. Web Client (dev/remote-client/client.js)

Captures pointer events and sends normalized coordinates:

```javascript
canvas.addEventListener('pointerdown', function(e) {
    const point = {
        x: e.clientX / canvas.width,
        y: e.clientY / canvas.height,
        pressure: e.pressure || 1.0,
        t: Date.now()
    };
    ws.send(JSON.stringify({ type: 'startStroke', point, ... }));
});
```

**Pressure Support:**
- Safari on iPadOS supports `PointerEvent.pressure` (0.0-1.0)
- Apple Pencil 2nd gen: pressure data is available
- Fallback: If `pressure` is undefined, default to 1.0

### 6. Status View (Sources/AppKit/UI/RemoteControlStatusView.swift)

Shows in toolbar:
- Green indicator when connected
- Displays controller name (e.g., "iPad Air")
- "Take control" button to revoke session

## Security

1. **PIN-based pairing**: User must enter 4-digit PIN shown in app
2. **Token-based authentication**: Remembered devices bypass PIN
3. **Single active session**: Only one controller at a time
4. **Local network only**: Server bound to localhost/Wi-Fi interface

## TDD Workflow

### Test Files Created

1. **Tests/CoreTests/RemoteControlTests.swift**
   - Tests JSON parsing for all message types
   - Validates coordinate normalization
   - Checks error handling for invalid messages

2. **Tests/AppKitTests/RemoteControl/WebSocketAdapterTests.swift**
   - Tests adapter mapping of RemoteAction → Port calls
   - Uses RecordingRemoteControlPort test double

3. **Tests/AppKitTests/RemoteControl/RemoteControlStatusTests.swift**
   - Tests status view state changes

### Run Tests

```bash
# Generate Xcode project
xcodegen generate

# Run unit tests
xcodebuild -project fiti.xcodeproj -scheme fiti-unit \
  -destination 'platform=macOS' test SYMROOT=/tmp/fiti-build

# Run integration tests
xcodebuild -project fiti.xcodeproj -scheme fiti-integration \
  -destination 'platform=macOS' test SYMROOT=/tmp/fiti-build
```

## Workflow Integration

To connect fiti to the existing editor infrastructure, the `RemoteControlPort` would be implemented by `AppController` or `CanvasView`:

```swift
// In AppController.swift
extension AppController: RemoteControlPort {
    func remote_startStroke(_ s: RemoteStartStroke) {
        // Convert normalized coords to document space
        let point = convertToDocumentPoint(s.point)
        // Start stroke in editor
        editor.startStroke(point: point, tool: s.tool, color: s.color, width: s.width)
    }
    
    func remote_appendPoints(_ a: RemoteAppendPoints) {
        let points = a.points.map(convertToDocumentPoint)
        editor.appendPoints(points)
    }
    
    func remote_endStroke(strokeId: String) {
        editor.endStroke()
    }
    
    func remote_undo() {
        undoManager.undo()
    }
    
    func remote_redo() {
        undoManager.redo()
    }
}
```

## Deployment

### Local Development

1. **Start WebSocket server** (in AppController initialization):
   ```swift
   let pairingManager = PairingManager()
   let adapter = WebSocketAdapter(port: self, pairingManager: pairingManager)
   let server = WebSocketServer(serverPort: 9987, controlPort: self, pairingManager: pairingManager)
   
   Task {
       try? await server.start()
   }
   ```

2. **Access from iPad**:
   - Find Mac IP address: `ipconfig getifaddr en0`
   - Open iPad Safari to: `http://<mac-ip>:9987/remote`
   - Serve static files from `dev/remote-client/` directory

### Production

1. Bundle web client as static assets in app
2. Serve via embedded HTTP server
3. Add Bonjour service for auto-discovery
4. Use TLS for encrypted WebSocket (wss://)

## Timeline

- **Day 1**: Core port + tests (DONE)
- **Day 2**: WebSocket adapter + pairing manager (DONE - stub)
- **Day 3**: Integration with AppController + UI
- **Day 4**: Production WebSocket implementation (Network.framework)
- **Day 5**: End-to-end testing + polish

## Next Steps

1. ✅ Core port definition and tests
2. ✅ WebSocket adapter stub
3. ✅ Pairing manager
4. ✅ Web client prototype
5. ⏳ Integration with AppController (connect RemoteControlPort to actual editor)
6. ⏳ Full WebSocket server implementation (using Network.framework)
7. ⏳ Add "Take control" button to UI
8. ⏳ End-to-end testing on real iPad
9. ⏳ Performance optimization (reduce latency)

## Testing Checklist

- [ ] Message parsing tests pass
- [ ] Adapter mapping tests pass
- [ ] WebSocket server starts on port 9987
- [ ] PIN pairing works correctly
- [ ] "Remember device" stores tokens
- [ ] Start stroke → points → end stroke flow works
- [ ] Pressure values transmitted correctly
- [ ] Undo/redo commands received
- [ ] Single active controller enforced
- [ ] "Take control" revokes session
- [ ] Local drawing disabled when remote active
- [ ] Graceful disconnect/reconnect

## Notes

- Safari PointerEvent.pressure works with Apple Pencil 2nd gen
- For older iPads or inconsistent pressure, fallback to 1.0
- Consider native iPad app if pressure reliability is critical
- Coordinate normalization handles different screen sizes automatically

---

**Files to commit:**
- Sources/Core/Ports/RemoteControl/RemoteControl.swift
- Sources/AppKit/Adapters/RemoteControl/RemoteControl.swift
- Sources/AppKit/Adapters/RemoteControl/PairingManager.swift
- Sources/AppKit/Adapters/RemoteControl/WebSocketServer.swift (stub)
- Sources/AppKit/UI/RemoteControlStatusView.swift
- Tests/CoreTests/RemoteControlTests.swift
- Tests/AppKitTests/RemoteControl/WebSocketAdapterTests.swift
- Tests/AppKitTests/RemoteControl/RemoteControlStatusTests.swift
- dev/remote-client/index.html
- dev/remote-client/client.js
