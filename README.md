# esx_prisonerconvoy (v1.4.1)

Stable ESX prisoner convoy with a configurable AI bus driver and customizable pathing.

## Features
- Spawns AI driver + prison bus near chosen station
- Optional **custom route** to prison via `Config.Routes.ToPrison.Nodes`
- Prison checkpoint → drop-off → waiting area
- Guard escort → `PrisonerPickUp` → auto-jail to `PrisonerJail` with on-screen countdown
- Auto-release to `PrisonReleasePoint`
- Anti-stall, segmented navigation, `/convoy stuck` teleport/nudge
- Minimal officer helper for `/convoy jail [min]` (nearest player within 6m)

## Commands
- `/convoy start` — choose nearest station, spawn bus/driver
- `/convoy load` — load nearest eligible prisoner (or self if allowed)
- `/convoy loadme` — load yourself
- `/convoy stuck` — teleport bus to nearest road and re-prime driver
- `/convoy jail [minutes]` — quick jail nearest player (6m) with built-in timer
- `/convoy stop` — abort & cleanup

## Key Config
- **Driving**: `Config.DriveStyle = 786603`, `Config.DriveSpeed = 18.0`
- **Routing**: set `Config.Routes.ToPrison.Enabled = true` and fill `Nodes = { vector3(...), ... }`
- **Pickup/Jail/Release**:
  - `Config.PrisonerPickUp` (escort handoff)
  - `Config.PrisonerJail` (cell)
  - `Config.PrisonReleasePoint` (release spawn)

Install: drop the folder into `resources/[esx]/esx_prisonerconvoy` and `ensure esx_prisonerconvoy`.
