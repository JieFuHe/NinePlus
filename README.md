# NineBot+

NineBot+ is a personal iOS app for viewing and managing Ninebot vehicle status, with Home Screen widgets, Lock Screen widgets, Siri Shortcuts, trip history, location views, and local ride recording.

This project is intended for personal builds. It is not configured for App Store distribution by default.

## Features

- Vehicle dashboard with battery, estimated range, status, charging state, and location.
- Home Screen and Lock Screen widgets.
- Siri Shortcuts and App Intents support.
- Trip history, mileage trends, and local ride recording.
- MapKit vehicle location and reverse geocoding.
- Local cache shared between the app and widgets through App Groups.

## Requirements

- macOS with Xcode.
- An Apple Developer account for device signing.
- A configured iOS device.
- A compatible vehicle API proxy endpoint reachable from the iPhone.

## Build

1. Clone the repository.
2. Open `mini-ninebot/mini-ninebot.xcodeproj` in Xcode.
3. Select your Apple Developer Team for the app target and the `NinebotWidgets` target.
4. Replace the sample Bundle IDs with your own:
   - App: `com.example.NineBotPlus`
   - Widgets: `com.example.NineBotPlus.NinebotWidgets`
5. Enable the same App Group for both targets, for example `group.com.example.NineBotPlus`.
6. Build and run on a physical iPhone.

## Setup

1. Open the app on the iPhone.
2. Go to the profile/settings tab.
3. Enter your proxy endpoint and optional Bearer Token.
4. Bind your account.
5. Return to the vehicle dashboard and refresh.
6. Add the Home Screen or Lock Screen widgets after the first successful refresh.

## Widgets

Widgets read the latest cached vehicle snapshot from the shared App Group container. iOS controls widget background refresh frequency, so opening the app and refreshing manually is the fastest way to update widget data immediately.

## Privacy

The app stores configuration, login state, vehicle snapshots, cached addresses, trip records, and local ride records on the device. Do not commit personal tokens, account data, signing certificates, provisioning profiles, or generated build artifacts to this repository.
