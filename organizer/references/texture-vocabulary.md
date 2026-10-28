# Texture Vocabulary

## Purpose

Controlled whitelist for the `texture` field: **what the thing making the sound is
made of.** Metal, wood, glass, plastic, cloth — plus a small set of surface and
hardness terms for when no material word appears.

Texture is not a category and not a style. Category records what the sound *is*
(`Foley / Doors`), style records the genre the material was made for (`Lo-Fi`),
texture records the **material**. They are independent fields so that
"a metal door" and "everything metal" are each a single filter.

## Where texture comes from

Texture is **read from the path, never inferred from the audio.**

This is not a limitation we are working around — it is the honest position.
There is no reliable acoustic boundary between plastic and wood. A system that
claims to hear one is doing exactly what D-013 documented: producing a confident
label with nothing behind it. Metal reverb was heard as "a rooster crowing".

Material is, however, written into filenames constantly, because the people who
recorded these sounds needed to find them again:

```text
Bare_Feet_Metal_SLOW_MED_WALK.wav
Plastic_Creak_Bottle_File_2_Takes_7.wav
金屬撞擊聲.wav
木門開關.wav
```

That is the evidence, and the user can verify it by opening Finder.

When no texture term appears in the path, the texture is **left empty.**
Not guessed, not filled with a placeholder.

## Matching rules

1. Match on **word boundaries** for English, never raw substrings.
   `tin` must not match inside `painting`, `ice` must not match inside `service`.
2. Chinese is matched as a **substring**, because Chinese has no word boundaries
   (same rule as the category reader, D-023).
3. **Material beats surface.** If the path says both `soft` and `cloth`,
   the texture is Cloth — the material is the more specific fact.
   Surface and hardness terms are a fallback, not a competitor.
4. Folder evidence outranks filename evidence.

## The genre collision

`metal` and `rock` are material words **and** music genres. The style reader
already gates them: they only count as a style inside `Drums/` or `Instruments/`
(D-020). The texture reader takes the mirror of that gate — inside those
production categories, `metal` and `rock` are read as genre, and the texture is
**left empty** rather than claimed by both fields.

This loses a little real information (`kick_metal` might genuinely mean a metallic
kick) and that is the intended trade: one word cannot be evidence for two
different fields at once, and a blank is recoverable where a wrong label is not.

---

# 1. Textures

```text
Metal
Wood
Glass
Plastic
Paper
Cardboard
Cloth
Leather
Rubber
Stone
Concrete
Ceramic
Water
Sand
Gravel
Dirt
Snow
Ice
Foam
Rope
Wire
Bone
Soft
Hard
Wet
Dry
Rough
Smooth
Hollow
```

---

# 2. Aliases

Left side is matched case-insensitively, on word boundaries for English
and as a substring for Chinese.

```text
metal -> Metal
metallic -> Metal
steel -> Metal
iron -> Metal
aluminium -> Metal
aluminum -> Metal
tin -> Metal
brass -> Metal
copper -> Metal
chain -> Metal
金屬 -> Metal
金属 -> Metal
鐵 -> Metal
铁 -> Metal
鋼 -> Metal
钢 -> Metal
wood -> Wood
wooden -> Wood
timber -> Wood
plank -> Wood
木 -> Wood
木頭 -> Wood
木头 -> Wood
木質 -> Wood
glass -> Glass
bottle -> Glass
玻璃 -> Glass
plastic -> Plastic
vinyl -> Plastic
塑膠 -> Plastic
塑料 -> Plastic
paper -> Paper
newspaper -> Paper
紙 -> Paper
纸 -> Paper
cardboard -> Cardboard
carton -> Cardboard
紙板 -> Cardboard
纸板 -> Cardboard
cloth -> Cloth
fabric -> Cloth
textile -> Cloth
canvas -> Cloth
denim -> Cloth
布 -> Cloth
織物 -> Cloth
织物 -> Cloth
leather -> Leather
皮革 -> Leather
rubber -> Rubber
橡膠 -> Rubber
橡胶 -> Rubber
stone -> Stone
rock -> Stone
pebble -> Stone
石 -> Stone
石頭 -> Stone
石头 -> Stone
concrete -> Concrete
cement -> Concrete
混凝土 -> Concrete
水泥 -> Concrete
ceramic -> Ceramic
porcelain -> Ceramic
陶瓷 -> Ceramic
water -> Water
liquid -> Water
splash -> Water
水 -> Water
液體 -> Water
液体 -> Water
sand -> Sand
沙 -> Sand
gravel -> Gravel
碎石 -> Gravel
dirt -> Dirt
soil -> Dirt
mud -> Dirt
泥 -> Dirt
土 -> Dirt
snow -> Snow
雪 -> Snow
ice -> Ice
冰 -> Ice
foam -> Foam
sponge -> Foam
泡沫 -> Foam
海綿 -> Foam
rope -> Rope
繩 -> Rope
绳 -> Rope
wire -> Wire
cable -> Wire
電線 -> Wire
电线 -> Wire
bone -> Bone
骨 -> Bone
soft -> Soft
柔軟 -> Soft
柔软 -> Soft
hard -> Hard
堅硬 -> Hard
坚硬 -> Hard
wet -> Wet
濕 -> Wet
湿 -> Wet
dry -> Dry
乾 -> Dry
干 -> Dry
rough -> Rough
粗糙 -> Rough
smooth -> Smooth
光滑 -> Smooth
hollow -> Hollow
中空 -> Hollow
```

---

# 3. Surface Terms

Fallback only. A material term anywhere in the path wins over these.

```text
Soft
Hard
Wet
Dry
Rough
Smooth
Hollow
```

---

# 4. Genre-Colliding Aliases

Also music genre names. Inside `Drums/` or `Instruments/` these are read as
genre by the style reader, and the texture is left empty (see above).

```text
metal
rock
```
