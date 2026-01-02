# Release 1.0.115 (build 115)

- Khata Book: increased transaction fetch window so full months load without truncation.
- Fund transfer labels continue to include plant names for sender/receiver for clearer audit trails.
- Advance flows: description selector always visible; additional notes hidden for advance entries; driver chips show plant names.

Build command:
`flutter build appbundle --release --dart-define=ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-6163248993890252/1567348677 --dart-define=IOS_REWARDED_AD_UNIT_ID= --build-name=1.0.115 --build-number=115 --target lib/main.dart`
