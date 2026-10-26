# FlashQuest

FlashQuest is an offline-first Android-only flashcard study app built with
Flutter and Dart. Create decks and cards, study at your own pace, and track
mastery locally with SQLite. The app does not require an account or network
connection. Android is the only supported deployment target in this repository.

## Features

- Create, edit, and delete decks and flashcards.
- Track each card as **Known** or **Review** and view deck mastery progress.
- Study with an animated question-and-answer card.
- Swipe left to skip a card without changing its saved mastery. Keyboard and
  screen-reader actions are also available.
- Retry Review and skipped cards in a new round with **Retry Remaining Cards**.
- Use **Study Again** to confirm a mastery reset for a deck and start a fresh
  session; card content and other decks are unchanged.
- Responsive layouts, accessible controls, and friendly retryable error states.

## Technology

- Flutter and Dart
- Material 3
- SQLite through `sqflite`
- `sqflite_common_ffi` for real SQLite-backed tests on the development host

Dependency versions and the Dart SDK constraint are declared in
[`pubspec.yaml`](pubspec.yaml); [`pubspec.lock`](pubspec.lock) records the
resolved dependency versions.

## Prerequisites

- Flutter SDK with Dart 3.13.2 or later, within the Dart 3.x range.
- Android SDK and an Android device or emulator.
- Flutter's supported Android build toolchain. See the
  [Flutter Android setup guide](https://docs.flutter.dev/platform-integration/android/setup).

This project does not include iOS, web, Windows, Linux, or macOS build
configurations.

## Run the app

From the project directory:

```sh
flutter pub get
flutter run
```

To run static analysis and the test suite:

```sh
flutter analyze
flutter test
```

## Build an Android APK

Build a release APK with:

```sh
flutter build apk --release
```

The resulting APK is written to
`build/app/outputs/flutter-apk/app-release.apk`. To build separate APKs for
supported CPU architectures:

```sh
flutter build apk --release --split-per-abi
```

Build outputs are generated locally and are not intended to be committed. The
current Android release build uses the existing debug signing configuration;
configure production signing separately before distributing through an app
store. This repository preparation does not change the application ID or
signing configuration.

## Study Mode

1. Open a deck with cards and start studying. Each new session includes every
   card, regardless of its previously saved Known or Review status.
2. Tap a card to reveal the answer, then mark it **Known** or **Review**.
   Grading is saved to the local database.
3. Swipe left to skip a card. A skip changes only the in-memory study session;
   it does not update the saved classification.
4. At the end of a round, review the summary and choose **Retry Remaining
   Cards** to study the Review and skipped cards in their original order.
5. From deck details, **Study Again** offers a confirmation before resetting
   that deck's saved mastery to Review and opening a fresh session.

## Local database

FlashQuest stores `flashquest_drill.db` in the app's private database directory
on the device. Schema version 1 contains `decks` and `flashcards` tables. Cards
reference their deck with cascading deletion; indexes support deck ordering and
per-deck mastery queries. Schema creation and upgrades use migrations. Saved
mastery is stored per card, while study queues, skipped cards, and round
progress exist only for the current session.

The database is local application data, not a project asset. It is not included
in this repository and is not modified by these repository-preparation steps.

## Project structure

```text
android/                 Android app and Gradle configuration
assets/icon/             FlashQuest icon artwork
lib/
  core/                  Shared presentation and lifecycle helpers
  data/                  SQLite database and repository implementations
  features/              Deck, flashcard, startup, and study flows
  models/                Deck, flashcard, and mastery models
  repositories/          Repository contracts and exceptions
  widgets/               Shared interface components
test/                    Unit, database, view-model, and widget tests
tool/                    Project utilities
```

## Licensing and attribution

No project-level license file is currently included. Third-party dependencies
retain their own licenses and notices in their respective upstream packages.
