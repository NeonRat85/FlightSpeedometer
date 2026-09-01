# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0]

### Fixed

- **Skyriding showed 0.0 km/h.** `GetUnitSpeed("player")` returns 0 while gliding
  and does not report glide velocity. The addon now reads `forwardSpeed`, the third
  return of `C_PlayerInfo.GetGlidingInfo()`, whenever `isGliding` is true. The same
  call now also serves the airborne check, reducing it to one API call per tick.
- **Session max stuck at 0.0 on the ground.** Max tracking was gated behind the
  airborne test, so with "always show" enabled it displayed a real speed next to a
  zero maximum. It now tracks whenever the readout is live.

### Added

- Test harness coverage for the skyriding path and for ground-speed max tracking.

## [1.4.0]

### Changed

- `/fspeed reset` now restores default size *and* position, matching the options
  panel's Reset button. Previously the two disagreed about what "reset" meant.

## [1.3.0]

### Fixed

Audit against [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source):

- Use `UICheckButtonTemplate`'s built-in `parentKey="Text"` label instead of
  creating a redundant second FontString beside it.
- Stop overwriting `category.ID` after registration. Category lookup matches on
  `category:GetID()` at call time, so the override was unnecessary and risked
  colliding with any other addon hardcoding the same string.

## [1.2.0]

### Changed

- `## Interface` now targets retail plus several classic flavours:
  `120100, 120007, 50504, 38001, 20506, 11509`.
- `Settings.OpenToCategory` is called behind an existence check.

## [1.1.0]

### Added

- Options panel registered under Options → AddOns, built as a canvas category via
  `Settings.RegisterCanvasLayoutCategory` with a legacy
  `InterfaceOptions_AddCategory` fallback for older clients.
- Right-click the readout to open the options panel.

## [1.0.0]

### Added

- Initial release: speed readout in km/h or mph, converted from yards/second.
- Auto show/hide while flying, gliding, or on a flight path.
- Colour-coded readout, percentage of base speed, session max, personal best.
- Draggable and scalable display with per-account saved settings.
- Slash commands under `/fspeed` and `/flightspeed`.
