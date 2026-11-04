# Changelog

All notable changes to this project will be documented in this file.
Releases before 1.2.0 were made by the original author (kbarni); this
repository is a fork of https://github.com/kbarni/checkers.koplugin.

## [1.3.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.3.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.3.0] - 2026-11-04

### Changed
- Looks and plays like the other board games of the collection: the shared
  title bar (menu, close), status line and **Undo** button, and **New game**
  in its place once the game is over. Opened from **Tools → Games → Board
  games**, no longer from its own Tools entry.
- The board is drawn for e-ink: flat black and white pieces with a crown on
  kings, the selected piece ringed and its destinations dotted, and the
  squares of the last move (multi-jumps included) shaded.
- The title-bar menu holds New game, Difficulty (Easy, Medium, Hard, Expert),
  Players (1 against the AI, or 2) and, against the AI, Play as Black or
  White; your pieces are at the bottom either way. Rules open from it too.
- Tapping a piece that cannot move says why, including when a capture
  elsewhere is compulsory.
- Undo also works in the middle of a multi-jump, taking back the whole turn.
- In French, Spanish and German.

### Added
- The game in progress, with its undo history, is saved and restored on next
  launch (it used to be lost on exit).

### Removed
- The computer-vs-computer mode. Settings from 1.2.0 carry over (sides become
  players and colour, the four levels stay); a computer-vs-computer setting
  becomes playing Black against the AI.
- The piece icons copied into KOReader's icons folder, and the patch to
  KOReader's buttons they needed.

## [1.2.0] - 2026-11-04

### Changed
- The computer answers in a few seconds at every level on slow e-readers:
  its search now runs on a compact board with move/undo, iterative
  deepening, a transposition table and move ordering, under a per-level time
  budget (Easy 0.5 s, Medium 1 s, Hard 2 s, Expert 2.5 s). Expert used to
  take up to 100 s per move on a desktop (around 40 minutes on a Kobo);
  it now reaches its full depth on about 9 moves in 10 within the budget,
  with no measurable loss of strength.
