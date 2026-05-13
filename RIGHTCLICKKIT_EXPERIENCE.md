# RightClickKit Project Experience

This document records project-wide implementation lessons that should inform
future RightClickKit work. Storage-specific performance notes remain in
`STORAGE_ANALYSIS_EXPERIENCE.md`.

Last updated: 2026-05-13

## Product Lessons

RightClickKit became useful when it stopped being "a shell script editor" and
became a native intent configurator.

Good defaults:

- expose choices, toggles, pickers, and focused commands;
- keep shell/YAML/Automator as generated implementation detail;
- make background activity visible and controllable;
- prefer native macOS windows, menus, status items, and materials;
- keep logs, but turn failures into short user-facing summaries.

Avoid:

- fake system UI such as floating status-bar replacements;
- hidden background loops with no progress indicator;
- putting expensive I/O on hover or pointer movement;
- claiming "complete" while work is still queued;
- adding a second control center through the pet overlay.

## Agent Lessons

The Agent should have exactly two visible entry surfaces:

- macOS system status bar item (`NSStatusItem`);
- the floating companion pet.

The status bar is the control surface. The pet is an ambient state/reminder
surface. Do not duplicate all controls into the pet.

Stability decisions that worked:

- Keep `StatusBarController` AppKit-based.
- Use a standard square status item with template SF Symbol.
- Avoid `autosaveName` on the status item because stale restored placement can
  make debugging confusing.
- Create status item before showing the pet.
- Keep experimental bridges off by default.
- Route user-visible activity through `ActivityStore` and `rck notify`.

The pet badge/popover should remain lightweight:

- badge opens activity history;
- mark-read controls close when no unread items remain;
- trash clears history;
- popover must scroll within its own bounds, not leak wheel events to the app
  behind it.

## Pet Lessons

RightClickKit pets use the Codex/hatch-pet atlas contract:

- 8 columns x 9 rows;
- 192 x 208 px cells;
- `1536x1872` transparent-capable WebP atlas.

Current default:

```text
assets/pets/rck-dimo/rck-dimo-spritesheet.webp
```

Important implementation choices:

- `rck-dimo` is the default bundled pet.
- `fireball` remains an explicit built-in alternate.
- `rck pet use default` clears `current-pet.txt` and resolves to `rck-dimo`.
- User-installed custom pets live in `~/.rightclickkit/pets/<pet-id>/`.
- Built-in pet ids should prefer bundle resources; custom ids can resolve from
  the user pet directory.

RCK Dimo generation lessons:

- Generate the base first and record it with `record_imagegen_result.py`.
- Row strips must use input images: layout guide, canonical base, approved base.
- Long image generation inside subagents can disconnect before returning source
  paths. If the user allows it, main-thread sequential generation is more
  reliable.
- Record each successful row immediately, so transient provider failures do not
  lose completed work.
- Treat 429 and 502 from the image provider as transient pressure; retry with
  backoff and low concurrency.
- `running-left` can be derived from `running-right` only after visual review
  confirms there is no text, logo, handed prop, or direction-specific asymmetry.
- Missing `ffmpeg` should not block a validated spritesheet/contact sheet.

Future pet behavior should add a `PetMoodController`:

```text
failed > waiting > running > review > short success/hello animations > idle
```

Suggested state mapping:

- `idle`: no work and no unread activity.
- `running`: background task active, scan running, action in progress.
- `review`: result is ready or user attention is needed.
- `waiting`: permission/user/external app wait.
- `failed`: recent error.
- `jumping`: short success/completion reaction.
- `waving`: launch, hover/click greeting, lightweight acknowledgement.
- `running-right` / `running-left`: pointer-following or directional movement.

## Image Generation Lessons

The `$imagegen` skill can be present even when the built-in `image_gen` tool is
not injected into a session. In that case, the modified skill now tries the
current Codex provider Images API before giving up.

The working local path was:

```text
~/.codex/config.toml -> model_provider -> base_url
<base_url>/v1/images/generations
<base_url>/v1/images/edits
```

Auth may be stored in `~/.codex/auth.json` even when `OPENAI_API_KEY` is not
exported.

Operational rule:

- Do not print tokens.
- For probe requests, use low quality and a tiny prompt.
- For grounded pet row strips, use edits with attached images.
- Save original generated sources under `~/.codex/generated_images/...` before
  recording them into hatch-pet.

## Tree And Storage Lessons

Tree and Storage both improved after the same principle was applied:

```text
Do expensive file-system work in the background; publish UI updates on a sane
heartbeat; make progress visible.
```

Tree-specific:

- Text tree output should be virtualized or plain text where possible.
- Do not impose arbitrary fixed limits when the user expects adjustable depth.
- Left outline navigation can become the bottleneck even when text rendering is
  fast; keep disclosure/loading local to clicked paths.
- Avoid wrapping long tree text in compact UI cells; horizontal scrolling is
  better than layout churn.

Storage-specific:

- Hover must never start `du`.
- Click should update selection immediately, then scan asynchronously.
- Cache expanded nodes so going back does not re-run `du`.
- Complete only means all active and queued work is done.
- Background scans need visible active/queued indicators.

## Documentation Lessons

Keep documentation split by audience:

- `README.md`: what the project is, how to install, common commands.
- `HANDOFF.md`: current architecture and what the next engineer/agent must know.
- `STORAGE_ANALYSIS_EXPERIENCE.md`: detailed Storage/Tree scanner lessons.
- `RIGHTCLICKKIT_EXPERIENCE.md`: cross-project lessons and agent/pet experience.
- `.agent/skills/*`: executable local knowledge for future implementation.

Do not let handoff files become stale development diaries. Move durable lessons
to experience docs, and keep the handoff focused on the current shape of the
system.
