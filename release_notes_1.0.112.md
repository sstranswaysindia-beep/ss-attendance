# SS Transways India Admin 1.0.112

- New Spot Audit directory: admin wizard now preloads all plants, vehicles, and drivers from the consolidated `plant_directory.php` endpoint for faster dropdowns.
- Added browser dashboard at `backend/spot_audits.php` so supervisors/admins can review submitted spot audits with filtering plus section-level details.
- Submission fixes: spot audits respect per-role plant access, admins bypass the plant gate, and the wizard gracefully falls back to scoped APIs when the directory request fails.
- Build: driver/supervisor Flutter target (`lib/main.dart`) bundled with rewarded-ad dart defines, exported as `app-release.aab` under `build/app/outputs/bundle/release/`.
