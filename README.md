# Fluently

Fix, improve or translate any selected text on your Mac with one keystroke. Select text in any app (Mail, Slack, Chrome, Notes, Mimestream...), press **both Shift keys together**, and the corrected text replaces your selection.

- Runs on **Apple's on-device model** (`fm`, built into macOS 27): free, private, nothing leaves your Mac.
- Falls back to **Claude Haiku** (Anthropic API) only if the local model fails. The API key is optional.
- Works the same with English and Russian keyboard layouts active.
- Also fixes text typed in the wrong keyboard layout (`ghbdtn` -> `привет`), instantly and offline.

## What it does

Select text, press both Shift keys, then (optionally) a letter within 1 second:

| Keys | Action |
| --- | --- |
| ⇧⇧ (wait 1 s) | Fix spelling, grammar and punctuation only |
| ⇧⇧ then **f** | Same, without waiting |
| ⇧⇧ then **i** | Improve clarity and flow, keep length and tone |
| ⇧⇧ then **e** | Translate to English (any source language), lightly improved |
| ⇧⇧ then **r** | Translate to Russian |
| ⇧⇧ then **s** | Translate to Argentine (Rioplatense) Spanish |
| ⇧⇧ then **w** | Fix text typed in the wrong keyboard layout (RU <-> EN) |
| ⇧⇧ then **Esc**, or ⇧⇧ again | Cancel |
| ⌃⌥F / ⌃⌥I | Fix / Improve directly, without the Shift chord |

Every prompt also replaces em and en dashes with plain hyphens and keeps your formatting and line breaks. Your clipboard is saved before and restored after, so the tool never leaves its output on it.

A pencil icon (✎) in the menu bar shows what is happening:

| Icon | Meaning |
| --- | --- |
| `…` | Waiting for the second key |
| spinner | Working |
| `✓ 1.2s fm` | Done by the local model |
| `✓ 1.2s H` | Done by Claude Haiku (fallback) |
| `✓ EN>RU` / `✓ RU>EN` | Wrong-layout fix done |
| `∅` | Nothing was selected |
| `✗` | Failed - see the Hammerspoon console |

## Requirements

- A Mac with Apple silicon running **macOS 27** or later, with **Apple Intelligence turned on** (System Settings → Apple Intelligence & Siri). This provides the `fm` command.
- [Hammerspoon](https://www.hammerspoon.org) - free, runs the script.
- [Karabiner-Elements](https://karabiner-elements.pqrs.org) - free, turns "both Shift keys" into a single key Hammerspoon can catch.
- Optional: an [Anthropic API key](https://console.anthropic.com) for the Haiku fallback. Without macOS 27 the key is required, since everything then goes to Haiku.

Check the local model works before you start. In Terminal:

```sh
fm respond "Say hello in Russian"
```

You should get a reply within a few seconds. If you get `command not found`, you are not on macOS 27; if it errors about availability, turn on Apple Intelligence and wait for the model to finish downloading.

## Install

### Quick install

```sh
git clone https://github.com/maxsaritasa/fluently.git
cd fluently
./install.sh
```

The script checks requirements, installs Hammerspoon and Karabiner-Elements with Homebrew if they are missing (it asks first), copies the files, backs up anything it changes, and optionally stores your API key in the Keychain. Then do the three manual steps it prints, described in steps 4 to 6 below.

### Manual install

**1. Install the apps**

```sh
brew install --cask hammerspoon karabiner-elements
```

Or download them from their websites. Open each one once.

**2. Copy the Hammerspoon module**

```sh
mkdir -p ~/.hammerspoon
cp hammerspoon/claude_text_fixer.lua ~/.hammerspoon/
echo 'require("claude_text_fixer")' >> ~/.hammerspoon/init.lua
```

If you already use Hammerspoon, this adds one line to your existing config and leaves the rest alone.

**3. Copy the Karabiner rule**

```sh
mkdir -p ~/.config/karabiner/assets/complex_modifications
cp karabiner/claude-text-fixer.json ~/.config/karabiner/assets/complex_modifications/
```

**4. Enable the Karabiner rule**

Karabiner-Elements → **Complex Modifications** → **Add predefined rule** → find **Claude Text Fixer** → **Enable**.

Karabiner also needs its own macOS permissions (Input Monitoring and the driver extension). It walks you through these the first time you open it.

**5. Give Hammerspoon Accessibility access**

System Settings → Privacy & Security → **Accessibility** → turn on **Hammerspoon**. Without this it cannot copy and paste for you.

**6. Reload Hammerspoon**

Click the Hammerspoon icon in the menu bar → **Reload Config**. A ✎ should appear in the menu bar.

**7. (Optional) Add your Anthropic API key**

```sh
security add-generic-password -a "$USER" -s anthropic_api_key -w
```

Paste the key when prompted. It is stored in the macOS Keychain, never in a file. Reload Hammerspoon afterwards.

### Try it

Open any text field, type `teh meeting is tommorow — dont be late`, select it, press both Shift keys and wait a second. It should become `The meeting is tomorrow - don't be late.`

## Configuration

Settings live at the top of `~/.hammerspoon/claude_text_fixer.lua`. Reload Hammerspoon after any change.

| Setting | Default | What it does |
| --- | --- | --- |
| `USE_FM` | `true` | `false` sends everything to Claude Haiku |
| `FM_ACTIONS` | all five | Actions that use the local model. Remove one (e.g. `spanish`) to send it to Haiku |
| `FM_CYRILLIC` | `true` | `false` sends any text containing Cyrillic to Haiku |
| `FM_TIMEOUT` | `20` | Seconds before giving up on the local model |
| `FM_FALLBACK_TO_HAIKU` | `true` | Retry on Haiku when the local model fails |
| `MODEL` | `claude-haiku-5-5` | Anthropic model used for the fallback |
| `LEADER_TIMEOUT` | `1` | Seconds to press the second key before it defaults to fix |
| `RESTORE_CLIPBOARD` | `true` | Put your old clipboard back after pasting |
| `RESTORE_DELAY` | `0.5` | Seconds to wait before restoring; raise it if an app pastes your old clipboard |
| `SWITCH_LAYOUT_AFTER_FIX` | `true` | After ⇧⇧ w, switch the input source to the layout the text was meant for |

**Changing a prompt.** The prompts are in the `PROMPTS` table, in plain English. For example, to translate to Spain Spanish instead of Argentine, edit `PROMPTS.spanish`.

**Changing the key chord.** Edit the Karabiner rule. If both Shifts fire by accident when typing capitals, lower `basic.simultaneous_threshold_milliseconds` from 150 to 80. After editing the file in `assets/complex_modifications`, remove and re-add the rule in Karabiner: editing the file alone does not update a rule that is already enabled.

**Adding a key.** Hotkeys are bound by physical key code (the `KEY` table), not by letter, so they work with any input source. Add the key's ANSI code to `KEY`, add a prompt to `PROMPTS`, and add a `leader:bind` line.

## How it works

1. Karabiner sees both Shift keys pressed within 150 ms and sends **F18**, a key no keyboard has, so it cannot clash with anything.
2. Hammerspoon catches F18 and waits up to a second for a second key.
3. It presses ⌘C, reads the selected text, and sends it with the action's prompt to the local model (`fm respond`) or, on failure, to the Anthropic API.
4. It puts the reply on the clipboard, presses ⌘V, and restores your old clipboard half a second later.

It uses real ⌘C / ⌘V instead of a macOS Service because many apps (Slack, Chrome, Electron apps, Mimestream) accept text from a Service but ignore its "replace selection" output. Every app honours paste.

The wrong-layout fix (⇧⇧ w) is a plain character map, not a model call: it counts Latin vs Cyrillic letters to pick the direction, converts key-for-key, and switches your input source so the next thing you type comes out right. It supports both Apple's "Russian" and "Russian - PC" layouts.

## Troubleshooting

Open the Hammerspoon console from the ✎ menu → **Open console**. Errors start with `fix-with-claude`.

| Symptom | Fix |
| --- | --- |
| Nothing happens, no `…` in the menu bar | Karabiner is not sending F18. Open Karabiner-EventViewer and press both Shifts: you should see `f18`. If you see two shift events, enable the rule (step 4) and, under Karabiner → Devices, tick "Modify events" for your keyboard |
| `…` appears, then nothing | Hammerspoon lacks Accessibility access (step 5), or the console shows a Lua error |
| `∅` with text selected | The app did not copy. Try ⌘C manually in that app; some fields block copying |
| Menu bar shows `H` instead of `fm` | The local model failed and Haiku answered. Check the console line, and run `fm respond "hello"` in Terminal |
| `✗` with "no Anthropic API key" | The local model failed and there is no key for the fallback. Fix `fm`, or add a key (step 7) |
| Every call takes 20 s then falls back | The local model is hanging, usually on first use. Run `fm respond "hello"` once in Terminal, or raise `FM_TIMEOUT` |
| Output has an intro line or quotes around it | The local model followed the prompt loosely. Tighten the prompt, or remove that action from `FM_ACTIONS` |
| `✗` with `HTTP 401` | Wrong or missing API key. `security find-generic-password -a "$USER" -s anthropic_api_key -w` should print it |
| `✗` with `HTTP 404` | The Haiku model name changed. Update `MODEL` from docs.claude.com |
| Pasted text is your old clipboard | The app reads the paste slowly. Raise `RESTORE_DELAY` |
| Works in English layout but not in Russian | You added a binding by letter (`"i"`) instead of key code (`KEY.i`) |
| ⇧⇧ w gets a symbol wrong | Run `hs.keycodes.layouts()` in the console to see your Russian layout's name, then fix that one pair in the matching `zipInto` line |
| Edits have no effect | Reload Hammerspoon. For Karabiner asset edits, remove and re-add the rule |

## Uninstall

```sh
rm ~/.hammerspoon/claude_text_fixer.lua
rm ~/.config/karabiner/assets/complex_modifications/claude-text-fixer.json
security delete-generic-password -a "$USER" -s anthropic_api_key   # if you added a key
```

Then remove the `require("claude_text_fixer")` line from `~/.hammerspoon/init.lua`, disable the rule in Karabiner, and reload Hammerspoon. Remove the apps themselves if nothing else uses them.

## Privacy

With the local model, selected text never leaves your Mac. If the fallback runs (or `USE_FM = false`), the text is sent to the Anthropic API under your own key. The tool keeps no logs or history.
