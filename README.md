# fiti

Native macOS transparent drawing overlay. Press a hotkey, draw on top of any app, press again to hide. fiti is a Swift port of the [telestrator](https://github.com/steveruizok/telestrator) concept, with a hexagonal Core / AppKit / DevHTTP architecture so the rendering layer and the document model can evolve independently.

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

The cask installs `Fiti.app` to `/Applications` and the menubar status icon launches it. The app sits in the menubar (no Dock icon) and stays inactive until the activation hotkey or menu item is invoked.

## Use

| Action | Shortcut |
| --- | --- |
| Toggle activate/deactivate (system-wide) | `Opt+F` |
| Deactivate (while active) | `Esc` |
| Clear all strokes | `Cmd+K` |
| Undo / Redo | `Cmd+Z` / `Cmd+Shift+Z` |

The activation hotkey is registered via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and rebindable through the library's API (`KeyboardShortcuts.Name.toggleActivation`). A Preferences UI for in-app rebinding is on the roadmap.

While active, the cursor becomes a circle that matches the current pen color, opacity, and width. The toolbar (color quick-picks, custom color, width slider, opacity slider, undo/redo/clear, hide-drawings) appears beside the cursor and remembers its position across launches.

## Development

`just check` runs the full CI gate (unit tests + integration tests + lint + build). See [ONBOARDING.md](./ONBOARDING.md) for orientation: stack, build commands, architecture, key paths, and the dev HTTP introspection surface that lets Claude Code (and you) drive the running app over `localhost:9876`.

Releases are tag-driven: `just bump <version>` updates `Info.plist`, generates release notes from the commit log, creates an annotated tag, and pushes. The release workflow builds, signs, notarizes, and uploads a DMG, then updates the Homebrew cask.

## License

MIT. See [LICENSE](./LICENSE).
