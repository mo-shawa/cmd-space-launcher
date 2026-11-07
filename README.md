# Cmd-Space Launcher

A keyboard app launcher for macOS. Hammerspoon handles Cmd-Space and brings windows forward across Spaces. A small native AppKit panel handles search.

## Install

Tested on Apple silicon with macOS 15.6.1 and Hammerspoon 1.1.1. To install from Terminal, run

```sh
git clone https://github.com/mo-shawa/cmd-space-launcher.git
cd cmd-space-launcher
./install.command --configure-macos
open -a Hammerspoon
```

The installer builds the panel for that Mac using Swift from Xcode or the Xcode Command Line Tools. If needed, run `xcode-select --install`, finish that installation, and retry. If Hammerspoon is missing from Applications, the installer uses `brew install --cask hammerspoon`. Install Homebrew or Hammerspoon first if neither is present.

`--configure-macos` turns off Spotlight’s Cmd-Space shortcut and enables switching to a Space containing the selected app’s windows. It backs up existing Spotlight preferences before editing them. Omit the flag to manage those settings yourself.

1. If Hammerspoon was already running, choose **Reload Config** in its menu. The launcher enables Hammerspoon at login and hides its Dock icon. Its menu bar icon stays available.
2. Enable Hammerspoon in **System Settings → Privacy & Security → Accessibility**.
3. If Raycast also uses Cmd-Space, clear **Raycast Settings → General → Raycast Hotkey**, or quit Raycast.
4. Press **Cmd-Space**, type an app name, and press **Return**.

## Use

- Type a name or abbreviation to search. Use ↑ and ↓ to move, Return to open, and Escape to dismiss. Typing `codex` finds ChatGPT.
- Pick an app for a query of one to four characters to remember that choice. For example, choose WhatsApp for `w`; next time it appears first for `w`. Picking another match for the same query updates the preference.
- Press ↓ in an empty search to see your last 12 distinct launcher picks, newest first. The first ↓ selects the most recent app. Press Return to open it, or start typing to search normally.

The launcher stores up to 128 learned queries and 12 recent bundle IDs in this Mac’s Hammerspoon settings. Dismissing the panel records nothing. To clear both lists, run `hs.settings.clear("CmdSpaceLauncher.history.v1")` in the Hammerspoon Console.

## Update or remove

Pull the latest commit or extract a newer ZIP, then rerun `./install.command` and reload Hammerspoon. History survives updates. The installer keeps the source and executable under `~/.hammerspoon/.cmd-space-launcher/` and links the active release as `~/.hammerspoon/CmdSpaceLauncher`.

On a Mac with an existing `~/.hammerspoon/init.lua`, the installer backs up the file and adds one loader line. It migrates known, unmodified versions of the earlier standalone launcher. If your config is a symlink, the installer prints the line to add to your dotfiles. If you customized an earlier Cmd-Space binding, remove that binding when switching to this one.

To disable the launcher, remove `require("CmdSpaceLauncher.launcher")` from `~/.hammerspoon/init.lua` and reload Hammerspoon. You can re-enable Spotlight under **System Settings → Keyboard → Keyboard Shortcuts → Spotlight**. Installer backups live under `~/.hammerspoon/.cmd-space-launcher/`.
