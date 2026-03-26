# DualCast – Dual-Camera Twitch/RTMP Streaming App for iOS

## Project Overview

Build a native iOS app (Swift/SwiftUI, minimum deployment target iOS 17.0) that streams both front and rear iPhone cameras simultaneously to Twitch (or any RTMP endpoint) with a composited picture-in-picture layout, a live Mapbox route map overlay, and Twitch chat integration. The app targets iPhone 15 Pro Max but should work on any iPhone that supports `AVCaptureMultiCamSession` (iPhone XS and later).

This is a road-trip / overland driving livestream app. Think dashcam meets IRL streaming. The primary use case is mounting the phone on a vehicle windshield and streaming a long drive (hours at a time) with the rear camera showing the road and the front camera showing the driver, or vice versa — user's choice.

## Core Technical Stack

- **Language:** Swift 6+ with strict concurrency
- **UI Framework:** SwiftUI (with UIKit bridging only where necessary for camera preview layers)
- **Camera & Streaming:** [HaishinKit.swift](https://github.com/HaishinKit/HaishinKit.swift) — this is the critical dependency. It supports RTMP/SRT streaming, `AVCaptureMultiCamSession` for dual cameras, PiP compositing, and hardware H.264/HEVC encoding. Use SPM to integrate it.
- **Maps:** Mapbox Maps SDK for iOS (via SPM). Use `mapbox-maps-ios` package.
- **Persistence:** SwiftData or UserDefaults for settings. CoreLocation for GPS tracking. Store route data (array of CLLocationCoordinate2D + timestamps) locally for the trip.

## Architecture

Use MVVM with observable classes. Key components:

```
DualCast/
├── App/
│   ├── DualCastApp.swift          # App entry point
│   └── AppState.swift             # Global observable state
├── Streaming/
│   ├── StreamManager.swift        # HaishinKit RTMP connection + dual camera setup
│   ├── CameraCompositor.swift     # Manages PiP layout compositing (which cam is main, PiP corner)
│   └── AudioManager.swift         # Mic audio capture, mute toggle
├── Map/
│   ├── MapOverlayView.swift       # Mapbox map as SwiftUI overlay
│   ├── RouteTracker.swift         # CoreLocation tracking, stores route polyline
│   └── MapConfiguration.swift     # Style URL, zoom level, visibility settings
├── Chat/
│   ├── TwitchChatView.swift       # IRC-based Twitch chat overlay
│   └── TwitchIRC.swift            # Lightweight Twitch IRC client (wss://irc-ws.chat.twitch.tv)
├── Views/
│   ├── StreamView.swift           # Main streaming view with camera preview + overlays
│   ├── SettingsView.swift         # Configuration page
│   ├── ControlBar.swift           # Bottom control bar (mute, swap, PiP corner, map toggle, etc.)
│   └── PanicModeOverlay.swift     # "Paused" overlay for security checkpoint mode
├── Models/
│   └── StreamConfig.swift         # Persisted settings model
└── Utilities/
    └── Extensions.swift
```

## Feature Specifications

### 1. Dual Camera Streaming

Use HaishinKit's multi-camera support to capture from both front and rear cameras simultaneously. The video that goes out over RTMP should be a single composited frame.

**Layout:**
- One camera is "main" (fills the full frame)
- The other camera is "PiP" (smaller inset window)
- Default: rear camera = main, front camera = PiP
- User can **swap** which is main vs PiP with a single tap on the PiP window or a button
- PiP corner is selectable: top-left, top-right, bottom-left, bottom-right
- PiP size: approximately 25% of frame width, with a small border/rounded corners
- The composited output is what gets encoded and sent to RTMP — viewers see the PiP layout

**HaishinKit multi-camera setup reference:**
```swift
// Attach front camera as secondary (PiP)
let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
stream.attachMultiCamera(front)

// Attach back camera as primary (main)
let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
stream.attachCamera(back)
```

HaishinKit supports PiP and split layouts natively. Explore its video mixing / multi-camera capabilities to composite the two feeds into a single output stream.

**Stream settings:**
- Resolution: 1280x720 (720p) default, with option for 1920x1080 in settings
- Frame rate: 30fps
- Video codec: H.264 (hardware accelerated via VideoToolbox)
- Audio codec: AAC
- Bitrate: 2500 kbps default for 720p, 4500 for 1080p (configurable in settings)

### 2. RTMP Streaming to Twitch

- User enters their Twitch stream key in settings
- RTMP URL default: `rtmp://live.twitch.tv/app/` (editable for other RTMP services)
- Big "GO LIVE" button to start streaming
- Show connection status indicator (connecting, live, disconnected, error)
- Show current bitrate and dropped frames count as small overlay text
- Auto-reconnect on connection drop (with exponential backoff, max 5 attempts)

### 3. Mapbox Route Map (PiP Overlay)

A small Mapbox map displayed as an overlay on the stream preview (and optionally composited into the outgoing stream).

**Map behavior:**
- Shows current location as a pulsing dot
- Draws the route as a polyline as the user drives
- Default zoom: ~15 (street-level, zoomed in)
- Map style: configurable in settings. Default to `mapbox://styles/mapbox/dark-v11` (dark theme works best as overlay)
- Map PiP is positionable in any of the 4 corners (independent of camera PiP corner)
- Map size: approximately 20% of frame width, rounded corners, slight opacity (85%)
- Toggle map overlay visibility on/off
- Toggle route tracking on/off (when on, stores GPS breadcrumbs locally even if map overlay is hidden)

**Route tracking:**
- Use CoreLocation with `CLLocationManager`, `desiredAccuracy: kCLLocationAccuracyBest`
- Store route as array of `(latitude, longitude, timestamp, speed)` tuples
- Persist route data to local file (JSON) so it survives app restart
- Option to start new route / clear route in settings

**Important:** The map overlay should be composited into the video stream output (not just shown on the local preview). This means it needs to be rendered into the video mixing pipeline. If HaishinKit's video mixing supports bitmap overlays, render the Mapbox view to a bitmap and composite it. If this is too complex, start with the map visible only on the local preview and mark stream-compositing as a TODO.

### 4. Audio Controls

- Microphone audio included in stream by default
- Mute/unmute button (microphone icon with slash when muted)
- When muted, stream continues with silent audio (don't drop the audio track — Twitch requires audio)
- Visual indicator on screen when muted

### 5. Twitch Chat Overlay

- Connect to Twitch IRC via WebSocket (`wss://irc-ws.chat.twitch.tv:443`)
- Parse IRC messages for the channel matching the stream key's channel
- Display chat as a semi-transparent overlay on the stream preview
- Chat overlay is toggleable on/off
- When visible, it appears as a translucent dark panel with scrolling chat messages
- The chat overlay is LOCAL ONLY — it does NOT get composited into the outgoing stream (viewers already have chat on Twitch)
- Chat auto-scrolls to newest message
- Channel name: derive from stream key or let user enter their Twitch username in settings

### 6. Settings Page

Accessible via gear icon. Persisted to UserDefaults or SwiftData. Fields:

**Stream Settings:**
- Twitch Stream Key (secure text field, stored in Keychain)
- RTMP URL (default: `rtmp://live.twitch.tv/app/`)
- Resolution picker: 720p / 1080p
- Bitrate slider: 1000-6000 kbps
- Twitch Username (for chat connection)

**Map Settings:**
- Mapbox Access Token (secure text field)
- Map Style URL (default: `mapbox://styles/mapbox/dark-v11`)
- Options: dark-v11, streets-v12, outdoors-v12, satellite-streets-v12
- Route tracking enabled/disabled toggle
- Clear route data button (with confirmation)

**Display Settings:**
- Camera PiP corner picker (visual 4-corner selector)
- Map PiP corner picker
- Map zoom level slider (10-18, default 15)

### 7. Panic Mode / Security Checkpoint Mode

This is a critical feature for overland travel safety. When approaching a security checkpoint (e.g., military checkpoint in Mexico), the user may need to appear to stop streaming, but wants to maintain some level of security recording.

**Activation:** Prominent "PAUSE" button (or swipe gesture) on the main stream view.

**What happens when activated:**
- The video feed is replaced with a static "Stream Paused" image/card (a calm, innocuous graphic — maybe the app logo on a dark background with "Stream Paused" text)
- **Audio continues streaming** (this is the key security feature — audio evidence continues)
- **GPS/map tracking continues** (route is still being recorded)
- **Map overlay is still being composited into stream** so viewers can see location updating even though video appears paused
- Twitch chat overlay is hidden locally (less distraction, nothing suspicious on screen)
- The local screen shows the "paused" overlay but semi-transparent so the user can still faintly see the camera feed underneath (maybe 15-20% opacity for the camera, 80% for the pause overlay)
- A small, subtle indicator shows that audio is still live (e.g., a tiny pulsing dot in corner)

**Deactivation:** Tap "RESUME" button or swipe gesture. Everything returns to normal.

**The idea:** To someone glancing at the phone, it looks like the app is paused/idle. But audio and GPS are still streaming to Twitch. Viewers on Twitch see the "paused" card but hear everything and can see the map moving.

### 8. Local Recording (Bonus/Optional)

If feasible, simultaneously record to local device storage (Camera Roll or app documents) as a backup. This is secondary to streaming but valuable for security. Use HaishinKit's local recording capability if available.

## UI/UX Design

### Main Stream View (Landscape)
```
┌──────────────────────────────────────────┐
│ ● LIVE  00:42:15          🔇  ⚙️        │  ← Status bar: live indicator, duration, mute, settings
│                                          │
│                              ┌────────┐  │
│                              │  PiP   │  │  ← Camera PiP (movable corner)
│     Main Camera Feed         │ Camera │  │
│                              └────────┘  │
│                                          │
│  ┌────────┐                              │
│  │  Map   │     ┌──────────────────────┐ │
│  │  PiP   │     │ Chat overlay (semi-  │ │  ← Chat overlay (toggleable)
│  └────────┘     │ transparent, local   │ │
│                 │ only, scrolling)     │ │
│                 └──────────────────────┘ │
│                                          │
│  [🔇] [📷 Swap] [🗺️] [💬] [⏸️ Panic]   │  ← Control bar
└──────────────────────────────────────────┘
```

### Control Bar Buttons:
- **Mute toggle** (mic icon)
- **Swap cameras** (swap main/PiP)
- **Map toggle** (show/hide map overlay)
- **Chat toggle** (show/hide Twitch chat)
- **Panic/Pause button** (security checkpoint mode)
- **PiP corner cycle** (long-press on PiP to move to next corner)

### Color Scheme:
- Dark UI, semi-transparent controls
- Red accent for LIVE indicator
- Use SF Symbols for all icons

## Technical Notes

### HaishinKit Integration
- Use the latest version via SPM: `https://github.com/HaishinKit/HaishinKit.swift`
- The library supports `AVCaptureMultiCamSession` for dual cameras
- It supports video mixing for overlays and PiP compositing
- RTMP publishing is straightforward — see their README examples
- Make sure to configure `AVAudioSession` for `.playAndRecord`

### Mapbox Integration
- SPM: `https://github.com/mapbox/mapbox-maps-ios`
- The access token should be set via `MapboxOptions.accessToken` at app launch
- For compositing into video: render the MapView to a `UIImage` on a timer and feed it to HaishinKit's video mixer as a bitmap overlay

### Twitch IRC (Chat)
- Protocol: WebSocket to `wss://irc-ws.chat.twitch.tv:443`
- Auth: `PASS oauth:<user_oauth_token>` and `NICK <username>` (for read-only anonymous chat, use `NICK justinfan<random_numbers>` with no PASS)
- Join channel: `JOIN #<channel_name>`
- Parse PRIVMSG for chat messages
- No external dependencies needed — use `URLSessionWebSocketTask`

### Privacy & Permissions
- Camera (front + rear)
- Microphone
- Location (always — for background tracking during long drives)
- Add all necessary `Info.plist` entries with clear usage descriptions

### Battery & Thermal Management
- This app will run for hours. Consider:
  - Allow the user to reduce to 720p/24fps if thermal throttling occurs
  - Monitor `ProcessInfo.thermalState` and show warnings
  - Keep screen brightness low option
  - `UIApplication.shared.isIdleTimerDisabled = true` to prevent screen lock

### Error Handling
- Handle RTMP disconnections gracefully with auto-reconnect
- Handle GPS signal loss gracefully (show last known position on map)
- Handle camera interruptions (phone calls, etc.)
- Show user-facing error messages as transient toast notifications

## Build & Run

- Xcode 16+
- iOS 17.0+ deployment target
- Real device required (multi-camera doesn't work in simulator)
- You'll need a Twitch account with a stream key and a Mapbox access token to test

## What to Build First (Priority Order)

1. Basic single-camera RTMP stream to Twitch (prove the pipeline works)
2. Add dual-camera with PiP compositing
3. Add camera swap and PiP corner selection
4. Add audio mute/unmute
5. Add settings page with stream key, bitrate, resolution
6. Add Mapbox map overlay on local preview
7. Add GPS route tracking
8. Add Twitch chat overlay (local only)
9. Add panic/security checkpoint mode
10. Composite map into outgoing stream (if feasible)
11. Add local recording backup
12. Polish UI, thermal management, error handling

## License

This is a personal project. MIT license. Use whatever dependencies are compatible.
