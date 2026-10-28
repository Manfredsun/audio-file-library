# Organizer Taxonomy

## Purpose

This is the controlled category taxonomy for the Foley Sound Library Manager.

Runtime agents should prefer these categories.

Do not create new permanent categories automatically.

---

# 1. Top-Level Categories

```text
Foley
Ambience
Impacts
Vehicles
Machines
Human
Animals
Nature
UI
Musical
Drums
Instruments
Designed
Other
Unclassified
```

---

# 2. Foley

```text
Foley
├── Footsteps
├── Doors
├── Cloth
├── Body
├── Props
├── Handling
├── Movement
├── Furniture
├── Containers
└── Surface Interaction
```

---

## Foley / Footsteps

Use for human-like foot movement where footsteps are the dominant event.

Subcategory examples:

```text
Concrete
Wood
Metal
Gravel
Dirt
Grass
Carpet
Tile
Water
Snow
Stairs
```

Prefer surface as a tag when exact hierarchy becomes too deep.

---

## Foley / Doors

Use for:

```text
open
close
slam
creak
rattle
latch
handle
hinge
```

Possible subcategories:

```text
Metal Door
Wood Door
Glass Door
Sliding Door
Cabinet Door
Locker Door
Gate
```

---

## Foley / Cloth

Use for:

```text
cloth movement
fabric handling
clothing rustle
folding
dragging fabric
```

---

## Foley / Body

Use for non-speech body sounds and body movement Foley.

Examples:

```text
body movement
hand clap
finger snap
skin contact
body fall
```

Avoid placing clear footsteps here.

---

## Foley / Props

Use for small or medium physical objects manipulated as Foley.

Examples:

```text
keys
cups
books
tools
bags
small household objects
```

Use more specific categories when clearly available.

---

## Foley / Handling

Use when the defining event is manipulation rather than object identity.

Examples:

```text
pickup
set down
grab
place
handle
shuffle
```

---

## Foley / Movement

Use for general movement Foley that is not clearly footsteps, cloth, or a specific prop event.

---

## Foley / Furniture

Examples:

```text
chair
table
drawer
desk
sofa
cabinet
```

---

## Foley / Containers

Examples:

```text
box
bottle
jar
can
bag
case
```

---

## Foley / Surface Interaction

Use for:

```text
scrape
rub
drag
brush
tap
knock
contact
```

when the surface interaction is the primary identity.

---

# 3. Ambience

Use for environmental beds and continuous spaces.

Examples:

```text
Interior
Exterior
Urban
Rural
Room Tone
Crowd
Traffic
Industrial
Weather
Nature Ambience
```

---

# 4. Impacts

Use when the dominant event is an impact and the source object is not better represented as a Foley category.

Suggested:

```text
Impacts/Metal
Impacts/Wood
Impacts/Glass
Impacts/Plastic
Impacts/Stone
Impacts/Body
Impacts/Generic
```

---

# 5. Vehicles

Examples:

```text
Car
Motorcycle
Truck
Bus
Train
Aircraft
Boat
Bicycle
```

Possible events:

```text
engine
passby
start
stop
door
horn
interior
```

Do not create overly deep permanent category trees for every event. Use tags.

---

# 6. Machines

Examples:

```text
Mechanical
Motor
Fan
Tool
Appliance
Industrial Machine
Electronics
```

---

# 7. Human

Use for human-produced non-musical sound not better categorized under Foley.

Examples:

```text
Breath
Cough
Sneeze
Cheer
Laugh
Cry
Shout
Murmur
Crowd Voice
```

Speech content transcription is outside this taxonomy.

---

# 8. Animals

Examples:

```text
Dog
Cat
Bird
Horse
Insect
Farm Animal
Wild Animal
Unknown Animal
```

---

# 9. Nature

Examples:

```text
Wind
Rain
Thunder
Water
Fire
Leaves
Forest
Ocean
River
```

---

# 10. UI

Use for designed interface / notification / button sounds.

Examples:

```text
Click
Notification
Alert
Confirm
Error
Transition
Digital Tone
```

---

# 11. Musical

Use for musical or tonal sounds that are not ordinary Foley.

Examples:

```text
Instrument
Tone
Drone
Hit
Chord
Rhythmic
```

---

# 12. Drums

Use for drum and percussion material from music production libraries:
sample packs, drum machines, breaks.

Category is the **instrument role**. Musical style (Lo-Fi, Boom Bap, Tech House)
is a separate field, not a category — see `style-vocabulary.md`.
A kick is a kick whichever genre it was made for, and you want to be able to ask
both "a Boom Bap kick" and "everything Boom Bap".

```text
Kick
Snare
Clap
Hi-Hat
Cymbal
Tom
Percussion
808
Drum Loop
Break
Fill
```

`Drums / Break` is for sampled full-kit breakbeats; `Drums / Drum Loop` is for
produced or programmed loops. When unsure, prefer `Drum Loop`.

Prefer `Impacts` for recorded real-world collisions that are not musical material.

---

# 13. Instruments

Use for pitched and vocal material from music production libraries.

```text
Bass
Keys
Guitar
Synth
Brass
Strings
Vocal
Chord
Lead
Pad
Melodic Loop
```

`808` lives under `Drums`, not `Instruments / Bass`: it is used as a kick.

Prefer `Musical` for recordings of acoustic instrument performance that are not
production sample material.

---

# 14. Designed

Use for sounds that were synthesised or heavily processed for production use,
where there is no real-world source to name.

These dominate cinematic and trailer libraries and do not fit Foley, Ambience or Impacts:
a riser has no physical object, a whoosh is not a real object moving through air.

Examples:

```text
Whoosh
Riser
Downer
Impact Hit
Transition
Stinger
Texture
Drone
Sweep
Glitch
```

Prefer `Impacts` when the sound is a recorded real-world collision.
Prefer `Designed / Impact Hit` when it is a produced cinematic hit.

---

# 15. Other

Use when a sound is recognizable but does not reasonably fit existing categories.

Use sparingly.

---

# 16. Unclassified

Use when the source cannot be reliably mapped.

`Unclassified` is not a failure.

It is a legitimate review state.

---

# 17. Taxonomy Rule

Prefer:

```text
stable categories
+
rich tags
```

over:

```text
hundreds of hyper-specific category paths
```
