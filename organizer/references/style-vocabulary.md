# Style Vocabulary

## Purpose

Controlled whitelist of musical styles for the `style` field.

Style is **not** a category. Category records the instrument role (`Drums / Kick`);
style records the genre the material was made for. They are independent fields so
that both "a Boom Bap kick" and "everything Boom Bap" are a single filter.

## Where style comes from

Style is **read from the path, never inferred from the audio**.

A kick is a kick. There is no reliable acoustic boundary between a Boom Bap kick
and a Tech House kick, and any system claiming to hear one is doing what D-013
documented. Sample packs name their genre in the folder — that is the evidence,
and the user can verify it by opening Finder.

When no style term appears in the path, the style is **left empty**. Not guessed,
not filled with a placeholder. A wrong style label is worse than none, because
after the fact you cannot tell which labels were read and which were invented.

## Matching rules

1. Match on **word boundaries**, never raw substrings. `pop` must not match
   inside `City Pop`, and `house` must not match inside `Tech House`.
2. **Longer phrases win.** `tech house` is checked before `house`;
   `city pop` before `pop`; `future bass` before `bass`.
3. Folder evidence outranks filename evidence, same as category evidence.

---

# 1. Styles

```text
Lo-Fi
Boom Bap
Hip Hop
Trap
Drill
Phonk
R&B
Soul
Funk
Disco
Jazz
House
Tech House
Deep House
Techno
Trance
Dubstep
Drum & Bass
Jungle
Garage
EDM
Future Bass
Synthwave
Chiptune
Cyberpunk
City Pop
Kawaii
Ambient
Cinematic
Rock
Metal
Pop
Latin
Afrobeat
Reggaeton
Reggae
Country
World
```

---

# 2. Aliases

Vendor folder names, mapped to the canonical style above.
Left side is matched case-insensitively on word boundaries.

```text
lofi -> Lo-Fi
lo-fi -> Lo-Fi
lo fi -> Lo-Fi
boom bap -> Boom Bap
boombap -> Boom Bap
hip hop -> Hip Hop
hiphop -> Hip Hop
rnb -> R&B
r&b -> R&B
tech house -> Tech House
deep house -> Deep House
drum and bass -> Drum & Bass
drum & bass -> Drum & Bass
dnb -> Drum & Bass
d&b -> Drum & Bass
future bass -> Future Bass
synth wave -> Synthwave
synthwave -> Synthwave
retrowave -> Synthwave
chiptune -> Chiptune
8 bit -> Chiptune
8-bit -> Chiptune
cyberpunk -> Cyberpunk
city pop -> City Pop
citypop -> City Pop
kawaii -> Kawaii
afrobeat -> Afrobeat
afrobeats -> Afrobeat
reggaeton -> Reggaeton
trap -> Trap
drill -> Drill
phonk -> Phonk
soul -> Soul
funk -> Funk
funky -> Funk
disco -> Disco
jazz -> Jazz
jazzy -> Jazz
house -> House
techno -> Techno
trance -> Trance
dubstep -> Dubstep
jungle -> Jungle
garage -> Garage
edm -> EDM
ambient -> Ambient
cinematic -> Cinematic
trailer -> Cinematic
rock -> Rock
metal -> Metal
pop -> Pop
latin -> Latin
reggae -> Reggae
country -> Country
world -> World
```

---

# 3. Ambiguous Aliases

These words are genre names **and** ordinary sound-description words.
They only count as a style when the sound is music-production material —
that is, when its category is under `Drums/` or `Instruments/`.

The parser reads the first block below, so the word list comes first.

```text
metal
rock
pop
house
jungle
country
world
garage
soul
ambient
```

Without that gate they produce confident nonsense. Real cases from the library:

- `Ultimate Bare Feet Expansion/Bare_Feet_Metal 1_SLOW_MED_WALK.wav` → **Metal**
  （金屬地板上的赤腳腳步聲）
- `Surround The Rain/Rain On Concrete, Drips On Metal.wav` → **Metal**
- `Rock The Speakerbox - Melee/BASEBALL BAT Aluminum Hit Head.wav` → **Rock**
  （Rock The Speakerbox 是廠商名字）
- `Coll Anderson - House Library Add Ons/EFX INT Door Bang.wav` → **House**
  （房子的音效庫）

None of those are music.

The gate is per-word, not per-style: `tech house` and `deep house` stay
unconditional, because nobody names a door recording "tech house".

---

# 4. Style Rule

One style per sound. A pack named `Lofi Hip Hop` matches both `lofi` and
`hip hop`; the longer, more specific phrase wins, and where two equally specific
phrases both match, the first listed in section 1 wins.

Do not create new styles automatically. An unmatched pack is an unknown style,
which is a legitimate state — see `confidence-rules.md`.
