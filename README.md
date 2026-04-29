# Checkers for KOReader

English draughts (checkers) plugin for [KOReader](https://koreader.rocks). Play human vs human or against a built-in AI opponent.

![Checkers game with settings dialog open](checkers_screenshot.png)

## Features

- **Standard English draughts rules** — forced captures, multi-jump, king promotion, 40-move draw rule
- **AI opponent** — alpha-beta search with four difficulty levels (Easy / Medium / Hard / Expert)
- **Flexible modes** — each side (Black, White) can independently be Human or AI
- **Undo** — steps back over the AI's reply so you always return to your own turn
- **Persistent settings** — mode and difficulty are remembered between sessions

## Installation

1. Download or clone this repository as a folder named `checkers.koplugin`.
2. Copy the folder into KOReader's plugins directory on your device:
   - Kindle / Kobo (USB): `<device>/koreader/plugins/checkers.koplugin/`
   - Linux desktop: `~/.config/koreader/plugins/checkers.koplugin/`
3. Restart KOReader (or reload plugins via **Settings → Plugin settings → Reload plugins**).

The plugin will appear under **Tools → Checkers** in the KOReader menu.

> Icons are automatically installed to `~/.config/koreader/icons/checkers/` on the first run.

## Usage

### Starting a game

Open **Tools → Checkers** to open the New Game dialog. Choose which side each player is (Human or AI) and the difficulty, then tap **Save**. The game starts immediately.

You can reopen the settings at any time using the **⚙ gear icon** in the top-left corner of the board.

### Playing

- **Tap a piece** to select it — valid destination squares are shown as dots.
- **Tap a destination** to move. If a capture is available, it is forced (the dots only show legal moves).
- When a multi-jump is possible after a capture, the piece stays selected and you must continue jumping.

### Toolbar buttons

| Button | Action |
|--------|--------|
| **‹** (bottom-left) | Undo — steps back over the AI's reply |
| **+** (bottom-right) | New game (asks for confirmation) |
| **⚙** (top-left) | Open settings / change mode or difficulty |
| **✕** (top-right) | Exit Checkers |

### Difficulty levels

| Level  | Search depth | Notes |
|--------|-------------|-------|
| Easy   | 3 | Misses short-term threats |
| Medium | 5 | Plays solid, misses some tactics |
| Hard   | 7 | Strong club-level play |
| Expert | 9 | May think for several seconds per move |

## Rules summary (English draughts)

- Black moves first (down the board), White moves up.
- Men move diagonally forward one square.
- Captures jump over an adjacent enemy to the empty square beyond; captures are **forced**.
- A chain of captures in one turn is a **multi-jump** — you must continue as long as captures are available.
- A man reaching the far rank is **crowned king** and may move or capture in any diagonal direction.
- The game ends when a player has no legal moves, or after **40 consecutive moves without a capture** (draw).

## License

MIT
