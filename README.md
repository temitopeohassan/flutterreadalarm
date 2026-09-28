# flutterreadalarm
Repo for the ReadAlarm Mobile App

## Development

```sh
flutter pub get
flutter analyze
flutter test test            # unit + widget tests
flutter build apk --release  # APKs land in build/app/outputs/flutter-apk/
```

## Continuous integration

`.github/workflows/flutter-ci.yml` runs on every push to `main` or `claude/**`,
on pull requests, and on demand (**Actions → Flutter CI → Run workflow**):

| Job | What it does |
| --- | --- |
| Analyze & test | `dart format` check, `flutter analyze`, `flutter test test` |
| Build APK | Release APKs (per-ABI and universal), uploaded as the `readalarm-apks-<sha>` artifact |
| Regenerate screenshots | Runs `screenshot_test` and uploads the PNGs as `readalarm-screenshots-<sha>` |

Download the APKs from the run's **Artifacts** section. Release builds are
signed with the debug key until a release keystore is configured in
`android/app/build.gradle.kts`.

## Screenshots

`screenshots/` holds a PNG of every screen (1080×2400). They are produced by
driving the real app through each flow in `screenshot_test/`:

```sh
flutter test screenshot_test
```

| | | | |
| --- | --- | --- | --- |
| ![Welcome](screenshots/01_onboarding_welcome.png) | ![Home](screenshots/12_home.png) | ![Set alarm](screenshots/16_set_alarm.png) | ![Now playing](screenshots/18_now_playing.png) |
