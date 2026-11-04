# Same Goat

*We're all in the same goat.*

Household chore tracker for iPhone and iPad (iOS 17+, iPhone 14 and later) and Mac (macOS 14+, Intel and Apple silicon).
Parents assign chores with point values; kids mark them done; points are awarded only when a parent approves.

## Build
    brew install xcodegen
    xcodegen generate
    open SameGoat.xcodeproj

* **Try it without iCloud:** pick the `SameGoat-iOS-Local` or `SameGoat-macOS-Local` scheme. Data stays on the device; Family > "Switch user" lets you act as anyone.
* **Real build (iCloud sync + invites):** pick `SameGoat-iOS` / `SameGoat-macOS`, signed with the team in `project.yml` (`DEVELOPMENT_TEAM`) and the bundle ID `com.samegoat.SameGoat` (the CloudKit container is `iCloud.<bundle id>`). To use your own team, change both. Before shipping, deploy the CloudKit schema to Production in the CloudKit Console.
* Tests: `xcodebuild -scheme SameGoat-macOS-Local -configuration Local -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`

## How it works
* Data: Core Data + CloudKit. The household is shared via `CKShare`; each person signs in with their own Apple ID and picks their profile.
* Roles are enforced in the app (`HouseholdService`), not by CloudKit, so this is built for trusted family use.

## Languages

English and Spanish. Text lives in `Shared/Localizable.xcstrings` (a String Catalog, shared with the
widgets). Building in Xcode adds new strings to it automatically; give each a Spanish translation in
the catalog editor. Strings built in code need `String(localized:)` to be picked up. Siri phrases
are English only for now.

## App Store

`docs/app-store/` has the listing copy, review notes and privacy policy. `./scripts/take-screenshots.sh`
stages the demo family on a 6.9" iPhone and a 13" iPad simulator and writes the screenshots App Store
Connect asks for to `docs/app-store/screenshots/` (not committed; rerun it before each submission).

## Contributing and CI
`main` is protected: changes land through pull requests, and the CI checks must pass.

| Check | What it enforces |
|---|---|
| `scripts/check-banned-patterns.sh` | No `as!`, `fatalError(`, `print(` or TODO/FIXME in `Shared/` (held at zero) |
| `scripts/check-test-count.sh` | Number of test methods never drops (`test-count-baseline.txt`) |
| `scripts/check-coverage.sh` | Line coverage outside `Views/` never drops (`coverage-baseline.txt`) |
| `scripts/verify-macos-universal.sh` | The Release Mac app contains both Intel and Apple silicon code |
| CI build jobs | iPhone and Mac build in both the iCloud and Local configurations |

**Ratchets only go up.** Don't edit the baseline files in a feature branch: after a PR merges, the
`coverage-ratchet` and `test-count-ratchet` workflows raise them on `main` themselves (using a deploy
key that is the ruleset's only bypass). To lower one on purpose, run the script with `--update` and
explain why in the commit.
