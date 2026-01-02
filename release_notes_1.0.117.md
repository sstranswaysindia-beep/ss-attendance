# Release 1.0.117 (build 117)

- Khata Book: mobile fetch window raised to 5,000 (API allows up to 20,000) so full months load like the browser.
- Safety: plant-aware tyre picker fixes retained; disable_flag respected across vehicle endpoints.
- Fund transfer and advance flows continue to include plant names for clarity.

Build command:
`flutter build appbundle --release --dart-define=ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-6163248993890252/1567348677 --dart-define=IOS_REWARDED_AD_UNIT_ID= --build-name=1.0.117 --build-number=117 --target lib/main.dart`
