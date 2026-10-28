# Agent contract

This is a native macOS sound library manager. Runtime analysis is local and deterministic.

- Human metadata outranks accepted suggestions, which outrank unaccepted suggestions and imported metadata. Explicitly clearing a field is a human decision.
- Never automatically rename, move, delete, rewrite, retag, or modify embedded metadata in original audio files.
- SQLite belongs to the Swift application. The analysis engine returns validated structured results and never persists directly.
- Unknown, uncertain, failed, offline, missing, and permission-lost states must remain explicit and recoverable.
- Library relinking preserves sound IDs, metadata, collection membership, and waveforms. Conflicts abort the transaction.
- Organized hard links are created only after human confirmation. Undo checks identity and tree boundaries, preserves replacement files, and records each outcome. Do not scan the generated tree back into the library.
- Background automatic writes must check current provenance inside their transaction. Bulk changes require a successful database backup first.
- Keep audio decoding, scanning, relinking, and bulk database work off the main thread.
- Markdown vocabulary is authoritative; generated JSON must remain synchronized. Add forward migrations; never rewrite migration history.
- Before code changes, create a task card and follow harness/LOOP.md. Use scripts/verify.sh; only a matching PASS permits delivery. High-risk changes require an independent reviewer.
- Do not lower test counts, weaken policy, remove assertions, or bypass review to obtain PASS.
- Tests use generated or temporary fixtures, never a person's real library.
- Preserve Git history. Publishing is a separate explicit action after release acceptance.

Product direction: ROADMAP.md. Decisions: docs/DECISIONS.md. Latest state: docs/HANDOFF.md.
