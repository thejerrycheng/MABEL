# Mabel reference server

Two small Python servers that let you validate the Vision Pro app
end-to-end without needing the real robot:

| Script             | What it does                                                             |
|--------------------|--------------------------------------------------------------------------|
| `server.py`        | WebSocket telemetry server. Accepts `teleop_frame`, sends `robot_state`. |
| `fake_cameras.py`  | Serves three MJPEG streams (main + two wrists) with moving labels.       |

## Setup

```bash
cd mabel-server
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Run

In one terminal:

```bash
python server.py --host 0.0.0.0 --port 9090
```

In another:

```bash
python fake_cameras.py --host 0.0.0.0 --port 8080
```

The fake camera server prints your LAN IP at startup — copy that into
the app's `Config.plist` as `network.host`. Then launch the Vision Pro
app and press **Start Teleop** — you should see:

- Moving dots in all three camera panes
- The connection pill flip to green
- Battery and mode fields populated in the dashboard

## Wiring in your real retargeter

Replace the `_default_frame_handler` in `server.py`:

```python
server = TeleopServer(on_teleop_frame=my_retargeter.handle)
```

`handle(payload)` receives the decoded `TeleopFrame` as a dict. Use the
helpers `unpack_transform` and `joint_world_transform` to pull out the
16-float row-major matrices for each joint or the head. See the
top-level `README.md` for the full wire schema.
