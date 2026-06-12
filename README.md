# Nebula Hub

A fully decked out, **mobile friendly**, **dark themed** Roblox script hub — everything lives in a single file: [`NebulaHub.lua`](NebulaHub.lua).

## Features

- **Dark theme with live accent colour** — change the accent from the Settings tab with a full HSV colour picker and the whole UI recolours instantly.
- **Mobile friendly**
  - The window auto-sizes to fit small screens.
  - Every control (sliders, dropdowns, colour picker, dragging) works with touch.
  - A floating, draggable **N bubble** lets you hide / show the hub on mobile.
  - Bigger touch targets when a touch screen is detected.
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
