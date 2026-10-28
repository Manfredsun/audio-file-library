# Tagging Rules

## Purpose

Tags provide searchable characteristics that should not be encoded into category names.

Use canonical vocabulary consistently.

---

# 1. General Rules

A good tag should be:

- audible or contextually reliable
- useful for search
- canonical
- concise
- non-duplicative

Avoid:

- speculative brands
- speculative locations
- arbitrary synonyms
- sentence-like tags
- near-duplicate tags

---

# 2. Material

Preferred examples:

```text
metal
wood
glass
plastic
ceramic
paper
fabric
rubber
stone
concrete
leather
water
```

Do not create both:

```text
metal
metallic
```

Use `metal`.

---

# 3. Action

Preferred examples:

```text
hit
slam
drop
scrape
slide
open
close
shake
roll
drag
rattle
break
tap
knock
grab
pickup
set-down
rustle
creak
```

---

# 4. Character

Preferred:

```text
heavy
light
soft
hard
sharp
dull
bright
dark
clean
dirty
thin
thick
hollow
solid
resonant
dry
```

Only use when audibly meaningful.

---

# 5. Environment

Preferred:

```text
indoor
outdoor
close
distant
small-room
large-room
reverberant
dry
```

Avoid guessing exact physical locations.

---

# 6. Temporal

Preferred:

```text
short
medium
long
single
repeating
sustained
slow
fast
```

---

# 7. Movement

Useful examples:

```text
walking
running
shuffling
rolling
sliding
dragging
swinging
```

---

# 8. Mechanical Qualities

Examples:

```text
mechanical
motorized
electronic
industrial
loose
rattling
```

Use only when supported.

---

# 9. Tag Count

Do not maximize tag count.

Target:

```text
3–8 useful tags
```

Fewer is acceptable.

Unknown sounds may have zero tags.

---

# 10. Synonym Control

Prefer one canonical term.

Examples:

```text
close
NOT closing + shut + closed

slam
NOT slam + bang-close + hard-close

metal
NOT metallic + steel-like
```

Use multiple terms only when they represent meaningfully different searchable dimensions.

---

# 11. Unknown Source

If source is unknown but qualities are clear:

Allowed:

```text
metal
impact
short
mechanical
```

Not allowed:

```text
door
locker
cabinet
```

unless supported.

---

# 12. New Tags

Runtime Organizer may suggest a non-canonical tag only when:

- it adds real search value
- no existing canonical tag captures it
- it is clearly supported

Such tags should be marked for vocabulary review by the application or development tooling rather than silently becoming permanent canonical vocabulary.
