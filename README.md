# NovaLink Voice

The mobile softphone for **NovaLink Voice**, a hosted business phone service from
NovaLink Fiber. Customers sign in with their NovaLink Voice portal account and make
and receive calls on their business line from Android or iOS.

Calling is built on the [Linphone SDK](https://www.linphone.org/) (liblinphone) by
Belledonne Communications. The UI is Flutter; the call engine runs natively
(Kotlin on Android, Swift on iOS).

## License

NovaLink Voice is free software, licensed under the **GNU Affero General Public
License v3.0**. See [`LICENSE`](LICENSE). Third-party components and their licenses,
including the Linphone SDK, are listed in [`NOTICE`](NOTICE).

Each release in the Google Play Store and Apple App Store is tagged in this
repository (`v<version>`), and that tag is the complete corresponding source for
that store build.

## How it works

- **Sign-in:** the app exchanges the user's portal email and password for that
  user's own SIP extension. No account is built into the app.
- **Calls:** SIP over TLS with the server certificate verified, through the NovaLink
  Voice push gateway (Flexisip) to the PBX.
- **Incoming calls while the app is closed:** Firebase Cloud Messaging on Android,
  APNs VoIP push with CallKit on iOS.
- **Emergency numbers** (911, 112, 9911) open the phone's own dialer so the call
  goes out over the cellular network with the device's location.

The app only works with a NovaLink Voice account.

## Building

Requires Flutter (stable), JDK 17 and the Android SDK; iOS also requires macOS
with Xcode and CocoaPods.

```bash
flutter pub get
flutter build apk          # Android
flutter build ios          # iOS (macOS only; run `pod install` in ios/ first)
```

**Push notifications:** Android push needs a Firebase project. Put its
`google-services.json` in `android/app/` (gitignored). Without it the app builds
and runs, but cannot be woken for incoming calls while closed.

**Release signing:** if `android/key.properties` exists it supplies the release
keystore (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); otherwise
release builds are signed with the debug key. Store builds are signed with
NovaLink's own keys, which are not part of this repository.

`tool/patch-flutter-lipo-xcode27.py` works around a Flutter `lipo` failure with
Xcode 27; `tool/make_icon.py` regenerates the launcher icons.
