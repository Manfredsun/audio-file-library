# Organizer Examples

## Example 1 — Clear Door Slam

Input:

```text
Filename:
metal_door_04.wav

Audio:
clear heavy metal door slam
```

Output:

```json
{
  "status": "recognized",
  "display_name": "Heavy Metal Door Slam",
  "category": "Foley/Doors",
  "subcategory": "Metal Door",
  "tags": ["metal", "heavy", "slam", "indoor", "short"],
  "description": "Heavy metal door slam with a short resonant tail.",
  "confidence": 0.94,
  "needs_review": false,
  "alternative_categories": []
}
```

---

## Example 2 — Drawer Close

Input:

```text
Filename:
REC_00129.wav

Audio:
small wooden drawer closing softly
```

Output:

```json
{
  "status": "recognized",
  "display_name": "Soft Wooden Drawer Close",
  "category": "Foley/Furniture",
  "subcategory": "Drawer",
  "tags": ["wood", "soft", "close", "indoor", "short"],
  "description": "Soft wooden drawer close with a dry indoor sound.",
  "confidence": 0.89,
  "needs_review": false,
  "alternative_categories": []
}
```

---

## Example 3 — Ambiguous Metal Impact

Input:

```text
Filename:
REC_0384.wav

Audio:
short metallic impact with mechanical resonance
```

Output:

```json
{
  "status": "uncertain",
  "display_name": "Short Metallic Mechanical Impact",
  "category": "Unclassified",
  "subcategory": null,
  "tags": ["metal", "mechanical", "impact", "short"],
  "description": "Short metallic mechanical impact; the exact source is unclear.",
  "confidence": 0.47,
  "needs_review": true,
  "alternative_categories": [
    "Impacts/Metal",
    "Machines/Mechanical",
    "Foley/Doors"
  ]
}
```

---

## Example 4 — Filename Conflict

Input:

```text
Filename:
door.wav

Folder:
Doors

Audio:
clear footsteps on concrete
```

Output:

```json
{
  "status": "recognized",
  "display_name": "Concrete Footsteps",
  "category": "Foley/Footsteps",
  "subcategory": "Concrete",
  "tags": ["concrete", "walking", "hard", "indoor"],
  "description": "Footsteps on a hard concrete surface.",
  "confidence": 0.86,
  "needs_review": true,
  "alternative_categories": []
}
```

Reason for review:

```text
audio and filename context disagree
```

---

## Example 5 — Unknown

Input:

```text
Audio:
brief processed sound with no reliable source identity
```

Output:

```json
{
  "status": "unknown",
  "display_name": null,
  "category": "Unclassified",
  "subcategory": null,
  "tags": [],
  "description": null,
  "confidence": 0.19,
  "needs_review": true,
  "alternative_categories": []
}
```

---

## Example 6 — Clear Properties, Unknown Object

Input:

```text
Audio:
small ceramic object taps a hard surface
exact object unclear
```

Output:

```json
{
  "status": "suggested",
  "display_name": "Small Ceramic Object Tap",
  "category": "Foley/Props",
  "subcategory": null,
  "tags": ["ceramic", "small", "tap", "hard", "short"],
  "description": "Small ceramic object tapping a hard surface.",
  "confidence": 0.72,
  "needs_review": true,
  "alternative_categories": [
    "Foley/Surface Interaction"
  ]
}
```
