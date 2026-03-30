# RN Commander Manual

RN Commander is a Renoise tool for writing effect commands, changing note column values, applying quick pattern actions, and randomizing effect data.

## Install

Double-click on the .xrnx file. Renise will open and install the script.

## Open The Tool

You can open RN Commander from:

- Tools menu
- Pattern Editor menu
- Assigned Renoise keybindings

## Main Layout

RN Commander has a left panel and a right panel.

- Left panel: effect command buttons for `Effect Columns` or `Sample FX`
- Right panel: `Main`, `Quickies`, and `Randomizer`

## Left Panel

Choose whether commands are written to:

- `Effect Columns`
- `Sample FX`

Each command has:

- a button with the command name
- a small hex value field for the amount
- a short description

Clicking a command writes it to the current row or across the selected line range.

## Main Tab

The Main tab contains:

- Selection Range controls
- Note Column Value sliders for Volume, Panning, and Delay
- Effect Amount sliders for Effect Columns and Sample FX
- Transform tools for redistributing, shifting, scaling, condensing, and remapping values

If a pattern range is selected, most actions apply across that selection.

## Quickies Tab

Quickies provides fast pattern actions:

- Volume ramps up and down
- Gate patterns
- Cut presets
- Retrigger presets
- Retrigger volume ramps
- Slice commands

Use the Selection Range controls first if you want Quickies to target a specific block of lines.

## Randomizer Tab

The Randomizer can:

- randomize effect values
- use fill probability to control density
- work on the current selection or the whole track
- limit output to Min/Max only
- skip overwriting existing data
- lock current effects while changing amounts
- only affect rows with notes or existing effects

## Basic Workflow

1. Select a track and line, or make a pattern selection.
2. Choose `Effect Columns` or `Sample FX` on the left.
3. Click a command button or use one of the tabs on the right.
4. Adjust sliders or randomizer settings as needed.

## Notes

- Most tools work on sequencer tracks.
- Many actions are selection-aware.
- Hex values are shown in the UI for effect amounts.
- If nothing is selected, some actions fall back to the current row or current track settings.