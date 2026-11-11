# flutterreadalarm
Repo for the ReadAlarm Mobile App

## What works

- **Library:** import PDF and EPUB files (up to 100 MB) with the system file
  picker. Text, title, author and chapters are extracted on the device.
  Scanned PDFs, password-protected PDFs and DRM EPUBs are rejected with an
  explanation.
- **Reading aloud:** the phone's text-to-speech engine reads sentence by
  sentence, with pause/resume, skip, speed, and (Premium) voice and pitch.
  Sentences are queued with the speech engine minutes ahead and a
  foreground service holds a wake lock, so reading continues with the
  screen locked; Pause/Stop sit on the lock screen. Your place is saved as
  you go.
- **Alarms:** exact alarms per weekday or one-off. They ring over the lock
  screen, keep ringing until answered, survive reboots, and offer Start
  reading or Snooze 10 min. Alarm sessions stop after 15/30/60 minutes.
- **Onboarding and Settings → Alarm health:** real Android permission
  requests (notifications, exact alarms/full-screen alarms, battery
  optimisation) and a guide for your phone brand's auto-start setting.
- **Stats:** minutes read per day, weekly total and streak from your
  sessions. Everything is saved on the device.

**Free tier:** 3 books, 1 alarm, and 15 minutes of reading a day (reset
at local midnight). When the minutes run out, the paywall explains when
reading resets.

Only one alarm can be switched on: alarms beyond it (e.g. from an earlier
version, which allowed 3) are switched off, the first one added staying on.

**Ads (free users only):** an AdMob banner at the bottom of the main
screens, an interstitial after some sessions (at most 3 a day, 10 minutes
apart, never over the lock screen). Google's consent form is shown first where the law
requires it (EEA, UK), with "Ad privacy options" in Settings. No ads on the
alarm screens or for Premium.

**Premium:** Google Play subscriptions, Monthly and Yearly, no free trial.
Purchases are checked on the phone with Google Play at start-up and whenever
the app comes back, so a cancelled or lapsed subscription returns the app to
the free tier. Pending payments (e.g. cash) unlock Premium once Play
confirms them.

## Setting up ads and payments

The app is built with **Google's test ads** and **placeholder product ids**.
Until the steps below are done, ads are test ads and the paywall says
purchases aren't available.

### 1. Google Play Console (payments)

1. Create the app in [Play Console](https://play.google.com/console) with
   package name `com.readalarm.readalarm`, and set up a payments profile.
2. Create an **upload key** and sign the release build with it. Put
   `android/key.properties` next to `android/app/` (never commit it):
   ```properties
   storeFile=../upload-keystore.jks   # relative to android/app
   storePassword=…
   keyAlias=upload
   keyPassword=…
   ```
3. Build `flutter build appbundle --release` and upload it to **Testing →
   Internal testing**. Add yourself as a tester and **install from the Play
   Store link**: purchases only work in a copy installed from Play.
4. **Monetize → Subscriptions**: create two subscriptions, each with one
   auto-renewing base plan and **no free-trial offer**:
   | Product id | Base plan | Price |
   | --- | --- | --- |
   | `readalarm_premium_monthly` | monthly | ₦1,500 |
   | `readalarm_premium_yearly` | yearly | ₦12,000 |
5. **Settings → License testing**: add your Google account, so test
   purchases aren't charged.

### 2. AdMob (ads)

1. In [AdMob](https://admob.google.com), add the app (Android, link it to
   the Play listing once it exists) and note its **App ID**
   (`ca-app-pub-…~…`).
2. Create two ad units: **Banner** and **Interstitial**, and
   note their ids (`ca-app-pub-…/…`).
3. **Privacy & messaging**: create a GDPR consent message for the app.
4. Add the ids to GitHub (**Settings → Secrets and variables → Actions**):
   `ADMOB_APP_ID`, `ADMOB_BANNER_ID` and `ADMOB_INTERSTITIAL_ID`. CI then builds with real ads. Locally:
   ```sh
   flutter build appbundle --release -PadmobAppId=ca-app-pub-…~… \
     --dart-define=ADMOB_BANNER_ID=ca-app-pub-…/… \
     --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-…/…
   ```
   Never tap your own real ads: test with the default (test) build.
5. Publish an `app-ads.txt` on your developer website (AdMob shows its
   contents).

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

Download the APKs from the run's **Artifacts** section. CI builds are all
signed with the same test key (`android/app/test-signing.p12`, not secret), so
each new APK installs over the last. Never use it for Play: build the Play
bundle with your upload key (see above). `readalarm-diagnostics.apk` adds a
"Generate Report" bar for sending diagnostics.

## Screenshots

`screenshots/` holds a PNG of every screen (1080×2400). They are produced by
driving the real app through each flow in `screenshot_test/`:

```sh
flutter test screenshot_test
```

| | | | |
| --- | --- | --- | --- |
| ![Welcome](screenshots/01_onboarding_welcome.png) | ![Home](screenshots/13_home.png) | ![Set alarm](screenshots/17_set_alarm.png) | ![Now playing](screenshots/19_now_playing.png) |
