# EarlySync

A macOS menu bar app that syncs your [Early](https://early.app) (formerly Timeular) time-tracking status to your [Luxafor](https://luxafor.com) LED light and macOS Focus mode.

**When you start tracking in Early → Luxafor changes color + macOS Focus activates. When you stop → both reset.**

## Features

- 🔴 Luxafor LED reflects your current Early activity (red = deep work, blue = meeting, green = break, etc.)
- 🎯 macOS Focus mode activates/deactivates based on Early activity
- ⚙️ Fully configurable activity → color/focus mapping
- 🔑 Credentials stored securely in macOS Keychain
- 📊 Lives quietly in the menu bar — no Dock icon

## Architecture

```
EarlyPoller (30s) → StatusEngine (state machine) → LuxaforClient + FocusManager
```

## Build

Requires Xcode 15+ and macOS 13+.

```bash
# Open in Xcode
open EarlySync.xcodeproj

# Or build from command line
xcodebuild -scheme EarlySync -configuration Release build
```

## Setup

1. Generate an Early API Key & Secret at [product.early.app](https://product.early.app)
2. Find your Luxafor Webhook userId in the Luxafor app (Webhook tab)
3. On first launch, the app will guide you through creating two Apple Shortcuts:
   - "EarlySync: Focus On" — uses "Set Focus" action
   - "EarlySync: Focus Off" — disables Focus
4. Enter your credentials in Preferences

## Activity → State Mapping (defaults)

| Early Activity | Luxafor | macOS Focus |
|---|---|---|
| Deep Work / Focus | 🔴 Red | Work / DND |
| Meeting / Call | 🔵 Blue | Do Not Disturb |
| Break / Lunch | 🟢 Green | Off |
| Admin / Email | 🟡 Yellow | Off |
| Not tracking | ⚫ Off | Off |

## Development

Phase 1 (this commit): Early API client — auth, polling, token refresh, state model.

See [PLAN.md](PLAN.md) for the full build roadmap.

## Requirements

- macOS 13 (Ventura) or later
- Early account with API access
- Luxafor Flag, Flag 2, Bluetooth, or ORB device
- Luxafor software installed (for webhook mode)

## License

MIT
