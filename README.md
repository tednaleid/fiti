# fiti

<p align="center">
  <video src="https://github.com/user-attachments/assets/88a51d14-608d-4eb6-9685-d56ff53678b5" controls muted width="100%"></video>
</p>

Native macOS transparent drawing overlay. Press a hotkey, draw on top of any app, press it again to hide. Useful for annotating during screen shares, demos, and recordings: circle the thing you're pointing at, sketch over a diagram, or scribble notes that auto-fade after a few seconds.

The app sits in the menubar with no Dock icon and stays out of your way until you activate it.

## Install

```bash
brew install --cask tednaleid/fiti/fiti
```

Or, if you already have the tap:

```bash
brew install --cask fiti
```

To update:

```bash
brew upgrade --cask fiti
```

The cask installs `Fiti.app` to `/Applications`.

## Use

Press `Opt+F` to activate. With the pen the cursor becomes a circle that previews the current color, opacity, and width, and a floating toolbar appears: tool buttons (pen, arrow, text), color quick-picks, a color-wheel button for custom colors, size and opacity controls with a live preview of the current mark, a hide/show toggle, and an auto-fade toggle. The toolbar remembers its position across launches and stays clickable even while another app is frontmost.

### System-wide

| Action | Shortcut |
| --- | --- |
| Activate / deactivate | `Opt+F` |
| Deactivate (while active) | `Esc` |

`Opt+F` is registered via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and rebindable in Preferences if it collides with another app.

### While fiti is active

These single-key shortcuts only fire while fiti has key focus, and pass through to whatever app you're in otherwise.

| Action | Shortcut |
| --- | --- |
| Pen / Arrow / Text tool | `p` / `a` / `t` |
| Select (press and hold) | `Space` |
| Pick color | `1`-`8` |
| Size larger / smaller | `s` / `Shift+S` |
| Opacity more / less | `o` / `Shift+O` |
| Toggle hide drawings | `h` |
| Toggle auto-fade | `f` |
| Clear (or delete selection) | `Delete` |

Size and opacity step through preset values, and apply to whichever tool is active (for text, size sets the font size).

Hover over any toolbar control to see its action and shortcut. The menubar's "Drawing" submenu lists them too.

### Menubar

| Action | Shortcut |
| --- | --- |
| Undo / Redo | `Cmd+Z` / `Cmd+Shift+Z` |
| Clear | `Cmd+K` |
| Preferences | `Cmd+,` |
| Quit | `Cmd+Q` |

### Auto-fade

Toggle the clock glyph on the toolbar (or press `f`) to enable auto-fade. Drawings stay solid for 8 seconds after the last stroke, ramp down to invisible over the following 2 seconds, then clear. Any new stroke or `Cmd+Z` resets the timer and restores everything at full opacity. Toggling off mid-fade snaps strokes back to full opacity.

## Development

`just check` runs the full CI gate (unit tests + integration tests + lint + build). See [ONBOARDING.md](./ONBOARDING.md) for orientation: stack, build commands, architecture, key paths, and the dev HTTP introspection surface that lets Claude Code (and you) drive the running app over `localhost:9876`.

Releases are tag-driven: `just bump <version>` updates `Info.plist`, generates release notes from the commit log, creates an annotated tag, and pushes. The release workflow builds, signs, notarizes, and uploads a DMG, then updates the Homebrew cask.

## License

MIT. See [LICENSE](./LICENSE).
