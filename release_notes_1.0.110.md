# SS Transways India 1.0.110

- Admin supervisor approvals now mirror the mobile filter controls: choose supervisors/drivers/all, see plant/range filters, and approve with the same API.
- Backend web panel (`backend/supervisor_approvals_admin.php`) reuses the mobile API so browser approvals stay in sync and include the new role filters.
- Build: admin-only Flutter target (`lib/main_admin.dart`) bundled with rewarded-ad dart defines and packaged as `admin-app-release.aab`.
