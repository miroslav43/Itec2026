# 🎨 iTEC OVERRIDE

> Real-time AR-like collaborative graffiti battle app

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green.svg)](https://nodejs.org)
[![Socket.IO](https://img.shields.io/badge/Socket.IO-4.7-black.svg)](https://socket.io)

## 🎯 Overview

iTEC OVERRIDE is a cross-platform mobile app where users scan real-world posters (anchor images) and each poster becomes a shared digital canvas. Multiple users can draw at the same time and compete for territory in real-time!

### Key Features

- **📷 Poster Recognition** - Scan QR codes on posters to join battles
- **🎨 Real-time Drawing** - Draw with neon brush effects on shared canvases
- **⚔️ Territory System** - Compete for canvas territory with your team
- **👥 Multiplayer** - See other users' drawings appear in real-time
- **🎮 Cyberpunk UI** - Neon-styled interface with haptic feedback

---

## 📂 Project Structure

```
MAXXX/
├── backend/              # Node.js WebSocket server
│   ├── src/
│   │   └── server.js     # Main server with Socket.IO
│   └── package.json
│
├── mobile_app/           # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/       # Data models
│   │   ├── providers/    # State management
│   │   ├── screens/      # App screens
│   │   ├── services/     # Business logic
│   │   ├── theme/        # Cyberpunk styling
│   │   └── widgets/      # UI components
│   ├── assets/           # Images, sounds, fonts
│   └── pubspec.yaml
│
├── shared/               # Shared models/schemas
│   └── models.js
│
├── scripts/              # Utility scripts
│   ├── generate_qr_codes.js
│   └── copy_posters.js
│
├── images/               # Original poster images
│   └── afis1-10.png
│
└── README.md
```

---

## 🚀 Quick Start

### Prerequisites

- **Flutter SDK** 3.0+ ([Install](https://docs.flutter.dev/get-started/install))
- **Node.js** 18+ ([Install](https://nodejs.org))
- **Android Studio** (for Android builds)
- **Xcode** (for iOS builds, macOS only)

### 1. Start the Backend Server

```bash
cd backend
npm install
npm start
```

Server will run on `http://localhost:3000`

### 2. Configure Mobile App

Edit `mobile_app/lib/providers/socket_provider.dart` to set your server URL:

```dart
// For Android Emulator:
static const String _defaultServerUrl = 'http://10.0.2.2:3000';

// For iOS Simulator:
static const String _defaultServerUrl = 'http://localhost:3000';

// For Real Device (use your computer's IP):
static const String _defaultServerUrl = 'http://192.168.1.100:3000';
```

### 3. Run the Flutter App

```bash
cd mobile_app
flutter pub get
flutter run
```

---

## 📱 How the App Works

### Flow

1. **Launch** → App opens directly to camera mode
2. **Scan** → Point camera at poster QR code
3. **Detect** → Visual feedback shows poster detected
4. **Battle** → Join the poster's drawing room
5. **Draw** → Draw on shared canvas with your team color
6. **Compete** → Territory updates in real-time

### Poster Recognition

The app uses **QR code scanning** as the primary detection method:

1. Each poster has a unique QR code (e.g., `ITEC_AFIS1`)
2. Camera continuously scans for QR codes
3. When detected, user joins that poster's battle room

**To generate QR codes for posters:**

```bash
cd scripts
npm install
npm run generate-qr
```

QR codes will be saved to `/qr_codes/` folder with a printable HTML page.

### Adding New Posters

1. **Backend** - Add to `POSTERS` object in `backend/src/server.js`:
   ```javascript
   'afis11': { id: 'afis11', name: 'New Poster Name', gridSize: 20 }
   ```

2. **Mobile App** - Add to `posters` map in `lib/providers/app_state_provider.dart`:
   ```dart
   'afis11': Poster(id: 'afis11', name: 'New Poster Name', imagePath: 'assets/posters/afis11.png')
   ```

3. **QR Mapping** - Add to `qrToPosterMap` in `lib/services/poster_recognition_service.dart`:
   ```dart
   'ITEC_AFIS11': 'afis11',
   'afis11': 'afis11',
   ```

4. **Generate QR** - Run the QR generator script

---

## 🎨 Drawing System

### Normalized Coordinates

All drawing coordinates are normalized to 0-1 range:
- `(0, 0)` = top-left corner
- `(1, 1)` = bottom-right corner

This ensures drawings appear at the same position on all devices regardless of screen size.

### Stroke Data Structure

```json
{
  "id": "unique-stroke-id",
  "userId": "user-123",
  "teamId": "blue",
  "points": [
    {"x": 0.5, "y": 0.3},
    {"x": 0.51, "y": 0.32}
  ],
  "color": "#00D4FF",
  "size": 8,
  "timestamp": 1679012345678,
  "isEraser": false
}
```

### Territory Grid

- Canvas divided into 20x20 grid (400 cells)
- Each stroke updates grid cells it passes through
- Cell ownership = team of last stroke through it
- Territory percentage = (team cells / total cells) × 100

---

## 🔧 Backend API

### REST Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Server status |
| `/api/posters` | GET | List all posters |
| `/api/posters/:id` | GET | Get poster details |
| `/api/teams` | GET | List all teams |
| `/api/rooms/:posterId/state` | GET | Get room state |

### WebSocket Events

**Client → Server:**

| Event | Payload | Description |
|-------|---------|-------------|
| `join_poster_room` | `{posterId, userId, teamId, username}` | Join a poster battle |
| `send_stroke` | `{points, color, size, isEraser}` | Send completed stroke |
| `drawing_point` | `{point, color, size}` | Live drawing preview |
| `get_poster_state` | `{posterId}` | Request current state |
| `leave_room` | - | Leave current room |

**Server → Client:**

| Event | Payload | Description |
|-------|---------|-------------|
| `room_joined` | `{posterId, user, strokes, territory, userCount}` | Joined successfully |
| `receive_stroke` | `{stroke}` | New stroke from another user |
| `territory_update` | `{teams, dominant, total}` | Territory changed |
| `user_joined` | `{user, userCount}` | User joined room |
| `user_left` | `{socketId, userCount}` | User left room |

---

## 📦 Building for Production

### Android APK

```bash
cd mobile_app

# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release
```

APK location: `build/app/outputs/flutter-apk/app-release.apk`

### iOS Build

```bash
cd mobile_app

# Generate Xcode project
flutter build ios --release --no-codesign

# Open in Xcode
open ios/Runner.xcworkspace
```

Then in Xcode:
1. Select your development team
2. Set bundle identifier
3. Build and run on device

---

## 🎮 Demo Flow for Hackathon

### Setup (Before Demo)

1. Start backend server on a laptop
2. Note the laptop's IP address
3. Update mobile app with server IP
4. Build and install on 2+ devices
5. Print QR codes and attach to posters

### Demo Steps

1. **Show Camera Mode** - App launches directly to scanner
2. **Scan Poster** - Point at QR code, show detection feedback
3. **Join Battle** - Automatic connection to room
4. **Draw Together** - Both users draw on same canvas
5. **Show Territory** - Demonstrate ownership changes
6. **Real-time Sync** - Show strokes appearing on both devices

### Talking Points

- "Scan any poster to start a graffiti battle"
- "Draw with neon brushes in real-time"
- "Compete for territory with your team"
- "All drawings sync across devices instantly"

---

## 🛠️ Troubleshooting

### Camera Not Working

- Check camera permissions in device settings
- Ensure no other app is using camera
- Try restarting the app

### Can't Connect to Server

- Verify backend is running (`npm start`)
- Check server URL in socket_provider.dart
- For real device: use computer's local IP, not localhost
- Ensure devices are on same WiFi network
- Check firewall isn't blocking port 3000

### QR Code Not Detected

- Ensure good lighting
- Hold phone steady
- QR code should be clearly visible in frame
- Try manual poster selection (POSTERS button)

### Drawings Not Syncing

- Check connection status indicator
- Verify both devices joined same poster room
- Restart the app and rejoin

---

## 🎁 Bonus Features (If Time Permits)

- [ ] Glitch effect when multiple users draw simultaneously
- [ ] Simple leaderboard showing top teams
- [ ] Sticker placement mode
- [ ] AI sticker generator placeholder
- [ ] Sound effects and music

---

## 📄 License

MIT License - Built for iTEC Hackathon 2026

---

## 👥 Team

Built with ❤️ and lots of ☕

**iTEC OVERRIDE** - *Draw. Compete. Override.*
