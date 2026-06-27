--[[
	HUDController.lua
	Type:     LocalScript
	Location: StarterPlayerScripts

	@description  Tap, BuyRune, fruit teleport-collect, ore auto-mine with MineRange detection.
	@version      4.4.0

	v4.4.0  Auto-mine no longer hangs on a depleted ore until it regenerates.
	        The inner loop now rotates to the next ore the moment the current
	        one is mined out, using layered depletion signals:
	          1. known depletion / "can-mine" / health attributes
	          2. a generic "stall" detector (no observable change for N hits)
	          3. a per-ore time budget + small hit cap as hard upper bounds
	        Ores are also visited nearest-first each pass for tighter routing,
	        and RUN DUMP now prints every ore attribute / child so the exact
	        depletion signal for a given game can be pinned down.
]]

-- ── Services ──────────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not UserInputService.TouchEnabled then return end

-- ── Player ────────────────────────────────────────────────────────────────────
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local old = PlayerGui:FindFirstChild("HUDController")
if old then old:Destroy() end

-- ── Remotes ───────────────────────────────────────────────────────────────────
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local InputDispatch = Remotes:WaitForChild("Tap")
local ItemDispatch  = Remotes:WaitForChild("BuyRune")
local FruitRemote   = Remotes:FindFirstChild("CollectFruit")
local MineDispatch  = Remotes:WaitForChild("MineOre")

-- ── Framework ─────────────────────────────────────────────────────────────────
local Framework = nil
do
	local ok, r = pcall(function() return require(ReplicatedStorage:WaitForChild("Framework")) end)
	if ok then Framework = r else warn("[HUD] Framework:", r) end
end

-- ── State ─────────────────────────────────────────────────────────────────────
local isTapping    = false
local isBuyingRune = false
local fruitActive  = false
local mineActive   = false

local tapThread:      thread? = nil
local runeThread:     thread? = nil
local fruitThread:    thread? = nil
local fruitChildConn: RBXScriptConnection? = nil
local mineThread:     thread? = nil

local tapCounter    = 0
local runeCounter   = 0
local fruitTotal    = 0
local fruitAttempts = 0
local fruitFails    = 0
local mineTotal     = 0
local mineOreCount  = 0   -- ores rotated through (for debug)
local counterReset  = tick()
local hudVisible    = true
local debugVisible  = false

local fruitCooldown  = {}
local fruitCollected = {}
local _oresCache: Instance? = nil

-- ── Timing ────────────────────────────────────────────────────────────────────
local TELEPORT_WAIT  = 0.25
local FRUIT_SCAN     = 0.15
local FRUIT_RETRY    = 0.5
local MINE_INTERVAL  = 0.15   -- seconds between mine hits
local MINE_MAX_HITS  = 40     -- hard safety cap per ore per pass
local MINE_STALL_HITS = 4     -- consecutive no-change hits => treat as depleted, rotate
local MINE_ORE_BUDGET = 4.0   -- max seconds to spend on one ore before rotating
local MINE_EMPTY_WAIT = 0.4   -- pause when no ores are available before rescanning

-- Attributes that, when set, indicate an ore is currently depleted / regenerating.
local MINE_DEPLETED_BOOL = {
	"Depleted","Mined","IsMined","Regenerating","Regening","IsRegening",
	"Respawning","OnCooldown","Cooldown","Broken","Destroyed","Dead",
}
-- Attributes where a value of `false` means the ore can't be mined right now.
local MINE_CANMINE_BOOL = {
	"CanMine","Mineable","IsMineable","Active","Available","Alive","Enabled",
}
-- Numeric attributes that count remaining ore; <= 0 means depleted.
local MINE_HEALTH_ATTRS = {
	"Health","CurrentHealth","HP","Hp","Amount","Remaining","RemainingHealth",
	"HitsLeft","Hits","HitCount","Durability","Capacity","Resource","Yield",
	"Quantity","Count","Ore","OreAmount","Stock",
}

-- ── Pure helpers ──────────────────────────────────────────────────────────────
local function getRoot(): BasePart?
	local char = LocalPlayer.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return (hrp and hrp:IsA("BasePart")) and hrp or nil
end

local function getClientFruits(): Instance?
	return workspace:FindFirstChild("ClientFruits")
end

local function getOresFolder(): Instance?
	if _oresCache and _oresCache.Parent then return _oresCache end
	_oresCache = workspace:FindFirstChild("Ores")
		or workspace:FindFirstChild("Ores", true)
	return _oresCache
end

-- Returns center position and radius of the MineRange part
local function getMineRange(ore: Model): (Vector3?, number?)
	local mr = ore:FindFirstChild("MineRange")
	if not mr then return nil, nil end
	if mr:IsA("BasePart") then
		return mr.Position, math.max(mr.Size.X, mr.Size.Z) / 2
	elseif mr:IsA("Model") then
		local cf, sz = mr:GetBoundingBox()
		return cf.Position, math.max(sz.X, sz.Z) / 2
	end
	return nil, nil
end

local function inRange(hrpPos: Vector3, center: Vector3, radius: number): boolean
	local d = hrpPos - center
	return Vector3.new(d.X, 0, d.Z).Magnitude <= radius
end

-- True if the ore reports, via any known attribute, that it's depleted/regenerating.
local function isOreDepleted(ore: Model): boolean
	for _, name in ipairs(MINE_DEPLETED_BOOL) do
		if ore:GetAttribute(name) == true then return true end
	end
	for _, name in ipairs(MINE_CANMINE_BOOL) do
		if ore:GetAttribute(name) == false then return true end
	end
	for _, name in ipairs(MINE_HEALTH_ATTRS) do
		local v = ore:GetAttribute(name)
		if type(v) == "number" and v <= 0 then return true end
	end
	return false
end

-- A compact signature of the ore's observable, mining-affected state.
-- While an ore is actively being mined this changes every hit; once depleted
-- (regenerating on a timer) it goes static, which is what we key off of.
local function oreFingerprint(ore: Model): string
	local parts = {}
	for _, name in ipairs(MINE_HEALTH_ATTRS) do
		local v = ore:GetAttribute(name)
		if v ~= nil then parts[#parts+1] = name .. "=" .. tostring(v) end
	end
	for _, name in ipairs(MINE_DEPLETED_BOOL) do
		local v = ore:GetAttribute(name)
		if v ~= nil then parts[#parts+1] = name .. "=" .. tostring(v) end
	end
	for _, name in ipairs(MINE_CANMINE_BOOL) do
		local v = ore:GetAttribute(name)
		if v ~= nil then parts[#parts+1] = name .. "=" .. tostring(v) end
	end
	local mp = ore:FindFirstChild("MainPart")
	if not (mp and mp:IsA("BasePart")) then mp = ore.PrimaryPart end
	if mp and mp:IsA("BasePart") then
		parts[#parts+1] = "T=" .. string.format("%.2f", mp.Transparency)
		parts[#parts+1] = "Col=" .. tostring(mp.CanCollide)
		parts[#parts+1] = "Sz=" .. string.format("%.1f", mp.Size.Magnitude)
	end
	return table.concat(parts, "|")
end

local function getFruitId(model: Model)
	for _, a in ipairs({"Id","ID","id","FruitId","FruitID","fruitId"}) do
		local v = model:GetAttribute(a)
		if typeof(v) == "number" then return v end
		if typeof(v) == "string" and v ~= "" then return tonumber(v) or v end
	end
	local n = model.Name:match("_(%d+)$")
	if n then return tonumber(n) end
	local s = model.Name:match("_([^_]+)$")
	return (s and s ~= "") and (tonumber(s) or s) or nil
end

local function getFruitPart(model: Model): BasePart?
	local mp = model:FindFirstChild("MainPart")
	if mp and mp:IsA("BasePart") then return mp end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function teleportTo(pos: Vector3): boolean
	local root = getRoot()
	if not root then return false end
	root.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
	return true
end

-- ── UI Root ───────────────────────────────────────────────────────────────────
local UIRoot = Instance.new("ScreenGui")
UIRoot.Name = "HUDController"; UIRoot.ResetOnSpawn = false
UIRoot.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
UIRoot.IgnoreGuiInset = true; UIRoot.Parent = PlayerGui

-- ── Indicator ─────────────────────────────────────────────────────────────────
local Indicator = Instance.new("TextButton")
Indicator.Name = "StatusIndicator"
Indicator.Size = UDim2.new(0, 52, 0, 52)
Indicator.Position = UDim2.new(0, 14, 0.5, -26)
Indicator.BackgroundColor3 = Color3.fromRGB(26, 26, 38)
Indicator.BorderSizePixel = 0; Indicator.Text = "⚡"
Indicator.TextSize = 22; Indicator.Font = Enum.Font.GothamBold
Indicator.TextColor3 = Color3.fromRGB(240, 230, 255)
Indicator.ZIndex = 10; Indicator.Parent = UIRoot
do
	Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)
	local s = Instance.new("UIStroke", Indicator)
	s.Color = Color3.fromRGB(55, 55, 85); s.Thickness = 1
end

-- ── HUD panel — 362px tall for 4 sections ────────────────────────────────────
local HUDPanel = Instance.new("Frame")
HUDPanel.Name = "HUDPanel"
HUDPanel.Size = UDim2.new(0, 235, 0, 362)
HUDPanel.Position = UDim2.new(0, 74, 0.5, -181)
HUDPanel.BackgroundColor3 = Color3.fromRGB(13, 13, 19)
HUDPanel.BorderSizePixel = 0; HUDPanel.ZIndex = 5; HUDPanel.Parent = UIRoot
do
	Instance.new("UICorner", HUDPanel).CornerRadius = UDim.new(0, 13)
	local s = Instance.new("UIStroke", HUDPanel)
	s.Color = Color3.fromRGB(42, 42, 68); s.Thickness = 1
end

local HeaderBar = Instance.new("Frame", HUDPanel)
HeaderBar.Size = UDim2.new(1, 0, 0, 40)
HeaderBar.BackgroundColor3 = Color3.fromRGB(20, 20, 31)
HeaderBar.BorderSizePixel = 0; HeaderBar.ZIndex = 6
do
	Instance.new("UICorner", HeaderBar).CornerRadius = UDim.new(0, 13)
	local p = Instance.new("Frame", HeaderBar)
	p.Size = UDim2.new(1,0,0,10); p.Position = UDim2.new(0,0,1,-10)
	p.BackgroundColor3 = Color3.fromRGB(20,20,31); p.BorderSizePixel = 0; p.ZIndex = 6
end

local HeaderText = Instance.new("TextLabel", HeaderBar)
HeaderText.Size = UDim2.new(1,-54,1,0); HeaderText.Position = UDim2.new(0,14,0,0)
HeaderText.BackgroundTransparency = 1; HeaderText.Text = "⚡ Input Manager  ·  dev"
HeaderText.TextColor3 = Color3.fromRGB(185,185,215); HeaderText.TextSize = 12
HeaderText.Font = Enum.Font.GothamBold
HeaderText.TextXAlignment = Enum.TextXAlignment.Left; HeaderText.ZIndex = 7

local DebugBtn = Instance.new("TextButton", HeaderBar)
DebugBtn.Size = UDim2.new(0,36,0,22); DebugBtn.Position = UDim2.new(1,-42,0.5,-11)
DebugBtn.BackgroundColor3 = Color3.fromRGB(35,35,55); DebugBtn.BorderSizePixel = 0
DebugBtn.Text = "DBG"; DebugBtn.TextColor3 = Color3.fromRGB(140,140,200)
DebugBtn.TextSize = 10; DebugBtn.Font = Enum.Font.GothamBold; DebugBtn.ZIndex = 8
Instance.new("UICorner", DebugBtn).CornerRadius = UDim.new(0,5)

-- TAP  (label Y=46, btn Y=70)
local TapRateLabel = Instance.new("TextLabel", HUDPanel)
TapRateLabel.Size=UDim2.new(1,-16,0,20); TapRateLabel.Position=UDim2.new(0,8,0,46)
TapRateLabel.BackgroundTransparency=1; TapRateLabel.Text="TAP  ·  — /s"
TapRateLabel.TextColor3=Color3.fromRGB(105,105,145); TapRateLabel.TextXAlignment=Enum.TextXAlignment.Left
TapRateLabel.TextSize=12; TapRateLabel.Font=Enum.Font.Gotham; TapRateLabel.ZIndex=6

local TapToggle = Instance.new("TextButton", HUDPanel)
TapToggle.Size=UDim2.new(1,-20,0,38); TapToggle.Position=UDim2.new(0,10,0,70)
TapToggle.BackgroundColor3=Color3.fromRGB(52,195,72); TapToggle.BorderSizePixel=0
TapToggle.Text="▶  START TAP"; TapToggle.TextColor3=Color3.fromRGB(255,255,255)
TapToggle.TextSize=13; TapToggle.Font=Enum.Font.GothamBold; TapToggle.ZIndex=6
Instance.new("UICorner",TapToggle).CornerRadius=UDim.new(0,9)

local Div1 = Instance.new("Frame", HUDPanel)
Div1.Size=UDim2.new(1,-20,0,1); Div1.Position=UDim2.new(0,10,0,116)
Div1.BackgroundColor3=Color3.fromRGB(38,38,58); Div1.BorderSizePixel=0; Div1.ZIndex=6

-- RUNE  (label Y=124, btn Y=148)
local RuneRateLabel = Instance.new("TextLabel", HUDPanel)
RuneRateLabel.Size=UDim2.new(1,-16,0,20); RuneRateLabel.Position=UDim2.new(0,8,0,124)
RuneRateLabel.BackgroundTransparency=1; RuneRateLabel.Text="RUNE  ·  — /s"
RuneRateLabel.TextColor3=Color3.fromRGB(105,105,145); RuneRateLabel.TextXAlignment=Enum.TextXAlignment.Left
RuneRateLabel.TextSize=12; RuneRateLabel.Font=Enum.Font.Gotham; RuneRateLabel.ZIndex=6

local RuneToggle = Instance.new("TextButton", HUDPanel)
RuneToggle.Size=UDim2.new(1,-20,0,38); RuneToggle.Position=UDim2.new(0,10,0,148)
RuneToggle.BackgroundColor3=Color3.fromRGB(130,80,220); RuneToggle.BorderSizePixel=0
RuneToggle.Text="▶  START RUNE"; RuneToggle.TextColor3=Color3.fromRGB(255,255,255)
RuneToggle.TextSize=13; RuneToggle.Font=Enum.Font.GothamBold; RuneToggle.ZIndex=6
Instance.new("UICorner",RuneToggle).CornerRadius=UDim.new(0,9)

local Div2 = Instance.new("Frame", HUDPanel)
Div2.Size=UDim2.new(1,-20,0,1); Div2.Position=UDim2.new(0,10,0,194)
Div2.BackgroundColor3=Color3.fromRGB(38,38,58); Div2.BorderSizePixel=0; Div2.ZIndex=6

-- FRUIT  (label Y=202, btn Y=226)
local FruitRateLabel = Instance.new("TextLabel", HUDPanel)
FruitRateLabel.Size=UDim2.new(1,-16,0,20); FruitRateLabel.Position=UDim2.new(0,8,0,202)
FruitRateLabel.BackgroundTransparency=1; FruitRateLabel.Text="FRUIT  ·  — collected"
FruitRateLabel.TextColor3=Color3.fromRGB(105,105,145); FruitRateLabel.TextXAlignment=Enum.TextXAlignment.Left
FruitRateLabel.TextSize=12; FruitRateLabel.Font=Enum.Font.Gotham; FruitRateLabel.ZIndex=6

local FruitToggle = Instance.new("TextButton", HUDPanel)
FruitToggle.Size=UDim2.new(1,-20,0,38); FruitToggle.Position=UDim2.new(0,10,0,226)
FruitToggle.BackgroundColor3=Color3.fromRGB(210,120,40); FruitToggle.BorderSizePixel=0
FruitToggle.Text="▶  START FRUIT"; FruitToggle.TextColor3=Color3.fromRGB(255,255,255)
FruitToggle.TextSize=13; FruitToggle.Font=Enum.Font.GothamBold; FruitToggle.ZIndex=6
Instance.new("UICorner",FruitToggle).CornerRadius=UDim.new(0,9)

local Div3 = Instance.new("Frame", HUDPanel)
Div3.Size=UDim2.new(1,-20,0,1); Div3.Position=UDim2.new(0,10,0,272)
Div3.BackgroundColor3=Color3.fromRGB(38,38,58); Div3.BorderSizePixel=0; Div3.ZIndex=6

-- MINE  (label Y=280, btn Y=304)
local MineRateLabel = Instance.new("TextLabel", HUDPanel)
MineRateLabel.Size=UDim2.new(1,-16,0,20); MineRateLabel.Position=UDim2.new(0,8,0,280)
MineRateLabel.BackgroundTransparency=1; MineRateLabel.Text="MINE  ·  — hits"
MineRateLabel.TextColor3=Color3.fromRGB(105,105,145); MineRateLabel.TextXAlignment=Enum.TextXAlignment.Left
MineRateLabel.TextSize=12; MineRateLabel.Font=Enum.Font.Gotham; MineRateLabel.ZIndex=6

local MineToggle = Instance.new("TextButton", HUDPanel)
MineToggle.Size=UDim2.new(1,-20,0,38); MineToggle.Position=UDim2.new(0,10,0,304)
MineToggle.BackgroundColor3=Color3.fromRGB(55,155,195); MineToggle.BorderSizePixel=0
MineToggle.Text="▶  START MINE"; MineToggle.TextColor3=Color3.fromRGB(255,255,255)
MineToggle.TextSize=13; MineToggle.Font=Enum.Font.GothamBold; MineToggle.ZIndex=6
Instance.new("UICorner",MineToggle).CornerRadius=UDim.new(0,9)

-- ── Debug panel ───────────────────────────────────────────────────────────────
local DebugPanel = Instance.new("Frame")
DebugPanel.Name="DebugPanel"; DebugPanel.Size=UDim2.new(0,370,0,362)
DebugPanel.Position=UDim2.new(0,317,0.5,-181)
DebugPanel.BackgroundColor3=Color3.fromRGB(13,13,19)
DebugPanel.BorderSizePixel=0; DebugPanel.Visible=false; DebugPanel.ZIndex=5; DebugPanel.Parent=UIRoot
do
	Instance.new("UICorner",DebugPanel).CornerRadius=UDim.new(0,13)
	local s=Instance.new("UIStroke",DebugPanel); s.Color=Color3.fromRGB(42,42,68); s.Thickness=1
end

local DebugHeader = Instance.new("Frame", DebugPanel)
DebugHeader.Size=UDim2.new(1,0,0,40); DebugHeader.BackgroundColor3=Color3.fromRGB(20,20,31)
DebugHeader.BorderSizePixel=0; DebugHeader.ZIndex=6
do
	Instance.new("UICorner",DebugHeader).CornerRadius=UDim.new(0,13)
	local p=Instance.new("Frame",DebugHeader)
	p.Size=UDim2.new(1,0,0,10); p.Position=UDim2.new(0,0,1,-10)
	p.BackgroundColor3=Color3.fromRGB(20,20,31); p.BorderSizePixel=0; p.ZIndex=6
end

local DebugHeaderText = Instance.new("TextLabel", DebugHeader)
DebugHeaderText.Size=UDim2.new(1,-100,1,0); DebugHeaderText.Position=UDim2.new(0,14,0,0)
DebugHeaderText.BackgroundTransparency=1; DebugHeaderText.Text="🔍 Debug  ·  v4.4"
DebugHeaderText.TextColor3=Color3.fromRGB(185,185,215); DebugHeaderText.TextSize=11
DebugHeaderText.Font=Enum.Font.GothamBold; DebugHeaderText.TextXAlignment=Enum.TextXAlignment.Left; DebugHeaderText.ZIndex=7

local RunDumpBtn = Instance.new("TextButton", DebugHeader)
RunDumpBtn.Size=UDim2.new(0,74,0,22); RunDumpBtn.Position=UDim2.new(1,-80,0.5,-11)
RunDumpBtn.BackgroundColor3=Color3.fromRGB(40,100,180); RunDumpBtn.BorderSizePixel=0
RunDumpBtn.Text="RUN DUMP"; RunDumpBtn.TextColor3=Color3.fromRGB(220,235,255)
RunDumpBtn.TextSize=10; RunDumpBtn.Font=Enum.Font.GothamBold; RunDumpBtn.ZIndex=8
Instance.new("UICorner",RunDumpBtn).CornerRadius=UDim.new(0,5)

local DebugScroll = Instance.new("ScrollingFrame", DebugPanel)
DebugScroll.Size=UDim2.new(1,-16,1,-56); DebugScroll.Position=UDim2.new(0,8,0,44)
DebugScroll.BackgroundColor3=Color3.fromRGB(8,8,14); DebugScroll.BorderSizePixel=0
DebugScroll.ScrollBarThickness=4; DebugScroll.ScrollBarImageColor3=Color3.fromRGB(60,60,100)
DebugScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; DebugScroll.CanvasSize=UDim2.new(0,0,0,0)
DebugScroll.ZIndex=6
Instance.new("UICorner",DebugScroll).CornerRadius=UDim.new(0,7)

local DebugTextBox = Instance.new("TextBox", DebugScroll)
DebugTextBox.Size=UDim2.new(1,-8,0,0); DebugTextBox.Position=UDim2.new(0,4,0,4)
DebugTextBox.BackgroundTransparency=1; DebugTextBox.Text="Press RUN DUMP with ores/fruits visible."
DebugTextBox.TextColor3=Color3.fromRGB(150,210,150); DebugTextBox.TextSize=10; DebugTextBox.Font=Enum.Font.Code
DebugTextBox.TextXAlignment=Enum.TextXAlignment.Left; DebugTextBox.TextYAlignment=Enum.TextYAlignment.Top
DebugTextBox.TextWrapped=true; DebugTextBox.MultiLine=true
DebugTextBox.ClearTextOnFocus=false; DebugTextBox.TextEditable=true
DebugTextBox.AutomaticSize=Enum.AutomaticSize.Y; DebugTextBox.ZIndex=7

local CopyHint = Instance.new("TextLabel", DebugPanel)
CopyHint.Size=UDim2.new(1,-16,0,14); CopyHint.Position=UDim2.new(0,8,1,-18)
CopyHint.BackgroundTransparency=1; CopyHint.Text="tap box → select all → copy"
CopyHint.TextColor3=Color3.fromRGB(70,70,110); CopyHint.TextSize=10
CopyHint.Font=Enum.Font.Gotham; CopyHint.TextXAlignment=Enum.TextXAlignment.Center; CopyHint.ZIndex=6

-- ── Drag ──────────────────────────────────────────────────────────────────────
local DRAG_THRESHOLD = 8
local function makeDraggable(handle: GuiObject, target: GuiObject): () -> boolean
	local dragging=false; local wasDragged=false
	local dragStart: Vector3; local startPos: UDim2
	handle.InputBegan:Connect(function(i: InputObject)
		if i.UserInputType~=Enum.UserInputType.MouseButton1
			and i.UserInputType~=Enum.UserInputType.Touch then return end
		dragging=true; wasDragged=false; dragStart=i.Position; startPos=target.Position
	end)
	UserInputService.InputChanged:Connect(function(i: InputObject)
		if not dragging then return end
		if i.UserInputType~=Enum.UserInputType.MouseMovement
			and i.UserInputType~=Enum.UserInputType.Touch then return end
		local d=i.Position-dragStart
		if d.Magnitude>=DRAG_THRESHOLD then
			wasDragged=true
			target.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(i: InputObject)
		if i.UserInputType==Enum.UserInputType.MouseButton1
			or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
	end)
	return function(): boolean return wasDragged end
end

local indicatorDragged = makeDraggable(Indicator, Indicator)
makeDraggable(HeaderBar, HUDPanel)
makeDraggable(DebugHeader, DebugPanel)

-- ── Behavior (all UI locals now in scope) ─────────────────────────────────────

local function dumpToString(): string
	local L={"==== HUD DEBUG v4.4 ===="}
	local cf=getClientFruits(); local of=getOresFolder(); local root=getRoot()
	table.insert(L,"HRP: "..(root and tostring(root.Position) or "NONE"))
	table.insert(L,"CLIENTFRUITS: "..(cf and cf:GetFullName() or "NONE"))
	table.insert(L,"ORES: "..(of and of:GetFullName() or "NONE"))
	table.insert(L,"Framework: "..(Framework and "loaded" or "MISSING"))
	table.insert(L,"FruitRemote: "..(FruitRemote and FruitRemote.ClassName or "MISSING"))
	if cf then
		table.insert(L,""); table.insert(L,"=== FRUITS ===")
		for _,o in ipairs(cf:GetChildren()) do
			if o:IsA("Model") then
				table.insert(L,string.format("N:%s ID:%s",o.Name,tostring(getFruitId(o))))
			end
		end
	end
	if of then
		table.insert(L,""); table.insert(L,"=== ORES (full attribute dump) ===")
		for _,o in ipairs(of:GetChildren()) do
			if o:IsA("Model") then
				local oreId=o:GetAttribute("OreId")
				local mrPos,mrR=getMineRange(o)
				table.insert(L,string.format("N:%s | OreId:%s | depleted?:%s | MR_pos:%s | MR_r:%.1f",
					o.Name,tostring(oreId),tostring(isOreDepleted(o)),
					mrPos and tostring(mrPos) or "NONE",mrR or 0))
				-- every attribute (so the real depletion signal can be identified)
				local attrs=o:GetAttributes()
				local akeys={}
				for k in pairs(attrs) do table.insert(akeys,k) end
				table.sort(akeys)
				if #akeys>0 then
					local pieces={}
					for _,k in ipairs(akeys) do
						table.insert(pieces,string.format("%s=%s(%s)",k,tostring(attrs[k]),typeof(attrs[k])))
					end
					table.insert(L,"   attrs: "..table.concat(pieces,", "))
				else
					table.insert(L,"   attrs: <none>")
				end
				-- direct children (timer parts / prompts often live here)
				local kids={}
				for _,c in ipairs(o:GetChildren()) do
					table.insert(kids,c.Name.."<"..c.ClassName..">")
				end
				table.insert(L,"   children: "..(#kids>0 and table.concat(kids,", ") or "<none>"))
			end
		end
	end
	table.insert(L,"")
	table.insert(L,string.format("Fruit: %d collected / %d attempts / %d fails",fruitTotal,fruitAttempts,fruitFails))
	table.insert(L,string.format("Mine: %d hits / %d ores rotated",mineTotal,mineOreCount))
	table.insert(L,"==== END ====")
	return table.concat(L,"\n")
end

local function collectFruit(fruitId, model: Model)
	if not fruitId or fruitCollected[fruitId] then return end
	local now=os.clock()
	if fruitCooldown[fruitId] and now-fruitCooldown[fruitId]<FRUIT_RETRY then return end
	fruitCooldown[fruitId]=now; fruitAttempts+=1
	task.spawn(function()
		local part=getFruitPart(model)
		if part then teleportTo(part.Position); task.wait(TELEPORT_WAIT) end
		if not model or not model.Parent then fruitFails+=1; return end
		if Framework and Framework.Network and typeof(Framework.Network.Fire)=="function" then
			local ok,success,rn,ra=pcall(function() return Framework.Network.Fire("CollectFruit",fruitId) end)
			if ok and success then
				fruitCollected[fruitId]=true; fruitTotal+=1
				print("[Fruit] ✓ Framework:",model.Name,"ID:",fruitId,rn,ra); return
			else fruitFails+=1; print("[Fruit] ✗ Framework:",model.Name,"ID:",fruitId,"suc=",tostring(success)) end
		end
		if FruitRemote and FruitRemote:IsA("RemoteFunction") then
			local ok,r=pcall(function() return FruitRemote:InvokeServer(fruitId) end)
			if ok and r then
				fruitCollected[fruitId]=true; fruitTotal+=1
				print("[Fruit] ✓ RemoteFunction:",model.Name,"ID:",fruitId); return
			else fruitFails+=1; print("[Fruit] ✗ RemoteFunction:",model.Name,"ID:",fruitId) end
		end
		if FruitRemote and FruitRemote:IsA("RemoteEvent") then
			pcall(function() FruitRemote:FireServer(fruitId) end)
		end
	end)
end

local function tryFruitModel(model: Model)
	if not fruitActive or not model or not model.Parent then return end
	local cf=getClientFruits()
	if not cf or model.Parent~=cf then return end
	local id=getFruitId(model); if not id or fruitCollected[id] then return end
	collectFruit(id,model)
end

local function scanFruits(): number
	local cf=getClientFruits(); if not cf then return 0 end
	local count=0
	for _,o in ipairs(cf:GetChildren()) do
		if o:IsA("Model") then count+=1; tryFruitModel(o) end
	end
	return count
end

-- Mine loop: teleport into each ore's MineRange, swing until it's depleted,
-- then immediately rotate to the next ore (nearest-first) instead of waiting
-- for the spent ore to regenerate in place.
local function mineOne(entry, root: BasePart): boolean
	local ore=entry.model; local oreId=entry.id
	if not ore.Parent then return false end

	local mrPos,mrRadius=getMineRange(ore)
	if not mrPos or not mrRadius then return false end

	-- already regenerating? skip without wasting hits
	if isOreDepleted(ore) then return false end

	-- teleport into the circle if needed
	if not inRange(root.Position,mrPos,mrRadius) then
		root.CFrame=CFrame.new(mrPos+Vector3.new(0,3,0))
		task.wait(TELEPORT_WAIT)
	end

	local hits=0
	local stall=0
	local lastFp=oreFingerprint(ore)
	local startedAt=os.clock()
	mineOreCount+=1

	while mineActive and ore.Parent and hits<MINE_MAX_HITS do
		root=getRoot(); if not root then return true end

		-- re-center if we drifted out of range
		if not inRange(root.Position,mrPos,mrRadius) then
			root.CFrame=CFrame.new(mrPos+Vector3.new(0,3,0))
			task.wait(TELEPORT_WAIT)
		end

		pcall(function() MineDispatch:InvokeServer(oreId) end)
		mineTotal+=1; hits+=1
		MineRateLabel.Text=string.format("MINE  ·  %d hits  ·  %s",mineTotal,oreId)
		task.wait(MINE_INTERVAL)

		-- (1) explicit depletion signal → rotate now
		if isOreDepleted(ore) then break end

		-- (2) generic stall: nothing observable changed for N hits → depleted/regening
		local fp=oreFingerprint(ore)
		if fp==lastFp then
			stall+=1
			if stall>=MINE_STALL_HITS then break end
		else
			stall=0; lastFp=fp
		end

		-- (3) hard per-ore time budget → never camp a single ore
		if os.clock()-startedAt>=MINE_ORE_BUDGET then break end
	end
	return true
end

local function autoMineLoop()
	while mineActive do
		local of=getOresFolder()
		if not of then
			MineRateLabel.Text="MINE  ·  no ore folder"
			task.wait(1); continue
		end

		local root=getRoot()
		if not root then task.wait(0.25); continue end

		-- snapshot current, mineable ores
		local ores={}
		for _,child in ipairs(of:GetChildren()) do
			if child:IsA("Model") then
				local id=child:GetAttribute("OreId")
				if type(id)=="string" and id~="" then
					local mrPos=select(1,getMineRange(child))
					local dist=mrPos and (root.Position-mrPos).Magnitude or math.huge
					table.insert(ores,{model=child,id=id,pos=mrPos,dist=dist})
				end
			end
		end

		if #ores==0 then
			MineRateLabel.Text="MINE  ·  0 ores found"
			task.wait(MINE_EMPTY_WAIT); continue
		end

		-- nearest-first so we route tightly between ores
		table.sort(ores,function(a,b) return a.dist<b.dist end)

		local minedAny=false
		for _,entry in ipairs(ores) do
			if not mineActive then break end
			root=getRoot(); if not root then break end
			-- skip ores already regenerating up front
			if entry.model.Parent and not isOreDepleted(entry.model) then
				if mineOne(entry,root) then minedAny=true end
			end
		end

		-- everything in this pass was depleted; wait briefly for a regen instead
		-- of hammering the same spent nodes in a tight loop
		if not minedAny and mineActive then
			MineRateLabel.Text=string.format("MINE  ·  %d hits  ·  all regening",mineTotal)
			task.wait(MINE_EMPTY_WAIT)
		end
	end
end

-- ── Connections ───────────────────────────────────────────────────────────────
Indicator.MouseButton1Up:Connect(function()
	if indicatorDragged() then return end
	hudVisible=not hudVisible; HUDPanel.Visible=hudVisible
end)

DebugBtn.MouseButton1Click:Connect(function()
	debugVisible=not debugVisible; DebugPanel.Visible=debugVisible
	DebugBtn.TextColor3=debugVisible and Color3.fromRGB(100,210,100) or Color3.fromRGB(140,140,200)
end)

RunDumpBtn.MouseButton1Click:Connect(function()
	RunDumpBtn.Text="SCANNING..."
	task.spawn(function()
		local t=dumpToString(); DebugTextBox.Text=t
		print("════════════════"); print(t); print("════════════════")
		RunDumpBtn.Text="RUN DUMP"
	end)
end)

local function setTapping(state: boolean)
	isTapping=state
	if isTapping then
		TapToggle.Text="■  STOP TAP"; TapToggle.BackgroundColor3=Color3.fromRGB(200,50,50)
		tapCounter=0; counterReset=tick()
		tapThread=task.spawn(function()
			while isTapping do pcall(function() InputDispatch:FireServer() end); tapCounter+=1; task.wait() end
		end)
	else
		TapToggle.Text="▶  START TAP"; TapToggle.BackgroundColor3=Color3.fromRGB(52,195,72)
		TapRateLabel.Text="TAP  ·  — /s"; tapThread=nil
	end
end
TapToggle.MouseButton1Click:Connect(function() setTapping(not isTapping) end)

local function setRuneBuying(state: boolean)
	isBuyingRune=state
	if isBuyingRune then
		RuneToggle.Text="■  STOP RUNE"; RuneToggle.BackgroundColor3=Color3.fromRGB(170,40,170)
		runeCounter=0
		runeThread=task.spawn(function()
			while isBuyingRune do pcall(function() ItemDispatch:FireServer("Basic") end); runeCounter+=1; task.wait() end
		end)
	else
		RuneToggle.Text="▶  START RUNE"; RuneToggle.BackgroundColor3=Color3.fromRGB(130,80,220)
		RuneRateLabel.Text="RUNE  ·  — /s"; runeThread=nil
	end
end
RuneToggle.MouseButton1Click:Connect(function() setRuneBuying(not isBuyingRune) end)

local function setFruitActive(state: boolean)
	fruitActive=state
	if fruitActive then
		FruitToggle.Text="■  STOP FRUIT"; FruitToggle.BackgroundColor3=Color3.fromRGB(170,70,20)
		fruitTotal=0; fruitAttempts=0; fruitFails=0; fruitCooldown={}; fruitCollected={}
		print("[Fruit] Started  wait="..tostring(TELEPORT_WAIT).."s")
		local cf=getClientFruits()
		if cf and not fruitChildConn then
			fruitChildConn=cf.ChildAdded:Connect(function(child)
				if not fruitActive then return end
				task.wait(0.05); if child:IsA("Model") then tryFruitModel(child) end
			end)
		end
		fruitThread=task.spawn(function()
			while fruitActive do
				local found=scanFruits()
				FruitRateLabel.Text=string.format("FRUIT  ·  %d collected  ·  %d found",fruitTotal,found)
				task.wait(FRUIT_SCAN)
			end
		end)
	else
		FruitToggle.Text="▶  START FRUIT"; FruitToggle.BackgroundColor3=Color3.fromRGB(210,120,40)
		FruitRateLabel.Text="FRUIT  ·  — collected"
		if fruitChildConn then fruitChildConn:Disconnect(); fruitChildConn=nil end
		fruitThread=nil
	end
end
FruitToggle.MouseButton1Click:Connect(function() setFruitActive(not fruitActive) end)

local function setMineActive(state: boolean)
	mineActive=state
	if mineActive then
		MineToggle.Text="■  STOP MINE"; MineToggle.BackgroundColor3=Color3.fromRGB(25,100,145)
		mineTotal=0; mineOreCount=0
		print("[Mine] Started — workspace.Ores  interval="..tostring(MINE_INTERVAL).."s  budget="..tostring(MINE_ORE_BUDGET).."s")
		mineThread=task.spawn(autoMineLoop)
	else
		MineToggle.Text="▶  START MINE"; MineToggle.BackgroundColor3=Color3.fromRGB(55,155,195)
		MineRateLabel.Text="MINE  ·  — hits"
		print("[Mine] Stopped."); mineThread=nil
	end
end
MineToggle.MouseButton1Click:Connect(function() setMineActive(not mineActive) end)

-- ── Rate counter ──────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
	local now=tick()
	if now-counterReset>=1 then
		if isTapping then TapRateLabel.Text=string.format("TAP  ·  %d /s",tapCounter) end
		if isBuyingRune then RuneRateLabel.Text=string.format("RUNE  ·  %d /s",runeCounter) end
		tapCounter=0; runeCounter=0; counterReset=now
	end
end)
