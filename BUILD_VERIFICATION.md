# FlashQuest verification — 26 October 2026

Swipe-left skipping and explicit retry rounds are implemented in the existing
`StudySession`, `StudyViewModel`, and Study screen. A deliberate left swipe skips
either face without a database write. Tap-to-flip, vertical content scrolling,
Known/Review persistence, large card dimensions, centered bold text, colors,
rounded corners, and the outer shadow are preserved. The hint appears above the
card. Screen readers have a **Skip card** action; keyboard users can press Left
Arrow. Reduced motion skips the animation. Turn tokens and interaction locks
reject duplicate callbacks, held-key repeats, and grading during a skip.

Each pass ends with an explicit summary unless every card is Known. **Retry
Remaining Cards** presents only Review and skipped cards in the original order.
Mastered counts are cumulative within the session; Review and Skipped reflect
each remaining card's latest session action, so these categories do not overlap.
All-skipped passes wait for the user. Every new session includes the entire deck,
including cards saved as Known. Failed writes retain the current card and state.

**Verification passed:** `flutter analyze` reports no issues; all **247 Flutter
tests pass** (233 before the changes). Tests include real SQLite persistence,
failed writes, skips leaving saved records unchanged, mixed and all-skipped
rounds, stale callbacks, multiple pointers, keyboard repeat, screen-reader
actions, reduced motion, long-text scrolling, narrow/landscape layouts, text
scaling, existing shadow/style checks, and Android accessibility guidelines.
Rendered question and round-summary previews were also inspected.

**Final APKs** are in `build/app/outputs/flutter-apk/`. Sizes below are exact
filesystem bytes; MiB means 1,048,576 bytes. Select the APK matching the device's
CPU architecture. Each architecture APK is independently installable.

| Build | Exact bytes | MiB | Reduction from original debug | Output |
| --- | ---: | ---: | ---: | --- |
| ARM64 release | 16,678,982 | 15.9063 | 91.25% | [app-arm64-v8a-release.apk](build/app/outputs/flutter-apk/app-arm64-v8a-release.apk) |
| ARMv7 release | 13,874,702 | 13.2319 | 92.72% | [app-armeabi-v7a-release.apk](build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk) |
| x86_64 release | 18,179,144 | 17.3370 | 90.46% | [app-x86_64-release.apk](build/app/outputs/flutter-apk/app-x86_64-release.apk) |
| Updated debug, all three ABIs | 190,588,659 | 181.7595 | — | [app-debug.apk](build/app/outputs/flutter-apk/app-debug.apk) |

Builds used Flutter 3.47.2 / Dart 3.13.2. These commands all completed successfully:

```powershell
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release --split-per-abi
flutter build apk --release --target-platform android-arm64 --analyze-size
flutter build apk --release --split-per-abi --split-debug-info=build/release-symbols
```

The final sharing APKs come from the last command. Flutter's defaults provide AOT
compilation, tree shaking, R8 code shrinking, and resource shrinking; no Android
configuration changes were needed. Separating Dart debug symbols saved another
720,896 bytes per ARM64/x86_64 APK and 917,504 bytes for ARMv7. Keep the matching
files in [build/release-symbols](build/release-symbols/) and the R8 mapping in
`build/app/outputs/mapping/release/` for diagnostics. Dart obfuscation was not enabled.
This uses [Flutter's supported size-reduction options](https://docs.flutter.dev/perf/app-size).

Other retained artifacts and exact sizes:

| Artifact | Exact bytes | Output |
| --- | ---: | --- |
| Original debug APK, unchanged | 190,588,777 | [before-skip-retry/app-debug.apk](build/before-skip-retry/app-debug.apk) |
| Standard ARM64 release before symbol separation | 17,399,878 | [release-baseline/app-arm64-v8a-release.apk](build/release-baseline/app-arm64-v8a-release.apk) |
| Standard ARMv7 release before symbol separation | 14,792,206 | [release-baseline/app-armeabi-v7a-release.apk](build/release-baseline/app-armeabi-v7a-release.apk) |
| Standard x86_64 release before symbol separation | 18,900,040 | [release-baseline/app-x86_64-release.apk](build/release-baseline/app-x86_64-release.apk) |
| ARM64 analysis APK, ordinary release symbols | 17,399,874 | [app-release.apk](build/app/outputs/flutter-apk/app-release.apk), also copied to [app-arm64-analysis.apk](build/size-analysis/app-arm64-analysis.apk) |

The original debug APK was dominated by Flutter debug engines for three ABIs:
40,083,280 bytes for x86_64, 38,828,704 for ARM64, and 33,150,308 for ARMv7.
Other major entries were the packaged Dart kernel (15,376,816 bytes), ARM64 Vulkan
validation library (15,240,080), and isolate snapshot (4,405,748). These are
development overhead, not large decks or application images. Flutter documents
why [debug sizes do not represent release sizes](https://docs.flutter.dev/perf/app-size#debug-builds-are-not-representative).

In the optimized ARM64 APK, the two native libraries dominate:
`libflutter.so` is 11,747,864 bytes and `libapp.so` is 4,391,816 bytes. All Flutter
assets together occupy 133,861 packaged bytes; DEX occupies 249,494. The Material
icon font was tree-shaken from 1,645,184 to 3,804 bytes. The app package itself
accounts for approximately 149 KB in the ordinary-release Dart analysis.

The unused `cupertino_icons` dependency was removed after checking for code
references. `sqflite` and `path` remain required. The test-only
`sqflite_common_ffi` and launcher-generation tooling remain available. Although
the debug APK includes native SQLite libraries from the test dependency's build
hook, release tree shaking excludes them automatically. The production sqflite
path remains intact. Branding images are small and retained; the launcher-source
image is tooling input, not an additional runtime asset.

The supported ARM64 analysis completed and produced
[arm64-code-size-analysis.json](build/size-analysis/arm64-code-size-analysis.json),
with its terminal breakdown in [flutter-analysis.log](build/size-analysis/flutter-analysis.log).
This SDK rejects combining `--analyze-size` with `--split-debug-info`, so analysis
was run on an ordinary single-ABI release. Exact final optimized sizes and their
SHA-256 checksums are in [final-apk-report.json](build/size-analysis/final-apk-report.json).
The reproducible ZIP inspection tool is [tool/apk_size_report.py](tool/apk_size_report.py).

**Signing and updates:** release still uses the existing **debug signing key**
configured in `android/app/build.gradle.kts`. No signing configuration, production
key, password, or private-key material was changed or exposed. `apksigner verify`
passed for the original debug APK, updated debug APK, analysis APK, and all final
release APKs. All have the same public certificate SHA-256 fingerprint:

```text
675a9820a8d484e87859aaaf7eea5d09afed964ca3c89054538f81c3f6b233ce
```

The application ID remains `com.example.flashquest_drill`, version name `1.0.0`,
minimum SDK 24 and target SDK 36. Version codes are 1 for debug/analysis, 1001 for
ARMv7, 2001 for ARM64, and 4001 for x86_64. These ABI offsets are added by
[Flutter's split build](https://docs.flutter.dev/deployment/android#build-an-apk).
All inspected APKs pass `zipalign -c -P 16 4`.

If the installed app came from the original local debug APK, the matching ABI
release has the same signer and application ID and a higher version code: there
is no signing conflict for an in-place update. Android's update rules require
[matching signing certificates](https://developer.android.com/studio/publish/app-signing#considerations).
The installed device's signer was not checked because no Android device was
connected. A debug APK made on another machine may use a different key.

Use an in-place update such as `adb install -r <matching-release.apk>` after
checking device compatibility. This command was not executed on a device.
Keep the installed app and local decks if Android reports a signing mismatch;
resolve the original key and arrange a verified data backup before any migration.
Uninstalling or clearing storage deletes locally stored decks. Returning later
to debug version code 1 would be a downgrade; build a new debug APK with a version
code at least as high as the installed release instead of uninstalling.
These debug-signed releases are local sharing/testing builds, not production
signing credentials for store publication.

Source checksums confirm that all 45 protected Android/configuration, database,
model, and branding files are unchanged. Flashcard/deck CRUD files are also
unchanged. Skip adds no database field or saved status. Original source snapshots
and the original debug APK are retained in `build/before-skip-retry/`.
No installed application or production database was accessed or modified.

Physical Android verification remains necessary: install the matching release
over the existing debug app and confirm decks/mastery survive; check cold launch,
Known/Review saving and reopening; exercise real swipe thresholds, long-text
scrolling, TalkBack custom actions, external keyboard, reduced motion, and the
card shadow on actual hardware. ARMv7/ARM64/x86_64 runtime compatibility has been
checked at the APK/package level, not by running each ABI on a device.
