# Release acceptance

Preview candidate: Audio File Library 1.0.2-rc.1; App 1.0.2, build 4. Released as a **public preview, not a verified stable release**, at the user's direction on 2026-10-29. The original full manual acceptance remains pending.

Native verification run 2026-10-27-021: 541 App tests, zero failures; V1–V5 passes, including independent review of the same source fingerprint. The settings label fix is included.

The user subsequently requested immediate open-source publication and waived the 30–50 sample manual sound-classification check as a publication prerequisite. This does not imply those checks passed, and does not attest to real Logic Pro drag/organize workflows.

Required human acceptance:

- Search, preview, drag into Logic Pro, and explicit organize/undo using an isolated test library.
- Review 30–50 representative sounds to assess classification usefulness and false confidence.

This candidate uses the production app identifier and data location. Previous Beta metadata is separate and is not merged automatically. The app is ad-hoc signed and not notarized by Apple.

The public source manifest remains release_ready=false to distinguish this preview from a verified stable release; the private development commit gate has not been modified. Optional real-device tests: [QA checklist](QA-CHECKLIST.md).
