# Confidence Rules

## Purpose

Confidence helps determine review priority.

It is not guaranteed probability.

---

# 1. Scale

```text
0.0–1.0
```

---

# 2. General Interpretation

Suggested initial interpretation:

```text
0.85–1.00
Strong

0.65–0.84
Moderate

0.40–0.64
Weak / uncertain

0.00–0.39
Very weak / unknown
```

These are initial guidelines only.

Production thresholds must be calibrated against the evaluation dataset.

---

# 3. Increase Confidence When

- source is clearly audible
- event is distinctive
- material is clear
- action is clear
- filename/folder context agrees with audio
- category mapping is straightforward

---

# 4. Reduce Confidence When

- multiple sources overlap
- sound is very short or degraded
- source identity is ambiguous
- context conflicts with audio
- classification requires object-specific guessing
- several categories are similarly plausible
- sound is heavily processed

---

# 5. Status Guidance

Typical mapping:

```text
recognized
usually strong confidence

suggested
usually moderate confidence

uncertain
usually weak-to-moderate confidence

unknown
usually very weak confidence
```

Do not treat this mapping as rigid.

---

# 6. Needs Review

Prefer:

```text
needs_review = true
```

when:

- confidence < 0.70
- status = uncertain
- status = unknown
- context conflict exists
- important fields rely on speculation

Exact thresholds are configurable.

---

# 7. False Confidence

False confidence is worse than honest uncertainty.

Do not increase confidence simply because the schema expects a result.

---

# 8. Evaluation

Confidence thresholds should eventually be compared with:

```text
human correction rate
category accuracy
tag usefulness
unknown detection quality
```

Use evaluation evidence to adjust application policies.
