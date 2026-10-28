# Decisions

## Local analysis

Runtime classification uses deterministic acoustic measurements and literal path evidence. No model or external service is a dependency.

## Human authority

Manual metadata, including explicitly empty values, survives automatic analysis and path rereads. Accepted metadata is protected from lower-authority automatic updates.

## Organization and undo

Only human-confirmed organized hard links may be created. A durable journal records file identity and undo status. Undo claims the directory entry, verifies identity, and never recursively deletes. Replacements, offline roots, failed writes, and interrupted work are preserved or retried. Recovery locations are shown when a concurrent change prevents safe restoration.

## Relinking and indexing

Move library references atomically without replacing sound records. Abort on collisions or identity mismatches. Use per-scan identities instead of timestamp ordering, skip audio symlinks, and exclude only the root generated _Organized tree; preserve existing duplicate records for human-reviewed repair.

## Release safety

Bulk writes stop when backup fails. Fixes require a matching harness PASS and independent review. Publish a clean source snapshot under MIT with third-party notices; keep private history local. The beta is ad-hoc signed and unnotarized.

## Scan ownership

A per-library active token is checked inside every scanner write transaction. Superseded scans stop, relinking invalidates the old token, and UI callbacks carry a request identity. This prevents old discovery or metadata batches from changing a newer scan's results, including across database connections.

## Appearance and language

A single app saves system/light/dark appearance and system/Traditional Chinese/English language. Appearance applies immediately without recreating services; language applies next launch without interrupting work. Language overrides remain in the app preference domain. Unsupported languages fall back to English.

Native String Catalogs provide interface text and plurals. Canonical categories/styles/textures are translated only for display; bilingual search adds parameterized read-only aliases while retaining word AND / field OR. Custom names, tags, notes, collections, stored analyses and physical paths keep their original text. No database migration or analysis rule changes are needed.
