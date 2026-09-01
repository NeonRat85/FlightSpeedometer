# Flight Speedometer

A World of Warcraft addon that displays your movement speed in real-world units — km/h or mph — while flying, skyriding, or on a flight path.

![Version](https://img.shields.io/badge/version-1.5.0-blue)
![Interface](https://img.shields.io/badge/interface-120100-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Real-world units** — km/h or mph, converted from the game's yards/second
- **Skyriding support** — reads true glide velocity, which the usual speed API does not report
- **Auto show/hide** — appears while flying, gliding, or on a taxi; optionally always on
- **Colour-coded** — white at run speed, warming through gold to orange-red as you accelerate
- **Session max and personal best**, with the best kept across sessions
- **Options panel** under Options → AddOns, plus slash commands
- **Draggable and scalable**, with position saved per account

## Installation

Copy the `FlightSpeedometer` folder into your AddOns directory:

```
World of Warcraft/_retail_/Interface/AddOns/FlightSpeedometer/
```

The folder must contain `FlightSpeedometer.toc` and `FlightSpeedometer.lua`. Restart the client or `/reload`.

## Usage

Open the options three ways: **Options → AddOns → Flight Speedometer**, `/fspeed` with no arguments, or right-click the readout itself.

| Command | Effect |
| --- | --- |
| `/fspeed config` | Open the options panel |
| `/fspeed kmh` \| `mph` \| `toggle` | Change units |
| `/fspeed lock` \| `unlock` | Allow or prevent dragging |
| `/fspeed always` | Also show speed on the ground |
| `/fspeed percent` | Toggle the % of base speed line |
| `/fspeed max` | Toggle the max speed line |
| `/fspeed smooth` | Toggle smoothing of the number |
| `/fspeed scale <n>` | Set display scale (0.5–3) |
| `/fspeed reset` | Restore default size and position |
| `/fspeed clear` | Clear session max and personal best |

## How the conversion works

`GetUnitSpeed("player")` returns yards per second. One yard is 0.9144 m, so:

- **km/h** = yd/s × 3.29184
- **mph** = yd/s × 3600 ÷ 1760 &nbsp;(1 mile = 1760 yards)

Normal run speed is 7 yd/s, which the addon treats as 100%.

| Speed | yd/s | km/h | mph |
| --- | --- | --- | --- |
| Run speed (100%) | 7 | 23.0 | 14.3 |
| 310% flying | 21.7 | 71.4 | 44.4 |
| Skyriding max dive | 65 | 214.0 | 133.0 |
| Skyriding with abilities | 100 | 329.2 | 204.5 |

### The skyriding quirk

`GetUnitSpeed` returns **0** while skyriding — it does not report glide velocity. The real value comes from the third return of `C_PlayerInfo.GetGlidingInfo()`:

```lua
local isGliding, canGlide, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
```

The addon uses `forwardSpeed` whenever `isGliding` is true and falls back to `GetUnitSpeed` otherwise. The same call doubles as the airborne check, so it costs one API call per tick.

## Development

### Running the tests

Tests need a Lua 5.1-compatible interpreter. LuaJIT matches the client's dialect:

```bash
winget install DEVCOM.LuaJIT --source winget
```

The harness stubs the WoW API (`CreateFrame`, `GetUnitSpeed`, `GetGlidingInfo`, `Settings`, slash dispatch) and drives the addon through its real code paths — conversions, visibility logic, every slash command, and all panel widgets:

```bash
luajit tests/harness.lua FlightSpeedometer.lua
```

It exits non-zero on failure, and runs in CI on every push.

A syntax-only check, if that is all you need:

```bash
luajit -e "assert(loadfile('FlightSpeedometer.lua'))"
```

### What the tests cannot tell you

The stub returns whatever it is told to, so a green run proves the addon's *internal* logic is consistent. It cannot prove the live client behaves as assumed. API signatures here were verified against [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) rather than community wikis, which were wrong on at least two points during development.

## Compatibility

The `## Interface` line targets retail plus several classic flavours. Behaviour differs:

| Build | Notes |
| --- | --- |
| 120100 / 120007 | Full feature set including skyriding |
| 50504 / 38001 / 20506 | No `GetGlidingInfo`; guarded, falls back to `IsFlying()` |
| 11509 (Classic Era) | No flying — readout appears only with "always show" enabled |

## License

MIT — see [LICENSE](LICENSE).
