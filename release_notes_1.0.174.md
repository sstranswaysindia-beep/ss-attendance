## 1.0.174

- Allowed past attendance adjust requests and check-in/check-out flows to skip vehicle assignment for office plants/roles so drivers can submit past attendance without hitting the vehicle mapping guard.
- Mobile UI now detects when a plant/role contains “office” and only requires a vehicle in non-office contexts, aligning the frontend with the backend behavior.
- Web attendance header now hides the redundant “Check-in / Check-out with photo” label, removes the standalone “Attendance” heading, moves the date badge to sit beside the status, and no longer shows the Assignment ID tag.
- Added a “Welcome” prefix in front of the driver name so the greeting is more friendly.
- Removed the extra top padding around the attendance card so the content sits flush with the browser edge.
- Status and check-in/check-out time labels remain visible even when there is already an open attendance record so the UI keeps both modes clearly labeled.
- Web attendance now refreshes the GPS blob right before each check-in/check-out submit (including auto submits) so the backend receives the latest location every time.
- Attendance API now reads `location_json` both from JSON requests and multipart form submissions, so the captured GPS blob is saved even when a photo upload is sent.
- Fixed a JavaScript syntax error that prevented the “Open Camera” button from streaming the camera feed when the page tried to capture the user’s GPS ahead of the punch.
- Removed the legacy “notes” field from the web attendance form since punch-in/punch-out no longer needs manual notes.
- Bumped pubspec version to `1.0.174+174` in preparation for the build.

Built artifacts:
- `build/app/outputs/bundle/release/app-release.aab`
