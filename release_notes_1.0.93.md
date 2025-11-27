# Release 1.0.93 (Build 93)

- Adds supervisor absent toggle support in the mobile backend so supervisors can mark/reset attendance directly from the app.
- Keeps trip and vehicle APIs aligned with mobile behaviour after recent admin updates.
- Rebuilt main driver/supervisor Android bundle (`app-release.aab`) with version 1.0.93+93 for Play submission.
- Captures device model, OS, and app version for every login/session (driver, supervisor, admin) so we can audit who runs which build.
