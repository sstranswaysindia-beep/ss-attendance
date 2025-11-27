# Release 1.0.91 (Build 91)

- Rolls forward driver/supervisor build to include the latest Khata Book safeguards and backend toggles shipped with the admin release.
- Supervisor dashboard now supports marking drivers absent directly from Today’s Attendance, with records stored via `supervisor_absence_marks`.
- Drivers marked absent are blocked from opening the Mark Attendance screen, with the server enforcing the restriction during submissions.
- Dependency metadata bumped to 1.0.91+91 in preparation for store submission.
- Admin bundle remains available separately under `admin-app-release.aab`; this bundle targets the primary app (`lib/main.dart`).
