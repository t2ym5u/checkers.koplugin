# Changelog

All notable changes to this project will be documented in this file.
Releases before 1.2.0 were made by the original author (kbarni); this
repository is a fork of https://github.com/kbarni/checkers.koplugin.

## [1.2.0] - 2026-11-04

### Changed
- The computer answers in a few seconds at every level on slow e-readers:
  its search now runs on a compact board with move/undo, iterative
  deepening, a transposition table and move ordering, under a per-level time
  budget (Easy 0.5 s, Medium 1 s, Hard 2 s, Expert 2.5 s). Expert used to
  take up to 100 s per move on a desktop (around 40 minutes on a Kobo);
  it now reaches its full depth on about 9 moves in 10 within the budget,
  with no measurable loss of strength.
