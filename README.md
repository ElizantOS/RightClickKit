# RightClickKit

RightClickKit is a native macOS toolkit for building personal productivity
actions around right-click workflows, local scans, and a small status-bar agent.

The project started as a Finder Quick Action manager, then grew into a local
companion app:

- manage Finder right-click actions from versioned service files;
- open native Directory Tree and Storage Analysis windows;
- keep a menu bar Agent alive for notifications, activity, and the companion pet;
- let local AI/Codex workflows create or switch pet assets through skills.

The guiding product rule is:

```text
The user configures intent, RightClickKit writes and runs the machinery.
```

## What Is Included

- `RightClickKitApp`: main SwiftUI configuration app.
- `RightClickKitAgent`: accessory Agent with real `NSStatusItem`, activity
  notifications, and the floating companion pet.
- `RightClickKitStorageView`: native storage analyzer with progressive scanning
  and a growing sunburst/rose chart.
- `RightClickKitTreeView`: native directory tree viewer with fast tree text,
  outline navigation, inspector, and export flows.
- `rck`: CLI helper used by Finder workflows, reports, notifications, and pet
  management.

The default bundled pet is `rck-dimo`, a Dimo-inspired RightClickKit companion.
Fireball remains available as an alternate built-in pet.

## Install

```bash
./scripts/install.sh
```

This builds the Swift package and installs:

- CLI: `~/.rightclickkit/bin/rck`
- App: `~/Applications/RightClickKit.app`
- Agent helper: `~/Applications/RightClickKit.app/Contents/Helpers/RightClickKitAgent.app`
- Login Agent: `~/Library/LaunchAgents/com.elizantos.RightClickKit.agent.plist`
- Finder workflows: `~/Library/Services/*.workflow`

Then use Finder:

```text
Right-click a file or folder -> Quick Actions/Services -> Open in Code
Right-click a folder -> Quick Actions/Services -> Show Directory Tree
Right-click a folder -> Quick Actions/Services -> Analyze Storage
```

You can also launch the app directly:

```bash
open ~/Applications/RightClickKit.app
```

## CLI

```bash
~/.rightclickkit/bin/rck install --repo "$PWD"
~/.rightclickkit/bin/rck uninstall
~/.rightclickkit/bin/rck list
~/.rightclickkit/bin/rck run open-in-code /path/to/folder
~/.rightclickkit/bin/rck logs open-in-code
~/.rightclickkit/bin/rck report directory-tree [--no-open] /path/to/folder
~/.rightclickkit/bin/rck report storage-analysis [--no-open] /path/to/folder
~/.rightclickkit/bin/rck notify "Build done" --status done --level success
~/.rightclickkit/bin/rck notify list
~/.rightclickkit/bin/rck pet list
~/.rightclickkit/bin/rck pet use default
~/.rightclickkit/bin/rck pet use fireball
~/.rightclickkit/bin/rck pet install /absolute/path/to/pet-folder
```

`storage-analysis` opens the native Storage Analysis window immediately and
scans in the background. `directory-tree` opens the native Directory Tree window.
With `--no-open`, both commands write local report data instead of launching UI.

## Services

Services live under:

```text
services/<service-id>/service.yaml
services/<service-id>/action.zsh
```

Supported action types:

- `openWithApp`
- `openWithCodeEditor`
- `openTerminalHere`
- `copyPaths`
- `runCommand`
- `showDirectoryTree`
- `analyzeStorage`

Old services without `mode`/`action` still load as `rawScript`.

At runtime, generated workflows call:

```text
Finder Quick Action -> generated .workflow -> ~/.rightclickkit/bin/rck run <service-id> "$@"
```

Scripts receive:

- `"$@"`: selected Finder paths
- `RCK_SERVICE_ID`: the service id
- `RCK_ITEMS_FILE`: newline-delimited selected paths
- `RCK_HELPER`: the `rck` helper executable path
- `RCK_REPOSITORY_ROOT`: configured repository root

## Pets

RightClickKit pets use the Codex/hatch-pet atlas contract:

- `1536x1872` WebP atlas
- 8 columns x 9 rows
- 192 x 208 px cells
- transparent background

User-installed pets live under:

```text
~/.rightclickkit/pets/<pet-id>/
  pet.json
  spritesheet.webp
```

Bundled pets live under `assets/pets/` and are copied into both the main app and
Agent helper bundles during install. Use `.agent/skills/rightclickkit-pet/` when
creating or promoting pet assets so the `hatch-pet` and `$imagegen` workflow
stays consistent.

## Development

```bash
swift build --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm
./scripts/smoke-test.sh
./scripts/install.sh
```

Logs are written to:

```text
~/Library/Logs/RightClickKit/<service-id>.log
~/Library/Logs/RightClickKit/<service-id>.launcher.log
~/Library/Logs/RightClickKit/agent-launchd.out.log
~/Library/Logs/RightClickKit/agent-launchd.err.log
```

## More Notes

- `HANDOFF.md`: current architecture, runtime flows, and next steps.
- `STORAGE_ANALYSIS_EXPERIENCE.md`: storage/tree performance lessons.
- `RIGHTCLICKKIT_EXPERIENCE.md`: project-wide implementation lessons,
  including Agent, pet, image generation, and skill workflow notes.
