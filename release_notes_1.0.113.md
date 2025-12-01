# Release 1.0.113 (build 113)

- Fixed trips overview to keep showing ongoing trips even if they started before the selected date range.
- Disabled meter reading header action in driver/supervisor dashboards until the feature is ready again.
- Delete trip requests now send user/driver identity so notification logs capture who deleted the trip.

Build command:
`flutter build appbundle --release --dart-define=ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-6163248993890252/1567348677 --dart-define=IOS_REWARDED_AD_UNIT_ID= --build-name=1.0.113 --build-number=113 --target lib/main.dart`
