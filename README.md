# OmaWalk

Omarchy bar plugin for an InMovement Unsit treadmill. Daily steps and distance over Bluetooth, graphs for day / week / month, a speed dial while you walk.

Needs any Bluetooth adapter that can see the BM70 console. The Unsit phone app must be closed — the treadmill only talks to one client.

## Install

```sh
omarchy plugin add https://github.com/Critters/OmaWalk.git --enable --yes
python3 -m venv ~/.local/share/omawalk/venv
~/.local/share/omawalk/venv/bin/pip install bleak
omarchy restart shell
```

Place the chip:

```sh
omarchy bar move omawalk --section right
```

## Use

First open: power the treadmill, close the phone app, walk, then **Scan** and pick `BM70_DT`.

- Click the bar icon for graphs.
- Day / week / month and steps / distance switch the same chart.
- Cog: bar chip shows nothing, steps, or distance; **Rescan** forgets the saved treadmill.

History lives in `~/.local/share/omawalk/state.json` and survives plugin and Omarchy updates.

## Debug

```sh
~/.local/share/omawalk/venv/bin/python omawalkd.py scan --seconds 12
~/.local/share/omawalk/venv/bin/python omawalkd.py dump
```
