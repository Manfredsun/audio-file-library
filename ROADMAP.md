# Roadmap

Current candidate: 1.0.2-rc.1. Release is blocked until docs/RELEASE-STATUS.md is cleared with evidence.

Implemented: library access and offline state, indexing, paginated browser, search, instant preview, waveform cache, manual metadata, local deterministic suggestions, category browsing, virtual collections, original-file drag, naming preview, explicit hard-link organization and undo, database backups.

Native verification: 541 App tests, 0 failures; independent review approved, release remains PENDING for human acceptance.

Added: system/light/dark appearance, Traditional Chinese/English on next launch, translated built-in labels, bilingual built-in search, and app-scoped preferences. Canonical metadata and paths stay unchanged.

Current work: validate identity-safe undo, provenance protection, library relinking, generated-tree exclusion, reproducible builds, and sanitized public packaging.

Not release promises: virtual scrolling, a complete incremental watcher, external AI analysis, cloud services, or automatic source-file reorganization.

Acceptance: scripts/verify.sh PASS with at least 486 existing tests plus regressions, independent review, clean-source build, DMG validation, and human workflow/classification checks.
