--[[
	Vibe Code Central  ·  Sell Lemons Autofarm  (v2.0)
	A full rewrite of the original Rayfield script.

	WHAT CHANGED
	  • Look   — hand-rolled glass UI (no external Rayfield fetch), animated
	             toggles/sliders/buttons, gradient accent, drop shadow, mobile
	             friendly, draggable + minimisable, floating show/hide bubble.
	  • Feel   — typed notifications with progress bars, hover/press feedback,
	             a "Stop everything" panic switch and a UI-toggle keybind.
	  • Perf   — every farm runs on ONE shared Heartbeat scheduler instead of a
	             pile of `while true` loops; purchase / tree look-ups are cached
	             and kept fresh by events (DescendantAdded / AttributeChanged)
	             instead of walking GetDescendants() dozens of times a second.

	Run from an executor:
	  loadstring(game:HttpGet("<raw url to this file>"))()
]]

------------------------------------------------------------------------
--  SERVICES
------------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

------------------------------------------------------------------------
--  SINGLE-INSTANCE GUARD  (kill a previous copy cleanly)
------------------------------------------------------------------------
local GENV = (getgenv and getgenv()) or _G
if GENV.__SellLemons and GENV.__SellLemons.destroy then
	pcall(GENV.__SellLemons.destroy)
end
local Hub = { connections = {} }
GENV.__SellLemons = Hub

local function track(conn)
	Hub.connections[#Hub.connections + 1] = conn
	return conn
end

------------------------------------------------------------------------
--  GUI PARENT (executor-friendly)
------------------------------------------------------------------------
local function guiParent()
	local ok, hui = pcall(function() return gethui() end)
	if ok and hui then return hui end
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then return pg end
	return game:GetService("CoreGui")
end

------------------------------------------------------------------------
--  THEME
------------------------------------------------------------------------
local Theme = {
	BG      = Color3.fromRGB(15, 16, 20),
	Panel   = Color3.fromRGB(22, 24, 30),
	Panel2  = Color3.fromRGB(30, 33, 41),
	Stroke  = Color3.fromRGB(46, 50, 62),
	Text    = Color3.fromRGB(236, 238, 245),
	SubText = Color3.fromRGB(150, 156, 170),
	Accent  = Color3.fromRGB(245, 205, 66),   -- lemon
	Accent2 = Color3.fromRGB(126, 217, 87),   -- leaf green
	Good    = Color3.fromRGB(126, 217, 87),
	Bad     = Color3.fromRGB(245, 90, 95),
	Warn    = Color3.fromRGB(245, 180, 70),
	Info    = Color3.fromRGB(96, 170, 255),
}

local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local UI_SCALE = (function()
	local cam = workspace.CurrentCamera
	local w = (cam and cam.ViewportSize.X) or 1280
	return math.clamp(w / 980, IS_TOUCH and 0.78 or 0.85, 1.05)
end)()

------------------------------------------------------------------------
--  TINY HELPERS
------------------------------------------------------------------------
local function new(class, props, parent)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do inst[k] = v end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(inst, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, inst)
end

local function stroke(inst, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

local function gradient(inst, c1, c2, rot)
	return new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c1),
			ColorSequenceKeypoint.new(1, c2),
		}),
		Rotation = rot or 90,
	}, inst)
end

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst,
		TweenInfo.new(t or 0.16, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props)
	tw:Play()
	return tw
end

-- subtle press-bounce for any clickable
local function pressable(btn)
	local scale = new("UIScale", { Scale = 1 }, btn)
	track(btn.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = 0.96 }) end))
	track(btn.MouseButton1Up:Connect(function() tween(scale, 0.12, { Scale = 1 }) end))
	track(btn.MouseLeave:Connect(function() tween(scale, 0.12, { Scale = 1 }) end))
end

local function dragify(frame, handle)
	handle = handle or frame
	local dragging, startPos, startInput
	track(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startInput, startPos = true, input.Position, frame.Position
			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if changed then changed:Disconnect() end
				end
			end)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startInput
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
end

-- accent live-recolour registry (for the colour picker in Settings)
local accentTargets = {}
local function trackAccent(inst, prop)
	accentTargets[#accentTargets + 1] = { inst = inst, prop = prop }
	inst[prop] = Theme.Accent
end
local function setAccent(color)
	Theme.Accent = color
	for _, t in ipairs(accentTargets) do
		if t.inst and t.inst.Parent then tween(t.inst, 0.2, { [t.prop] = color }) end
	end
end

-- abbreviate big numbers: 12,345,678 -> 12.35M
local ABBR = { "", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(value)
	local n = tonumber(value)
	if not n then return tostring(value) end
	local neg = n < 0
	n = math.abs(n)
	local i = 1
	while n >= 1000 and i < #ABBR do n = n / 1000; i = i + 1 end
	local s = (i == 1) and string.format("%d", n) or string.format("%.2f%s", n, ABBR[i])
	return neg and ("-" .. s) or s
end

------------------------------------------------------------------------
--  ROOT SCREENGUI
------------------------------------------------------------------------
local screen = new("ScreenGui", {
	Name = "SellLemonsHub",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 9990,
}, guiParent())
Hub.screen = screen

------------------------------------------------------------------------
--  NOTIFICATIONS
------------------------------------------------------------------------
local notifyHolder = new("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, math.floor(280 * UI_SCALE), 1, -32),
	BackgroundTransparency = 1,
}, screen)
new("UIListLayout", {
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, notifyHolder)

local function Notify(opts)
	opts = opts or {}
	local accent = ({ success = Theme.Good, error = Theme.Bad, warning = Theme.Warn, info = Theme.Info })[opts.Type]
		or Theme.Info
	local dur = opts.Duration or 4

	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, notifyHolder)
	corner(card, 10)
	stroke(card, Theme.Stroke, 1, 0.4)
	new("Frame", {
		Size = UDim2.new(0, 3, 1, -16), Position = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = accent, BorderSizePixel = 0,
	}, card)
	local body = new("Frame", { Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 18, 0, 0), BackgroundTransparency = 1 }, card)
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, body)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		Text = opts.Title or "Notice", TextColor3 = accent, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, body)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, Text = opts.Content or "", TextColor3 = Theme.Text, TextSize = 12,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	}, body)
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = accent, BorderSizePixel = 0,
	}, card)

	tween(card, 0.2, { BackgroundTransparency = 0.05 })
	tween(bar, dur, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
	task.delay(dur, function()
		tween(card, 0.25, { BackgroundTransparency = 1 })
		task.wait(0.25)
		card:Destroy()
	end)
end
Hub.Notify = Notify

------------------------------------------------------------------------
--  MAIN WINDOW
------------------------------------------------------------------------
local WIN_W, WIN_H = math.floor(560 * UI_SCALE), math.floor(380 * UI_SCALE)

local shadow = new("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, WIN_W + 60, 0, WIN_H + 60),
	BackgroundTransparency = 1,
	Image = "rbxassetid://6014261993",
	ImageColor3 = Color3.new(0, 0, 0),
	ImageTransparency = 0.45,
	ScaleType = Enum.ScaleType.Slice,
	SliceCenter = Rect.new(49, 49, 450, 450),
}, screen)

local window = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, WIN_W, 0, WIN_H),
	BackgroundColor3 = Theme.BG,
	BorderSizePixel = 0,
}, screen)
corner(window, 14)
stroke(window, Theme.Stroke, 1, 0.3)
gradient(window, Theme.BG, Color3.fromRGB(11, 12, 15), 90)
track(window:GetPropertyChangedSignal("Position"):Connect(function()
	shadow.Position = window.Position
end))

-- header
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0 }, window)
corner(header, 14)
gradient(header, Theme.Panel2, Theme.Panel, 90)
new("Frame", { -- mask the bottom corners of the rounded header
	Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14),
	BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, ZIndex = 0,
}, header)
dragify(window, header)

new("TextLabel", {
	Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(0, 34, 1, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "🍋", TextSize = 22,
	TextColor3 = Theme.Text,
}, header)
new("TextLabel", {
	Position = UDim2.new(0, 50, 0, 8), Size = UDim2.new(1, -160, 0, 18),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "Vibe Code Central",
	TextColor3 = Theme.Text, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
}, header)
new("TextLabel", {
	Position = UDim2.new(0, 50, 0, 26), Size = UDim2.new(1, -160, 0, 14),
	BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "Sell Lemons · autofarm v2.0",
	TextColor3 = Theme.SubText, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local function headerButton(text, x, color)
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0),
		Size = UDim2.new(0, 28, 0, 28), BackgroundColor3 = Theme.Panel2, BorderSizePixel = 0,
		AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = text, TextSize = 16,
		TextColor3 = color or Theme.Text,
	}, header)
	corner(b, 8)
	pressable(b)
	track(b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.Stroke }) end))
	track(b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundColor3 = Theme.Panel2 }) end))
	return b
end

local closeBtn = headerButton("×", -12, Theme.Bad)
local minBtn   = headerButton("–", -48)

-- sidebar
local SIDE_W = math.floor(132 * UI_SCALE)
local sidebar = new("Frame", {
	Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(0, SIDE_W, 1, -48),
	BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
}, window)
gradient(sidebar, Theme.Panel, Color3.fromRGB(18, 20, 25), 90)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)
new("UIPadding", {
	PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, sidebar)

-- content area
local content = new("Frame", {
	Position = UDim2.new(0, SIDE_W, 0, 48), Size = UDim2.new(1, -SIDE_W, 1, -48),
	BackgroundTransparency = 1,
}, window)

------------------------------------------------------------------------
--  TAB / SECTION / CONTROL FACTORY
------------------------------------------------------------------------
local tabs = {}
local activeTab

local function selectTab(tab)
	if activeTab == tab then return end
	for _, t in ipairs(tabs) do
		local on = (t == tab)
		t.page.Visible = on
		tween(t.button, 0.16, { BackgroundColor3 = on and Theme.Panel2 or Theme.Panel })
		tween(t.label, 0.16, { TextColor3 = on and Theme.Text or Theme.SubText })
		tween(t.pill, 0.16, { Size = on and UDim2.new(0, 3, 0.62, 0) or UDim2.new(0, 3, 0, 0) })
	end
	activeTab = tab
end

local Window = {}

function Window:Tab(name, icon)
	local button = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "",
	}, sidebar)
	corner(button, 9)
	local pill = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0, 0), BorderSizePixel = 0,
	}, button)
	corner(pill, 2)
	trackAccent(pill, "BackgroundColor3")
	local label = new("TextLabel", {
		Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -16, 1, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
		Text = (icon and (icon .. "  ") or "") .. name, TextColor3 = Theme.SubText, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, button)

	local page = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		Visible = false, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Stroke,
		ScrollBarImageTransparency = 0.3, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, content)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
	}, page)

	local tab = { button = button, label = label, pill = pill, page = page }
	tabs[#tabs + 1] = tab
	track(button.MouseButton1Click:Connect(function() selectTab(tab) end))
	track(button.MouseEnter:Connect(function()
		if activeTab ~= tab then tween(button, 0.12, { BackgroundColor3 = Color3.fromRGB(26, 28, 35) }) end
	end))
	track(button.MouseLeave:Connect(function()
		if activeTab ~= tab then tween(button, 0.12, { BackgroundColor3 = Theme.Panel }) end
	end))

	------------------------------------------------------------------
	local Section = {}
	Section.__index = Section

	function tab:Section(titleText)
		local frame = new("Frame", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
		}, page)
		corner(frame, 11)
		stroke(frame, Theme.Stroke, 1, 0.5)
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
		new("UIPadding", {
			PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		}, frame)
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			Text = titleText, TextColor3 = Theme.SubText, TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, frame)
		return setmetatable({ frame = frame }, Section)
	end

	-- shared label+desc row used by several controls
	local function labelStack(parent, name, desc, rightInset)
		local holder = new("Frame", {
			Size = UDim2.new(1, -(rightInset or 0), 1, 0), BackgroundTransparency = 1,
		}, parent)
		new("UIListLayout", { Padding = UDim.new(0, 1), VerticalAlignment = Enum.VerticalAlignment.Center }, holder)
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
			Text = name, TextColor3 = Theme.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		}, holder)
		if desc then
			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
				Text = desc, TextColor3 = Theme.SubText, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
			}, holder)
		end
		return holder
	end

	function Section:Button(o)
		local h = math.max(36, o.Desc and 46 or 36)
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Theme.Panel2, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "",
		}, self.frame)
		corner(b, 9)
		local s = stroke(b, Theme.Stroke, 1, 0.5)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, b)
		labelStack(b, o.Name, o.Desc)
		new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.new(0, 18, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			Text = "›", TextSize = 18, TextColor3 = Theme.SubText,
		}, b)
		pressable(b)
		track(b.MouseEnter:Connect(function()
			tween(b, 0.12, { BackgroundColor3 = Theme.Stroke }); tween(s, 0.12, { Color = Theme.Accent, Transparency = 0.2 })
		end))
		track(b.MouseLeave:Connect(function()
			tween(b, 0.12, { BackgroundColor3 = Theme.Panel2 }); tween(s, 0.12, { Color = Theme.Stroke, Transparency = 0.5 })
		end))
		track(b.MouseButton1Click:Connect(function()
			if o.Callback then task.spawn(o.Callback) end
		end))
		return b
	end

	function Section:Toggle(o)
		local state = o.Default or false
		local h = o.Desc and 46 or 38
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Theme.Panel2, BorderSizePixel = 0,
		}, self.frame)
		corner(row, 9)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, row)
		labelStack(row, o.Name, o.Desc, 56)

		local sw = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 44, 0, 22), BackgroundColor3 = Theme.BG, BorderSizePixel = 0,
			AutoButtonColor = false, Text = "",
		}, row)
		corner(sw, 11)
		local knob = new("Frame", {
			Position = UDim2.new(0, 3, 0.5, -8), Size = UDim2.new(0, 16, 0, 16),
			BackgroundColor3 = Color3.fromRGB(210, 214, 224), BorderSizePixel = 0,
		}, sw)
		corner(knob, 8)

		local function apply(v, fire)
			state = v
			tween(sw, 0.16, { BackgroundColor3 = v and Theme.Accent or Theme.BG })
			tween(knob, 0.16, {
				Position = v and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
				BackgroundColor3 = v and Color3.fromRGB(25, 27, 33) or Color3.fromRGB(210, 214, 224),
			})
			if fire and o.Callback then task.spawn(o.Callback, v) end
		end
		track(sw.MouseButton1Click:Connect(function() apply(not state, true) end))
		apply(state, false)

		local api = { Set = function(_, v) apply(v and true or false, true) end, Get = function() return state end }
		if o.Flag then Hub[o.Flag .. "Toggle"] = api end
		return api
	end

	function Section:Slider(o)
		local minv, maxv = o.Min or 0, o.Max or 100
		local value = math.clamp(o.Default or minv, minv, maxv)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Theme.Panel2, BorderSizePixel = 0 }, self.frame)
		corner(row, 9)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8) }, row)
		new("TextLabel", {
			Size = UDim2.new(1, -60, 0, 15), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
			Text = o.Name, TextColor3 = Theme.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		local valLabel = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 60, 0, 15),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = Theme.Accent, TextSize = 13,
			Text = tostring(value) .. (o.Suffix or ""), TextXAlignment = Enum.TextXAlignment.Right,
		}, row)
		trackAccent(valLabel, "TextColor3")

		local track_ = new("Frame", {
			Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = Theme.BG, BorderSizePixel = 0,
		}, row)
		corner(track_, 3)
		local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, track_)
		corner(fill, 3)
		trackAccent(fill, "BackgroundColor3")
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Color3.fromRGB(240, 242, 248), BorderSizePixel = 0, ZIndex = 2,
		}, track_)
		corner(knob, 7)

		local function render()
			local a = (value - minv) / (maxv - minv)
			fill.Size = UDim2.new(a, 0, 1, 0)
			knob.Position = UDim2.new(a, 0, 0.5, 0)
			valLabel.Text = tostring(value) .. (o.Suffix or "")
		end
		local function setFromX(px)
			local a = math.clamp((px - track_.AbsolutePosition.X) / track_.AbsoluteSize.X, 0, 1)
			local raw = minv + a * (maxv - minv)
			value = o.Step and (math.floor(raw / o.Step + 0.5) * o.Step) or math.floor(raw + 0.5)
			value = math.clamp(value, minv, maxv)
			render()
			if o.Callback then task.spawn(o.Callback, value) end
		end
		render()

		local sliding = false
		local hit = new("TextButton", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 24), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, row)
		track(hit.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				sliding = true; setFromX(i.Position.X)
			end
		end))
		track(hit.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then sliding = false end
		end))
		track(UserInputService.InputChanged:Connect(function(i)
			if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				setFromX(i.Position.X)
			end
		end))
		return { Set = function(_, v) value = math.clamp(v, minv, maxv); render(); if o.Callback then task.spawn(o.Callback, value) end end }
	end

	function Section:Input(o)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, o.Desc and 56 or 46), BackgroundColor3 = Theme.Panel2, BorderSizePixel = 0 }, self.frame)
		corner(row, 9)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6) }, row)
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
			Text = o.Name, TextColor3 = Theme.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		local box = new("TextBox", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -8), Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Theme.BG, BorderSizePixel = 0, Font = Enum.Font.Gotham, TextSize = 12,
			TextColor3 = Theme.Text, PlaceholderText = o.Placeholder or "", PlaceholderColor3 = Theme.SubText,
			Text = o.Default or "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		corner(box, 7)
		local s = stroke(box, Theme.Stroke, 1, 0.4)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
		track(box.Focused:Connect(function() tween(s, 0.12, { Color = Theme.Accent, Transparency = 0.1 }) end))
		track(box.FocusLost:Connect(function()
			tween(s, 0.12, { Color = Theme.Stroke, Transparency = 0.4 })
			if o.Callback then task.spawn(o.Callback, box.Text) end
		end))
		return box
	end

	function Section:Label(text)
		return new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, Text = text, TextColor3 = Theme.SubText, TextSize = 12,
			TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		}, self.frame)
	end

	if #tabs == 1 then selectTab(tab) end
	return tab
end

------------------------------------------------------------------------
--  MINIMISE / CLOSE  +  FLOATING BUBBLE
------------------------------------------------------------------------
local bubble = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 60, 0.5, 0),
	Size = UDim2.new(0, 48, 0, 48), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
	AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = "🍋", TextSize = 24, Visible = false,
}, screen)
corner(bubble, 24)
stroke(bubble, Theme.Accent, 1.5, 0.2)
dragify(bubble)

local function setOpen(open)
	if open then
		window.Visible = true; shadow.Visible = true
		window.Size = UDim2.new(0, 0, 0, 0)
		tween(window, 0.2, { Size = UDim2.new(0, WIN_W, 0, WIN_H) }, Enum.EasingStyle.Back)
		tween(shadow, 0.2, { ImageTransparency = 0.45 })
		bubble.Visible = false
	else
		tween(window, 0.18, { Size = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Quad)
		tween(shadow, 0.18, { ImageTransparency = 1 })
		task.delay(0.18, function() window.Visible = false; shadow.Visible = false end)
		bubble.Visible = true
	end
end
track(minBtn.MouseButton1Click:Connect(function() setOpen(false) end))
track(bubble.MouseButton1Click:Connect(function() setOpen(true) end))

function Hub.destroy()
	for _, c in ipairs(Hub.connections) do pcall(function() c:Disconnect() end) end
	Hub.alive = false
	pcall(function() Hub.screen:Destroy() end)
	if Hub.statusGui then pcall(function() Hub.statusGui:Destroy() end) end
end
track(closeBtn.MouseButton1Click:Connect(function() Hub.destroy() end))

-- UI toggle keybind
local toggleKey = Enum.KeyCode.RightShift
track(UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == toggleKey then
		setOpen(not window.Visible)
	end
end))

------------------------------------------------------------------------
--  ════════════════  GAME LOGIC  ════════════════
------------------------------------------------------------------------

-- locate the player's tycoon
local userTycoon = (function()
	for _, v in ipairs(workspace:GetChildren()) do
		if v:IsA("Folder") and v.Name:match("Tycoon%d") then
			local owner = v:FindFirstChild("Owner")
			if owner and owner.Value == LocalPlayer then return v end
		end
	end
	return nil
end)()

if not userTycoon then
	Notify({ Title = "Tycoon not found", Content = "Couldn't find a tycoon you own. Claim a plot, then re-run.", Type = "error", Duration = 7 })
end

local Remotes = userTycoon and userTycoon:FindFirstChild("Remotes")
local function remote(name) return Remotes and Remotes:FindFirstChild(name) end

-- feature flags
local F = {
	AutoBuy = false, AutoUpgrade = false, AutoFruit = false, AutoRebirth = false,
	AutoEvolve = false, AutoPowerLevel = false, AutoAscend = false,
}
local stats = { buys = 0, upgrades = 0, fruit = 0, rebirths = 0, evolves = 0, ascends = 0 }

------------------------------------------------------------------------
--  SHARED HEARTBEAT SCHEDULER
--  One Heartbeat connection runs every farm at its own cadence. Each job
--  has a "busy" guard so a long (yielding) job never overlaps itself and
--  never blocks the others.
------------------------------------------------------------------------
local Scheduler = {}
do
	local jobs = {}
	function Scheduler.every(interval, fn, name)
		local job = { interval = interval, nextAt = 0, busy = false }
		job.run = function()
			job.busy = true
			local ok, err = pcall(fn)
			job.busy = false
			if not ok then warn("[SellLemons] " .. (name or "job") .. ": " .. tostring(err)) end
		end
		jobs[#jobs + 1] = job
		return job
	end
	Hub.alive = true
	track(RunService.Heartbeat:Connect(function()
		if not Hub.alive then return end
		local now = os.clock()
		for _, job in ipairs(jobs) do
			if not job.busy and now >= job.nextAt then
				job.nextAt = now + job.interval
				task.spawn(job.run)
			end
		end
	end))
end

------------------------------------------------------------------------
--  AUTO BUY  (event-driven cache instead of GetDescendants spam)
------------------------------------------------------------------------
do
	local Purchases = userTycoon and userTycoon:FindFirstChild("Purchases")
	local candidates = {}   -- model -> Purchase RemoteFunction

	local function index(obj)
		if candidates[obj] or not obj:IsA("Model") then return end
		local p = obj:FindFirstChild("Purchase")
		if p and p:IsA("RemoteFunction") then
			candidates[obj] = p
			-- count a genuine purchase (Purchased flips true) for accurate stats
			track(obj:GetAttributeChangedSignal("Purchased"):Connect(function()
				if obj:GetAttribute("Purchased") == true then stats.buys += 1 end
			end))
		end
	end

	if Purchases then
		for _, obj in ipairs(Purchases:GetDescendants()) do index(obj) end
		track(Purchases.DescendantAdded:Connect(index))
		track(Purchases.DescendantRemoving:Connect(function(obj) candidates[obj] = nil end))
	end

	Scheduler.every(0.1, function()
		if not F.AutoBuy then return end
		for model, purchase in pairs(candidates) do
			if model.Parent
				and model:GetAttribute("Shown") == true
				and model:GetAttribute("Purchased") ~= true then
				pcall(function() purchase:InvokeServer() end)
			end
		end
	end, "AutoBuy")
end

------------------------------------------------------------------------
--  AUTO UPGRADE  (cache the Upgrade remotes, refresh occasionally)
------------------------------------------------------------------------
do
	local remotes = {}
	local level = {}
	local lastScan = 0

	local function rescan()
		table.clear(remotes)
		local Purchases = userTycoon and userTycoon:FindFirstChild("Purchases")
		if not Purchases then return end
		for _, obj in ipairs(Purchases:GetDescendants()) do
			if obj:IsA("RemoteFunction") and obj.Name == "Upgrade" then
				remotes[#remotes + 1] = obj
			end
		end
	end

	Scheduler.every(0.25, function()
		if not F.AutoUpgrade then return end
		if os.clock() - lastScan > 3 then rescan(); lastScan = os.clock() end
		for _, r in ipairs(remotes) do
			if r.Parent then
				local lvl = (level[r] or 0) + 1
				while lvl <= 100 do
					local ok, res = pcall(function() return r:InvokeServer(lvl) end)
					if (not ok) or res == false then break end
					level[r] = lvl
					stats.upgrades += 1
					lvl += 1
				end
			end
		end
	end, "AutoUpgrade")
end

------------------------------------------------------------------------
--  AUTO POWER LEVEL
------------------------------------------------------------------------
Scheduler.every(0.25, function()
	if not F.AutoPowerLevel then return end
	local r = remote("UpgradePowerLevel")
	if r then pcall(function() r:InvokeServer() end) end
end, "AutoPowerLevel")

------------------------------------------------------------------------
--  NUMBER PARSING (for the rebirth investor readout)
------------------------------------------------------------------------
local NUM_SCALE = {
	thousand = 1e3, million = 1e6, billion = 1e9, trillion = 1e12, quadrillion = 1e15,
	quintillion = 1e18, sextillion = 1e21, septillion = 1e24, octillion = 1e27,
	nonillion = 1e30, decillion = 1e33, undecillion = 1e36, duodecillion = 1e39,
	tredecillion = 1e42, quattuordecillion = 1e45, quindecillion = 1e48,
	sexdecillion = 1e51, septendecillion = 1e54, octodecillion = 1e57,
	novemdecillion = 1e60, vigintillion = 1e63,
	k = 1e3, m = 1e6, b = 1e9, t = 1e12, qd = 1e15, qn = 1e18, sx = 1e21, sp = 1e24,
}
local function parseNumber(s)
	if not s then return nil end
	s = tostring(s):gsub(",", ""):lower()
	local num = s:match("[%d%.]+")
	local val = num and tonumber(num)
	if not val then return nil end
	local word = s:match("[%d%.%s]+([a-z]+)")
	if word and NUM_SCALE[word] then val = val * NUM_SCALE[word] end
	return val
end

------------------------------------------------------------------------
--  AUTO REBIRTH
------------------------------------------------------------------------
local RebirthGainMultiple = 1.0
local MinPotential = 1
do
	local RebirthCooldown, RebirthTimeout = 2, 8

	local function investorBody()
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local r = pg and pg:FindFirstChild("Rebirth")
		local im = r and r:FindFirstChild("InvestorsMenu")
		return im and im:FindFirstChild("Body")
	end
	local function readQuantity(frameName)
		local body = investorBody()
		local frame = body and body:FindFirstChild(frameName)
		local q = frame and frame:FindFirstChild("Quantity")
		return q and parseNumber(q.Text)
	end

	Scheduler.every(0.5, function()
		if not F.AutoRebirth then return end
		local r = remote("Rebirth")
		local potential = readQuantity("Potential")
		local current = readQuantity("Amount") or 0
		local worthIt = r and potential
			and potential >= MinPotential
			and potential >= current * RebirthGainMultiple
		if not worthIt then return end

		local done = false
		local signal = remote("Rebirthed")
		local conn
		if signal and signal:IsA("RemoteEvent") then
			conn = signal.OnClientEvent:Connect(function() done = true end)
		end
		pcall(function() r:InvokeServer() end)
		stats.rebirths += 1
		local t = 0
		while not done and t < RebirthTimeout do task.wait(0.1); t += 0.1 end
		if conn then conn:Disconnect() end
		task.wait(RebirthCooldown)
	end, "AutoRebirth")
end

------------------------------------------------------------------------
--  AUTO EVOLVE
------------------------------------------------------------------------
local EvolveAt = 100
do
	local EvolveCooldown, EvolveTimeout = 2, 8
	local function progress()
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local r = pg and pg:FindFirstChild("Rebirth")
		local em = r and r:FindFirstChild("EvolutionMenu")
		local body = em and em:FindFirstChild("Body")
		local p = body and body:FindFirstChild("Progress")
		if not p then return nil end
		return tonumber(tostring(p.Text):match("[%d%.]+"))
	end

	Scheduler.every(0.5, function()
		if not F.AutoEvolve then return end
		local r = remote("Evolve")
		local prog = progress()
		if not (r and prog and prog >= EvolveAt) then return end

		local done = false
		local signal = remote("Evolved")
		local conn
		if signal and signal:IsA("RemoteEvent") then
			conn = signal.OnClientEvent:Connect(function() done = true end)
		end
		pcall(function() r:InvokeServer() end)
		stats.evolves += 1
		local t = 0
		while not done and t < EvolveTimeout do task.wait(0.1); t += 0.1 end
		if conn then conn:Disconnect() end
		task.wait(EvolveCooldown)
	end, "AutoEvolve")
end

------------------------------------------------------------------------
--  AUTO ASCEND
------------------------------------------------------------------------
do
	local AscendCooldown, AscendTimeout = 2, 8
	Scheduler.every(0.5, function()
		if not F.AutoAscend then return end
		local r = remote("Ascend")
		if not r then return end

		local done = false
		local signal = remote("Ascended")
		local conn
		if signal and signal:IsA("RemoteEvent") then
			conn = signal.OnClientEvent:Connect(function() done = true end)
		end
		pcall(function() r:InvokeServer() end)
		stats.ascends += 1
		local t = 0
		while not done and t < AscendTimeout do task.wait(0.1); t += 0.1 end
		if conn then conn:Disconnect() end
		task.wait(AscendCooldown)
	end, "AutoAscend")
end

------------------------------------------------------------------------
--  LEMON TREES  (cached, event-maintained)
------------------------------------------------------------------------
local Trees = {}
do
	local function addTree(obj)
		if obj:IsA("Model") and obj.Name == "LemonTree" and not table.find(Trees, obj) then
			Trees[#Trees + 1] = obj
		end
	end
	local function removeTree(obj)
		local i = table.find(Trees, obj)
		if i then table.remove(Trees, i) end
	end
	for _, v in ipairs(workspace:GetDescendants()) do addTree(v) end
	track(workspace.DescendantAdded:Connect(addTree))
	track(workspace.DescendantRemoving:Connect(removeTree))
end

local function collectFruit(tree)
	for _, obj in ipairs(tree:GetDescendants()) do
		if obj:IsA("BasePart") then obj.CanCollide = false end
	end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.CFrame = tree:GetPivot() + Vector3.new(0, 5, 0)
	for _, obj in ipairs(tree:GetDescendants()) do
		if not F.AutoFruit then return end
		if obj:IsA("BasePart") and obj.Name == "Fruit" then
			obj.CanCollide = false
			local clickPart = obj:FindFirstChild("ClickPart")
			local detector = clickPart and clickPart:FindFirstChildOfClass("ClickDetector")
			if detector then
				task.wait(0.45)
				if fireclickdetector then
					pcall(fireclickdetector, detector)
					stats.fruit += 1
				end
			end
		end
	end
end

Scheduler.every(0.1, function()
	if not F.AutoFruit then return end
	for _, tree in ipairs(Trees) do
		if not F.AutoFruit then break end
		if tree and tree.Parent then pcall(collectFruit, tree) end
	end
end, "AutoFruit")

------------------------------------------------------------------------
--  SEWER / LEVERS  (manual buttons)
------------------------------------------------------------------------
local function touchPart(hrp, part)
	if not firetouchinterest then return end
	pcall(firetouchinterest, hrp, part, 0)
	pcall(firetouchinterest, hrp, part, 1)
end

local function pullAllLevers()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return 0 end
	local map = workspace:FindFirstChild("Map")
	local sewer = map and map:FindFirstChild("Sewer")
	local root = sewer or workspace
	local pulled = 0
	for _, o in ipairs(root:GetDescendants()) do
		if o:IsA("BasePart") and (o.Name == "Lever" or string.find(string.lower(o.Name), "lever", 1, true)) then
			touchPart(hrp, o); pulled += 1
		end
	end
	if sewer then
		for _, o in ipairs(sewer:GetDescendants()) do
			if o:IsA("BasePart") and (o.Name == "VineKey" or o.Name == "UFOKey") then touchPart(hrp, o) end
		end
	end
	return pulled
end

local function doSewerRun()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, "no character" end
	local map = workspace:FindFirstChild("Map")
	local sewer = map and map:FindFirstChild("Sewer")
	if not sewer then return false, "sewer not loaded" end
	for _, o in ipairs(sewer:GetDescendants()) do
		if o:IsA("BasePart") and string.find(string.lower(o.Name), "lever", 1, true) then touchPart(hrp, o) end
	end
	for _, folderName in ipairs({ "CashVine", "SewerAlien" }) do
		local folder = sewer:FindFirstChild(folderName)
		if folder then
			for _, o in ipairs(folder:GetDescendants()) do
				if o:IsA("BasePart") and (o.Name == "VineKey" or o.Name == "UFOKey") then touchPart(hrp, o) end
			end
		end
	end
	task.wait(0.3)
	local cashVine = sewer:FindFirstChild("CashVine")
	if cashVine then
		local vineDoor = cashVine:FindFirstChild("VineDoor")
		if vineDoor then
			for _, o in ipairs(vineDoor:GetDescendants()) do
				if o:IsA("BasePart") then touchPart(hrp, o) end
			end
		end
	end
	task.wait(0.3)
	if cashVine then
		local vineModel = cashVine:FindFirstChild("CashVine")
		if vineModel then
			pcall(function() hrp.CFrame = vineModel:GetPivot() + Vector3.new(0, 3, 0) end)
			task.wait(0.2)
			for _, o in ipairs(vineModel:GetDescendants()) do
				if o:IsA("BasePart") then touchPart(hrp, o) end
			end
		end
	end
	return true
end

local SEWER_ALIEN_POS = Vector3.new(-42, -41, 180)
local function teleportToAlien()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, "no character" end
	pcall(function() hrp.CFrame = CFrame.new(SEWER_ALIEN_POS) end)
	return true
end

------------------------------------------------------------------------
--  ════════════════  BUILD THE UI  ════════════════
------------------------------------------------------------------------
local function flagToggle(section, name, flagName, desc, onEnable)
	section:Toggle({
		Name = name, Desc = desc, Default = false, Flag = flagName,
		Callback = function(v)
			if v and onEnable and not onEnable() then
				if Hub[flagName .. "Toggle"] then Hub[flagName .. "Toggle"]:Set(false) end
				return
			end
			F[flagName] = v
			Notify({ Title = name, Content = v and "Enabled" or "Disabled", Type = v and "success" or "info", Duration = 2.5 })
		end,
	})
end

-- TAB: Tycoon
local tycoonTab = Window:Tab("Tycoon", "🏭")
do
	local s = tycoonTab:Section("Money makers")
	flagToggle(s, "Auto Buy", "AutoBuy", "Buys every available dropper / upgrade button")
	flagToggle(s, "Auto Upgrade", "AutoUpgrade", "Maxes every upgrade the server allows")
	flagToggle(s, "Auto Power Level", "AutoPowerLevel", "Spends power level automatically")

	local p = tycoonTab:Section("Progression")
	flagToggle(p, "Auto Rebirth", "AutoRebirth", "Rebirths when it's worth it", function()
		if not remote("Rebirth") then
			Notify({ Title = "Auto Rebirth", Content = "Rebirth remote not found!", Type = "error", Duration = 5 })
			return false
		end
		return true
	end)
	p:Slider({
		Name = "Rebirth multiplier", Min = 1, Max = 50, Default = 1, Step = 1, Suffix = "x",
		Callback = function(v) RebirthGainMultiple = v end,
	})
	flagToggle(p, "Auto Evolve", "AutoEvolve", "Evolves at full progress (x10 income)", function()
		if not remote("Evolve") then
			Notify({ Title = "Auto Evolve", Content = "Evolve remote not found!", Type = "error", Duration = 5 })
			return false
		end
		return true
	end)
	flagToggle(p, "Auto Ascend", "AutoAscend", "Ascends whenever the server allows", function()
		if not remote("Ascend") then
			Notify({ Title = "Auto Ascend", Content = "Ascend remote not found!", Type = "error", Duration = 5 })
			return false
		end
		return true
	end)
end

-- TAB: Lemons
local lemonTab = Window:Tab("Lemons", "🍋")
do
	local s = lemonTab:Section("Fruit")
	flagToggle(s, "Auto Fruit", "AutoFruit", "Flies to every lemon tree and harvests fruit")
	s:Label("Tip: pair Auto Fruit with the sewer tools below for full lemon coverage.")
end

-- TAB: Sewer
local sewerTab = Window:Tab("Sewer", "🕳️")
do
	local s = sewerTab:Section("One-shot tools")
	s:Button({
		Name = "Pull all levers", Desc = "Touches every lever + grabs sewer keys",
		Callback = function()
			local n = pullAllLevers()
			Notify({ Title = "Pull all levers", Content = n > 0 and ("Pulled " .. n .. " lever(s) + keys") or "No levers found",
				Type = n > 0 and "success" or "warning", Duration = 4 })
		end,
	})
	s:Button({
		Name = "Vine harvest", Desc = "Levers → keys → harvest the cash vine",
		Callback = function()
			Notify({ Title = "Vine harvest", Content = "Running...", Type = "info", Duration = 2 })
			task.spawn(function()
				local ok, err = doSewerRun()
				Notify({ Title = "Vine harvest", Content = ok and "Done! Vine harvested." or ("Failed: " .. tostring(err)),
					Type = ok and "success" or "error", Duration = 5 })
			end)
		end,
	})
	s:Button({
		Name = "Teleport to sewer alien", Desc = "Warp to the alien spot",
		Callback = function()
			local ok, err = teleportToAlien()
			Notify({ Title = "Teleport", Content = ok and "Teleported!" or ("Failed: " .. tostring(err)),
				Type = ok and "success" or "error", Duration = 3 })
		end,
	})
end

-- TAB: Settings
local settingsTab = Window:Tab("Settings", "⚙️")
do
	local s = settingsTab:Section("Quick controls")
	s:Button({
		Name = "Stop everything", Desc = "Turns every auto-farm off at once",
		Callback = function()
			for flag in pairs(F) do
				F[flag] = false
				if Hub[flag .. "Toggle"] then Hub[flag .. "Toggle"]:Set(false) end
			end
			Notify({ Title = "Panic", Content = "All farms stopped.", Type = "warning", Duration = 3 })
		end,
	})

	local a = settingsTab:Section("Appearance")
	local accents = {
		{ "Lemon", Color3.fromRGB(245, 205, 66) },
		{ "Leaf", Color3.fromRGB(126, 217, 87) },
		{ "Sky", Color3.fromRGB(96, 170, 255) },
		{ "Rose", Color3.fromRGB(245, 110, 150) },
		{ "Violet", Color3.fromRGB(170, 130, 255) },
	}
	for _, entry in ipairs(accents) do
		a:Button({
			Name = "Accent: " .. entry[1],
			Callback = function() setAccent(entry[2]) end,
		})
	end

	local h = settingsTab:Section("Hub")
	h:Label("Press Right Shift to hide / show this window.")
	h:Button({
		Name = "Unload hub", Desc = "Stops all farms and removes the UI",
		Callback = function()
			for flag in pairs(F) do F[flag] = false end
			Hub.destroy()
		end,
	})
end

------------------------------------------------------------------------
--  ════════════════  LIVE STATUS HUD  ════════════════
------------------------------------------------------------------------
do
	local parent = guiParent()
	pcall(function()
		local old = parent:FindFirstChild("SellLemonsStatus")
		if old then old:Destroy() end
	end)

	local sgui = new("ScreenGui", {
		Name = "SellLemonsStatus", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9989,
	}, parent)
	Hub.statusGui = sgui

	local frame = new("Frame", {
		Position = UDim2.new(0, 14, 0, 90), Size = UDim2.new(0, 214, 0, 226),
		BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.05, BorderSizePixel = 0, Active = true,
	}, sgui)
	corner(frame, 12)
	stroke(frame, Theme.Stroke, 1, 0.4)
	gradient(frame, Theme.Panel, Color3.fromRGB(17, 18, 23), 90)

	local title = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Panel2, BorderSizePixel = 0 }, frame)
	corner(title, 12)
	new("Frame", { Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = Theme.Panel2, BorderSizePixel = 0 }, title)
	new("TextLabel", {
		Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = "🍋 LIVE STATUS", TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Text,
	}, title)
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0, 8, 0, 8),
		BorderSizePixel = 0,
	}, title)
	corner(dot, 4)
	trackAccent(dot, "BackgroundColor3")
	dragify(frame, title)

	-- FPS sparkline
	local graph = new("Frame", {
		Position = UDim2.new(0, 10, 0, 38), Size = UDim2.new(1, -20, 0, 30),
		BackgroundColor3 = Theme.BG, BorderSizePixel = 0,
	}, frame)
	corner(graph, 6)
	local BARS = 32
	local bars = {}
	for i = 1, BARS do
		local b = new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new((i - 1) / BARS, 1, 1, -2),
			Size = UDim2.new(1 / BARS, -1, 0, 1), BorderSizePixel = 0,
		}, graph)
		trackAccent(b, "BackgroundColor3")
		bars[i] = b
	end

	local body = new("TextLabel", {
		Position = UDim2.new(0, 12, 0, 74), Size = UDim2.new(1, -22, 1, -82), BackgroundTransparency = 1,
		Font = Enum.Font.Code, RichText = true, TextSize = 12, TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "starting...",
	}, frame)

	-- fps tracking
	local fps, frames, fpsT = 60, 0, os.clock()
	local hist = {}
	track(RunService.RenderStepped:Connect(function()
		frames += 1
		if os.clock() - fpsT >= 0.5 then
			fps = math.floor(frames / (os.clock() - fpsT) + 0.5)
			frames, fpsT = 0, os.clock()
			hist[#hist + 1] = fps
			if #hist > BARS then table.remove(hist, 1) end
		end
	end))

	local function onoff(b) return b and "<font color='#7CD957'>ON</font>" or "<font color='#6A6F7D'>off</font>" end

	Scheduler.every(0.25, function()
		if not sgui.Parent then return end
		-- graph
		local maxFps = 60
		for _, v in ipairs(hist) do if v > maxFps then maxFps = v end end
		for i = 1, BARS do
			local v = hist[#hist - BARS + i] or 0
			local h = math.clamp(v / maxFps, 0.02, 1)
			bars[i].Size = UDim2.new(1 / BARS, -1, h, -2)
		end
		-- cash
		local cash = "?"
		local ls = LocalPlayer:FindFirstChild("leaderstats")
		local c = ls and ls:FindFirstChild("Cash")
		if c then cash = abbrev(c.Value) end

		body.Text = string.format(
			"FPS  <font color='#ECEEF5'>%d</font>   Cash <font color='#F5CD42'>%s</font>\n\n"
			.. "Buy   %-7d %s\nUpg   %-7d %s\nFruit %-7d %s\nReb   %-7d %s\nEvo   %-7d %s\nAsc   %-7d %s",
			fps, cash,
			stats.buys, onoff(F.AutoBuy),
			stats.upgrades, onoff(F.AutoUpgrade),
			stats.fruit, onoff(F.AutoFruit),
			stats.rebirths, onoff(F.AutoRebirth),
			stats.evolves, onoff(F.AutoEvolve),
			stats.ascends, onoff(F.AutoAscend)
		)
	end, "StatusHUD")
end

------------------------------------------------------------------------
Notify({
	Title = "Loaded 🍋",
	Content = userTycoon and "Sell Lemons autofarm v2.0 ready." or "Loaded, but no tycoon found yet.",
	Type = userTycoon and "success" or "warning",
	Duration = 5,
})
