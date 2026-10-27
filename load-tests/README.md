# Optional staging load scenario

`feed.k6.js` exercises the feed RPC with synthetic authenticated users. It is not part of CI and was not executed for this handoff. Its thresholds are test criteria, not measured production capacity.

Required environment variables: `STAGING_URL`, `STAGING_REF`, `PRODUCTION_REF`, `CONFIRM_STAGING=yes`, `STAGING_ANON_KEY`, `SESSIONS_FILE`, and optionally `PEAK_VUS` (default 10). The staging and production references must be different. Verify both projects before running. The safety guard cannot know if an operator has mislabeled a project.

Each virtual user needs a distinct synthetic user ID and fresh test access token with `expires_at`. Keep this file outside Git. Never use real users' sessions. Begin with a small, explicitly authorized stage and monitor database connections, errors, latency, provider usage and cost.

The script offers stages up to 30,000 VUs; this does **not** mean the app has passed any such stage. Large-scale readiness requires a separate capacity exercise and an appropriate test environment.
