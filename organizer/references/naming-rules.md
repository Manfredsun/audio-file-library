# Naming Rules

## Purpose

Display Names are human-readable app metadata.

They do not rename the source file.

---

# 1. Goal

A display name should answer:

> What will I hear if I click this?

Keep names short enough for a browser list.

---

# 2. Preferred Patterns

Use naturally, not mechanically:

```text
[Character] + [Material / Source] + [Action]
```

Examples:

```text
Heavy Metal Door Slam
Soft Wooden Drawer Close
Small Plastic Object Drop
Dry Cloth Rustle
Fast Concrete Footsteps
```

---

# 3. Specificity

Use the most specific reliable object name.

If clear:

```text
Metal Locker Door Close
```

If uncertain:

```text
Metal Door Close
```

If still uncertain:

```text
Metallic Mechanical Impact
```

Do not pretend to know the object.

---

# 4. Avoid

Avoid:

```text
Possible...
Maybe...
Unknown Sound...
Interesting...
Audio Effect...
Foley Sound...
```

Confidence belongs in metadata, not the display name.

---

# 5. Length

Prefer roughly:

```text
2–6 words
```

Longer names are allowed if needed for clarity.

Avoid full sentences.

---

# 6. Capitalization

Use Title Case for English display names.

Example:

```text
Heavy Metal Door Slam
```

---

# 7. Repetition

Avoid repeating category information unnecessarily if it creates awkward names.

Use names that sound natural to a sound editor.

---

# 8. Unknown

For `unknown` results:

```text
display_name = null
```

is acceptable.

Do not force a synthetic name.
