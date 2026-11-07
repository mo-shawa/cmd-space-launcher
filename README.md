# Cmd-Space Launcher

A native app switcher for macOS. Press **⌘Space**, type a few letters, and hit **Return**.

## Why I built it

I wanted to get back to WhatsApp the way I use ⌘Tab, except I wanted to type its name. If its window is on another Space, `wha` and Return should take me there and bring that window to the front. If the window is minimized, the launcher restores it. If the app is closed, it opens it.

Spotlight searches files as well as apps, and Raycast puts apps alongside commands and extensions. For ⌘Space I wanted a short list of apps in a native search field that I could tune to my own habits. I can type `codex` for ChatGPT, teach `w` to mean WhatsApp, or press ↓ to get back to an app I just used.

## Install

On a Mac with Homebrew and the Xcode Command Line Tools, run

```sh
brew install --cask mo-shawa/tap/cmd-space-launcher
```

Homebrew installs Hammerspoon, builds the panel for your Mac, and opens Hammerspoon. The installer frees ⌘Space by disabling Spotlight’s shortcut and enables the macOS setting that switches to a Space with open windows for the selected app. It backs up existing Spotlight preferences before editing them. If the developer tools are missing, run `xcode-select --install`, let it finish, and retry.

1. Grant Hammerspoon access in **System Settings → Privacy & Security → Accessibility**.
2. If Raycast uses ⌘Space, clear **Raycast Settings → General → Raycast Hotkey**, or quit Raycast.
3. If Hammerspoon was already running, choose **Reload Config** from its menu bar icon. The launcher enables Hammerspoon at login and hides its Dock icon.

Tested on Apple silicon with macOS 15.6.1 and Hammerspoon 1.1.1.

## Use

- Type a name or abbreviation to search. Use ↑ and ↓ to move, Return to open, and Escape to dismiss. Typing `codex` finds ChatGPT.
- Pick an app for a query of one to four characters to remember that choice. For example, choose WhatsApp for `w`; next time it appears first for `w`. Picking another match for the same query updates the preference.
- Press ↓ in an empty search to see your last 12 distinct launcher picks, newest first. The first ↓ selects the most recent app. Press Return to open it, or start typing to search normally.

The launcher stores up to 128 learned queries and 12 recent bundle IDs in this Mac’s Hammerspoon settings. Dismissing the panel records nothing. To clear both lists, run `hs.settings.clear("CmdSpaceLauncher.history.v1")` in the Hammerspoon Console.

## Update or remove

To update, run `brew upgrade --cask mo-shawa/tap/cmd-space-launcher` and reload Hammerspoon. Your history survives updates.

To uninstall, run `brew uninstall --cask mo-shawa/tap/cmd-space-launcher` and reload Hammerspoon. You can re-enable Spotlight under **System Settings → Keyboard → Keyboard Shortcuts → Spotlight**. The Space-switching preference is under **System Settings → Desktop & Dock → Mission Control**.

The installer backs up an existing `~/.hammerspoon/init.lua` before adding its loader. Backups live under `~/.hammerspoon/.cmd-space-launcher/`. If your config is a symlink, follow the installer’s instructions to add the loader to your dotfiles. If you customized an earlier ⌘Space binding, remove that binding when switching to this one.

For a source install, run `./install.command` in a checkout. Add `--configure-macos` to apply the same Spotlight and Space settings as the cask. Open Hammerspoon or reload its config afterward.
