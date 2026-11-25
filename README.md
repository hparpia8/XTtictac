# XTtictac

Two-player tic-tac-toe for Xteink e-readers running the stock XT Licorice firmware. It is a Lua mini app
("InkApp"): no custom firmware and no flashing. Controls and details: [apps/tictactoe](apps/tictactoe/README.md).

## Will it run on my reader?

| Reader | Status |
|---|---|
| X4 Classic, Licorice 20261124 | Works (API 2.0) |
| Other Licorice readers with Left, Right and Select buttons | Untested. The package installs only if the firmware uses the same package key. |
| Touch-only readers | Not playable: touch is ignored and a Select button is needed |

It is unofficial, so installing it is at your own risk.

## Install

**1. Download `tictactoe.xtapp`** from the [latest release](https://github.com/hparpia8/XTtictac/releases/latest),
under *Assets* (not the source code archives). To build it yourself, see [Build](#build).

**2. Copy it** to the top folder of the reader's SD card, with the reader in USB mode or with a card reader.
Then eject the card.

**3. Install it** on the reader: All Files → `tictactoe.xtapp` → *Install this package?* → OK. Wait for
**Installed**. A file named `._tictactoe.xtapp` is macOS clutter: ignore it.

**4. Play:** side drawer → **InkApp** → Tic-Tac-Toe.

| Problem | What to do |
|---|---|
| **Install failed** | Download and copy the file again. If it still fails, the firmware probably uses another package key: rebuild with `xtpack.py --image`, as [the toolkit's notes](https://github.com/omer-faruq-xteink/touch-licorice-apps/blob/main/docs/firmware-notes.md) explain. That needs a dump of your reader's flash, which holds your Wi-Fi password, so keep it private. |
| No **InkApp** row | Firmware before 26110701 hides it: tap or select Settings → About → Model ten times quickly (seen on the X4 Pro only) |
| Old icon or version | Uninstall Tic-Tac-Toe, then install it again |

## Build

With Python 3.10+, from this folder:

```bash
pip install cryptography pillow
git clone https://github.com/omer-faruq-xteink/touch-licorice-apps
python touch-licorice-apps/xtpack.py apps/tictactoe -o tictactoe.xtapp
```

## Also here

`apps/keyprobe` is a developer tool that shows a reader's key events and which drawing calls work on it.

[MIT License](LICENSE). The turn line's letters are from Lexend ([OFL](apps/tictactoe/OFL.txt)).
