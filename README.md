# Cmd-Space Launcher

A native app switcher for macOS. Press **⌘Space**, type a few letters, and hit **Return**.

## Why I built it

I wanted to switch between apps by typing a few letters of their names. Opening a closed app worked. The frustrating part was getting back to one that was already running. Sometimes macOS switched to the right Space and left the window behind another one.

Spotlight searches across my Mac, and Raycast offers commands and extensions. What I wanted from ⌘Space was simpler. I type an app’s name and press Return. If it’s running, the launcher brings its window forward, switching Spaces or restoring a minimized window as needed. If it’s closed, it opens.

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
- When you pick an app after typing one to four characters, it comes first the next time you type those same characters. Choosing a different match updates that preference.
- Press ↓ in an empty search to see your last 12 distinct launcher picks, newest first. The first ↓ selects the most recent app. Press Return to open it, or start typing to search normally.

The list includes apps in the usual Applications folders, Finder, and standalone system utilities such as Keychain Access, Archive Utility, and Wireless Diagnostics. If Xcode is installed, its app folders contribute tools such as Simulator and Instruments. The launcher skips background agents in those extra folders and doesn't crawl through bundled helpers or plug-ins.

The launcher stores up to 128 learned queries and 12 recent bundle IDs in this Mac’s Hammerspoon settings. Dismissing the panel records nothing. To clear both lists, run `hs.settings.clear("CmdSpaceLauncher.history.v1")` in the Hammerspoon Console.

## Choose what Return does for an app

Search for an app and highlight it. Click the gear or press **⌘,**. Click a choice (or press its number) to save it for that app on this Mac. Saving closes the panel without opening the app. **Esc** goes back without saving.

| Choice | What happens when you press Return |
| --- | --- |
| **1 · Switch to the app** | The default. Go to its existing window, even on another Space. |
| **2 · Open a new window here** | Ask the running app for a new window and bring that window to the desktop where you pressed ⌘Space. For example, open a fresh Finder window and leave the old one where it was. |
| **3 · Bring an existing window here** | Bring one existing window to this desktop, preferring the app’s focused window. Other windows stay where they are. If the app has no window, ask it to reopen. |

**⌥Return** uses the normal switch once without changing your saved choice. For a closed app, all three choices launch it once; the app controls any session it restores.

You can opt in for any app. New-window mode looks for an enabled **File → New Window** (or Finder’s **New Finder Window**) in English. Apps that use a different menu title, open tabs, or only support one window may not work. The launcher tells you when it can’t complete the action. Both “here” modes need a regular desktop; they don’t force windows into or out of full screen or Split View. Moving windows uses macOS’s private Spaces interfaces, which can change between OS releases. The launcher checks the window actually arrived before focusing it.

The single-window move fallback uses the SkyLight operation documented by [ferry](https://github.com/softmaxe/ferry) and [yabai](https://github.com/asmvik/yabai). It does not require either tool or changes to System Integrity Protection.

## Update or remove

To update, run `brew upgrade --cask mo-shawa/tap/cmd-space-launcher` and reload Hammerspoon. Your history and per-app choices survive updates.

To uninstall, run `brew uninstall --cask mo-shawa/tap/cmd-space-launcher` and reload Hammerspoon. You can re-enable Spotlight under **System Settings → Keyboard → Keyboard Shortcuts → Spotlight**. The Space-switching preference is under **System Settings → Desktop & Dock → Mission Control**.

The installer backs up an existing `~/.hammerspoon/init.lua` before adding its loader. Backups live under `~/.hammerspoon/.cmd-space-launcher/`. If your config is a symlink, follow the installer’s instructions to add the loader to your dotfiles. If you customized an earlier ⌘Space binding, remove that binding when switching to this one.

For a source install, run `./install.command` in a checkout. Add `--configure-macos` to apply the same Spotlight and Space settings as the cask. Open Hammerspoon or reload its config afterward.
