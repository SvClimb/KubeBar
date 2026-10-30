# KubeBar

macOS menu bar app (SwiftUI, SwiftPM, macOS 14+) that assembles kubectl/stern/etc. commands and opens them in a terminal. UI is localized (en/ru): strings in code are English and double as keys; Russian lives in `Packaging/Localization/ru.lproj/Localizable.strings` — add a translation for every new UI string.

- Build and run: `Packaging/build-app.sh` (quits the running instance, runs the fresh build from `dist/KubeBar.app`; never touches /Applications, which holds the brew-installed copy). `--zip` builds a shareable archive.
- After changes, always run the new build: the old version must not stay running.
