# Release 1.0.87 (Build 87)

- Allow unlimited Watch & Earn sessions: backend skips daily cap/cooldown when configured to zero, and the app now shows “∞”/“unlimited” messaging instead of “Limit reached”.
- Notification bell opens a floating ticker that previews the latest alerts rather than a modal sheet, while toast fallback handles empty inboxes.
- Flutter/Android metadata bumped to 1.0.87+87 and a fresh release bundle generated at `build/app/outputs/bundle/release/app-release.aab`.
- Admin app adds a Geo Fencing screen with plant filters and per-user enable/disable toggles wired to the new admin APIs.
- Admin app adds a Proxy Attendance screen mirroring the same plant filters and toggle flow for `proxy_enabled`.
