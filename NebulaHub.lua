--[[
	███╗   ██╗███████╗██████╗ ██╗   ██╗██╗      █████╗     ██╗  ██╗██╗   ██╗██████╗
	████╗  ██║██╔════╝██╔══██╗██║   ██║██║     ██╔══██╗    ██║  ██║██║   ██║██╔══██╗
	██╔██╗ ██║█████╗  ██████╔╝██║   ██║██║     ███████║    ███████║██║   ██║██████╔╝
	██║╚██╗██║██╔══╝  ██╔══██╗██║   ██║██║     ██╔══██║    ██╔══██║██║   ██║██╔══██╗
	██║ ╚████║███████╗██████╔╝╚██████╔╝███████╗██║  ██║    ██║  ██║╚██████╔╝██████╔╝
	╚═╝  ╚═══╝╚══════╝╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝

	NEBULA HUB  -  v1.0
	A fully decked out, mobile friendly, dark themed Roblox script hub.

	Features:
	  - Sleek dark UI with accent theming (live recolour from Settings)
	  - Fully touch compatible: drag, sliders, dropdowns and pickers all work on mobile
	  - Floating bubble button to reopen the hub on mobile (draggable)
	  - Tabs, sections, buttons, toggles, sliders, dropdowns (single + multi),
	    keybinds, textboxes, labels, paragraphs and a full HSV colour picker
	  - Notification system with 4 severities and progress timers
	  - Script Finder tab: searches ScriptBlox + Rscripts for scripts (by keyword
	    or for the game you are in) and executes them in one tap
	  - Search bar that filters the controls of the open tab
	  - Config save / load (uses writefile when ran in an executor)
	  - FPS / ping watermark
	  - Keyboard toggle (RightShift by default, rebindable in Settings)

	The bottom of this file builds the actual hub using the library, so you can
	freely add your own tabs / buttons there. The library itself is exposed as
	`Library` if you want to reuse it for your own projects.
]]

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local Lighting         = game:GetService("Lighting")
local TeleportService  = game:GetService("TeleportService")
local StatsService     = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Camera      = workspace.CurrentCamera

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

----------------------------------------------------------------------
-- Gui parent resolution (executor -> CoreGui / gethui, studio -> PlayerGui)
----------------------------------------------------------------------
local function getGuiParent()
	local ok, hui = pcall(function()
		return gethui and gethui() or nil
	end)
	if ok and typeof(hui) == "Instance" then
		return hui
	end
	local ok2, coreGui = pcall(function()
		local cg = game:GetService("CoreGui")
		local probe = Instance.new("Folder")
		probe.Name = "__NebulaProbe"
		probe.Parent = cg
		probe:Destroy()
		return cg
	end)
	if ok2 and coreGui then
		return coreGui
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local GuiParent = getGuiParent()

-- Kill any previous instance of the hub
for _, inst in ipairs(GuiParent:GetChildren()) do
	if inst:IsA("ScreenGui") and inst.Name == "NebulaHub_UI" then
		inst:Destroy()
	end
end

----------------------------------------------------------------------
-- Library core
----------------------------------------------------------------------
local Library = {
	Flags        = {},   -- flag -> current value
	Items        = {},   -- flag -> { Set = fn }  (used by config loading)
	Connections  = {},
	ToggleKey    = Enum.KeyCode.RightShift,
	ConfigFolder = "NebulaHub",
	Theme = {
		Background = Color3.fromRGB(13, 13, 18),
		Sidebar    = Color3.fromRGB(17, 17, 23),
		Panel      = Color3.fromRGB(22, 22, 30),
		PanelSoft  = Color3.fromRGB(27, 27, 36),
		Element    = Color3.fromRGB(31, 31, 41),
		Stroke     = Color3.fromRGB(42, 42, 54),
		Text       = Color3.fromRGB(235, 235, 245),
		TextDim    = Color3.fromRGB(150, 150, 165),
		Accent     = Color3.fromRGB(132, 94, 255),
	},
}
local Theme = Library.Theme

local AccentRegistry = {} -- { {Object = inst, Property = "BackgroundColor3"} ... }

local function registerAccent(object, property)
	table.insert(AccentRegistry, { Object = object, Property = property })
	object[property] = Theme.Accent
end

function Library:SetAccent(color)
	Theme.Accent = color
	for _, entry in ipairs(AccentRegistry) do
		if entry.Object and entry.Object.Parent ~= nil then
			pcall(function()
				entry.Object[entry.Property] = color
			end)
		end
	end
end

local function track(connection)
	table.insert(Library.Connections, connection)
	return connection
end

----------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------
local function New(className, props, children)
	local inst = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			if key ~= "Parent" then
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function Round(parent, radius)
	return New("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

local function Stroke(parent, color, thickness, transparency)
	return New("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function Pad(parent, top, bottom, left, right)
	return New("UIPadding", {
		PaddingTop    = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		PaddingLeft   = UDim.new(0, left or 0),
		PaddingRight  = UDim.new(0, right or 0),
		Parent = parent,
	})
end

local function VList(parent, padding, alignment)
	return New("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = alignment or Enum.HorizontalAlignment.Center,
		Parent = parent,
	})
end

local function Tween(object, time, props, style)
	local tween = TweenService:Create(
		object,
		TweenInfo.new(time or 0.18, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Press-down scale feedback for buttons (mouse + touch)
local function Pressable(button, scaleDown)
	local scale = New("UIScale", { Scale = 1, Parent = button })
	local down = scaleDown or 0.96
	track(button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			Tween(scale, 0.08, { Scale = down })
		end
	end))
	track(button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			Tween(scale, 0.12, { Scale = 1 })
		end
	end))
end

-- Ripple click effect
local function Ripple(button, x, y)
	local relX = x - button.AbsolutePosition.X
	local relY = y - button.AbsolutePosition.Y
	local circle = New("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.82,
		Position = UDim2.new(0, relX, 0, relY),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 0, 0, 0),
		ZIndex = button.ZIndex + 2,
		Parent = button,
	})
	Round(circle, 999)
	local target = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.2
	Tween(circle, 0.4, { Size = UDim2.new(0, target, 0, target), BackgroundTransparency = 1 })
	task.delay(0.45, function()
		circle:Destroy()
	end)
end

-- Universal mouse + touch dragging
local function MakeDraggable(handle, target, onTap)
	local dragging = false
	local dragInput, dragStart, startPos
	local moved = 0

	track(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = 0
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if onTap and moved < 8 then
						onTap()
					end
				end
			end)
		end
	end))
	track(handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			moved = math.max(moved, math.abs(delta.X), math.abs(delta.Y))
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end))
end

----------------------------------------------------------------------
-- Config system (uses executor file API when available)
----------------------------------------------------------------------
local CAN_FILE = typeof(writefile) == "function"
	and typeof(readfile) == "function"
	and typeof(isfile) == "function"

local MemoryConfigs = {} -- fallback storage when no file API exists

local function configPath(name)
	return Library.ConfigFolder .. "/" .. name .. ".json"
end

local function encodeFlagValue(value)
	if typeof(value) == "Color3" then
		return { __type = "Color3", value.R, value.G, value.B }
	elseif typeof(value) == "EnumItem" then
		return { __type = "KeyCode", value.Name }
	end
	return value
end

local function decodeFlagValue(value)
	if typeof(value) == "table" and value.__type then
		if value.__type == "Color3" then
			return Color3.new(value[1], value[2], value[3])
		elseif value.__type == "KeyCode" then
			local ok, key = pcall(function()
				return Enum.KeyCode[value[1]]
			end)
			if ok then
				return key
			end
		end
	end
	return value
end

function Library:SaveConfig(name)
	if name == nil or name == "" then
		name = "default"
	end
	local data = {}
	for flag, value in pairs(Library.Flags) do
		data[flag] = encodeFlagValue(value)
	end
	local json = HttpService:JSONEncode(data)
	if CAN_FILE then
		pcall(function()
			if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
				if not isfolder(Library.ConfigFolder) then
					makefolder(Library.ConfigFolder)
				end
			end
			writefile(configPath(name), json)
		end)
	else
		MemoryConfigs[name] = json
	end
	return true
end

function Library:LoadConfig(name)
	if name == nil or name == "" then
		name = "default"
	end
	local json
	if CAN_FILE then
		local ok, result = pcall(function()
			if isfile(configPath(name)) then
				return readfile(configPath(name))
			end
			return nil
		end)
		if ok then
			json = result
		end
	else
		json = MemoryConfigs[name]
	end
	if not json then
		return false
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or typeof(data) ~= "table" then
		return false
	end
	for flag, raw in pairs(data) do
		local item = Library.Items[flag]
		if item and item.Set then
			pcall(function()
				item.Set(decodeFlagValue(raw))
			end)
		end
	end
	return true
end

function Library:ListConfigs()
	local names = {}
	if CAN_FILE and typeof(listfiles) == "function" then
		pcall(function()
			for _, path in ipairs(listfiles(Library.ConfigFolder)) do
				local name = path:match("([^/\\]+)%.json$")
				if name then
					table.insert(names, name)
				end
			end
		end)
	else
		for name in pairs(MemoryConfigs) do
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

----------------------------------------------------------------------
-- Root ScreenGui
----------------------------------------------------------------------
local ScreenGui = New("ScreenGui", {
	Name = "NebulaHub_UI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = GuiParent,
})

----------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------
local NotifyHolder = New("Frame", {
	Name = "Notifications",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 14),
	Size = UDim2.new(0, IS_MOBILE and 230 or 280, 1, -28),
	Parent = ScreenGui,
})
New("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
	Parent = NotifyHolder,
})

local NOTIFY_COLORS = {
	info    = Color3.fromRGB(96, 148, 255),
	success = Color3.fromRGB(86, 214, 134),
	warning = Color3.fromRGB(255, 190, 92),
	error   = Color3.fromRGB(255, 96, 110),
}

function Library:Notify(options)
	options = options or {}
	local title    = options.Title or "Nebula Hub"
	local body     = options.Content or ""
	local duration = options.Duration or 4
	local kind     = NOTIFY_COLORS[options.Type or "info"] or NOTIFY_COLORS.info

	local card = New("Frame", {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true,
		Parent = NotifyHolder,
	})
	Round(card, 10)
	local cardStroke = Stroke(card, Theme.Stroke, 1, 1)
	Pad(card, 10, 12, 14, 12)

	local bar = New("Frame", {
		BackgroundColor3 = kind,
		Position = UDim2.new(0, -14, 0, -10),
		Size = UDim2.new(0, 3, 1, 22),
		BackgroundTransparency = 1,
		Parent = card,
	})

	local titleLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = title,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = card,
	})
	local bodyLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = body,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	local progress = New("Frame", {
		BackgroundColor3 = kind,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -14, 1, 12),
		Size = UDim2.new(1, 28, 0, 2),
		Parent = card,
	})

	Tween(card, 0.25, { BackgroundTransparency = 0.05 })
	Tween(cardStroke, 0.25, { Transparency = 0.4 })
	Tween(bar, 0.25, { BackgroundTransparency = 0 })
	Tween(titleLabel, 0.25, { TextTransparency = 0 })
	Tween(bodyLabel, 0.25, { TextTransparency = 0.15 })
	Tween(progress, 0.25, { BackgroundTransparency = 0.2 })
	Tween(progress, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)

	task.delay(duration, function()
		if card.Parent then
			Tween(card, 0.25, { BackgroundTransparency = 1 })
			Tween(cardStroke, 0.25, { Transparency = 1 })
			Tween(bar, 0.25, { BackgroundTransparency = 1 })
			Tween(titleLabel, 0.25, { TextTransparency = 1 })
			Tween(bodyLabel, 0.25, { TextTransparency = 1 })
			Tween(progress, 0.25, { BackgroundTransparency = 1 })
			task.wait(0.3)
			card:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
function Library:CreateWindow(options)
	options = options or {}
	local windowTitle = options.Title or "Nebula Hub"
	local subtitle    = options.Subtitle or "v1.0"

	local viewport = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
	local winW = math.min(options.Width or 600, viewport.X - 20)
	local winH = math.min(options.Height or 430, viewport.Y - 20)
	local sidebarW = IS_MOBILE and 128 or 150
	local TOPBAR = IS_MOBILE and 46 or 42

	local Window = {
		Tabs = {},
		ActiveTab = nil,
		Visible = true,
		Minimized = false,
	}

	------------------------------------------------------------------
	-- Main frame + shadow
	------------------------------------------------------------------
	local Main = New("Frame", {
		Name = "Main",
		BackgroundColor3 = Theme.Background,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, winW, 0, winH),
		ClipsDescendants = true,
		Parent = ScreenGui,
	})
	Round(Main, 12)
	Stroke(Main, Theme.Stroke, 1, 0.2)

	New("ImageLabel", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.4,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 70, 1, 70),
		ZIndex = 0,
		Parent = Main,
	})

	------------------------------------------------------------------
	-- Top bar
	------------------------------------------------------------------
	local TopBar = New("Frame", {
		Name = "TopBar",
		BackgroundColor3 = Theme.Sidebar,
		Size = UDim2.new(1, 0, 0, TOPBAR),
		Parent = Main,
	})
	Round(TopBar, 12)
	New("Frame", { -- square off the bottom corners of the topbar
		BackgroundColor3 = Theme.Sidebar,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 12),
		Parent = TopBar,
	})

	local accentDot = New("Frame", {
		Size = UDim2.new(0, 10, 0, 10),
		Position = UDim2.new(0, 16, 0.5, -5),
		Parent = TopBar,
	})
	Round(accentDot, 999)
	registerAccent(accentDot, "BackgroundColor3")

	New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = windowTitle,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 34, 0, 0),
		Size = UDim2.new(0, 200, 1, 0),
		Parent = TopBar,
	})
	local subtitleLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = subtitle,
		TextSize = 11,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 34, 0, 0),
		Size = UDim2.new(0, 200, 1, 0),
		Parent = TopBar,
	})
	-- offset subtitle to sit right after the title text
	task.defer(function()
		local titleWidth = game:GetService("TextService"):GetTextSize(
			windowTitle, 15, Enum.Font.GothamBold, Vector2.new(400, 50)
		).X
		subtitleLabel.Position = UDim2.new(0, 34 + titleWidth + 8, 0, 1)
	end)

	local function topBarButton(text, xOffset)
		local button = New("TextButton", {
			BackgroundColor3 = Theme.Panel,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextSize = 14,
			TextColor3 = Theme.TextDim,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, xOffset, 0.5, 0),
			Size = UDim2.new(0, 30, 0, 30),
			AutoButtonColor = false,
			Parent = TopBar,
		})
		Round(button, 8)
		Pressable(button)
		track(button.MouseEnter:Connect(function()
			Tween(button, 0.12, { TextColor3 = Theme.Text, BackgroundColor3 = Theme.PanelSoft })
		end))
		track(button.MouseLeave:Connect(function()
			Tween(button, 0.12, { TextColor3 = Theme.TextDim, BackgroundColor3 = Theme.Panel })
		end))
		return button
	end

	local closeButton    = topBarButton("✕", -10)
	local minimizeButton = topBarButton("—", -46)

	------------------------------------------------------------------
	-- Sidebar
	------------------------------------------------------------------
	local Sidebar = New("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = Theme.Sidebar,
		Position = UDim2.new(0, 0, 0, TOPBAR),
		Size = UDim2.new(0, sidebarW, 1, -TOPBAR),
		Parent = Main,
	})
	New("Frame", { -- divider line
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		Parent = Sidebar,
	})

	-- Search box
	local searchHolder = New("Frame", {
		BackgroundColor3 = Theme.Panel,
		Position = UDim2.new(0, 10, 0, 10),
		Size = UDim2.new(1, -20, 0, 30),
		Parent = Sidebar,
	})
	Round(searchHolder, 8)
	Stroke(searchHolder, Theme.Stroke, 1, 0.4)
	New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "⌕",
		TextSize = 16,
		TextColor3 = Theme.TextDim,
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(0, 16, 1, 0),
		Parent = searchHolder,
	})
	local searchBox = New("TextBox", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		PlaceholderText = "Search...",
		PlaceholderColor3 = Theme.TextDim,
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Position = UDim2.new(0, 28, 0, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Parent = searchHolder,
	})

	-- Tab list
	local tabList = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 0, 48),
		Size = UDim2.new(1, -20, 1, -48 - 64),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Stroke,
		Parent = Sidebar,
	})
	VList(tabList, 4)

	-- User card at the bottom of the sidebar
	local userCard = New("Frame", {
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(1, -20, 0, 46),
		Parent = Sidebar,
	})
	Round(userCard, 10)
	Stroke(userCard, Theme.Stroke, 1, 0.4)
	local avatar = New("ImageLabel", {
		BackgroundColor3 = Theme.Element,
		Position = UDim2.new(0, 7, 0.5, -16),
		Size = UDim2.new(0, 32, 0, 32),
		Parent = userCard,
	})
	Round(avatar, 999)
	New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = LocalPlayer.DisplayName,
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 46, 0, 7),
		Size = UDim2.new(1, -52, 0, 14),
		Parent = userCard,
	})
	New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "@" .. LocalPlayer.Name,
		TextSize = 10,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 46, 0, 23),
		Size = UDim2.new(1, -52, 0, 13),
		Parent = userCard,
	})
	task.spawn(function()
		local ok, thumb = pcall(function()
			return Players:GetUserThumbnailAsync(
				LocalPlayer.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok and thumb then
			avatar.Image = thumb
		end
	end)

	------------------------------------------------------------------
	-- Content area
	------------------------------------------------------------------
	local Content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, sidebarW, 0, TOPBAR),
		Size = UDim2.new(1, -sidebarW, 1, -TOPBAR),
		Parent = Main,
	})

	------------------------------------------------------------------
	-- Floating bubble (reopen button, mainly for mobile)
	------------------------------------------------------------------
	local Bubble = New("TextButton", {
		Name = "Bubble",
		BackgroundColor3 = Theme.Panel,
		Font = Enum.Font.GothamBold,
		Text = IS_MOBILE and "✕" or "N",
		TextSize = 18,
		TextColor3 = Theme.Text,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.4, 0),
		Size = UDim2.new(0, 48, 0, 48),
		AutoButtonColor = false,
		Visible = IS_MOBILE,
		Parent = ScreenGui,
	})
	Round(Bubble, 999)
	local bubbleStroke = Stroke(Bubble, Theme.Accent, 2, 0.1)
	registerAccent(bubbleStroke, "Color")
	New("ImageLabel", {
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.5,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 30, 1, 30),
		ZIndex = 0,
		Parent = Bubble,
	})

	function Window:SetVisible(visible)
		Window.Visible = visible
		Main.Visible = visible
		Bubble.Visible = (not visible) or IS_MOBILE
		Bubble.Text = visible and "✕" or "N"
	end

	function Window:Toggle()
		Window:SetVisible(not Window.Visible)
	end

	MakeDraggable(Bubble, Bubble, function()
		Window:Toggle()
	end)
	MakeDraggable(TopBar, Main)

	track(closeButton.MouseButton1Click:Connect(function()
		Window:SetVisible(false)
		Library:Notify({
			Title = "Hub hidden",
			Content = IS_MOBILE and "Tap the floating N bubble to reopen."
				or ("Press " .. Library.ToggleKey.Name .. " or use the bubble to reopen."),
			Type = "info",
			Duration = 3,
		})
		if not IS_MOBILE then
			Bubble.Visible = true
		end
	end))

	track(minimizeButton.MouseButton1Click:Connect(function()
		Window.Minimized = not Window.Minimized
		if Window.Minimized then
			Tween(Main, 0.22, { Size = UDim2.new(0, winW, 0, TOPBAR) })
		else
			Tween(Main, 0.22, { Size = UDim2.new(0, winW, 0, winH) })
		end
		minimizeButton.Text = Window.Minimized and "+" or "—"
	end))

	track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Library.ToggleKey then
			Window:Toggle()
		end
	end))

	------------------------------------------------------------------
	-- Search filtering
	------------------------------------------------------------------
	local function applySearch()
		local query = string.lower(searchBox.Text)
		local tab = Window.ActiveTab
		if not tab then
			return
		end
		for _, entry in ipairs(tab.Elements) do
			if query == "" then
				entry.Frame.Visible = true
			else
				entry.Frame.Visible = string.find(string.lower(entry.Text), query, 1, true) ~= nil
			end
		end
	end
	track(searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch))

	------------------------------------------------------------------
	-- Tabs
	------------------------------------------------------------------
	local tabOrder = 0

	function Window:CreateTab(name, icon)
		tabOrder = tabOrder + 1

		local Tab = {
			Name = name,
			Elements = {}, -- { {Frame = frame, Text = searchable text} ... }
			Sections = {},
		}

		local tabButton = New("TextButton", {
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, IS_MOBILE and 38 or 34),
			LayoutOrder = tabOrder,
			Parent = tabList,
		})
		Round(tabButton, 8)
		local indicator = New("Frame", {
			Position = UDim2.new(0, 0, 0.5, -8),
			Size = UDim2.new(0, 3, 0, 16),
			BackgroundTransparency = 1,
			Parent = tabButton,
		})
		Round(indicator, 99)
		registerAccent(indicator, "BackgroundColor3")
		local iconLabel = New("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = icon or "•",
			TextSize = 14,
			TextColor3 = Theme.TextDim,
			Position = UDim2.new(0, 10, 0, 0),
			Size = UDim2.new(0, 20, 1, 0),
			Parent = tabButton,
		})
		local nameLabel = New("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = name,
			TextSize = 13,
			TextColor3 = Theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(0, 34, 0, 0),
			Size = UDim2.new(1, -38, 1, 0),
			Parent = tabButton,
		})

		local page = New("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, 0),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Stroke,
			Visible = false,
			Parent = Content,
		})
		Pad(page, 12, 12, 12, 12)
		VList(page, 10)

		Tab.Button = tabButton
		Tab.Page = page

		local function select()
			for _, other in ipairs(Window.Tabs) do
				other.Page.Visible = false
				Tween(other.Button, 0.15, { BackgroundTransparency = 1 })
				other.Button:FindFirstChildOfClass("Frame").BackgroundTransparency = 1
				for _, child in ipairs(other.Button:GetChildren()) do
					if child:IsA("TextLabel") then
						Tween(child, 0.15, { TextColor3 = Theme.TextDim })
					end
				end
			end
			page.Visible = true
			Window.ActiveTab = Tab
			Tween(tabButton, 0.15, { BackgroundTransparency = 0 })
			indicator.BackgroundTransparency = 0
			Tween(iconLabel, 0.15, { TextColor3 = Theme.Text })
			Tween(nameLabel, 0.15, { TextColor3 = Theme.Text })
			applySearch()
		end

		Tab.Select = select
		track(tabButton.MouseButton1Click:Connect(select))

		table.insert(Window.Tabs, Tab)
		if #Window.Tabs == 1 then
			select()
		end

		--------------------------------------------------------------
		-- Sections
		--------------------------------------------------------------
		local sectionOrder = 0

		function Tab:CreateSection(sectionName)
			sectionOrder = sectionOrder + 1

			local Section = {}

			local sectionFrame = New("Frame", {
				BackgroundColor3 = Theme.Sidebar,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = sectionOrder,
				Parent = page,
			})
			Round(sectionFrame, 10)
			Stroke(sectionFrame, Theme.Stroke, 1, 0.5)
			Pad(sectionFrame, 10, 12, 10, 10)
			VList(sectionFrame, 6)

			local headerHolder = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = 0,
				Parent = sectionFrame,
			})
			local headerBar = New("Frame", {
				Position = UDim2.new(0, 0, 0.5, -5),
				Size = UDim2.new(0, 3, 0, 10),
				Parent = headerHolder,
			})
			Round(headerBar, 99)
			registerAccent(headerBar, "BackgroundColor3")
			New("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = sectionName,
				TextSize = 13,
				TextColor3 = Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -10, 1, 0),
				Parent = headerHolder,
			})

			local elementOrder = 0
			local ROW = IS_MOBILE and 40 or 36

			local function registerSearchable(frame, text)
				table.insert(Tab.Elements, { Frame = frame, Text = text })
			end

			local function baseElement(height, searchText, autoSize)
				elementOrder = elementOrder + 1
				local frame = New("Frame", {
					BackgroundColor3 = Theme.Element,
					Size = UDim2.new(1, 0, 0, height),
					AutomaticSize = autoSize and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
					LayoutOrder = elementOrder,
					Parent = sectionFrame,
				})
				Round(frame, 8)
				local stroke = Stroke(frame, Theme.Stroke, 1, 0.6)
				track(frame.MouseEnter:Connect(function()
					Tween(stroke, 0.12, { Color = Theme.Accent, Transparency = 0.3 })
				end))
				track(frame.MouseLeave:Connect(function()
					Tween(stroke, 0.12, { Color = Theme.Stroke, Transparency = 0.6 })
				end))
				registerSearchable(frame, searchText)
				return frame
			end

			local function elementLabel(parent, text, widthOffset)
				return New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = text,
					TextSize = 12,
					TextColor3 = Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.new(0, 12, 0, 0),
					Size = UDim2.new(1, widthOffset or -24, 0, ROW),
					Parent = parent,
				})
			end

			----------------------------------------------------------
			-- Button
			----------------------------------------------------------
			function Section:AddButton(opts)
				opts = opts or {}
				local name = opts.Name or "Button"
				local callback = opts.Callback or function() end

				local frame = baseElement(ROW, name)
				local button = New("TextButton", {
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 1, 0),
					ClipsDescendants = true,
					Parent = frame,
				})
				Round(button, 8)
				elementLabel(frame, name)
				New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = "➜",
					TextSize = 13,
					TextColor3 = Theme.TextDim,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 0),
					Size = UDim2.new(0, 18, 1, 0),
					Parent = frame,
				})
				Pressable(button, 0.97)
				track(button.MouseButton1Click:Connect(function()
					local mouse = UserInputService:GetMouseLocation()
					Ripple(button, mouse.X, mouse.Y)
					task.spawn(callback)
				end))
				return {}
			end

			----------------------------------------------------------
			-- Toggle
			----------------------------------------------------------
			function Section:AddToggle(opts)
				opts = opts or {}
				local name = opts.Name or "Toggle"
				local flag = opts.Flag
				local callback = opts.Callback or function() end
				local value = opts.Default == true

				local frame = baseElement(ROW, name)
				elementLabel(frame, name, -70)

				local switch = New("Frame", {
					BackgroundColor3 = Theme.PanelSoft,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 38, 0, 20),
					Parent = frame,
				})
				Round(switch, 999)
				local switchStroke = Stroke(switch, Theme.Stroke, 1, 0.4)
				local knob = New("Frame", {
					BackgroundColor3 = Theme.TextDim,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 3, 0.5, 0),
					Size = UDim2.new(0, 14, 0, 14),
					Parent = switch,
				})
				Round(knob, 999)

				local hitbox = New("TextButton", {
					BackgroundTransparency = 1,
					Text = "",
					Size = UDim2.new(1, 0, 1, 0),
					Parent = frame,
				})

				local item = {}

				local function render(instant)
					local time = instant and 0 or 0.16
					if value then
						Tween(switch, time, { BackgroundColor3 = Theme.Accent })
						Tween(switchStroke, time, { Transparency = 1 })
						Tween(knob, time, {
							Position = UDim2.new(0, 21, 0.5, 0),
							BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						})
					else
						Tween(switch, time, { BackgroundColor3 = Theme.PanelSoft })
						Tween(switchStroke, time, { Transparency = 0.4 })
						Tween(knob, time, {
							Position = UDim2.new(0, 3, 0.5, 0),
							BackgroundColor3 = Theme.TextDim,
						})
					end
				end

				function item.Set(newValue)
					value = newValue == true
					if flag then
						Library.Flags[flag] = value
					end
					render()
					task.spawn(callback, value)
				end

				track(hitbox.MouseButton1Click:Connect(function()
					item.Set(not value)
				end))

				if flag then
					Library.Flags[flag] = value
					Library.Items[flag] = item
				end
				render(true)
				if value then
					task.spawn(callback, value)
				end
				return item
			end

			----------------------------------------------------------
			-- Slider
			----------------------------------------------------------
			function Section:AddSlider(opts)
				opts = opts or {}
				local name = opts.Name or "Slider"
				local min = opts.Min or 0
				local max = opts.Max or 100
				local decimals = opts.Decimals or 0
				local suffix = opts.Suffix or ""
				local flag = opts.Flag
				local callback = opts.Callback or function() end
				local value = math.clamp(opts.Default or min, min, max)

				local height = IS_MOBILE and 56 or 50
				local frame = baseElement(height, name)
				New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 12,
					TextColor3 = Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.new(0, 12, 0, 6),
					Size = UDim2.new(1, -90, 0, 16),
					Parent = frame,
				})
				local valueLabel = New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = "",
					TextSize = 12,
					TextColor3 = Theme.TextDim,
					TextXAlignment = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 6),
					Size = UDim2.new(0, 76, 0, 16),
					Parent = frame,
				})

				local track_ = New("Frame", {
					BackgroundColor3 = Theme.PanelSoft,
					Position = UDim2.new(0, 12, 1, -18),
					Size = UDim2.new(1, -24, 0, 8),
					Parent = frame,
				})
				Round(track_, 999)
				local fill = New("Frame", {
					Size = UDim2.new(0, 0, 1, 0),
					Parent = track_,
				})
				Round(fill, 999)
				registerAccent(fill, "BackgroundColor3")
				local knob = New("Frame", {
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.new(0, 14, 0, 14),
					ZIndex = 2,
					Parent = track_,
				})
				Round(knob, 999)
				New("UIStroke", {
					Color = Color3.fromRGB(0, 0, 0),
					Thickness = 1,
					Transparency = 0.7,
					Parent = knob,
				})

				-- generous invisible hitbox so it is easy to grab on touch screens
				local hitbox = New("TextButton", {
					BackgroundTransparency = 1,
					Text = "",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.new(1, 0, 0, 34),
					Parent = track_,
				})

				local item = {}

				local function format(num)
					if decimals <= 0 then
						return tostring(math.floor(num + 0.5))
					end
					return string.format("%." .. decimals .. "f", num)
				end

				local function render()
					local alpha = (max == min) and 0 or (value - min) / (max - min)
					fill.Size = UDim2.new(alpha, 0, 1, 0)
					knob.Position = UDim2.new(alpha, 0, 0.5, 0)
					valueLabel.Text = format(value) .. suffix
				end

				function item.Set(newValue)
					local snapped = tonumber(newValue) or min
					if decimals <= 0 then
						snapped = math.floor(snapped + 0.5)
					else
						local mult = 10 ^ decimals
						snapped = math.floor(snapped * mult + 0.5) / mult
					end
					value = math.clamp(snapped, min, max)
					if flag then
						Library.Flags[flag] = value
					end
					render()
					task.spawn(callback, value)
				end

				local sliding = false
				local function setFromPosition(x)
					local alpha = math.clamp(
						(x - track_.AbsolutePosition.X) / math.max(track_.AbsoluteSize.X, 1),
						0, 1
					)
					item.Set(min + (max - min) * alpha)
				end

				track(hitbox.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						sliding = true
						setFromPosition(input.Position.X)
					end
				end))
				track(UserInputService.InputChanged:Connect(function(input)
					if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch) then
						setFromPosition(input.Position.X)
					end
				end))
				track(UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						sliding = false
					end
				end))

				if flag then
					Library.Flags[flag] = value
					Library.Items[flag] = item
				end
				render()
				return item
			end

			----------------------------------------------------------
			-- Dropdown (single or multi select)
			----------------------------------------------------------
			function Section:AddDropdown(opts)
				opts = opts or {}
				local name = opts.Name or "Dropdown"
				local values = opts.Values or {}
				local multi = opts.Multi == true
				local flag = opts.Flag
				local callback = opts.Callback or function() end
				local selected
				if multi then
					selected = {}
					if typeof(opts.Default) == "table" then
						for _, v in ipairs(opts.Default) do
							selected[v] = true
						end
					end
				else
					selected = opts.Default
				end

				local frame = baseElement(ROW, name, true)
				frame.ClipsDescendants = true
				VList(frame, 0, Enum.HorizontalAlignment.Left)

				local header = New("TextButton", {
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, ROW),
					LayoutOrder = 1,
					Parent = frame,
				})
				New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 12,
					TextColor3 = Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.new(0, 12, 0, 0),
					Size = UDim2.new(0.45, -12, 1, 0),
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = header,
				})
				local currentLabel = New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Text = "",
					TextSize = 11,
					TextColor3 = Theme.TextDim,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextTruncate = Enum.TextTruncate.AtEnd,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -30, 0, 0),
					Size = UDim2.new(0.5, 0, 1, 0),
					Parent = header,
				})
				local arrow = New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = "▾",
					TextSize = 13,
					TextColor3 = Theme.TextDim,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 0),
					Size = UDim2.new(0, 16, 1, 0),
					Parent = header,
				})

				local listHolder = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Visible = false,
					LayoutOrder = 2,
					Parent = frame,
				})
				Pad(listHolder, 0, 8, 8, 8)
				VList(listHolder, 4)

				local optionButtons = {}
				local item = {}
				local open = false

				local function displayText()
					if multi then
						local parts = {}
						for _, v in ipairs(values) do
							if selected[v] then
								table.insert(parts, tostring(v))
							end
						end
						if #parts == 0 then
							return "None"
						end
						return table.concat(parts, ", ")
					end
					return selected ~= nil and tostring(selected) or "None"
				end

				local function currentValue()
					if multi then
						local out = {}
						for _, v in ipairs(values) do
							if selected[v] then
								table.insert(out, v)
							end
						end
						return out
					end
					return selected
				end

				local function renderOptions()
					for _, button in pairs(optionButtons) do
						button:Destroy()
					end
					optionButtons = {}
					for index, valueName in ipairs(values) do
						local isPicked = multi and selected[valueName] == true
							or (not multi and selected == valueName)
						local optButton = New("TextButton", {
							BackgroundColor3 = Theme.PanelSoft,
							BackgroundTransparency = isPicked and 0 or 0.5,
							Font = Enum.Font.Gotham,
							Text = "",
							AutoButtonColor = false,
							Size = UDim2.new(1, 0, 0, IS_MOBILE and 32 or 28),
							LayoutOrder = index,
							Parent = listHolder,
						})
						Round(optButton, 6)
						local pickedDot = New("Frame", {
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.new(0, 8, 0.5, 0),
							Size = UDim2.new(0, 6, 0, 6),
							BackgroundColor3 = Theme.Accent,
							BackgroundTransparency = isPicked and 0 or 1,
							Parent = optButton,
						})
						Round(pickedDot, 99)
						New("TextLabel", {
							BackgroundTransparency = 1,
							Font = isPicked and Enum.Font.GothamBold or Enum.Font.Gotham,
							Text = tostring(valueName),
							TextSize = 11,
							TextColor3 = isPicked and Theme.Text or Theme.TextDim,
							TextXAlignment = Enum.TextXAlignment.Left,
							Position = UDim2.new(0, 22, 0, 0),
							Size = UDim2.new(1, -28, 1, 0),
							Parent = optButton,
						})
						track(optButton.MouseButton1Click:Connect(function()
							if multi then
								selected[valueName] = not selected[valueName] or nil
							else
								selected = valueName
							end
							if flag then
								Library.Flags[flag] = currentValue()
							end
							currentLabel.Text = displayText()
							renderOptions()
							task.spawn(callback, currentValue())
							if not multi then
								open = false
								listHolder.Visible = false
								arrow.Text = "▾"
							end
						end))
						table.insert(optionButtons, optButton)
					end
				end

				track(header.MouseButton1Click:Connect(function()
					open = not open
					listHolder.Visible = open
					arrow.Text = open and "▴" or "▾"
				end))

				function item.Set(newValue)
					if multi then
						selected = {}
						if typeof(newValue) == "table" then
							for _, v in ipairs(newValue) do
								selected[v] = true
							end
						end
					else
						selected = newValue
					end
					if flag then
						Library.Flags[flag] = currentValue()
					end
					currentLabel.Text = displayText()
					renderOptions()
					task.spawn(callback, currentValue())
				end

				function item.SetValues(newValues)
					values = newValues or {}
					renderOptions()
					currentLabel.Text = displayText()
				end

				if flag then
					Library.Flags[flag] = currentValue()
					Library.Items[flag] = item
				end
				currentLabel.Text = displayText()
				renderOptions()
				return item
			end

			----------------------------------------------------------
			-- Textbox
			----------------------------------------------------------
			function Section:AddTextbox(opts)
				opts = opts or {}
				local name = opts.Name or "Textbox"
				local placeholder = opts.Placeholder or "..."
				local flag = opts.Flag
				local callback = opts.Callback or function() end
				local value = opts.Default or ""

				local frame = baseElement(ROW, name)
				elementLabel(frame, name, -150)

				local boxHolder = New("Frame", {
					BackgroundColor3 = Theme.PanelSoft,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.new(0, IS_MOBILE and 120 or 140, 0, ROW - 12),
					Parent = frame,
				})
				Round(boxHolder, 6)
				Stroke(boxHolder, Theme.Stroke, 1, 0.4)
				local box = New("TextBox", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					PlaceholderText = placeholder,
					PlaceholderColor3 = Theme.TextDim,
					Text = value,
					TextSize = 11,
					TextColor3 = Theme.Text,
					ClearTextOnFocus = false,
					Size = UDim2.new(1, -12, 1, 0),
					Position = UDim2.new(0, 6, 0, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = boxHolder,
				})

				local item = {}

				function item.Set(newValue)
					value = tostring(newValue or "")
					box.Text = value
					if flag then
						Library.Flags[flag] = value
					end
					task.spawn(callback, value)
				end

				function item.Get()
					return box.Text
				end

				track(box.FocusLost:Connect(function()
					value = box.Text
					if flag then
						Library.Flags[flag] = value
					end
					task.spawn(callback, value)
				end))

				if flag then
					Library.Flags[flag] = value
					Library.Items[flag] = item
				end
				return item
			end

			----------------------------------------------------------
			-- Keybind
			----------------------------------------------------------
			function Section:AddKeybind(opts)
				opts = opts or {}
				local name = opts.Name or "Keybind"
				local flag = opts.Flag
				local callback = opts.Callback or function() end       -- fired when the key is pressed
				local onChanged = opts.OnChanged or function() end     -- fired when the bind changes
				local key = opts.Default -- Enum.KeyCode or nil

				local frame = baseElement(ROW, name)
				elementLabel(frame, name, -110)

				local bindButton = New("TextButton", {
					BackgroundColor3 = Theme.PanelSoft,
					Font = Enum.Font.GothamBold,
					Text = key and key.Name or "None",
					TextSize = 11,
					TextColor3 = Theme.TextDim,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.new(0, 92, 0, ROW - 14),
					AutoButtonColor = false,
					Parent = frame,
				})
				Round(bindButton, 6)
				Stroke(bindButton, Theme.Stroke, 1, 0.4)
				Pressable(bindButton)

				local listening = false
				local item = {}

				function item.Set(newKey)
					key = newKey
					bindButton.Text = key and key.Name or "None"
					if flag then
						Library.Flags[flag] = key
					end
					task.spawn(onChanged, key)
				end

				track(bindButton.MouseButton1Click:Connect(function()
					listening = true
					bindButton.Text = "..."
					bindButton.TextColor3 = Theme.Accent
				end))

				track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
					if listening then
						if input.UserInputType == Enum.UserInputType.Keyboard then
							listening = false
							bindButton.TextColor3 = Theme.TextDim
							if input.KeyCode == Enum.KeyCode.Escape then
								item.Set(nil)
							else
								item.Set(input.KeyCode)
							end
						end
						return
					end
					if gameProcessed then
						return
					end
					if key and input.KeyCode == key then
						task.spawn(callback)
					end
				end))

				if flag then
					Library.Flags[flag] = key
					Library.Items[flag] = item
				end
				return item
			end

			----------------------------------------------------------
			-- Colour picker (full HSV)
			----------------------------------------------------------
			function Section:AddColorPicker(opts)
				opts = opts or {}
				local name = opts.Name or "Color"
				local flag = opts.Flag
				local callback = opts.Callback or function() end
				local color = opts.Default or Theme.Accent
				local hue, sat, val = Color3.toHSV(color)

				local frame = baseElement(ROW, name, true)
				frame.ClipsDescendants = true
				VList(frame, 0, Enum.HorizontalAlignment.Left)

				local header = New("TextButton", {
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, ROW),
					LayoutOrder = 1,
					Parent = frame,
				})
				New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 12,
					TextColor3 = Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.new(0, 12, 0, 0),
					Size = UDim2.new(1, -70, 1, 0),
					Parent = header,
				})
				local swatch = New("Frame", {
					BackgroundColor3 = color,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.new(0, 34, 0, 18),
					Parent = header,
				})
				Round(swatch, 5)
				Stroke(swatch, Theme.Stroke, 1, 0.3)

				local pickerHolder = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 122),
					Visible = false,
					LayoutOrder = 2,
					Parent = frame,
				})

				-- Saturation / value square
				local svBox = New("Frame", {
					BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
					Position = UDim2.new(0, 12, 0, 4),
					Size = UDim2.new(1, -56, 0, 100),
					Parent = pickerHolder,
				})
				Round(svBox, 6)
				local whiteOverlay = New("Frame", {
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					Size = UDim2.new(1, 0, 1, 0),
					Parent = svBox,
				})
				Round(whiteOverlay, 6)
				New("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
					Parent = whiteOverlay,
				})
				local blackOverlay = New("Frame", {
					BackgroundColor3 = Color3.fromRGB(0, 0, 0),
					Size = UDim2.new(1, 0, 1, 0),
					Parent = svBox,
				})
				Round(blackOverlay, 6)
				New("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(1, 0),
					}),
					Parent = blackOverlay,
				})
				local svCursor = New("Frame", {
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.new(0, 10, 0, 10),
					ZIndex = 3,
					Parent = svBox,
				})
				Round(svCursor, 99)
				New("UIStroke", {
					Color = Color3.fromRGB(0, 0, 0),
					Thickness = 1.5,
					Parent = svCursor,
				})

				-- Hue bar
				local hueBar = New("Frame", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 4),
					Size = UDim2.new(0, 16, 0, 100),
					Parent = pickerHolder,
				})
				Round(hueBar, 6)
				local hueKeypoints = {}
				for i = 0, 6 do
					table.insert(hueKeypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
				end
				New("UIGradient", {
					Color = ColorSequence.new(hueKeypoints),
					Rotation = 90,
					Parent = hueBar,
				})
				local hueCursor = New("Frame", {
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0, 0),
					Size = UDim2.new(1, 4, 0, 4),
					ZIndex = 3,
					Parent = hueBar,
				})
				Round(hueCursor, 99)
				New("UIStroke", {
					Color = Color3.fromRGB(0, 0, 0),
					Thickness = 1,
					Parent = hueCursor,
				})

				local hexLabel = New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Text = "",
					TextSize = 10,
					TextColor3 = Theme.TextDim,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.new(0, 12, 1, -16),
					Size = UDim2.new(1, -24, 0, 14),
					Parent = pickerHolder,
				})

				local item = {}
				local open = false

				local function render(fireCallback)
					color = Color3.fromHSV(hue, sat, val)
					swatch.BackgroundColor3 = color
					svBox.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
					svCursor.Position = UDim2.new(sat, 0, 1 - val, 0)
					hueCursor.Position = UDim2.new(0.5, 0, hue, 0)
					hexLabel.Text = string.format(
						"#%02X%02X%02X",
						math.floor(color.R * 255 + 0.5),
						math.floor(color.G * 255 + 0.5),
						math.floor(color.B * 255 + 0.5)
					)
					if flag then
						Library.Flags[flag] = color
					end
					if fireCallback then
						task.spawn(callback, color)
					end
				end

				function item.Set(newColor)
					hue, sat, val = Color3.toHSV(newColor)
					render(true)
				end

				track(header.MouseButton1Click:Connect(function()
					open = not open
					pickerHolder.Visible = open
				end))

				local svDragging = false
				local hueDragging = false

				local function updateSV(position)
					sat = math.clamp(
						(position.X - svBox.AbsolutePosition.X) / math.max(svBox.AbsoluteSize.X, 1), 0, 1)
					val = 1 - math.clamp(
						(position.Y - svBox.AbsolutePosition.Y) / math.max(svBox.AbsoluteSize.Y, 1), 0, 1)
					render(true)
				end
				local function updateHue(position)
					hue = math.clamp(
						(position.Y - hueBar.AbsolutePosition.Y) / math.max(hueBar.AbsoluteSize.Y, 1), 0, 1)
					render(true)
				end

				track(svBox.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						svDragging = true
						updateSV(input.Position)
					end
				end))
				track(hueBar.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						hueDragging = true
						updateHue(input.Position)
					end
				end))
				track(UserInputService.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch then
						if svDragging then
							updateSV(input.Position)
						end
						if hueDragging then
							updateHue(input.Position)
						end
					end
				end))
				track(UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch then
						svDragging = false
						hueDragging = false
					end
				end))

				if flag then
					Library.Flags[flag] = color
					Library.Items[flag] = item
				end
				render(false)
				return item
			end

			----------------------------------------------------------
			-- Label / paragraph
			----------------------------------------------------------
			function Section:AddLabel(text)
				local frame = baseElement(26, text or "")
				frame.BackgroundTransparency = 1
				frame:FindFirstChildOfClass("UIStroke"):Destroy()
				local label = New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Text = text or "",
					TextSize = 12,
					TextColor3 = Theme.TextDim,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					Position = UDim2.new(0, 4, 0, 0),
					Size = UDim2.new(1, -8, 1, 0),
					Parent = frame,
				})
				local item = {}
				function item.Set(newText)
					label.Text = tostring(newText)
				end
				return item
			end

			function Section:AddParagraph(titleText, bodyText)
				local frame = baseElement(0, (titleText or "") .. " " .. (bodyText or ""), true)
				Pad(frame, 10, 10, 12, 12)
				local title = New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = titleText or "",
					TextSize = 12,
					TextColor3 = Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					Size = UDim2.new(1, 0, 0, 16),
					Parent = frame,
				})
				local body = New("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Text = bodyText or "",
					TextSize = 11,
					TextColor3 = Theme.TextDim,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = true,
					Position = UDim2.new(0, 0, 0, 20),
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = frame,
				})
				local item = {}
				function item.Set(newTitle, newBody)
					if newTitle then
						title.Text = newTitle
					end
					if newBody then
						body.Text = newBody
					end
				end
				return item
			end

			table.insert(Tab.Sections, Section)
			return Section
		end

		return Tab
	end

	function Window:Destroy()
		for _, connection in ipairs(Library.Connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		ScreenGui:Destroy()
	end

	Library.Window = Window
	return Window
end

----------------------------------------------------------------------
-- Watermark (FPS / ping)
----------------------------------------------------------------------
local Watermark = New("Frame", {
	BackgroundColor3 = Theme.Panel,
	Position = UDim2.new(0, 14, 0, 14),
	Size = UDim2.new(0, 0, 0, 26),
	AutomaticSize = Enum.AutomaticSize.X,
	Visible = false,
	Parent = ScreenGui,
})
Round(Watermark, 7)
Stroke(Watermark, Theme.Stroke, 1, 0.3)
Pad(Watermark, 0, 0, 10, 10)
local watermarkAccent = New("Frame", {
	Position = UDim2.new(0, -10, 0, 0),
	Size = UDim2.new(0, 3, 1, 0),
	Parent = Watermark,
})
registerAccent(watermarkAccent, "BackgroundColor3")
local watermarkLabel = New("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Nebula Hub",
	TextSize = 11,
	TextColor3 = Theme.Text,
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = Watermark,
})

local fpsFrames = 0
local fpsValue = 60
track(RunService.Heartbeat:Connect(function()
	fpsFrames = fpsFrames + 1
end))
task.spawn(function()
	while ScreenGui.Parent do
		task.wait(1)
		fpsValue = fpsFrames
		fpsFrames = 0
		if Watermark.Visible then
			local ping = 0
			pcall(function()
				ping = math.floor(
					StatsService.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5
				)
			end)
			watermarkLabel.Text = string.format("Nebula Hub  |  %d fps  |  %d ms", fpsValue, ping)
		end
	end
end)

----------------------------------------------------------------------
----------------------------------------------------------------------
--  BUILD THE HUB
--  Everything below uses the library above. Add your own stuff here!
----------------------------------------------------------------------
----------------------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "Nebula Hub",
	Subtitle = "v1.0",
	Width = 600,
	Height = 430,
})

----------------------------------------------------------------------
-- HOME TAB
----------------------------------------------------------------------
local HomeTab = Window:CreateTab("Home", "⌂")

local welcomeSection = HomeTab:CreateSection("Welcome")
welcomeSection:AddParagraph(
	"Hey, " .. LocalPlayer.DisplayName .. "!",
	"Welcome to Nebula Hub. Use the tabs on the left to browse features. "
		.. (IS_MOBILE
			and "Drag the title bar to move the window and use the floating N bubble to hide or show the hub."
			or "Press RightShift to hide or show the hub (rebindable in Settings).")
)
welcomeSection:AddButton({
	Name = "Test notification",
	Callback = function()
		Library:Notify({
			Title = "It works!",
			Content = "This is what notifications look like.",
			Type = "success",
			Duration = 4,
		})
	end,
})

local serverSection = HomeTab:CreateSection("Server")
local playersLabel = serverSection:AddLabel("Players: ...")
task.spawn(function()
	while ScreenGui.Parent do
		playersLabel.Set(string.format(
			"Players: %d / %d   |   Place ID: %d",
			#Players:GetPlayers(),
			Players.MaxPlayers,
			game.PlaceId
		))
		task.wait(3)
	end
end)
serverSection:AddButton({
	Name = "Rejoin server",
	Callback = function()
		Library:Notify({ Title = "Rejoining", Content = "Teleporting back into this place...", Type = "info" })
		pcall(function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end)
	end,
})
serverSection:AddButton({
	Name = "Copy Place ID",
	Callback = function()
		local ok = pcall(function()
			(setclipboard or toclipboard)(tostring(game.PlaceId))
		end)
		Library:Notify({
			Title = ok and "Copied" or "Unavailable",
			Content = ok and ("Place ID " .. game.PlaceId .. " copied to clipboard.")
				or "Your environment has no clipboard function.",
			Type = ok and "success" or "warning",
		})
	end,
})

----------------------------------------------------------------------
-- PLAYER TAB
----------------------------------------------------------------------
local PlayerTab = Window:CreateTab("Player", "☻")

local DEFAULT_WALKSPEED = 16
local DEFAULT_JUMPPOWER = 50

local function getHumanoid()
	local character = LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function applyMovement()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	if Library.Flags.WalkSpeed then
		humanoid.WalkSpeed = Library.Flags.WalkSpeed
	end
	if Library.Flags.JumpPower then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Library.Flags.JumpPower
	end
end

local movementSection = PlayerTab:CreateSection("Movement")
movementSection:AddSlider({
	Name = "Walk speed",
	Min = 8,
	Max = 250,
	Default = DEFAULT_WALKSPEED,
	Suffix = " sps",
	Flag = "WalkSpeed",
	Callback = function(value)
		local humanoid = getHumanoid()
		if humanoid then
			humanoid.WalkSpeed = value
		end
	end,
})
movementSection:AddSlider({
	Name = "Jump power",
	Min = 20,
	Max = 350,
	Default = DEFAULT_JUMPPOWER,
	Flag = "JumpPower",
	Callback = function(value)
		local humanoid = getHumanoid()
		if humanoid then
			humanoid.UseJumpPower = true
			humanoid.JumpPower = value
		end
	end,
})
movementSection:AddToggle({
	Name = "Re-apply after respawn",
	Default = false,
	Flag = "KeepMovement",
	Callback = function() end,
})
movementSection:AddButton({
	Name = "Reset movement to default",
	Callback = function()
		local walkItem = Library.Items.WalkSpeed
		local jumpItem = Library.Items.JumpPower
		if walkItem then
			walkItem.Set(DEFAULT_WALKSPEED)
		end
		if jumpItem then
			jumpItem.Set(DEFAULT_JUMPPOWER)
		end
		Library:Notify({ Title = "Movement reset", Content = "Walk speed and jump power restored.", Type = "info" })
	end,
})

track(LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.6)
	if Library.Flags.KeepMovement then
		applyMovement()
	end
end))

local characterSection = PlayerTab:CreateSection("Character")
characterSection:AddButton({
	Name = "Reset character",
	Callback = function()
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end,
})
characterSection:AddSlider({
	Name = "Camera FOV",
	Min = 30,
	Max = 120,
	Default = 70,
	Suffix = "°",
	Flag = "CameraFOV",
	Callback = function(value)
		if workspace.CurrentCamera then
			workspace.CurrentCamera.FieldOfView = value
		end
	end,
})

----------------------------------------------------------------------
-- VISUALS TAB
----------------------------------------------------------------------
local VisualsTab = Window:CreateTab("Visuals", "✦")

local savedLighting = {
	Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime,
	FogEnd = Lighting.FogEnd,
	GlobalShadows = Lighting.GlobalShadows,
	Ambient = Lighting.Ambient,
}

local lightingSection = VisualsTab:CreateSection("Lighting")
lightingSection:AddToggle({
	Name = "Fullbright",
	Default = false,
	Flag = "Fullbright",
	Callback = function(enabled)
		if enabled then
			Lighting.Brightness = 2
			Lighting.GlobalShadows = false
			Lighting.Ambient = Color3.fromRGB(178, 178, 178)
		else
			Lighting.Brightness = savedLighting.Brightness
			Lighting.GlobalShadows = savedLighting.GlobalShadows
			Lighting.Ambient = savedLighting.Ambient
		end
	end,
})
lightingSection:AddToggle({
	Name = "Remove fog",
	Default = false,
	Flag = "NoFog",
	Callback = function(enabled)
		Lighting.FogEnd = enabled and 1e9 or savedLighting.FogEnd
	end,
})
lightingSection:AddSlider({
	Name = "Time of day",
	Min = 0,
	Max = 24,
	Decimals = 1,
	Default = math.floor(Lighting.ClockTime * 10 + 0.5) / 10,
	Suffix = "h",
	Flag = "TimeOfDay",
	Callback = function(value)
		Lighting.ClockTime = value
	end,
})
lightingSection:AddButton({
	Name = "Restore original lighting",
	Callback = function()
		for property, original in pairs(savedLighting) do
			pcall(function()
				Lighting[property] = original
			end)
		end
		Library:Notify({ Title = "Lighting restored", Content = "All lighting values reset.", Type = "info" })
	end,
})

local interfaceSection = VisualsTab:CreateSection("Interface")
interfaceSection:AddToggle({
	Name = "FPS / ping watermark",
	Default = false,
	Flag = "Watermark",
	Callback = function(enabled)
		Watermark.Visible = enabled
	end,
})

----------------------------------------------------------------------
-- SCRIPTS TAB
----------------------------------------------------------------------
local ScriptsTab = Window:CreateTab("Scripts", "≡")

local runnerSection = ScriptsTab:CreateSection("Quick runner")
runnerSection:AddParagraph(
	"Run your own code",
	"Type Luau code below and press Execute. Requires an executor that provides loadstring."
)
local codeBox = runnerSection:AddTextbox({
	Name = "Code",
	Placeholder = "print('hello')",
	Flag = "QuickCode",
})
runnerSection:AddButton({
	Name = "Execute",
	Callback = function()
		local source = codeBox.Get()
		if source == "" then
			Library:Notify({ Title = "Nothing to run", Content = "The code box is empty.", Type = "warning" })
			return
		end
		local compile = loadstring or load
		if not compile then
			Library:Notify({
				Title = "Executor required",
				Content = "loadstring is not available in this environment.",
				Type = "error",
			})
			return
		end
		local fn, compileError = compile(source)
		if not fn then
			Library:Notify({ Title = "Syntax error", Content = tostring(compileError), Type = "error", Duration = 6 })
			return
		end
		local ok, runtimeError = pcall(fn)
		if ok then
			Library:Notify({ Title = "Executed", Content = "Code ran without errors.", Type = "success" })
		else
			Library:Notify({ Title = "Runtime error", Content = tostring(runtimeError), Type = "error", Duration = 6 })
		end
	end,
})

local mySection = ScriptsTab:CreateSection("Your scripts")
mySection:AddParagraph(
	"Add your own buttons here",
	"Open NebulaHub.lua and find the SCRIPTS TAB block near the bottom. "
		.. "Copy one of the AddButton calls and drop your own code in its Callback."
)
mySection:AddButton({
	Name = "Example script slot 1",
	Callback = function()
		Library:Notify({
			Title = "Slot 1",
			Content = "Put your own code in this button's callback.",
			Type = "info",
		})
	end,
})
mySection:AddButton({
	Name = "Example script slot 2",
	Callback = function()
		Library:Notify({
			Title = "Slot 2",
			Content = "Put your own code in this button's callback.",
			Type = "info",
		})
	end,
})

----------------------------------------------------------------------
-- SCRIPT FINDER TAB
-- Searches public script APIs (ScriptBlox + Rscripts) and lets you
-- execute the results directly from the hub.
----------------------------------------------------------------------
local FinderTab = Window:CreateTab("Finder", "⌕")

do
	local FINDER_ROW = IS_MOBILE and 40 or 36

	--------------------------------------------------------------
	-- HTTP helpers (work across executors, fall back to HttpGet)
	--------------------------------------------------------------
	local function finderHttpGet(url)
		local requestFn = (typeof(syn) == "table" and syn.request)
			or (typeof(http) == "table" and http.request)
			or (typeof(fluxus) == "table" and fluxus.request)
			or http_request
			or request
		if typeof(requestFn) == "function" then
			local ok, response = pcall(requestFn, { Url = url, Method = "GET" })
			if ok and typeof(response) == "table" then
				local body = response.Body or response.body
				local status = response.StatusCode or response.status_code
				if typeof(body) == "string" and #body > 0 and (status == nil or status == 200) then
					return body
				end
			end
		end
		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and typeof(body) == "string" and #body > 0 then
			return body
		end
		return nil
	end

	local function finderGetJson(url)
		local body = finderHttpGet(url)
		if not body then
			return nil
		end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if ok and typeof(data) == "table" then
			return data
		end
		return nil
	end

	local function urlEncode(text)
		local encoded = tostring(text):gsub("[^%w%-%.%_%~ ]", function(char)
			return string.format("%%%02X", string.byte(char))
		end)
		encoded = encoded:gsub(" ", "%%20")
		return encoded
	end

	--------------------------------------------------------------
	-- Current game detection
	--------------------------------------------------------------
	local cachedGameName
	local function getGameName()
		if cachedGameName then
			return cachedGameName
		end
		local ok, info = pcall(function()
			return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
		end)
		if ok and typeof(info) == "table" and info.Name then
			cachedGameName = tostring(info.Name)
			return cachedGameName
		end
		return nil
	end

	-- Strips emojis / tags like "[UPDATE]" so the name searches better
	local function cleanGameName(name)
		local cleaned = name:gsub("%b[]", ""):gsub("%b()", "")
		cleaned = cleaned:gsub("[^%w%s]", "")
		cleaned = cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
		return cleaned
	end

	--------------------------------------------------------------
	-- Script sources
	--------------------------------------------------------------
	local function searchScriptBlox(query, page)
		local url = "https://scriptblox.com/api/script/search?q=" .. urlEncode(query)
			.. "&page=" .. tostring(page) .. "&max=20"
		local data = finderGetJson(url)
		local result = data and data.result
		if not result or typeof(result.scripts) ~= "table" then
			-- the API returns { message = "..." } when search is down
			local message = data and typeof(data.message) == "string" and data.message or nil
			return nil, nil, message
		end
		local entries = {}
		for _, raw in ipairs(result.scripts) do
			table.insert(entries, {
				Title = tostring(raw.title or "Untitled"),
				GameName = (typeof(raw.game) == "table" and tostring(raw.game.name or "")) or "",
				PlaceId = (typeof(raw.game) == "table" and tonumber(raw.game.gameId)) or nil,
				Views = tonumber(raw.views) or 0,
				Verified = raw.verified == true,
				HasKey = raw.key == true,
				Patched = raw.isPatched == true,
				Universal = raw.isUniversal == true,
				Paid = raw.scriptType == "paid",
				Source = (typeof(raw.script) == "string" and #raw.script > 0) and raw.script or nil,
				Slug = (typeof(raw.slug) == "string" and raw.slug) or nil,
				From = "ScriptBlox",
			})
		end
		return entries, math.max(tonumber(result.totalPages) or 1, 1)
	end

	local function searchRscripts(query, page)
		local url = "https://rscripts.net/api/v2/scripts?page=" .. tostring(page)
			.. "&orderBy=views&sort=desc&q=" .. urlEncode(query)
		local data = finderGetJson(url)
		if not data or typeof(data.scripts) ~= "table" then
			local message = data and typeof(data.error) == "string" and data.error or nil
			return nil, nil, message
		end
		local entries = {}
		for _, raw in ipairs(data.scripts) do
			table.insert(entries, {
				Title = tostring(raw.title or "Untitled"),
				GameName = (typeof(raw.game) == "table" and tostring(raw.game.title or "")) or "",
				PlaceId = (typeof(raw.game) == "table" and tonumber(raw.game.placeId)) or nil,
				Views = tonumber(raw.views) or 0,
				Verified = typeof(raw.user) == "table" and raw.user.verified == true,
				HasKey = raw.keySystem == true,
				Patched = false,
				Universal = false,
				Paid = raw.paid == true,
				RawUrl = (typeof(raw.rawScript) == "string" and #raw.rawScript > 0) and raw.rawScript or nil,
				From = "Rscripts",
			})
		end
		local totalPages = (typeof(data.info) == "table" and tonumber(data.info.maxPages)) or 1
		return entries, math.max(totalPages, 1)
	end

	-- Gets the actual Lua source for a result (some APIs only return links)
	local function resolveSource(entry)
		if entry.Source then
			return entry.Source
		end
		if entry.RawUrl then
			local body = finderHttpGet(entry.RawUrl)
			if body and #body > 0 then
				return body
			end
		end
		if entry.Slug then
			local data = finderGetJson("https://scriptblox.com/api/script/" .. entry.Slug)
			if data and typeof(data.script) == "table"
				and typeof(data.script.script) == "string" and #data.script.script > 0 then
				return data.script.script
			end
			local raw = finderHttpGet("https://rawscripts.net/raw/" .. entry.Slug)
			if raw and #raw > 0 and not raw:find("^%s*<") then
				return raw
			end
		end
		return nil
	end

	--------------------------------------------------------------
	-- Execute / copy actions
	--------------------------------------------------------------
	local function executeEntry(entry)
		Library:Notify({
			Title = "Fetching script",
			Content = entry.Title,
			Type = "info",
			Duration = 2,
		})
		local source = resolveSource(entry)
		if not source then
			Library:Notify({
				Title = "Fetch failed",
				Content = "Could not download this script's source.",
				Type = "error",
				Duration = 5,
			})
			return
		end
		local compile = loadstring or load
		if not compile then
			Library:Notify({
				Title = "Executor required",
				Content = "loadstring is not available in this environment.",
				Type = "error",
				Duration = 5,
			})
			return
		end
		local fn, compileError = compile(source)
		if not fn then
			Library:Notify({
				Title = "Syntax error",
				Content = tostring(compileError),
				Type = "error",
				Duration = 6,
			})
			return
		end
		local ok, runtimeError = pcall(fn)
		if ok then
			Library:Notify({
				Title = "Executed",
				Content = entry.Title .. (entry.HasKey and " (this script uses a key system)" or ""),
				Type = "success",
				Duration = 4,
			})
		else
			Library:Notify({
				Title = "Runtime error",
				Content = tostring(runtimeError),
				Type = "error",
				Duration = 6,
			})
		end
	end

	local function copyEntry(entry)
		local clipboard = setclipboard or toclipboard
		if not clipboard then
			Library:Notify({
				Title = "Unavailable",
				Content = "Your environment has no clipboard function.",
				Type = "warning",
			})
			return
		end
		local source = resolveSource(entry)
		if not source then
			Library:Notify({
				Title = "Fetch failed",
				Content = "Could not download this script's source.",
				Type = "error",
			})
			return
		end
		pcall(clipboard, source)
		Library:Notify({
			Title = "Copied",
			Content = "Script source copied to clipboard.",
			Type = "success",
		})
	end

	--------------------------------------------------------------
	-- UI: section builder matching the library style
	--------------------------------------------------------------
	local function finderSection(titleText, order)
		local sectionFrame = New("Frame", {
			BackgroundColor3 = Theme.Sidebar,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = FinderTab.Page,
		})
		Round(sectionFrame, 10)
		Stroke(sectionFrame, Theme.Stroke, 1, 0.5)
		Pad(sectionFrame, 10, 12, 10, 10)
		VList(sectionFrame, 6)

		local headerHolder = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 0,
			Parent = sectionFrame,
		})
		local headerBar = New("Frame", {
			Position = UDim2.new(0, 0, 0.5, -5),
			Size = UDim2.new(0, 3, 0, 10),
			Parent = headerHolder,
		})
		Round(headerBar, 99)
		registerAccent(headerBar, "BackgroundColor3")
		New("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = titleText,
			TextSize = 13,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(0, 10, 0, 0),
			Size = UDim2.new(1, -10, 1, 0),
			Parent = headerHolder,
		})
		return sectionFrame
	end

	--------------------------------------------------------------
	-- UI: search section
	--------------------------------------------------------------
	local searchSection = finderSection("Script Finder", 1)

	New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Search ScriptBlox or Rscripts for free Roblox scripts and run them right here, "
			.. "or let the hub find scripts made for the game you are playing.",
		TextSize = 11,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = searchSection,
	})

	-- Search bar row
	local searchRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, FINDER_ROW),
		LayoutOrder = 2,
		Parent = searchSection,
	})
	local searchBoxHolder = New("Frame", {
		BackgroundColor3 = Theme.Element,
		Size = UDim2.new(1, -86, 1, 0),
		Parent = searchRow,
	})
	Round(searchBoxHolder, 8)
	Stroke(searchBoxHolder, Theme.Stroke, 1, 0.4)
	New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "⌕",
		TextSize = 16,
		TextColor3 = Theme.TextDim,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(0, 16, 1, 0),
		Parent = searchBoxHolder,
	})
	local finderSearchBox = New("TextBox", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		PlaceholderText = "Search scripts (e.g. blade ball, admin)...",
		PlaceholderColor3 = Theme.TextDim,
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false,
		Position = UDim2.new(0, 32, 0, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Parent = searchBoxHolder,
	})
	local searchButton = New("TextButton", {
		Font = Enum.Font.GothamBold,
		Text = "Search",
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 80, 1, 0),
		AutoButtonColor = false,
		Parent = searchRow,
	})
	Round(searchButton, 8)
	registerAccent(searchButton, "BackgroundColor3")
	Pressable(searchButton)

	-- "This game" button
	local gameButton = New("TextButton", {
		BackgroundColor3 = Theme.Element,
		Font = Enum.Font.GothamMedium,
		Text = "🎮  Find scripts for this game",
		TextSize = 12,
		TextColor3 = Theme.Text,
		Size = UDim2.new(1, 0, 0, FINDER_ROW),
		AutoButtonColor = false,
		LayoutOrder = 3,
		Parent = searchSection,
	})
	Round(gameButton, 8)
	Stroke(gameButton, Theme.Stroke, 1, 0.6)
	Pressable(gameButton, 0.97)

	-- Source picker (segmented buttons)
	local sourceRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, FINDER_ROW - 8),
		LayoutOrder = 4,
		Parent = searchSection,
	})
	New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "Source",
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 2, 0, 0),
		Size = UDim2.new(0, 80, 1, 0),
		Parent = sourceRow,
	})

	local selectedSource = "ScriptBlox"
	local sourceButtons = {}
	local function refreshSourceButtons()
		for name, button in pairs(sourceButtons) do
			local active = name == selectedSource
			button.BackgroundColor3 = active and Theme.Accent or Theme.Element
			button.TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextDim
			button.Font = active and Enum.Font.GothamBold or Enum.Font.Gotham
		end
	end
	for index, name in ipairs({ "ScriptBlox", "Rscripts" }) do
		local button = New("TextButton", {
			Text = name,
			TextSize = 11,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(index - 1) * 92 - (index - 1) * 6, 0, 0),
			Size = UDim2.new(0, 92, 1, 0),
			AutoButtonColor = false,
			Parent = sourceRow,
		})
		Round(button, 8)
		Pressable(button)
		sourceButtons[name] = button
		track(button.MouseButton1Click:Connect(function()
			selectedSource = name
			refreshSourceButtons()
		end))
	end
	refreshSourceButtons()

	--------------------------------------------------------------
	-- UI: results section
	--------------------------------------------------------------
	local resultsSection = finderSection("Results", 2)

	local statusLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Search above, or tap 'Find scripts for this game'.",
		TextSize = 11,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = resultsSection,
	})

	local resultsHolder = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = resultsSection,
	})
	VList(resultsHolder, 6)

	-- Pagination row
	local pageRow = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Visible = false,
		LayoutOrder = 3,
		Parent = resultsSection,
	})
	local function pageButton(text, anchorRight)
		local button = New("TextButton", {
			BackgroundColor3 = Theme.Element,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextSize = 12,
			TextColor3 = Theme.Text,
			AnchorPoint = anchorRight and Vector2.new(1, 0) or Vector2.new(0, 0),
			Position = anchorRight and UDim2.new(1, 0, 0, 0) or UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(0, 76, 1, 0),
			AutoButtonColor = false,
			Parent = pageRow,
		})
		Round(button, 8)
		Stroke(button, Theme.Stroke, 1, 0.6)
		Pressable(button)
		return button
	end
	local prevButton = pageButton("◀ Prev", false)
	local nextButton = pageButton("Next ▶", true)
	local pageLabel = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Page 1 / 1",
		TextSize = 11,
		TextColor3 = Theme.TextDim,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = pageRow,
	})

	--------------------------------------------------------------
	-- Result cards
	--------------------------------------------------------------
	local BADGE_COLORS = {
		["THIS GAME"] = Theme.Accent,
		VERIFIED  = Color3.fromRGB(86, 214, 134),
		KEY       = Color3.fromRGB(255, 190, 92),
		PAID      = Color3.fromRGB(255, 150, 70),
		PATCHED   = Color3.fromRGB(255, 96, 110),
		UNIVERSAL = Color3.fromRGB(96, 148, 255),
	}

	local function clearResults()
		for _, child in ipairs(resultsHolder:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end

	local function formatViews(views)
		if views >= 1e6 then
			return string.format("%.1fM", views / 1e6)
		elseif views >= 1e3 then
			return string.format("%.1fK", views / 1e3)
		end
		return tostring(views)
	end

	local function createResultCard(entry, order, matchesGame)
		local card = New("Frame", {
			BackgroundColor3 = Theme.Element,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = resultsHolder,
		})
		Round(card, 8)
		Stroke(card, matchesGame and Theme.Accent or Theme.Stroke, 1, matchesGame and 0.3 or 0.6)
		Pad(card, 8, 10, 10, 10)
		VList(card, 4, Enum.HorizontalAlignment.Left)

		New("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = entry.Title,
			TextSize = 12,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = card,
		})

		local metaParts = {}
		if entry.GameName ~= "" then
			table.insert(metaParts, entry.GameName)
		end
		table.insert(metaParts, formatViews(entry.Views) .. " views")
		table.insert(metaParts, entry.From)
		New("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = table.concat(metaParts, "  •  "),
			TextSize = 10,
			TextColor3 = Theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = card,
		})

		local badges = {}
		if matchesGame then
			table.insert(badges, "THIS GAME")
		end
		if entry.Verified then
			table.insert(badges, "VERIFIED")
		end
		if entry.HasKey then
			table.insert(badges, "KEY")
		end
		if entry.Paid then
			table.insert(badges, "PAID")
		end
		if entry.Patched then
			table.insert(badges, "PATCHED")
		end
		if entry.Universal then
			table.insert(badges, "UNIVERSAL")
		end
		if #badges > 0 then
			local badgeRow = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 16),
				LayoutOrder = 3,
				Parent = card,
			})
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
				Parent = badgeRow,
			})
			for badgeIndex, badgeText in ipairs(badges) do
				local badge = New("TextLabel", {
					BackgroundColor3 = BADGE_COLORS[badgeText] or Theme.PanelSoft,
					BackgroundTransparency = 0.75,
					Font = Enum.Font.GothamBold,
					Text = " " .. badgeText .. " ",
					TextSize = 9,
					TextColor3 = BADGE_COLORS[badgeText] or Theme.TextDim,
					Size = UDim2.new(0, 0, 1, 0),
					AutomaticSize = Enum.AutomaticSize.X,
					LayoutOrder = badgeIndex,
					Parent = badgeRow,
				})
				Round(badge, 4)
			end
		end

		local buttonRow = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, IS_MOBILE and 32 or 28),
			LayoutOrder = 4,
			Parent = card,
		})
		local executeButton = New("TextButton", {
			Font = Enum.Font.GothamBold,
			Text = "▶  Execute",
			TextSize = 11,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Size = UDim2.new(0.5, -3, 1, 0),
			AutoButtonColor = false,
			Parent = buttonRow,
		})
		Round(executeButton, 7)
		registerAccent(executeButton, "BackgroundColor3")
		Pressable(executeButton)
		local copyButton = New("TextButton", {
			BackgroundColor3 = Theme.PanelSoft,
			Font = Enum.Font.GothamMedium,
			Text = "Copy script",
			TextSize = 11,
			TextColor3 = Theme.Text,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0.5, -3, 1, 0),
			AutoButtonColor = false,
			Parent = buttonRow,
		})
		Round(copyButton, 7)
		Stroke(copyButton, Theme.Stroke, 1, 0.5)
		Pressable(copyButton)

		track(executeButton.MouseButton1Click:Connect(function()
			task.spawn(executeEntry, entry)
		end))
		track(copyButton.MouseButton1Click:Connect(function()
			task.spawn(copyEntry, entry)
		end))
		return card
	end

	--------------------------------------------------------------
	-- Search state + runner
	--------------------------------------------------------------
	local finderState = {
		Query = "",
		Page = 1,
		TotalPages = 1,
		GameFilter = nil, -- PlaceId when launched from "this game"
		Busy = false,
	}

	local function updatePagination()
		pageRow.Visible = finderState.TotalPages > 1
		pageLabel.Text = "Page " .. finderState.Page .. " / " .. finderState.TotalPages
		prevButton.TextTransparency = finderState.Page <= 1 and 0.6 or 0
		nextButton.TextTransparency = finderState.Page >= finderState.TotalPages and 0.6 or 0
	end

	local function runFinderSearch(query, page, gameFilter)
		if finderState.Busy then
			return
		end
		query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if #query == 0 then
			Library:Notify({
				Title = "Empty search",
				Content = "Type something to search for first.",
				Type = "warning",
			})
			return
		end
		finderState.Busy = true
		finderState.Query = query
		finderState.Page = page
		finderState.GameFilter = gameFilter
		clearResults()
		pageRow.Visible = false
		statusLabel.Text = "Searching " .. selectedSource .. " for '" .. query .. "'..."

		task.spawn(function()
			local searchers = {
				ScriptBlox = searchScriptBlox,
				Rscripts = searchRscripts,
			}
			local usedSource = selectedSource
			local entries, totalPages, apiMessage = searchers[usedSource](query, page)

			-- If the chosen source is down (and we're on page 1), try the other one
			if not entries and page == 1 then
				local fallback = usedSource == "ScriptBlox" and "Rscripts" or "ScriptBlox"
				local fbEntries, fbTotalPages = searchers[fallback](query, page)
				if fbEntries then
					entries, totalPages = fbEntries, fbTotalPages
					usedSource = fallback
					Library:Notify({
						Title = "Switched source",
						Content = selectedSource .. " is unavailable, showing "
							.. fallback .. " results instead.",
						Type = "warning",
						Duration = 4,
					})
					selectedSource = fallback
					refreshSourceButtons()
				end
			end
			finderState.Busy = false

			if not entries then
				statusLabel.Text = "Search failed"
					.. (apiMessage and (": " .. apiMessage) or ". Make sure you are running this in an "
						.. "executor that allows HTTP requests (game:HttpGet / request).")
				Library:Notify({
					Title = "Search failed",
					Content = apiMessage or ("Could not reach " .. usedSource .. "."),
					Type = "error",
					Duration = 5,
				})
				return
			end

			finderState.TotalPages = math.max(tonumber(totalPages) or 1, 1)

			if #entries == 0 then
				statusLabel.Text = "No scripts found for '" .. query .. "'. Try different keywords "
					.. "or switch the source."
				updatePagination()
				return
			end

			-- When searching for the current game, float exact matches to the top
			local ordered = entries
			local matchCount = 0
			if gameFilter then
				local matching, others = {}, {}
				for _, entry in ipairs(entries) do
					if entry.PlaceId == gameFilter then
						table.insert(matching, entry)
					else
						table.insert(others, entry)
					end
				end
				matchCount = #matching
				ordered = {}
				for _, entry in ipairs(matching) do
					table.insert(ordered, entry)
				end
				for _, entry in ipairs(others) do
					table.insert(ordered, entry)
				end
			end

			for index, entry in ipairs(ordered) do
				createResultCard(entry, index, gameFilter ~= nil and entry.PlaceId == gameFilter)
			end

			if gameFilter then
				statusLabel.Text = "Found " .. #ordered .. " scripts for '" .. query .. "' - "
					.. matchCount .. " made exactly for this game (highlighted)."
			else
				statusLabel.Text = "Found " .. #ordered .. " scripts for '" .. query
					.. "' (page " .. finderState.Page .. " of " .. finderState.TotalPages .. ")."
			end
			updatePagination()
		end)
	end

	--------------------------------------------------------------
	-- Wire everything up
	--------------------------------------------------------------
	track(searchButton.MouseButton1Click:Connect(function()
		runFinderSearch(finderSearchBox.Text, 1, nil)
	end))
	track(finderSearchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			runFinderSearch(finderSearchBox.Text, 1, nil)
		end
	end))
	track(gameButton.MouseButton1Click:Connect(function()
		task.spawn(function()
			local name = getGameName()
			if not name then
				Library:Notify({
					Title = "Unknown game",
					Content = "Could not look up this game's name.",
					Type = "error",
				})
				return
			end
			local cleaned = cleanGameName(name)
			if #cleaned == 0 then
				cleaned = name
			end
			finderSearchBox.Text = cleaned
			runFinderSearch(cleaned, 1, game.PlaceId)
		end)
	end))
	track(prevButton.MouseButton1Click:Connect(function()
		if finderState.Page > 1 then
			runFinderSearch(finderState.Query, finderState.Page - 1, finderState.GameFilter)
		end
	end))
	track(nextButton.MouseButton1Click:Connect(function()
		if finderState.Page < finderState.TotalPages then
			runFinderSearch(finderState.Query, finderState.Page + 1, finderState.GameFilter)
		end
	end))

	-- Show the current game's name on the button once it resolves
	task.spawn(function()
		local name = getGameName()
		if name and gameButton.Parent then
			gameButton.Text = "🎮  Find scripts for: " .. name
		end
	end)
end

----------------------------------------------------------------------
-- SETTINGS TAB
----------------------------------------------------------------------
local SettingsTab = Window:CreateTab("Settings", "⚙")

local themeSection = SettingsTab:CreateSection("Theme")
themeSection:AddColorPicker({
	Name = "Accent colour",
	Default = Theme.Accent,
	Flag = "AccentColor",
	Callback = function(color)
		Library:SetAccent(color)
	end,
})

local behaviourSection = SettingsTab:CreateSection("Behaviour")
behaviourSection:AddKeybind({
	Name = "Toggle UI key",
	Default = Library.ToggleKey,
	Flag = "ToggleKey",
	OnChanged = function(key)
		Library.ToggleKey = key or Enum.KeyCode.RightShift
	end,
})

local configSection = SettingsTab:CreateSection("Configs")
if not CAN_FILE then
	configSection:AddLabel("No file API found - configs only last this session.")
end
local configName = configSection:AddTextbox({
	Name = "Config name",
	Placeholder = "default",
	Default = "default",
})
local configList
configSection:AddButton({
	Name = "Save config",
	Callback = function()
		local name = configName.Get()
		Library:SaveConfig(name)
		if configList then
			configList.SetValues(Library:ListConfigs())
		end
		Library:Notify({
			Title = "Config saved",
			Content = "Saved as '" .. (name ~= "" and name or "default") .. "'.",
			Type = "success",
		})
	end,
})
configList = configSection:AddDropdown({
	Name = "Saved configs",
	Values = Library:ListConfigs(),
	Callback = function(picked)
		if picked then
			configName.Set(picked)
		end
	end,
})
configSection:AddButton({
	Name = "Load selected config",
	Callback = function()
		local target = configName.Get()
		local ok = Library:LoadConfig(target)
		Library:Notify({
			Title = ok and "Config loaded" or "Not found",
			Content = ok and ("Loaded '" .. (target ~= "" and target or "default") .. "'.")
				or "No config with that name exists.",
			Type = ok and "success" or "warning",
		})
	end,
})

local dangerSection = SettingsTab:CreateSection("Danger zone")
dangerSection:AddButton({
	Name = "Unload Nebula Hub",
	Callback = function()
		Library:Notify({ Title = "Goodbye", Content = "Nebula Hub unloaded.", Type = "info", Duration = 2 })
		task.wait(0.4)
		Window:Destroy()
	end,
})

----------------------------------------------------------------------
-- Done
----------------------------------------------------------------------
Library:Notify({
	Title = "Nebula Hub loaded",
	Content = IS_MOBILE
		and "Use the floating N bubble to hide / show the hub."
		or "Press RightShift to hide / show the hub.",
	Type = "success",
	Duration = 5,
})

return Library
