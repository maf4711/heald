# Heald — iOS & iPad Client

Universal SwiftUI app (iPhone + iPad) for the heald fleet dashboard at **https://heald.sh**.

## Features

- **Fleet overview** — health counters, machine cards, live CPU charts
- **Machine detail** — CPU cores, RAM, disk, iCloud Drive, top processes, events
- **Journal / AI Fixes / Health** — activity from the cloud API
- **iPad** — sidebar + detail (`NavigationSplitView`)
- **iPhone** — tab bar navigation
- Auto-refresh (5–60s, configurable)
- Default API: `https://heald.sh` · key configurable in Settings

## Requirements

- Xcode 16+ / macOS with iOS 17 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Optional: Apple Developer team for device install

## Build

```bash
cd heald-ios
xcodegen generate
open Heald.xcodeproj
```

Simulator:

```bash
xcodegen generate
xcodebuild -scheme Heald -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build
xcodebuild -scheme Heald -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -configuration Debug build
```

## Configure

1. Launch app → enter API URL (`https://heald.sh`) and API key  
2. **Verbinden** / Test Connection  
3. Fleet appears when Mac daemons push metrics  

## Bundle ID

`com.heald.app` · Display name **Heald** · Version **2.0.0**
