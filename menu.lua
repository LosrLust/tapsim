-- TapSim V1.1 - lust
local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local UserInputService=game:GetService("UserInputService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local MarketplaceService=game:GetService("MarketplaceService")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer or Players.PlayerAdded:Wait()
local function guiParent()
	local pg=player:FindFirstChild("PlayerGui"); if pg then return pg end
	local ok,hui=pcall(function() return gethui() end); if ok and hui then return hui end
	return game:GetService("CoreGui")
end
local parent=guiParent()
local CoreGui=game:GetService("CoreGui")
local G=(getgenv and getgenv()) or _G
if G.__TapSimUI and typeof(G.__TapSimUI)=="Instance" then
	pcall(function() G.__TapSimUI:Destroy() end)
end
local function cleanup(container)
	if not container then return end
	for _,inst in ipairs(container:GetDescendants()) do
		if inst:IsA("ScreenGui") then
			if inst.Name=="TapSim_CustomUI" or inst.Name=="TapSim_CustomUI_v3" then
				inst:Destroy()
			elseif inst:FindFirstChild("Main") and inst:FindFirstChild("Shadow") then
				local top=inst.Main:FindFirstChild("TopBar")
				if top then
					local title=top:FindFirstChildWhichIsA("TextLabel")
					if title and string.find(title.Text or "","TapSim",1,true) then
						inst:Destroy()
					end
				end
			end
		end
	end
end
cleanup(parent); cleanup(CoreGui)

-- Cleanup loop to kill any other TapSim UI that respawns
task.spawn(function()
	for _=1,20 do
		task.wait(0.5)
		for _,container in ipairs({parent,CoreGui}) do
			if container then
				for _,inst in ipairs(container:GetDescendants()) do
					if inst:IsA("ScreenGui") then
						if (inst.Name=="TapSim_CustomUI" or inst.Name=="TapSim_CustomUI_v3") and inst~=G.__TapSimUI then
							inst:Destroy()
						else
							local top=inst:FindFirstChild("Main") and inst.Main:FindFirstChild("TopBar")
							if top then
								local title=top:FindFirstChildWhichIsA("TextLabel")
								if title and string.find(title.Text or "","TapSim",1,true) and inst~=G.__TapSimUI then
									inst:Destroy()
								end
							end
						end
					end
				end
			end
		end
	end
end)

local Config={
	Density=1,
	Anim={Speed=1,Intensity=1},
	Theme={
		BG=Color3.fromRGB(9,9,11),
		PANEL=Color3.fromRGB(16,16,20),
		PANEL_2=Color3.fromRGB(20,20,24),
		PANEL_3=Color3.fromRGB(12,12,15),
		TEXT=Color3.fromRGB(220,220,220),
		TEXT_DIM=Color3.fromRGB(140,140,140),
	},
	Accent=Color3.fromRGB(50,55,65),
	AccentDark=Color3.fromRGB(30,34,42),
	Layout={W=560,H=340,Top=44,Side=150,Pad=14,Control=32,Radius=14,DropMax=190},
}
local L=Config.Layout
local T={BG=Config.Theme.BG,P=Config.Theme.PANEL,P2=Config.Theme.PANEL_2,P3=Config.Theme.PANEL_3,TX=Config.Theme.TEXT,TD=Config.Theme.TEXT_DIM,A=Config.Accent,AD=Config.AccentDark}
local function px(n) return math.floor(n*Config.Density+0.5) end
local function tw(o,d,props,style,dir)
	local t=TweenService:Create(o,TweenInfo.new((d or 0.12)/Config.Anim.Speed,style or Enum.EasingStyle.Quad,dir or Enum.EasingDirection.Out),props)
	t:Play(); return t
end
local function pressable(b)
	local sc=Instance.new("UIScale",b); sc.Scale=1
	local d=0.04*Config.Anim.Intensity
	b.MouseButton1Down:Connect(function() tw(sc,0.08,{Scale=1-d}) end)
	b.MouseButton1Up:Connect(function() tw(sc,0.1,{Scale=1}) end)
	b.MouseLeave:Connect(function() tw(sc,0.1,{Scale=1}) end)
end

-- Data
local State={InfJump=false,AutoHatch=false,AutoTap=false,SelEgg=nil,EggAmt=1}
local HatchPassId=1568018875
local function getHatchOptions()
	local ok,owned=pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId,HatchPassId) end)
	if ok and owned then return {1,3,8} end
	return {1,3}
end
local function safeRequire(m)
	if not m then return nil end
	local ok,res=pcall(require,m); if ok then return res end
	warn(res); return nil
end
local Eggs=safeRequire(ReplicatedStorage:FindFirstChild("Game") and ReplicatedStorage.Game:FindFirstChild("Eggs"))
local function eggList()
	local t={}
	if type(Eggs)=="table" then for k in pairs(Eggs) do t[#t+1]=k end end
	table.sort(t); return t
end
local Remotes={}
for _,r in ipairs(ReplicatedStorage:GetDescendants()) do
	if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then Remotes[r.Name]=r end
end
local Network=safeRequire(ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Network"))
local AutoDeleteRemote=(ReplicatedStorage:FindFirstChild("5ae8909d-173b-43be-8a1a-bb27001ec215")
	and ReplicatedStorage["5ae8909d-173b-43be-8a1a-bb27001ec215"]:FindFirstChild("Events")
	and ReplicatedStorage["5ae8909d-173b-43be-8a1a-bb27001ec215"].Events:FindFirstChild("AutoDelete"))
local function tap()
	if Network and Network.FireServer then pcall(function() Network:FireServer("Tap",true,nil,true) end); return end
	local re=Remotes.Tap; if re and re:IsA("RemoteEvent") then re:FireServer(true,nil,true) end
end
local function openEgg(name,amt)
	if not name then return end
	if Network and Network.InvokeServer then pcall(function() Network:InvokeServer("OpenEgg",name,tonumber(amt) or 1,{}) end); return end
	local rf=Remotes.OpenEgg; if rf and rf:IsA("RemoteFunction") then rf:InvokeServer(name,tonumber(amt) or 1,{}) return end
	local re=Remotes.OpenEgg; if re and re:IsA("RemoteEvent") then re:FireServer(name,tonumber(amt) or 1,{}) end
end

local function extractPetNames(eggName)
	local out={}
	local eggData=Eggs and Eggs[eggName]
	if type(eggData)~="table" then return out end
	if type(eggData.Pets)=="table" then
		for petName in pairs(eggData.Pets) do
			if type(petName)=="string" then out[#out+1]=petName end
		end
	end
	table.sort(out)
	return out
end

local function getPetChance(eggName,petName)
	local eggData=Eggs and Eggs[eggName]
	if type(eggData)~="table" or type(eggData.Pets)~="table" then return nil end
	local total=0
	for _,v in pairs(eggData.Pets) do total=total+v end
	local w=eggData.Pets[petName]
	if not w or total<=0 then return nil end
	local pct=(w/total)*100
	if pct>9 then return string.format("%.0f%%",math.round(pct)) end
	if pct>1 then return string.format("%.1f%%",math.round(pct*10)/10) end
	if pct>0.1 then return string.format("%.2f%%",math.round(pct*100)/100) end
	if pct>0.01 then return string.format("%.3f%%",math.round(pct*1000)/1000) end
	return "???"
end

local function sendAutoDeleteConfig(config)
	if not AutoDeleteRemote then return end
	pcall(function() AutoDeleteRemote:FireServer(config) end)
end

-- Root
local gui=Instance.new("ScreenGui"); gui.Name="TapSim_CustomUI_v3"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Parent=parent
G.__TapSimUI=gui
local shadow=Instance.new("ImageLabel"); shadow.Name="Shadow"; shadow.AnchorPoint=Vector2.new(0.5,0.5); shadow.Size=UDim2.fromOffset(px(L.W+50),px(L.H+50)); shadow.Position=UDim2.new(0.5,0,0.5,0); shadow.BackgroundTransparency=1; shadow.Image="rbxassetid://1316045217"; shadow.ImageColor3=Color3.fromRGB(0,0,0); shadow.ImageTransparency=0.4; shadow.ScaleType=Enum.ScaleType.Slice; shadow.SliceCenter=Rect.new(10,10,118,118); shadow.Parent=gui
local main=Instance.new("Frame"); main.Name="Main"; main.AnchorPoint=Vector2.new(0.5,0.5); main.Size=UDim2.fromOffset(px(L.W),px(L.H)); main.Position=UDim2.new(0.5,0,0.5,0); main.BackgroundColor3=T.BG; main.BorderSizePixel=0; main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,px(L.Radius))
local stroke=Instance.new("UIStroke",main); stroke.Color=Color3.fromRGB(30,30,36); stroke.Transparency=0.4
local grad=Instance.new("UIGradient",main); grad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.BG),ColorSequenceKeypoint.new(1,T.P3)}); grad.Rotation=90

local top=Instance.new("Frame"); top.Name="TopBar"; top.Size=UDim2.new(1,0,0,px(L.Top)); top.BackgroundColor3=T.P; top.BorderSizePixel=0; top.Parent=main
Instance.new("UICorner",top).CornerRadius=UDim.new(0,px(L.Radius))
local topG=Instance.new("UIGradient",top); topG.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.P2),ColorSequenceKeypoint.new(1,T.P3)}); topG.Rotation=90
local title=Instance.new("TextLabel"); title.Size=UDim2.new(1,-px(60),1,0); title.Position=UDim2.fromOffset(px(12),0); title.BackgroundTransparency=1; title.Font=Enum.Font.GothamSemibold; title.TextSize=px(15); title.TextColor3=T.TX; title.TextXAlignment=Enum.TextXAlignment.Left; title.Text="TapSim UI v3"; title.Parent=top
local version=Instance.new("TextLabel"); version.Size=UDim2.fromOffset(px(48),px(18)); version.Position=UDim2.new(1,-px(96),0.5,-px(9)); version.BackgroundTransparency=1; version.Font=Enum.Font.Gotham; version.TextSize=px(11); version.TextColor3=T.TD; version.Text="v3"; version.Parent=top
local min=Instance.new("TextButton"); min.Size=UDim2.fromOffset(px(28),px(24)); min.Position=UDim2.new(1,-px(36),0.5,-px(12)); min.BackgroundColor3=T.P2; min.BorderSizePixel=0; min.Font=Enum.Font.GothamBold; min.TextSize=px(14); min.TextColor3=T.TX; min.Text="–"; min.AutoButtonColor=false; min.Parent=top
Instance.new("UICorner",min).CornerRadius=UDim.new(0,px(8)); pressable(min)

local side=Instance.new("Frame"); side.Size=UDim2.new(0,px(L.Side),1,-px(L.Top)); side.Position=UDim2.fromOffset(0,px(L.Top)); side.BackgroundColor3=T.P; side.BorderSizePixel=0; side.Parent=main
local sideG=Instance.new("UIGradient",side); sideG.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.P2),ColorSequenceKeypoint.new(1,T.P3)}); sideG.Rotation=90
local sidePad=Instance.new("UIPadding",side); sidePad.PaddingTop=UDim.new(0,px(12)); sidePad.PaddingLeft=UDim.new(0,px(8)); sidePad.PaddingRight=UDim.new(0,px(8))
local sideList=Instance.new("UIListLayout",side); sideList.Padding=UDim.new(0,px(8)); sideList.SortOrder=Enum.SortOrder.LayoutOrder

local content=Instance.new("Frame"); content.Size=UDim2.new(1,-px(L.Side),1,-px(L.Top)); content.Position=UDim2.fromOffset(px(L.Side),px(L.Top)); content.BackgroundColor3=T.BG; content.BorderSizePixel=0; content.Parent=main
local contentG=Instance.new("UIGradient",content); contentG.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.BG),ColorSequenceKeypoint.new(1,T.P3)}); contentG.Rotation=90

local function button(parent,text)
	local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,px(L.Control)); b.BackgroundColor3=T.P2; b.BorderSizePixel=0; b.Font=Enum.Font.Gotham; b.TextSize=px(13); b.TextColor3=T.TX; b.Text=text; b.AutoButtonColor=false; b.Parent=parent
	Instance.new("UICorner",b).CornerRadius=UDim.new(0,px(8))
	local s=Instance.new("UIStroke",b); s.Color=Color3.fromRGB(30,30,36); s.Transparency=0.5
	b.MouseEnter:Connect(function() tw(b,0.12,{BackgroundColor3=T.AD}); tw(s,0.12,{Transparency=0.25,Color=T.A}) end)
	b.MouseLeave:Connect(function() tw(b,0.12,{BackgroundColor3=T.P2}); tw(s,0.12,{Transparency=0.5,Color=Color3.fromRGB(30,30,36)}) end)
	pressable(b)
	return b
end
local function textRow(parent,text)
	local r=Instance.new("Frame"); r.Size=UDim2.new(1,0,0,px(L.Control)); r.BackgroundTransparency=1; r.Parent=parent
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Font=Enum.Font.GothamSemibold; l.TextSize=px(12); l.TextColor3=T.TD; l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=text; l.Parent=r
	return r
end
local function section(parent,titleText)
	local s=Instance.new("Frame"); s.Size=UDim2.new(1,0,0,0); s.AutomaticSize=Enum.AutomaticSize.Y; s.BackgroundColor3=T.P; s.BorderSizePixel=0; s.Parent=parent
	Instance.new("UICorner",s).CornerRadius=UDim.new(0,px(10))
	local t=Instance.new("TextLabel"); t.Size=UDim2.new(1,-px(16),0,px(20)); t.Position=UDim2.fromOffset(px(8),px(4)); t.BackgroundTransparency=1; t.Font=Enum.Font.GothamSemibold; t.TextSize=px(12); t.TextColor3=T.TD; t.TextXAlignment=Enum.TextXAlignment.Left; t.Text=titleText; t.Parent=s
	local list=Instance.new("UIListLayout",s); list.Padding=UDim.new(0,px(6)); list.SortOrder=Enum.SortOrder.LayoutOrder
	local pad=Instance.new("UIPadding",s); pad.PaddingTop=UDim.new(0,px(24)); pad.PaddingBottom=UDim.new(0,px(10)); pad.PaddingLeft=UDim.new(0,px(8)); pad.PaddingRight=UDim.new(0,px(8))
	return s
end
local function toggle(parent,label,cb)
	local h=Instance.new("Frame"); h.Size=UDim2.new(1,0,0,px(L.Control)); h.BackgroundTransparency=1; h.Parent=parent
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-px(60),1,0); l.BackgroundTransparency=1; l.Font=Enum.Font.Gotham; l.TextSize=px(13); l.TextColor3=T.TX; l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=label; l.Parent=h
	local tg=Instance.new("TextButton"); tg.Size=UDim2.fromOffset(px(48),px(22)); tg.Position=UDim2.new(1,-px(48),0.5,-px(11)); tg.BackgroundColor3=T.P2; tg.BorderSizePixel=0; tg.Text=""; tg.AutoButtonColor=false; tg.Parent=h
	local k=Instance.new("Frame"); k.Size=UDim2.fromOffset(px(18),px(18)); k.Position=UDim2.fromOffset(px(2),px(2)); k.BackgroundColor3=Color3.fromRGB(240,240,240); k.BorderSizePixel=0; k.Parent=tg
	Instance.new("UICorner",tg).CornerRadius=UDim.new(1,0); Instance.new("UICorner",k).CornerRadius=UDim.new(1,0)
	local v=false
	local function set(val)
		v=val
		tw(tg,0.12,{BackgroundColor3=v and T.AD or T.P2})
		tw(k,0.12,{Position=v and UDim2.fromOffset(px(28),px(2)) or UDim2.fromOffset(px(2),px(2))})
		if cb then cb(v) end
	end
	tg.MouseButton1Click:Connect(function() set(not v) end)
	tg.MouseEnter:Connect(function() tw(tg,0.12,{BackgroundColor3=v and T.AD or T.A}) end)
	tg.MouseLeave:Connect(function() tw(tg,0.12,{BackgroundColor3=v and T.AD or T.P2}) end)
	pressable(tg)
	set(false); return h
end
local function dropdown(parent,label,opts,cb)
	local wrap=Instance.new("Frame"); wrap.Size=UDim2.new(1,0,0,px(L.Control)); wrap.BackgroundTransparency=1; wrap.Parent=parent; wrap.AutomaticSize=Enum.AutomaticSize.Y
	local head=button(wrap,label..": None"); head.Position=UDim2.fromOffset(0,0); head.Size=UDim2.new(1,0,0,px(L.Control))
	local list=Instance.new("Frame"); list.BackgroundColor3=T.P; list.BorderSizePixel=0; list.Position=UDim2.fromOffset(0,px(L.Control+6)); list.Size=UDim2.new(1,0,0,0); list.Visible=false; list.Parent=wrap; list.ClipsDescendants=true
	Instance.new("UICorner",list).CornerRadius=UDim.new(0,px(8))
	local sc=Instance.new("ScrollingFrame"); sc.BackgroundTransparency=1; sc.BorderSizePixel=0; sc.Size=UDim2.new(1,0,1,0); sc.ScrollBarThickness=3; sc.ScrollBarImageColor3=T.A; sc.AutomaticCanvasSize=Enum.AutomaticSize.Y; sc.CanvasSize=UDim2.new(0,0,0,0); sc.Parent=list
	local ll=Instance.new("UIListLayout",sc); ll.Padding=UDim.new(0,px(4)); ll.SortOrder=Enum.SortOrder.LayoutOrder
	local pad=Instance.new("UIPadding",sc); pad.PaddingTop=UDim.new(0,px(6)); pad.PaddingBottom=UDim.new(0,px(6)); pad.PaddingLeft=UDim.new(0,px(6)); pad.PaddingRight=UDim.new(0,px(6))
	local open=false
	local function close()
		open=false
		list.Visible=false
		list.Size=UDim2.new(1,0,0,0)
		wrap.Size=UDim2.new(1,0,0,px(L.Control))
	end
	local function rebuild()
		for _,c in ipairs(sc:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
		for _,v in ipairs(opts) do
			local b=button(sc,tostring(v)); b.Size=UDim2.new(1,0,0,px(26)); b.Position=UDim2.fromOffset(0,0)
			b.MouseButton1Click:Connect(function()
				head.Text=label..": "..tostring(v); if cb then cb(v) end
				close()
			end)
		end
	end
	head.MouseButton1Click:Connect(function()
		open=not open
		if open then
			list.Visible=true
			local h=math.min(px(L.DropMax), (#opts*px(30))+px(12))
			tw(list,0.12,{Size=UDim2.new(1,0,0,h)})
			tw(wrap,0.12,{Size=UDim2.new(1,0,0,px(L.Control)+h+px(4))})
		else
			tw(list,0.12,{Size=UDim2.new(1,0,0,0)})
			tw(wrap,0.12,{Size=UDim2.new(1,0,0,px(L.Control))})
			task.delay(0.12,function() if not open then list.Visible=false end end)
		end
	end)
	rebuild()
	local function setSelected(v)
		head.Text=label..": "..tostring(v or "None")
		if cb then cb(v) end
	end
	return wrap,function(newOpts) opts=newOpts or {}; rebuild() end,setSelected,close
end

local function checklist(parent,items,onToggle,opts)
	opts=opts or {}
	local wrap=Instance.new("Frame"); wrap.Size=UDim2.new(1,0,0,0); wrap.AutomaticSize=Enum.AutomaticSize.Y; wrap.BackgroundTransparency=1; wrap.Parent=parent
	if opts.grid then
		local cols=math.max(1,opts.columns or 4)
		local pad=0.02
		local cellW=(1-((cols-1)*pad))/cols
		local grid=Instance.new("UIGridLayout",wrap)
		grid.SortOrder=Enum.SortOrder.LayoutOrder
		grid.CellPadding=UDim2.new(pad,0,0,px(8))
		grid.CellSize=UDim2.new(cellW,0,0,px(L.Control+8))
	else
		local list=Instance.new("UIListLayout",wrap); list.Padding=UDim.new(0,px(6)); list.SortOrder=Enum.SortOrder.LayoutOrder
	end
	local empty=Instance.new("TextLabel"); empty.Size=UDim2.new(1,0,0,px(L.Control)); empty.BackgroundTransparency=1; empty.Font=Enum.Font.Gotham; empty.TextSize=px(12); empty.TextColor3=T.TD; empty.TextXAlignment=Enum.TextXAlignment.Left; empty.Text="Select an egg to load pets"; empty.Parent=wrap
	local function rebuild(newItems,selectedSet)
		items=newItems or items or {}
		for _,c in ipairs(wrap:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		empty.Visible=(#items==0)
		if #items==0 then empty.Text="No pets found for this egg" end
		for _,name in ipairs(items) do
			local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,px(L.Control)); row.BackgroundTransparency=1; row.Parent=wrap
			local label=Instance.new("TextLabel"); label.Size=UDim2.new(1,-px(40),1,0); label.BackgroundTransparency=1; label.Font=Enum.Font.Gotham; label.TextSize=px(12); label.TextColor3=T.TX; label.TextXAlignment=Enum.TextXAlignment.Left; label.Text=(opts.getLabel and opts.getLabel(name) or name); label.TextWrapped=true; label.Parent=row
			local btn=Instance.new("TextButton"); btn.Size=UDim2.fromOffset(px(32),px(20)); btn.Position=UDim2.new(1,-px(32),0.5,-px(10)); btn.BackgroundColor3=T.P2; btn.BorderSizePixel=0; btn.Text=""; btn.AutoButtonColor=false; btn.Parent=row
			local dot=Instance.new("Frame"); dot.Size=UDim2.fromOffset(px(12),px(12)); dot.Position=UDim2.fromOffset(px(12),px(4)); dot.BackgroundColor3=Color3.fromRGB(240,240,240); dot.BorderSizePixel=0; dot.Parent=btn; dot.Visible=false
			Instance.new("UICorner",btn).CornerRadius=UDim.new(1,0); Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
			local on=false
			local function set(v,silent)
				on=v
				dot.Visible=on
				tw(btn,0.12,{BackgroundColor3=on and T.AD or T.P2})
				if onToggle and not silent then onToggle(name,on) end
			end
			btn.MouseButton1Click:Connect(function() set(not on) end)
			btn.MouseEnter:Connect(function() tw(btn,0.12,{BackgroundColor3=on and T.AD or T.A}) end)
			btn.MouseLeave:Connect(function() tw(btn,0.12,{BackgroundColor3=on and T.AD or T.P2}) end)
			pressable(btn)
			if selectedSet and selectedSet[name] then set(true,true) end
		end
	end
	rebuild(items)
	return wrap,rebuild
end

local function tabButton(name)
	local b=button(side,"  "..name); b.TextXAlignment=Enum.TextXAlignment.Left
	return b
end
local function tabPage(name)
	local p=Instance.new("ScrollingFrame"); p.Name=name.."_Page"; p.Size=UDim2.new(1,0,1,0); p.BackgroundTransparency=1; p.Visible=false; p.Parent=content
	p.BorderSizePixel=0; p.ScrollBarThickness=4; p.ScrollBarImageColor3=T.A; p.AutomaticCanvasSize=Enum.AutomaticSize.Y; p.CanvasSize=UDim2.new(0,0,0,0)
	local ll=Instance.new("UIListLayout",p); ll.Padding=UDim.new(0,px(10)); ll.SortOrder=Enum.SortOrder.LayoutOrder
	local pad=Instance.new("UIPadding",p); pad.PaddingTop=UDim.new(0,px(12)); pad.PaddingLeft=UDim.new(0,px(12)); pad.PaddingRight=UDim.new(0,px(12)); pad.PaddingBottom=UDim.new(0,px(12))
	return p
end

local tabs={}
local function setTab(name)
	for n,d in pairs(tabs) do
		local on=n==name
		d.page.Visible=on
		tw(d.button,0.12,{BackgroundColor3=on and T.AD or T.P2})
		if on then
			d.page.Position=UDim2.fromOffset(px(12),0)
			d.page.CanvasPosition=Vector2.new(0,0)
			tw(d.page,0.18,{Position=UDim2.fromOffset(0,0)})
		end
	end
end

local mainBtn=tabButton("Main"); local autoBtn=tabButton("Auto"); local miscBtn=tabButton("Misc")
local mainPage=tabPage("Main"); local autoPage=tabPage("Auto"); local miscPage=tabPage("Misc")
tabs.Main={button=mainBtn,page=mainPage}; tabs.Auto={button=autoBtn,page=autoPage}; tabs.Misc={button=miscBtn,page=miscPage}
mainBtn.MouseButton1Click:Connect(function() setTab("Main") end)
autoBtn.MouseButton1Click:Connect(function() setTab("Auto") end)
miscBtn.MouseButton1Click:Connect(function() setTab("Misc") end)

local s1=section(mainPage,"Overview"); button(s1,"Status: Ready"); button(s1,"Version: 2.0")
local s2b=section(autoPage,"Auto Delete (Egg Pets)"); s2b.LayoutOrder=3; s2b.Visible=false
local autoDeleteHint=textRow(s2b,"Saves per-egg pet list")
local selectedPetsByEgg={}
local currentEggForDelete=nil
local function listFromSet(set)
	local out={}
	for name in pairs(set or {}) do out[#out+1]=name end
	table.sort(out)
	return out
end
local function sendAutoDeleteAll()
	local payload={}
	for eggName,set in pairs(selectedPetsByEgg) do
		payload[eggName]=listFromSet(set)
	end
	sendAutoDeleteConfig(payload)
end
local function onPetToggle(name,on)
	if not State.SelEgg then return end
	selectedPetsByEgg[State.SelEgg]=selectedPetsByEgg[State.SelEgg] or {}
	if on then
		selectedPetsByEgg[State.SelEgg][name]=true
	else
		selectedPetsByEgg[State.SelEgg][name]=nil
	end
	sendAutoDeleteAll()
end
local _,updatePetList=checklist(s2b,{},onPetToggle,{
	grid=true,
	columns=4,
	getLabel=function(name)
		local chance=currentEggForDelete and getPetChance(currentEggForDelete,name)
		if chance then return name.." ("..chance..")" end
		return name
	end
})

local function refreshPetList(eggName)
	currentEggForDelete=eggName
	local pets=extractPetNames(eggName)
	if #pets==0 then
		updatePetList({}) -- will show empty message
	else
		updatePetList(pets,selectedPetsByEgg[eggName] or {})
	end
end

local s2=section(autoPage,"Automation"); s2.LayoutOrder=1
local autoDeleteOn=false
local _,_,setEggSelect=dropdown(s2,"Egg",eggList(),function(v)
	State.SelEgg=v
	s2b.Visible=(autoDeleteOn and State.SelEgg~=nil)
	autoPage.CanvasPosition=Vector2.new(0,0)
	refreshPetList(v)
end)
local _,eggAmtUpdate,setEggAmtSelect=dropdown(s2,"Egg Amount",getHatchOptions(),function(v) State.EggAmt=v end)
toggle(s2,"Auto Hatch",function(v) State.AutoHatch=v end)
local autoCrystal=false
toggle(s2,"Auto Enchant Crystals",function(v)
	autoCrystal=v
	if v then
		selectedPetsByEgg["Snowman"]={}
		for _,name in ipairs(extractPetNames("Snowman")) do
			selectedPetsByEgg["Snowman"][name]=true
		end
		sendAutoDeleteAll()
	else
		selectedPetsByEgg["Snowman"]=nil
		sendAutoDeleteAll()
	end
end)
local autoDeleteToggle=toggle(s2,"Auto Delete ▼",function(v)
	autoDeleteOn=v
	if v and State.SelEgg then
		s2b.Visible=true
	else
		s2b.Visible=false
	end
end)
toggle(s2,"Auto Tap",function(v) State.AutoTap=v end)

local s3=section(miscPage,"Misc")
toggle(s3,"Infinite Jump",function(v) State.InfJump=v end)

setTab("Main")

-- Loading overlay
local loading=Instance.new("Frame"); loading.Size=UDim2.new(1,0,1,0); loading.BackgroundColor3=T.P3; loading.BackgroundTransparency=0.2; loading.BorderSizePixel=0; loading.Parent=main
Instance.new("UICorner",loading).CornerRadius=UDim.new(0,px(L.Radius))
local loadText=Instance.new("TextLabel"); loadText.Size=UDim2.new(1,0,1,0); loadText.BackgroundTransparency=1; loadText.Font=Enum.Font.GothamSemibold; loadText.TextSize=px(16); loadText.TextColor3=T.TX; loadText.Text="Loading..."; loadText.Parent=loading
task.delay(0.3,function()
	tw(loading,0.25,{BackgroundTransparency=1}); tw(loadText,0.25,{TextTransparency=1})
	task.delay(0.3,function() loading:Destroy() end)
end)

-- Drag
do
	local dragging,dragStart,startPos,dragInput=false
	local function update(input)
		local d=input.Position-dragStart
		main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
	end
	top.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
			dragging=true; dragStart=input.Position; startPos=main.Position; dragInput=input
		end
	end)
	top.InputChanged:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
	end)
	UserInputService.InputChanged:Connect(function(input) if dragging and input==dragInput then update(input) end end)
	UserInputService.InputEnded:Connect(function(input) if input==dragInput then dragging=false end end)
end

-- Parallax shadow
RunService.RenderStepped:Connect(function()
	if not main.Visible then return end
	local cam=workspace.CurrentCamera; if not cam then return end
	local vp=cam.ViewportSize; if vp.X==0 or vp.Y==0 then return end
	local m=UserInputService:GetMouseLocation()
	local dx=(m.X-(vp.X/2))/(vp.X/2)*(6*Config.Anim.Intensity)
	local dy=(m.Y-(vp.Y/2))/(vp.Y/2)*(6*Config.Anim.Intensity)
	local base=main.Position
	shadow.Position=UDim2.new(base.X.Scale,base.X.Offset+dx,base.Y.Scale,base.Y.Offset+dy)
end)

-- Minimize + Right Ctrl
local minimized,visible=false,true
local full=main.Size
local function setMin(m)
	minimized=m
	if minimized then
		side.Visible=false; content.Visible=false; min.Text="+"
		tw(main,0.18,{Size=UDim2.fromOffset(full.X.Offset,px(L.Top))})
		tw(shadow,0.18,{Size=UDim2.fromOffset(full.X.Offset+px(50),px(L.Top)+px(50))})
	else
		side.Visible=true; content.Visible=true; min.Text="–"
		tw(main,0.18,{Size=full}); tw(shadow,0.18,{Size=UDim2.fromOffset(full.X.Offset+px(50),full.Y.Offset+px(50))})
	end
end
local function setVisible(v)
	visible=v
	if visible then
		main.Visible=true; shadow.Visible=true
		tw(main,0.18,{BackgroundTransparency=0}); tw(shadow,0.18,{ImageTransparency=0.4})
	else
		tw(main,0.12,{BackgroundTransparency=1}); tw(shadow,0.12,{ImageTransparency=1})
		task.delay(0.12,function() main.Visible=false; shadow.Visible=false end)
	end
end
min.MouseButton1Click:Connect(function() setMin(not minimized) end)
UserInputService.InputBegan:Connect(function(input,processed) if processed then return end if input.KeyCode==Enum.KeyCode.RightControl then setVisible(not visible) end end)

-- Gamepass hatch options update
task.spawn(function()
	local opts=getHatchOptions()
	State.EggAmt=opts[1]
	if eggAmtUpdate then eggAmtUpdate(opts) end
end)

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
	if not State.InfJump then return end
	local c=player.Character; local h=c and c:FindFirstChildOfClass("Humanoid")
	if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- Auto Hatch (max)
task.spawn(function()
	while true do
		RunService.Heartbeat:Wait()
		if State.AutoHatch then for _=1,5 do openEgg(State.SelEgg,State.EggAmt) end end
	end
end)

-- Auto Enchant Crystals (Snowman egg 8x)
task.spawn(function()
	while true do
		RunService.Heartbeat:Wait()
		if autoCrystal then
			for _=1,5 do openEgg("Snowman",8) end
		end
	end
end)

-- Auto Tap (fast)
task.spawn(function()
	while task.wait(0.05) do
		if State.AutoTap then for _=1,5 do tap() end end
	end
end)
-- TapSim Custom UI (compact)
local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local UserInputService=game:GetService("UserInputService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local MarketplaceService=game:GetService("MarketplaceService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer or Players.PlayerAdded:Wait()
local function guiParent()
	local pg=player:FindFirstChild("PlayerGui"); if pg then return pg end
	local ok,hui=pcall(function() return gethui() end); if ok and hui then return hui end
	return game:GetService("CoreGui")
end
local parent=guiParent()
local old=parent:FindFirstChild("TapSim_CustomUI"); if old then old:Destroy() end

local Config={
	Density=1,
	Anim={Speed=1,Intensity=1},
	Theme={
		BG=Color3.fromRGB(10,10,12),
		P=Color3.fromRGB(16,16,19),
		PL=Color3.fromRGB(22,22,26),
		PD=Color3.fromRGB(12,12,14),
		TX=Color3.fromRGB(210,210,210),
		TD=Color3.fromRGB(140,140,140),
	},
	Accent=Color3.fromRGB(45,50,60),
	AccentDark=Color3.fromRGB(32,36,44),
	Layout={MainW=520,MainH=320,TopH=40,TabW=140,Pad=12,ControlH=30,ToggleW=44,ToggleH=20,Radius=12,DropMax=180},
}
local L=Config.Layout
local function px(n) return math.floor(n*Config.Density+0.5) end
local function tw(o,d,props,style,dir)
	local t=TweenService:Create(o,TweenInfo.new((d or 0.12)/Config.Anim.Speed,style or Enum.EasingStyle.Quad,dir or Enum.EasingDirection.Out),props)
	t:Play(); return t
end
local T={BG=Config.Theme.BG,P=Config.Theme.P,PL=Config.Theme.PL,PD=Config.Theme.PD,TX=Config.Theme.TX,TD=Config.Theme.TD,A=Config.Accent,AD=Config.AccentDark}

local function pressable(b)
	local sc=Instance.new("UIScale",b); sc.Scale=1
	local d=0.04*Config.Anim.Intensity
	b.MouseButton1Down:Connect(function() tw(sc,0.08,{Scale=1-d}) end)
	b.MouseButton1Up:Connect(function() tw(sc,0.1,{Scale=1}) end)
	b.MouseLeave:Connect(function() tw(sc,0.1,{Scale=1}) end)
end
local State={InfJump=false,AutoHatch=false,AutoTap=false,SelEgg=nil,EggAmt=1}
local HatchPassId=1568018875
local HatchOptions={1,3,8}
local function getHatchOptions()
	local ok,owned=pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId,HatchPassId) end)
	if ok and owned then return {1,3,8} end
	return {1,3}
end

local function safeRequire(m)
	if not m then return nil end
	local ok,res=pcall(require,m); if ok then return res end
	warn(res); return nil
end
local Eggs=safeRequire(ReplicatedStorage:FindFirstChild("Game") and ReplicatedStorage.Game:FindFirstChild("Eggs"))
local function eggList()
	local t={}
	if type(Eggs)=="table" then for k in pairs(Eggs) do t[#t+1]=k end end
	table.sort(t); return t
end
local Remotes={}
for _,r in ipairs(ReplicatedStorage:GetDescendants()) do
	if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then Remotes[r.Name]=r end
end
local Network=safeRequire(ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Network"))
local function tap()
	if Network and Network.FireServer then
		pcall(function() Network:FireServer("Tap",true,nil,true) end); return
	end
	local re=Remotes.Tap
	if re and re:IsA("RemoteEvent") then re:FireServer(true,nil,true) end
end
local function openEgg(name,amt)
	if not name then return end
	if Network and Network.InvokeServer then
		pcall(function() Network:InvokeServer("OpenEgg",name,tonumber(amt) or 1,{}) end); return
	end
	local rf=Remotes.OpenEgg
	if rf and rf:IsA("RemoteFunction") then rf:InvokeServer(name,tonumber(amt) or 1,{}) return end
	local re=Remotes.OpenEgg
	if re and re:IsA("RemoteEvent") then re:FireServer(name,tonumber(amt) or 1,{}) end
end

local gui=Instance.new("ScreenGui"); gui.Name="TapSim_CustomUI"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Parent=parent
local shadow=Instance.new("ImageLabel"); shadow.Name="Shadow"; shadow.AnchorPoint=Vector2.new(0.5,0.5); shadow.Size=UDim2.fromOffset(px(L.MainW+40),px(L.MainH+40)); shadow.Position=UDim2.new(0.5,0,0.5,0); shadow.BackgroundTransparency=1; shadow.Image="rbxassetid://1316045217"; shadow.ImageColor3=Color3.fromRGB(0,0,0); shadow.ImageTransparency=0.35; shadow.ScaleType=Enum.ScaleType.Slice; shadow.SliceCenter=Rect.new(10,10,118,118); shadow.Parent=gui
local main=Instance.new("Frame"); main.Name="Main"; main.AnchorPoint=Vector2.new(0.5,0.5); main.Size=UDim2.fromOffset(px(L.MainW),px(L.MainH)); main.Position=UDim2.new(0.5,0,0.5,0); main.BackgroundColor3=T.BG; main.BorderSizePixel=0; main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,px(L.Radius))
local stroke=Instance.new("UIStroke",main); stroke.Color=Color3.fromRGB(40,44,52); stroke.Thickness=1; stroke.Transparency=0.2
Instance.new("UIGradient",main).Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.BG),ColorSequenceKeypoint.new(1,T.PD)}); main.UIGradient.Rotation=90
local scale=Instance.new("UIScale",main); scale.Scale=0.92

local top=Instance.new("Frame"); top.Name="TopBar"; top.Size=UDim2.new(1,0,0,px(L.TopH)); top.BackgroundColor3=T.P; top.BorderSizePixel=0; top.Parent=main
Instance.new("UICorner",top).CornerRadius=UDim.new(0,px(L.Radius))
local tg=Instance.new("UIGradient",top); tg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.P),ColorSequenceKeypoint.new(1,T.PD)}); tg.Rotation=90
local title=Instance.new("TextLabel"); title.Name="Title"; title.Size=UDim2.new(1,-px(56),1,0); title.Position=UDim2.fromOffset(px(8),0); title.BackgroundTransparency=1; title.Font=Enum.Font.GothamSemibold; title.TextSize=px(16); title.TextColor3=T.TX; title.TextXAlignment=Enum.TextXAlignment.Left; title.Text="TapSim UI"; title.Parent=top
local min=Instance.new("TextButton"); min.Name="Minimize"; min.Size=UDim2.fromOffset(px(28),px(24)); min.Position=UDim2.new(1,-px(34),0.5,-px(12)); min.BackgroundColor3=T.PL; min.BorderSizePixel=0; min.Font=Enum.Font.GothamBold; min.TextSize=px(14); min.TextColor3=T.TX; min.Text="–"; min.AutoButtonColor=false; min.Parent=top
Instance.new("UICorner",min).CornerRadius=UDim.new(0,px(6))
pressable(min)

local tabBar=Instance.new("Frame"); tabBar.Name="TabBar"; tabBar.Size=UDim2.new(0,px(L.TabW),1,-px(L.TopH)); tabBar.Position=UDim2.fromOffset(0,px(L.TopH)); tabBar.BackgroundColor3=T.P; tabBar.BorderSizePixel=0; tabBar.Parent=main
local tabLayout=Instance.new("UIListLayout",tabBar); tabLayout.Padding=UDim.new(0,px(8)); tabLayout.SortOrder=Enum.SortOrder.LayoutOrder
Instance.new("UIPadding",tabBar).PaddingTop=UDim.new(0,px(10))
local content=Instance.new("Frame"); content.Name="Content"; content.Size=UDim2.new(1,-px(L.TabW),1,-px(L.TopH)); content.Position=UDim2.fromOffset(px(L.TabW),px(L.TopH)); content.BackgroundColor3=T.BG; content.BorderSizePixel=0; content.Parent=main
local cg=Instance.new("UIGradient",content); cg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.BG),ColorSequenceKeypoint.new(1,T.PD)}); cg.Rotation=90

-- Modal
local modalDim=Instance.new("Frame"); modalDim.Name="ModalDim"; modalDim.Size=UDim2.new(1,0,1,0); modalDim.BackgroundColor3=Color3.fromRGB(0,0,0); modalDim.BackgroundTransparency=1; modalDim.BorderSizePixel=0; modalDim.Visible=false; modalDim.Parent=main
local modalCard=Instance.new("Frame"); modalCard.Name="ModalCard"; modalCard.Size=UDim2.fromOffset(px(320),px(170)); modalCard.AnchorPoint=Vector2.new(0.5,0.5); modalCard.Position=UDim2.new(0.5,0,0.5,0); modalCard.BackgroundColor3=T.P; modalCard.BorderSizePixel=0; modalCard.Parent=modalDim
Instance.new("UICorner",modalCard).CornerRadius=UDim.new(0,px(12))
local modalStroke=Instance.new("UIStroke",modalCard); modalStroke.Color=Color3.fromRGB(30,30,34); modalStroke.Transparency=0.5
local modalTitle=Instance.new("TextLabel"); modalTitle.Size=UDim2.new(1,-px(16),0,px(24)); modalTitle.Position=UDim2.fromOffset(px(8),px(8)); modalTitle.BackgroundTransparency=1; modalTitle.Font=Enum.Font.GothamSemibold; modalTitle.TextSize=px(14); modalTitle.TextColor3=T.TX; modalTitle.TextXAlignment=Enum.TextXAlignment.Left; modalTitle.Text="Modal"; modalTitle.Parent=modalCard
local modalBody=Instance.new("TextLabel"); modalBody.Size=UDim2.new(1,-px(16),1,-px(60)); modalBody.Position=UDim2.fromOffset(px(8),px(36)); modalBody.BackgroundTransparency=1; modalBody.Font=Enum.Font.Gotham; modalBody.TextSize=px(13); modalBody.TextColor3=T.TD; modalBody.TextWrapped=true; modalBody.TextXAlignment=Enum.TextXAlignment.Left; modalBody.TextYAlignment=Enum.TextYAlignment.Top; modalBody.Text=""; modalBody.Parent=modalCard
local modalClose=Instance.new("TextButton"); modalClose.Size=UDim2.fromOffset(px(80),px(26)); modalClose.Position=UDim2.new(1,-px(88),1,-px(34)); modalClose.BackgroundColor3=T.PL; modalClose.BorderSizePixel=0; modalClose.Font=Enum.Font.GothamSemibold; modalClose.TextSize=px(12); modalClose.TextColor3=T.TX; modalClose.Text="Close"; modalClose.AutoButtonColor=false; modalClose.Parent=modalCard
Instance.new("UICorner",modalClose).CornerRadius=UDim.new(0,px(8))
pressable(modalClose)
modalClose.MouseEnter:Connect(function() tw(modalClose,0.12,{BackgroundColor3=T.AD}) end)
modalClose.MouseLeave:Connect(function() tw(modalClose,0.12,{BackgroundColor3=T.PL}) end)

local function showModal(titleText,bodyText)
	modalTitle.Text=titleText or "Modal"
	modalBody.Text=bodyText or ""
	modalDim.Visible=true
	modalDim.BackgroundTransparency=1
	modalCard.Position=UDim2.new(0.5,0,0.5,px(8))
	tw(modalDim,0.18,{BackgroundTransparency=0.4})
	tw(modalCard,0.2,{Position=UDim2.new(0.5,0,0.5,0)})
end
modalClose.MouseButton1Click:Connect(function()
	tw(modalDim,0.12,{BackgroundTransparency=1})
	tw(modalCard,0.12,{Position=UDim2.new(0.5,0,0.5,px(6))})
	task.delay(0.15,function() modalDim.Visible=false end)
end)

local function btn(p,t)
	local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-px(L.Pad*2),0,px(L.ControlH)); b.Position=UDim2.fromOffset(px(L.Pad),0); b.BackgroundColor3=T.PL; b.BorderSizePixel=0; b.Font=Enum.Font.Gotham; b.TextSize=px(13); b.TextColor3=T.TX; b.Text=t; b.AutoButtonColor=false; b.Parent=p
	Instance.new("UICorner",b).CornerRadius=UDim.new(0,px(8))
	local s=Instance.new("UIStroke",b); s.Color=Color3.fromRGB(30,30,34); s.Transparency=0.5
	b.MouseEnter:Connect(function() tw(b,0.12,{BackgroundColor3=T.AD}); tw(s,0.12,{Color=T.A,Transparency=0.2}) end)
	b.MouseLeave:Connect(function() tw(b,0.12,{BackgroundColor3=T.PL}); tw(s,0.12,{Color=Color3.fromRGB(30,30,34),Transparency=0.5}) end)
	pressable(b)
	return b
end
local function section(p,h)
	local s=Instance.new("Frame"); s.Size=UDim2.new(1,-px(L.Pad*2),0,0); s.AutomaticSize=Enum.AutomaticSize.Y; s.BackgroundColor3=T.P; s.BorderSizePixel=0; s.Parent=p
	Instance.new("UICorner",s).CornerRadius=UDim.new(0,px(10))
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-px(16),0,px(24)); l.Position=UDim2.fromOffset(px(8),px(6)); l.BackgroundTransparency=1; l.Font=Enum.Font.GothamSemibold; l.TextSize=px(12); l.TextColor3=T.TD; l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=h; l.Parent=s
	local ll=Instance.new("UIListLayout",s); ll.Padding=UDim.new(0,px(6)); ll.SortOrder=Enum.SortOrder.LayoutOrder
	local pad=Instance.new("UIPadding",s); pad.PaddingTop=UDim.new(0,px(30)); pad.PaddingBottom=UDim.new(0,px(10)); pad.PaddingLeft=UDim.new(0,px(8)); pad.PaddingRight=UDim.new(0,px(8))
	return s
end
local function toggle(p,t,cb)
	local h=Instance.new("Frame"); h.Size=UDim2.new(1,-px(L.Pad*2),0,px(L.ControlH+2)); h.BackgroundTransparency=1; h.Parent=p
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-px(50),1,0); l.BackgroundTransparency=1; l.Font=Enum.Font.Gotham; l.TextSize=px(13); l.TextColor3=T.TX; l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=t; l.Parent=h
	local tg=Instance.new("TextButton"); tg.Size=UDim2.fromOffset(px(L.ToggleW),px(L.ToggleH)); tg.Position=UDim2.new(1,-px(L.ToggleW),0.5,-px(L.ToggleH/2)); tg.BackgroundColor3=T.PL; tg.BorderSizePixel=0; tg.Text=""; tg.AutoButtonColor=false; tg.Parent=h
	local k=Instance.new("Frame"); k.Size=UDim2.fromOffset(px(L.ToggleH-2),px(L.ToggleH-2)); k.Position=UDim2.fromOffset(px(2),px(1)); k.BackgroundColor3=Color3.fromRGB(240,240,240); k.BorderSizePixel=0; k.Parent=tg
	Instance.new("UICorner",tg).CornerRadius=UDim.new(1,0); Instance.new("UICorner",k).CornerRadius=UDim.new(1,0)
	local v=false
	local function set(val)
		v=val
		tw(tg,0.12,{BackgroundColor3=v and T.AD or T.PL})
		tw(k,0.12,{Position=v and UDim2.fromOffset(px(L.ToggleW-L.ToggleH+2),px(1)) or UDim2.fromOffset(px(2),px(1))})
		if cb then cb(v) end
	end
	tg.MouseButton1Click:Connect(function() set(not v) end)
	tg.MouseEnter:Connect(function() tw(tg,0.12,{BackgroundColor3=v and T.AD or T.A}) end)
	tg.MouseLeave:Connect(function() tw(tg,0.12,{BackgroundColor3=v and T.AD or T.PL}) end)
	pressable(tg)
	set(false); return h
end
local function cycle(p,label,opts,cb)
	local b=btn(p,label); local i=1
	local function upd()
		local v=opts[i]; b.Text=label..": "..tostring(v or "None"); if cb then cb(v,i) end
	end
	b.MouseButton1Click:Connect(function()
		if #opts==0 then return end
		i=i%#opts+1; upd()
	end)
	upd(); return b,function(newOpts) opts=newOpts or {}; i=1; upd() end
end
local function dropdown(p,label,opts,cb)
	local wrap=Instance.new("Frame"); wrap.Size=UDim2.new(1,-px(L.Pad*2),0,px(L.ControlH)); wrap.BackgroundTransparency=1; wrap.Parent=p; wrap.AutomaticSize=Enum.AutomaticSize.Y
	local head=btn(wrap,label..": None"); head.Position=UDim2.fromOffset(0,0); head.Size=UDim2.new(1,0,0,px(L.ControlH))
	local list=Instance.new("Frame"); list.BackgroundColor3=T.P; list.BorderSizePixel=0; list.Position=UDim2.fromOffset(0,px(L.ControlH+4)); list.Size=UDim2.new(1,0,0,0); list.Visible=false; list.Parent=wrap; list.ClipsDescendants=true
	Instance.new("UICorner",list).CornerRadius=UDim.new(0,px(8))
	local sc=Instance.new("ScrollingFrame"); sc.BackgroundTransparency=1; sc.BorderSizePixel=0; sc.Size=UDim2.new(1,0,1,0); sc.ScrollBarThickness=3; sc.ScrollBarImageColor3=T.A; sc.AutomaticCanvasSize=Enum.AutomaticSize.Y; sc.CanvasSize=UDim2.new(0,0,0,0); sc.Parent=list
	local ll=Instance.new("UIListLayout",sc); ll.Padding=UDim.new(0,px(4)); ll.SortOrder=Enum.SortOrder.LayoutOrder
	local pad=Instance.new("UIPadding",sc); pad.PaddingTop=UDim.new(0,px(6)); pad.PaddingBottom=UDim.new(0,px(6)); pad.PaddingLeft=UDim.new(0,px(6)); pad.PaddingRight=UDim.new(0,px(6))
	local open=false
	local function rebuild()
		for _,c in ipairs(sc:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
		for _,v in ipairs(opts) do
			local b=btn(sc,tostring(v)); b.Size=UDim2.new(1,0,0,px(26)); b.Position=UDim2.fromOffset(0,0)
			b.MouseButton1Click:Connect(function()
				head.Text=label..": "..tostring(v); if cb then cb(v) end
				open=false; list.Visible=false; list.Size=UDim2.new(1,0,0,0); wrap.Size=UDim2.new(1,-px(L.Pad*2),0,px(L.ControlH))
			end)
		end
	end
	head.MouseButton1Click:Connect(function()
		open=not open
		if open then
			list.Visible=true
			local h=math.min(px(L.DropMax), (#opts*px(30))+px(12))
			tw(list,0.12,{Size=UDim2.new(1,0,0,h)})
			tw(wrap,0.12,{Size=UDim2.new(1,-px(L.Pad*2),0,px(L.ControlH)+h+px(4))})
		else
			tw(list,0.12,{Size=UDim2.new(1,0,0,0)})
			tw(wrap,0.12,{Size=UDim2.new(1,-px(L.Pad*2),0,px(L.ControlH))})
			task.delay(0.12,function() if not open then list.Visible=false end end)
		end
	end)
	rebuild()
	return wrap,function(newOpts) opts=newOpts or {}; rebuild() end,head
end
local function tab(name)
	local b=btn(tabBar,"  "..name); b.TextXAlignment=Enum.TextXAlignment.Left
	local p=Instance.new("ScrollingFrame"); p.Name=name.."_Page"; p.Size=UDim2.new(1,0,1,0); p.BackgroundTransparency=1; p.Visible=false; p.Parent=content
	p.BorderSizePixel=0; p.ScrollBarThickness=4; p.ScrollBarImageColor3=T.A; p.AutomaticCanvasSize=Enum.AutomaticSize.Y; p.CanvasSize=UDim2.new(0,0,0,0)
	local ll=Instance.new("UIListLayout",p); ll.Padding=UDim.new(0,px(10)); ll.SortOrder=Enum.SortOrder.LayoutOrder
	local pad=Instance.new("UIPadding",p); pad.PaddingTop=UDim.new(0,px(12)); pad.PaddingLeft=UDim.new(0,px(12)); pad.PaddingRight=UDim.new(0,px(12)); pad.PaddingBottom=UDim.new(0,px(12))
	return b,p
end

local tabs={}
local function setTab(n)
	for name,data in pairs(tabs) do
		local on=(name==n); data.page.Visible=on
		tw(data.button,0.12,{BackgroundColor3=on and T.AD or T.PL})
		if on then data.page.Position=UDim2.fromOffset(px(12),0); data.page.BackgroundTransparency=1; tw(data.page,0.18,{Position=UDim2.fromOffset(0,0),BackgroundTransparency=1}) end
	end
end

local b1,p1=tab("Main"); local b2,p2=tab("Auto"); local b3,p3=tab("Misc")
tabs.Main={button=b1,page=p1}; tabs.Auto={button=b2,page=p2}; tabs.Misc={button=b3,page=p3}
b1.MouseButton1Click:Connect(function() setTab("Main") end)
b2.MouseButton1Click:Connect(function() setTab("Auto") end)
b3.MouseButton1Click:Connect(function() setTab("Misc") end)

local s1=section(p1,"Overview"); btn(s1,"Status: Ready"); btn(s1,"Version: 1.0")
local about=btn(s1,"Open Modal"); about.MouseButton1Click:Connect(function()
	showModal("System", "Premium UI modal example with smooth transitions.")
end)
local s2=section(p2,"Automation")
local _,updateEggs,eggHead=dropdown(s2,"Egg",eggList(),function(v) State.SelEgg=v end)
local eggAmtBtn,updateEggAmt=cycle(s2,"Egg Amount",HatchOptions,function(v) State.EggAmt=v end)
toggle(s2,"Auto Hatch",function(v) State.AutoHatch=v end)
toggle(s2,"Auto Tap",function(v) State.AutoTap=v end); toggle(s2,"Auto Rebirth")
local s3=section(p3,"Misc"); toggle(s3,"Infinite Jump",function(v) State.InfJump=v end); toggle(s3,"Anti AFK")
setTab("Main")

min.MouseEnter:Connect(function() tw(min,0.12,{BackgroundColor3=T.AD}) end)
min.MouseLeave:Connect(function() tw(min,0.12,{BackgroundColor3=T.PL}) end)

-- Hatch options (gamepass)
task.spawn(function()
	local opts=getHatchOptions()
	HatchOptions=opts
	updateEggAmt(opts)
	if State.EggAmt==8 and #opts==2 then State.EggAmt=3 end
end)

-- Animations
main.BackgroundTransparency=1; top.BackgroundTransparency=1; tabBar.BackgroundTransparency=1; content.BackgroundTransparency=1; title.TextTransparency=1; stroke.Transparency=1; shadow.ImageTransparency=1
tw(scale,0.25,{Scale=1})
tw(main,0.25,{BackgroundTransparency=0})
tw(top,0.25,{BackgroundTransparency=0})
tw(tabBar,0.25,{BackgroundTransparency=0})
tw(content,0.25,{BackgroundTransparency=0})
tw(title,0.25,{TextTransparency=0})
tw(stroke,0.25,{Transparency=0.2})
tw(shadow,0.25,{ImageTransparency=0.35})

-- Loading overlay
local loading=Instance.new("Frame"); loading.Name="Loading"; loading.Size=UDim2.new(1,0,1,0); loading.BackgroundColor3=T.PD; loading.BackgroundTransparency=0.2; loading.BorderSizePixel=0; loading.Parent=main
Instance.new("UICorner",loading).CornerRadius=UDim.new(0,px(L.Radius))
local loadingText=Instance.new("TextLabel"); loadingText.Size=UDim2.new(1,0,1,0); loadingText.BackgroundTransparency=1; loadingText.Font=Enum.Font.GothamSemibold; loadingText.TextSize=px(16); loadingText.TextColor3=T.TX; loadingText.Text="Loading..."; loadingText.Parent=loading
task.delay(0.3,function()
	tw(loading,0.25,{BackgroundTransparency=1})
	tw(loadingText,0.25,{TextTransparency=1})
	task.delay(0.3,function() loading:Destroy() end)
end)

-- Drag
do
	local dragging,dragStart,startPos,dragInput=false
	local function update(input)
		local d=input.Position-dragStart
		local pos=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
		main.Position=pos
	end
	top.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
			dragging=true; dragStart=input.Position; startPos=main.Position; dragInput=input
		end
	end)
	top.InputChanged:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
			dragInput=input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input==dragInput then update(input) end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input==dragInput then dragging=false end
	end)
end

-- Parallax shadow
RunService.RenderStepped:Connect(function()
	if not main.Visible then return end
	local cam=workspace.CurrentCamera; if not cam then return end
	local vp=cam.ViewportSize; if vp.X==0 or vp.Y==0 then return end
	local m=UserInputService:GetMouseLocation()
	local dx=(m.X-(vp.X/2))/(vp.X/2)*(6*Config.Anim.Intensity)
	local dy=(m.Y-(vp.Y/2))/(vp.Y/2)*(6*Config.Anim.Intensity)
	local base=main.Position
	shadow.Position=UDim2.new(base.X.Scale,base.X.Offset+dx,base.Y.Scale,base.Y.Offset+dy)
end)

-- Minimize + Right Ctrl
local minimized,visible=false,true
local full=main.Size
local function setMin(m)
	minimized=m
	if minimized then
		tabBar.Visible=false; content.Visible=false; min.Text="+"
		tw(main,0.18,{Size=UDim2.fromOffset(full.X.Offset,px(L.TopH))})
		tw(shadow,0.18,{Size=UDim2.fromOffset(full.X.Offset+px(40),px(L.TopH)+px(40))})
	else
		tabBar.Visible=true; content.Visible=true; min.Text="–"
		tw(main,0.18,{Size=full})
		tw(shadow,0.18,{Size=UDim2.fromOffset(full.X.Offset+px(40),full.Y.Offset+px(40))})
	end
end
local function setVisible(v)
	visible=v
	if visible then
		main.Visible=true; shadow.Visible=true
		tw(scale,0.18,{Scale=1})
		tw(main,0.18,{BackgroundTransparency=0})
	else
		tw(scale,0.12,{Scale=0.95},Enum.EasingStyle.Quad,Enum.EasingDirection.In)
		tw(main,0.12,{BackgroundTransparency=1},Enum.EasingStyle.Quad,Enum.EasingDirection.In)
		task.delay(0.12,function() main.Visible=false; shadow.Visible=false end)
	end
end
min.MouseButton1Click:Connect(function() setMin(not minimized) end)
UserInputService.InputBegan:Connect(function(input,processed)
	if processed then return end
	if input.KeyCode==Enum.KeyCode.RightControl then setVisible(not visible) end
end)

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
	if not State.InfJump then return end
	local c=player.Character
	local h=c and c:FindFirstChildOfClass("Humanoid")
	if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- Auto Hatch
task.spawn(function()
	while true do
		RunService.Heartbeat:Wait()
		if State.AutoHatch then
			for _=1,5 do openEgg(State.SelEgg,State.EggAmt) end
		end
	end
end)

-- Auto Tap (fast)
task.spawn(function()
	while task.wait(0.05) do
		if State.AutoTap then
			for _=1,5 do tap() end
		end
	end
end)

