# Release 1.0.116 (build 116)

- Khata Book: increased transaction fetch window (now default 2000, up to 5000) so full past months load on mobile.
- Safety: tyre picker uses plant filters and plant names consistently (from prior changes); disable_flag respected across vehicle APIs.
- Fund transfer labels and advance flows continue to include plant names.

Build command:
`flutter build appbundle --release --dart-define=ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-6163248993890252/1567348677 --dart-define=IOS_REWARDED_AD_UNIT_ID= --build-name=1.0.116 --build-number=116 --target lib/main.dart`
