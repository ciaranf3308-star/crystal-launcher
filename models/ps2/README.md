# models/ps2 — PlayStation 2 physical-media set (PENDING)

The POC carousel currently uses primitive meshes (BoxMesh case + CylinderMesh
disc) skinned with the real per-game textures. This directory will hold the
authored PS2 model set:

- `case.glb` — DVD keep-case, front face UV-mapped for `front.png`,
  back face for `back.png`, spine for `spine.png`. Pivot at case center-bottom
  (sits on the shelf plane, y=0).
- `disc.glb` — DVD disc, top face UV-mapped for `media.png`
  (physicalmedia slot). Pivot at disc center.
- `tray.glb` (optional) — open-case state for the inspect view.

Conventions (so one GDScript rig fits every system later):
- Units are meters. Case height ~0.19 m (real DVD case).
- Origin at the bottom-center of the object (resting on y=0).
- Front face points +Z.
- Materials use a single `ALBEDO_TEX` shader parameter the launcher sets
  per game from the media slots.

Other systems follow the same pattern: gba/gb/gbc/n64 → cartridge models,
psx → jewel case + disc, gamecube → case + mini-disc.
