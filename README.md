# Nebula Hub

A fully decked out, **mobile friendly**, **dark themed** Roblox script hub — everything lives in a single file: [`NebulaHub.lua`](NebulaHub.lua).

## Features

- **Dark theme with live accent colour** — change the accent from the Settings tab with a full HSV colour picker and the whole UI recolours instantly.
- **Mobile friendly**
  - The window auto-sizes to fit small screens.
  - Every control (sliders, dropdowns, colour picker, dragging) works with touch.
  - A floating, draggable **N bubble** lets you hide / show the hub on mobile.
  - Bigger touch targets when a touch screen is detected.
- **Script Finder** — searches script site APIs (ScriptBlox + Rscripts) right from the hub:
  - **"Find scripts for this game"** detects the game you're in and pulls up scripts made for it (exact matches highlighted on top).
  - **Search bar** to look up any script by keyword, with pagination and source switching.
  - Every result has **Execute** and **Copy script** buttons, plus badges for verified / key system / paid / patched / universal.
- **Automation Builder** — a no-code macro studio for making your own scripts for the game you're in:
  - Chain together **steps**: `Wait`, `Fire remote`, `Run Lua`, `Notify` and `Press key`.
  - **Scan game for remotes** finds every `RemoteEvent` / `RemoteFunction` and lets you fire them with typed arguments (numbers, booleans, strings, `nil`).
  - Reorder (▴ ▾) or delete (✕) any step, then **Play once** or **Loop** with an adjustable delay.
  - **Save / load** macros (uses `writefile` when available, session memory otherwise).
  - **Copy as Lua script** exports your macro as a clean standalone Lua file you can run anywhere.
- **Full control set** — buttons (with ripple), toggles, sliders, dropdowns (single + multi select), keybinds, textboxes, labels, paragraphs and an HSV colour picker.
- **Notifications** — 4 severities (info / success / warning / error) with progress timers.
- **Search bar** — filters the controls of the open tab as you type.
- **Configs** — save / load all your settings (uses `writefile` when available in an executor, falls back to session memory otherwise).
- **FPS / ping watermark** — toggle it in the Visuals tab.
- **Keyboard toggle** — `RightShift` hides / shows the hub (rebindable in Settings).

## Pre-built tabs

| Tab | Contents |
| --- | --- |
| Home | Welcome card, test notification, live server info, rejoin server, copy place ID |
| Player | Walk speed + jump power sliders, re-apply after respawn, reset character, camera FOV |
| Visuals | Fullbright, remove fog, time of day, restore lighting, watermark toggle |
| Scripts | Quick code runner (executor `loadstring`) + empty slots for your own scripts |
| Finder | Online script finder — search ScriptBlox / Rscripts or auto-find scripts for the current game, then execute or copy them |
| Builder | No-code automation builder — chain steps (waits, remote calls, Lua, notifications, key presses) into a macro, play/loop it, save it, or export it as a standalone Lua script |
| Settings | Accent colour picker, UI toggle keybind, config save/load, unload hub |

## How to run

**From an executor** (raw URL of this file on your fork/branch):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/<user>/<repo>/main/NebulaHub.lua"))()
```

**In Roblox Studio**: paste the contents of `NebulaHub.lua` into a `LocalScript` in `StarterPlayer > StarterPlayerScripts` and hit Play. (The Scripts tab's code runner needs an executor's `loadstring`; everything else works in Studio.)

## Adding your own scripts

Open `NebulaHub.lua` and scroll to the `SCRIPTS TAB` block near the bottom. Duplicate one of the button entries and put your code in the callback:

```lua
mySection:AddButton({
	Name = "My cool script",
	Callback = function()
		-- your code here
	end,
})
```

## Building a macro (no code needed)

Open the **Builder** tab and assemble a macro step by step:

1. Choose a **Step type** and fill in the **Value** box (the hint under the dropdown tells you what to type).
   - `Wait` → seconds to pause (e.g. `1.5`)
   - `Run Lua` → any Luau code (needs an executor)
   - `Notify` → an on-screen message
   - `Press key` → a key name (`E`, `Space`, `MouseButton1`, ...)
2. For a `Fire remote` step, press **Scan game for remotes**, pick one from the **Remote** dropdown, and (optionally) type comma-separated **args** like `1, true, "hello"`.
3. Press **➕ Add step**. Steps appear in *Your macro*, where you can reorder (▴ ▾) or remove (✕) them.
4. In **Playback**, hit **▶ Play macro** to run it once, or turn on **Loop macro** (with a delay) to repeat it.
5. In **Save & export**, save the macro for later, or press **Copy as Lua script** to get a clean standalone Lua file you can run anywhere.

Macros are stored as JSON under `NebulaHub/macros/` when your executor exposes a file API.

## Using the library for your own hub

The file returns the `Library` object, and the whole UI toolkit is reusable:

```lua
local Window = Library:CreateWindow({ Title = "My Hub", Subtitle = "v1.0" })
local Tab = Window:CreateTab("Main", "★")
local Section = Tab:CreateSection("General")

Section:AddButton({ Name = "Click me", Callback = function() print("hi") end })
Section:AddToggle({ Name = "God mode UI", Flag = "MyToggle", Default = false, Callback = print })
Section:AddSlider({ Name = "Speed", Min = 0, Max = 100, Default = 50, Flag = "MySlider", Callback = print })
Section:AddDropdown({ Name = "Mode", Values = { "A", "B", "C" }, Default = "A", Callback = print })
Section:AddDropdown({ Name = "Targets", Values = { "X", "Y" }, Multi = true, Callback = print })
Section:AddKeybind({ Name = "Do thing", Default = Enum.KeyCode.E, Callback = function() print("pressed") end })
Section:AddTextbox({ Name = "Name", Placeholder = "type...", Callback = print })
Section:AddColorPicker({ Name = "Colour", Default = Color3.fromRGB(255, 0, 0), Callback = print })
Section:AddLabel("Just some text")
Section:AddParagraph("Title", "Longer wrapped body text goes here.")

Library:Notify({ Title = "Hello", Content = "World", Type = "success", Duration = 4 })
```

Anything created with a `Flag` is stored in `Library.Flags` and automatically included in saved configs.
