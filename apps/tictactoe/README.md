# Tic-Tac-Toe

Two players on one reader, with buttons only. P1 is X and P2 is O; the first player alternates every game.
[How to install](../../README.md#install).

## Controls

| Button | Action |
|---|---|
| Left / Right | previous / next empty cell, then Restart; in a box, switch |
| Side buttons | the nearest empty cell in the row above / below; from the bottom row, Restart |
| Select | place a mark, or press the focused button |
| Back | the reader asks "Leave this InkApp?" |

- **Restart** asks "Quit this round?" once a game has a move in it.
- **After a game**, "New game?" starts the next one (Yes) or leaves the app (No).
- **The tally** (`P1 5 - 4 P2`) counts wins; draws and restarted games do not count.
- **Nothing is saved:** leaving the app clears the board and the tally.

## Development

Host API 0.8, no permissions. Run the tests, under Lua 5.4 and 5.5:

```bash
pip install lupa
python -I apps/tictactoe/test_tictactoe.py
```

What the X4 Classic (Licorice 20261118) does, and the code depends on:

- **Keys:** `left`, `right`, `ok`, `prev` and `next` (the side buttons), each with `down` and `up` and no repeats.
  Back never reaches the app, not even held. On a host that delivers it, it leaves the app, asking first in the middle of a game.
- **Held buttons** act once on hosts that send releases. `up` and `down` are mapped for other readers, untested.
- **Drawing:** `g:rect` draws outlines only, `g:polyline` raises an error, there is one text size, and
  `{ color = 0 }` draws white. So black boxes, round corners and large text are painted from lines and outlines.
- **Limit:** 1024 drawing commands a frame; the fullest screen uses 832.
- **Refresh:** the app never asks for a full refresh; the reader's own setting decides when the screen flashes.

## Credits

`icon.png` was drawn for this app. The turn line's letters were rasterised from
[Lexend](https://github.com/googlefonts/lexend) (Copyright 2018 The Lexend Project Authors), under the
[SIL Open Font License 1.1](OFL.txt).
