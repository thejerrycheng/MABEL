# Mabel Teleop — Vision Pro App

A visionOS app that teleoperates the **Mabel** robot: the headset streams the
operator's head and hand poses to the robot at 60 Hz, and renders the robot's
main and wrist cameras plus status telemetry back to the operator.

---

## Features

- **Hand tracking** — full 27-joint skeleton per hand (via `HandTrackingProvider`).
- **Head tracking** — device-pose sampling (via `WorldTrackingProvider`).
- **Three camera feeds** — main + left/right wrist, via MJPEG over HTTP.
- **Bidirectional telemetry** — one WebSocket carries outbound pose frames and
  inbound robot state (battery, mode, diagnostics, latency).
- **Immersive debug space** — visualize the exact joint data being transmitted,
  so retargeting bugs can be localized to the correct side of the wire.
- **Auto-reconnect** on both the telemetry socket and each video stream.

---

## Project structure

```
MabelTeleop/
├── App/                        # @main + window/space IDs
├── Configuration/              # endpoints, rates, tuning
├── Models/                     # Codable domain types (cross wire boundary)
├── Networking/
│   ├── Protocol/               # wire envelope + codec
│   ├── TelemetryClient.swift   # protocol (for DI / mocks)
│   ├── WebSocketTelemetryClient.swift
│   └── MJPEGVideoStream.swift
├── Tracking/                   # ARKit wrappers (isolated)
├── Services/                   # orchestrators: session + stream manager
├── ViewModels/                 # MVVM glue
├── Views/
│   ├── Components/             # reusable (CameraView, StatusPill)
│   └── Immersive/              # RealityKit debug scene
├── Utilities/                  # formatters, helpers
└── Resources/                  # Info.plist
MabelTeleopTests/               # XCTest suite
```

### Layer rules

1. `Models/` has zero framework dependencies (besides `Foundation` and `simd`).
2. Only `Tracking/` imports `ARKit`. The rest of the app consumes plain
   `Codable` structs.
3. Only `Networking/` talks to `URLSession`. Higher layers see
   `TelemetryClient` (protocol) and `VideoStream` (protocol).
4. Views never touch services directly — only `TeleopSession` and view models.

These rules make the whole app unit-testable on the simulator / CI without
ARKit hardware.

---

## Wire protocol

All messages share one envelope:

```json
{
  "type": "teleop_frame" | "robot_state" | "ping" | "pong" | "hello" | "error",
  "payload": { ... }
}
```

### `teleop_frame` (headset → robot, ~60 Hz)

```json
{
  "sequence": 12345,
  "timestamp": 98765.432,
  "head": {
    "transform": { "matrix": [16 floats, row-major] },
    "trackingState": "normal" | "limited" | "notAvailable"
  },
  "leftHand":  { "chirality": "left",  "anchorTransform": {...}, "joints": [...], "isTracked": true },
  "rightHand": { "chirality": "right", "anchorTransform": {...}, "joints": [...], "isTracked": true }
}
```

Each joint:

```json
{
  "joint": "thumb_tip",
  "localTransform": { "matrix": [16 floats] },
  "isTracked": true
}
```

Joint names follow the string values in `HandJoint`
(e.g. `wrist`, `thumb_knuckle`, `index_tip`, `forearm_arm`). Full list:
`HandJoint.allCases` — 27 joints.

All transforms are 4×4 **row-major** rigid transforms in ARKit's
right-handed world coordinate system (+Y up, −Z forward).

### `robot_state` (robot → headset, ad-lib)

```json
{
  "timestamp": 98765.500,
  "mode": "idle" | "teleop" | "autonomous" | "estopped" | "recovering",
  "battery": { "percentage": 0.87, "voltage": 24.9, "charging": false },
  "jointPositions": { "arm_l_shoulder": 0.1, ... },
  "diagnostics": [
    { "level": "warning", "component": "arm_r", "message": "High current" }
  ],
  "latencyMs": 28.4
}
```

### Minimal Python receiver

```python
import asyncio, json, websockets

async def handler(ws):
    async for msg in ws:
        env = json.loads(msg)
        if env["type"] == "teleop_frame":
            frame = env["payload"]
            head_m = frame["head"]["transform"]["matrix"]    # 16 floats, row-major
            if frame.get("leftHand"):
                for j in frame["leftHand"]["joints"]:
                    name, m = j["joint"], j["localTransform"]["matrix"]
                    # forward to your retargeter here
        elif env["type"] == "ping":
            await ws.send(json.dumps({"type": "pong", "payload": {}}))

asyncio.run(websockets.serve(handler, "0.0.0.0", 9090, subprotocols=None).wait_closed())
```

> **Full reference server:** See [`mabel-server/`](mabel-server/) for a complete
> async WebSocket server plus a fake MJPEG camera server for end-to-end
> smoke testing without the real robot.

---

## Camera streams

Each camera is an independent MJPEG endpoint:

| Camera       | Default URL                                      |
|--------------|--------------------------------------------------|
| Main         | `http://mabel.local:8080/camera/main/stream.mjpg`       |
| Left wrist   | `http://mabel.local:8080/camera/wrist_left/stream.mjpg` |
| Right wrist  | `http://mabel.local:8080/camera/wrist_right/stream.mjpg`|

Any `multipart/x-mixed-replace` server works — `web_video_server` (ROS),
`mjpg-streamer`, or a custom FastAPI endpoint. Switch to WebRTC later by
adding a new `VideoStream` conformer in `Networking/` and swapping it in
`VideoStreamManager`.

---

## Configuration

Edit `Configuration/AppConfiguration.swift` (or load a `Config.plist` at
launch) to change the host, ports, or transmission rate:

```swift
AppConfiguration(
    network: .init(
        host: "mabel.local",
        telemetryPort: 9090,
        telemetryPath: "/teleop",
        videoPort: 8080,
        mainCameraPath: "/camera/main/stream.mjpg",
        leftWristCameraPath: "/camera/wrist_left/stream.mjpg",
        rightWristCameraPath: "/camera/wrist_right/stream.mjpg"
    ),
    tracking: .init(
        transmissionRateHz: 60,
        sendFullSkeleton: true,
        minTrackingConfidence: 0.5
    ),
    video: .init(wristThumbnailWidth: 480, reconnectDelay: 1.5)
)
```

---

## Setup

1. Open Xcode 15.2+ (or 16). **File → New → Project → visionOS → App.** Name it
   `MabelTeleop`, pick SwiftUI, and save it somewhere outside this folder.
2. Delete the stub `ContentView.swift` and `<Name>App.swift` Xcode generated.
3. Drag the `MabelTeleop/` source folder from this package into the Xcode
   project navigator. Check **Create groups** and add everything to the app target.
4. Drag `MabelTeleopTests/` into your test target (create one if needed).
5. **Required Info.plist keys.** Xcode 15+ generates the Info.plist from build
   settings — don't add a physical `Info.plist` file. Instead:

   **Target → Build Settings**, confirm `GENERATE_INFOPLIST_FILE = Yes`, then
   add these `INFOPLIST_KEY_*` rows (they show up under "Info.plist Values"):

   | Key | Value |
   |---|---|
   | `INFOPLIST_KEY_NSHandsTrackingUsageDescription` | `Mabel Teleop tracks your hand poses so the robot can mirror your movements for remote operation.` |
   | `INFOPLIST_KEY_NSWorldSensingUsageDescription` | `Mabel Teleop reads your head pose to aim the robot's main camera and align retargeting.` |
   | `INFOPLIST_KEY_NSLocalNetworkUsageDescription` | `Mabel Teleop connects to the robot's telemetry and camera servers on your local network.` |

   For the keys Xcode doesn't expose as first-class build settings, use the
   target's **Info** tab and add them as Custom Target Properties:

   - `NSBonjourServices` → Array → `_mabel-teleop._tcp`, `_http._tcp`
   - `NSAppTransportSecurity` → Dictionary →
     - `NSAllowsLocalNetworking` → YES
     - `NSExceptionDomains` → Dictionary → `mabel.local` → Dictionary →
       - `NSExceptionAllowsInsecureHTTPLoads` → YES
       - `NSIncludesSubdomains` → YES

6. Add `MabelTeleop/Resources/Config.plist` to the app target (check the
   target-membership box in the File Inspector so it ships in the bundle).
7. Target deployment: **visionOS 1.2+**. Sign with your team.
8. Build & run on a Vision Pro. The simulator handles networking and UI but
   can't provide real hand/head tracking.

---

## Testing

```bash
xcodebuild test \
  -project MabelTeleop.xcodeproj \
  -scheme MabelTeleop \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

Included test targets:

- `WireCodecTests` — JSON round-trips for `TeleopFrame` and `RobotState`.
- `MJPEGFrameBufferTests` — SOI/EOI parsing, fragmented delivery, junk bytes.
- `MockTelemetryClient` — drop-in for session-level tests.

---

## Extending

| You want to…                         | Touch this file                                                        |
|--------------------------------------|------------------------------------------------------------------------|
| Swap JSON for MessagePack / Protobuf | `Networking/Protocol/WireEnvelope.swift`                               |
| Add a 4th camera                     | `Models/CameraID.swift` + `Configuration/AppConfiguration.swift`       |
| Switch MJPEG → WebRTC                | Add a new `VideoStream` conformer, wire in `VideoStreamManager`        |
| Use gRPC instead of WebSocket        | Add a new `TelemetryClient` conformer, inject it in `TeleopSession`    |
| Add a new tracked signal (e.g. eye)  | New `*TrackingService` in `Tracking/`, extend `TeleopFrame`            |
| Change retargeting frequency         | `AppConfiguration.Tracking.transmissionRateHz`                         |

---

## Coordinate frames — notes for the Mabel side

- Hand joint transforms are relative to their **hand anchor**, not world.
  Reconstruct world pose as `anchorTransform * localTransform`.
- ARKit uses **+Y up, −Z forward** (right-handed).
  ROS REP-103 uses **+Z up, +X forward**. If your retargeter consumes ROS
  frames, apply a one-shot frame change on ingest (don't fight it per-joint).
- `timestamp` is the headset's `CACurrentMediaTime()` (monotonic, seconds).
  It is *not* wall-clock. For alignment with robot timestamps, sync on the
  receive side — each side should keep its own clock.
