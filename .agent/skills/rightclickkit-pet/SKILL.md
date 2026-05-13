---
name: rightclickkit-pet
description: Create, install, switch, or review RightClickKit companion pet assets. Use when modifying the floating sprite, integrating hatch-pet outputs, changing pet manifests, or making the pet dynamically replaceable without hardcoding one bundled spritesheet.
---

# RightClickKit Pet

## Runtime Contract

RightClickKit pets use the Codex/hatch-pet atlas contract:

- `spritesheet.webp`
- 8 columns x 9 rows
- 192 x 208 px cells
- transparent background
- state rows consumed by `PetOverlayView`

Do not change renderer dimensions unless the Swift animation table and every
existing pet package are migrated together.

## Package Shape

Installed user pets live under:

```text
~/.rightclickkit/pets/<pet-id>/
  pet.json
  spritesheet.webp
```

`pet.json` should include at least:

```json
{
  "id": "my-pet",
  "name": "My Pet",
  "displayName": "My Pet",
  "description": "Short user-facing description.",
  "spritesheet": "spritesheet.webp"
}
```

The current selected pet is stored in:

```text
~/.rightclickkit/current-pet.txt
```

If no current pet is selected, the Agent defaults to bundled `rck-dimo`.
Bundled Fireball remains an explicit fallback/alternate pet, not the default.

Bundled pet resources are copied into the app and Agent helper bundles by
`scripts/install.sh` and `scripts/preview-app.sh`. Keep bundled default assets
under:

```text
assets/pets/<pet-id>/<pet-id>-spritesheet.webp
```

Current built-ins:

- `rck-dimo`: default RightClickKit companion.
- `fireball`: legacy fallback and explicit alternate.

## CLI Flow

Use the project CLI for user pet operations:

```zsh
rck pet install /absolute/path/to/pet-folder
rck pet list
rck pet use <pet-id>
rck pet current
rck pet use default
rck pet use rck-dimo
rck pet use fireball
```

After switching pets, the Agent reloads the spritesheet on the next animation
frame request. If the user wants immediate visual confirmation, restart the
Agent through install or quit/reopen it.

## Creating Pets

For new visual assets, compose this skill with `$hatch-pet`:

1. Use `$hatch-pet` to generate and QA the pet package.
2. Confirm `final/validation.json`, `qa/contact-sheet.png`, and preview videos
   are acceptable. If `ffmpeg` is missing, preview videos may fail while the
   validated spritesheet and contact sheet still succeed; record that limitation
   instead of blocking a validated pet.
3. Install the resulting package with `rck pet install <package-folder>`.
4. Switch with `rck pet use <pet-id>`.
5. Run build/smoke/install when code or scripts changed.

Do not hand-draw, tile, or fabricate pet rows in local scripts as a substitute
for `$hatch-pet` image generation. Deterministic scripts may only copy, validate,
package, or install already generated pet assets.

### Image Generation Lessons

Prefer `$hatch-pet` for full pet creation, and let it delegate visuals to
`$imagegen`. In this project, `$imagegen` may route through the current Codex
provider fallback when the built-in `image_gen` tool is not injected. That path
has worked against the configured `/v1/images/generations` and
`/v1/images/edits` endpoints, but it can be slow and may return transient 429
or 502 responses.

Operational rules from the RCK Dimo run:

- Generate and record the base image first.
- For row strips, attach the row layout guide, `references/canonical-base.png`,
  and `decoded/base.png`.
- Use `/v1/images/edits` for grounded row generation when using the Codex
  provider fallback, because row jobs require input images.
- Record each successful row immediately with `record_imagegen_result.py` so a
  later provider failure does not lose already completed work.
- Treat 429 and 502 as transient provider pressure. Retry with backoff and keep
  concurrency low.
- Do not rely on subagents for long image-generation requests unless explicitly
  needed; streamed subagent runs can disconnect before returning the generated
  source path. If the user allows it, main-thread sequential row generation is
  the most reliable path.
- `running-left` may be derived from `running-right` only when visual inspection
  confirms there is no text, logo, handed prop, or direction-specific asymmetric
  detail.

### Promoting A Pet To Built-In Default

To make a generated pet the default RCK companion:

1. Copy the validated `final/spritesheet.webp` into `assets/pets/<pet-id>/`.
2. Update `PetOverlayView` bundled candidate resolution so no selection defaults
   to that pet and `fireball` remains explicitly selectable.
3. Update `rck pet list/current/use` so `default` resolves to the new default
   pet id and built-ins do not duplicate user-installed pets.
4. Update both `scripts/install.sh` and `scripts/preview-app.sh` to copy the
   bundled spritesheet into the main app Resources and the Agent helper
   Resources.
5. Run build, smoke test, install, then verify `rck pet current`, `rck pet list`,
   and the Agent process.

## Code Boundaries

- `Sources/RightClickKitAgent/PetOverlayView.swift`: sprite playback and atlas
  loading. Keep asset selection data-driven.
- `Sources/rck/main.swift`: `rck pet` install/list/use/current commands.
- `Sources/RightClickKitCore/Paths.swift`: support paths for pets and current
  selection.
- `scripts/install.sh` and `scripts/preview-app.sh`: bundle default/fallback
  assets into the main app and Agent helper.

Avoid reintroducing hardcoded one-off pet names in the renderer. Built-in
pet ids should be centralized in the bundle-candidate/default-selection code.
Fireball is only the fallback/alternate.

## Ambient Behavior

The Agent pet may play short self-directed reactions while idle. Keep this layer
subordinate to real product state:

- Finder/action activity state wins over ambient reactions.
- Drag, hover, and click interactions interrupt ambient reactions immediately.
- Ambient reactions should only run when `ActivitySummary.mascotState == .idle`.
- Do not use failure/error rows for ambient play; reserve those for real
  activity failures.
- Keep reaction durations short, then return to activity-derived state so the
  parent SwiftUI state does not get stuck in a non-idle mode after the sprite
  playback has visually looped back to idle.

## Validation

For code changes, run:

```zsh
rtk swift build --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm
rtk ./scripts/smoke-test.sh
rtk ./scripts/install.sh
```

For asset-only changes, at minimum run:

```zsh
rtk rck pet install <pet-folder>
rtk rck pet use <pet-id>
rtk rck pet list
```

For default bundled pet changes, also verify:

```zsh
rtk rck pet use default
rtk rck pet current
rtk rck pet use fireball
rtk rck pet list
```
