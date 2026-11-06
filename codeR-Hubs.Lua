-- =========================================================
-- Vortex Hub: Optimized & Lag-Free (With Run, Search, Anim & Settings)
-- Version 2.0.0  |  Developer: codeR
-- All NEW interface uses black / dark-gray / white only.
-- =========================================================
local parent = (gethui and gethui()) or game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local TS = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

local VERSION = "2.0.0"
local env = (getgenv and getgenv()) or _G
local startClock = os.clock()
local alive = true

-- =========================================================
-- 0. CORE: connection bags, error log, settings data, helpers
--    (no UI is created in this section)
-- =========================================================
local function newBag()
    local bag = {list = {}}
    function bag.add(conn)
        bag.list[#bag.list + 1] = conn
        return conn
    end
    function bag.clear()
        for _, c in ipairs(bag.list) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(bag.list)
    end
    return bag
end

local mainBag = newBag()   -- connections that live as long as the hub
local pageBag = newBag()   -- connections that live as long as one Settings page
local track = mainBag.add
local cleanupTasks = {}    -- extra cleanup callbacks run on destroy

local errorLog = {}
local function logError(context, err)
    local stamp = "--:--:--"
    pcall(function() stamp = os.date("%H:%M:%S") end)
    errorLog[#errorLog + 1] = "[" .. stamp .. "] " .. tostring(context) .. ": " .. tostring(err)
    if #errorLog > 20 then table.remove(errorLog, 1) end
end

local COL = {
    panel = Color3.fromRGB(18, 18, 21),
    row = Color3.fromRGB(28, 28, 32),
    rowStroke = Color3.fromRGB(58, 58, 64),
    text = Color3.fromRGB(240, 240, 240),
    sub = Color3.fromRGB(150, 150, 156),
    btn = Color3.fromRGB(44, 44, 50),
    trackOff = Color3.fromRGB(58, 58, 64),
    white = Color3.fromRGB(235, 235, 235),
    black = Color3.fromRGB(12, 12, 14),
}

-- ---------- Settings schema (every setting is used by real code) ----------
local SCHEMA = {
    AutoSave              = {type = "bool", default = true},
    RememberLastTab       = {type = "bool", default = true},
    OpenOnExecution       = {type = "bool", default = true},
    ConfirmBeforeReset    = {type = "bool", default = true},
    UIScale               = {type = "number", default = 1, min = 0.8, max = 1.3, step = 0.05},
    UITransparency        = {type = "number", default = 0, min = 0, max = 0.6, step = 0.05},
    AnimationSpeed        = {type = "number", default = 1, min = 0.5, max = 2, step = 0.1},
    BlurEffect            = {type = "bool", default = true},
    ReduceVisualEffects   = {type = "bool", default = false},
    LivePreview           = {type = "bool", default = true},
    LowPerformanceMode    = {type = "bool", default = false},
    ReduceUIAnimations    = {type = "bool", default = false},
    UIOptimization        = {type = "bool", default = true},
    FPSDisplay            = {type = "bool", default = false},
    MemoryDiagnostics     = {type = "bool", default = false},
    AutoPerformanceAdjust = {type = "bool", default = false},
    PrivacyMode           = {type = "bool", default = false},
    HideSensitive         = {type = "bool", default = true},
    HidePreview           = {type = "bool", default = false},
    ToggleKey             = {type = "key", default = "RightShift"},
    TouchSensitivity      = {type = "number", default = 1, min = 0.5, max = 2, step = 0.1},
    DragSensitivity       = {type = "number", default = 1, min = 0.5, max = 2, step = 0.1},
    MobileButtonSize      = {type = "number", default = 1, min = 0.9, max = 1.5, step = 0.05},
    TouchFeedback         = {type = "bool", default = true},
    LastTab               = {type = "tab", default = "GENERAL"},
}

local SCHEMA_ORDER = {
    "AutoSave", "RememberLastTab", "OpenOnExecution", "ConfirmBeforeReset",
    "UIScale", "UITransparency", "AnimationSpeed", "BlurEffect", "ReduceVisualEffects", "LivePreview",
    "LowPerformanceMode", "ReduceUIAnimations", "UIOptimization", "FPSDisplay", "MemoryDiagnostics", "AutoPerformanceAdjust",
    "PrivacyMode", "HideSensitive", "HidePreview",
    "ToggleKey", "TouchSensitivity", "DragSensitivity", "MobileButtonSize", "TouchFeedback",
    "LastTab",
}

local TABS = {
    {id = "GENERAL", label = "GENERAL"},
    {id = "APPEARANCE", label = "APPEARANCE"},
    {id = "PERFORMANCE", label = "PERFORMANCE"},
    {id = "PRIVACY", label = "PRIVACY"},
    {id = "CONTROLS", label = "CONTROLS"},
    {id = "CONFIGURATION", label = "CONFIGURATION"},
    {id = "ADVANCED", label = "ADVANCED CORE"},
    {id = "ABOUT", label = "ABOUT"},
}

local function isValidTab(id)
    for _, t in ipairs(TABS) do
        if t.id == id then return true end
    end
    return false
end

-- Validates and normalizes a value for a setting (used by UI, load and import)
local function sanitizeValue(key, value)
    local def = SCHEMA[key]
    if not def then return nil end
    if def.type == "bool" then
        if type(value) == "boolean" then return value end
        return nil
    elseif def.type == "number" then
        if type(value) ~= "number" or value ~= value then return nil end
        value = math.clamp(value, def.min, def.max)
        local steps = math.floor((value - def.min) / def.step + 0.5)
        value = def.min + steps * def.step
        value = math.floor(value * 1000 + 0.5) / 1000
        return math.clamp(value, def.min, def.max)
    elseif def.type == "key" then
        if type(value) ~= "string" then return nil end
        local ok, item = pcall(function() return Enum.KeyCode[value] end)
        if ok and item and item ~= Enum.KeyCode.Unknown then return value end
        return nil
    elseif def.type == "tab" then
        if type(value) == "string" and isValidTab(value) then return value end
        return nil
    end
    return nil
end

local S = {}
local function resetSettingsToDefaults()
    for _, k in ipairs(SCHEMA_ORDER) do
        S[k] = SCHEMA[k].default
    end
end
resetSettingsToDefaults()

-- ---------- Storage (file when available, memory otherwise) ----------
local CONFIG_FILE = "VortexHub_Config.json"

local function canUseFiles()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

local function serializeSettings()
    local out = {}
    for _, k in ipairs(SCHEMA_ORDER) do out[k] = S[k] end
    return HttpService:JSONEncode(out)
end

local function applyDecoded(tbl)
    local count = 0
    for _, k in ipairs(SCHEMA_ORDER) do
        if tbl[k] ~= nil then
            local v = sanitizeValue(k, tbl[k])
            if v ~= nil then
                S[k] = v
                count = count + 1
            end
        end
    end
    return count
end

local function readStoredConfig()
    if canUseFiles() then
        local okExists, exists = pcall(isfile, CONFIG_FILE)
        if okExists and exists then
            local okRead, data = pcall(readfile, CONFIG_FILE)
            if okRead and type(data) == "string" and #data > 0 then return data end
        end
    end
    return env.VortexConfigMemory
end

local function saveConfig()
    local okEnc, json = pcall(serializeSettings)
    if not okEnc then
        logError("Save", json)
        return false, "Could not encode settings"
    end
    env.VortexConfigMemory = json
    if canUseFiles() then
        local ok, err = pcall(writefile, CONFIG_FILE, json)
        if ok then return true, "Configuration saved to file" end
        logError("Save", err)
        return true, "Saved in memory (file write failed)"
    end
    return true, "Saved in memory (no file access)"
end

local function deleteStoredConfig()
    env.VortexConfigMemory = nil
    if type(delfile) == "function" and canUseFiles() then
        local okExists, exists = pcall(isfile, CONFIG_FILE)
        if okExists and exists then pcall(delfile, CONFIG_FILE) end
    end
end

local function copyToClipboard(text)
    local fn = setclipboard or toclipboard
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, text)
    return ok
end

-- Load saved configuration silently at startup
do
    local raw = readStoredConfig()
    if raw then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and type(decoded) == "table" then
            applyDecoded(decoded)
        else
            logError("Startup load", "Saved configuration is invalid")
        end
    end
end

-- ---------- Animation helpers ----------
local function animDur(base)
    if S.ReduceUIAnimations or S.LowPerformanceMode then return 0.06 end
    return base / S.AnimationSpeed
end

local liveTweens = {}  -- one active tween per object (prevents duplicate tweens)

local function playTween(obj, props, base, style, dir, onDone)
    if not alive or not obj or not obj.Parent then return nil end
    local prev = liveTweens[obj]
    if prev then prev:Cancel() end
    local info = TweenInfo.new(animDur(base), style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out)
    local tw = TS:Create(obj, info, props)
    liveTweens[obj] = tw
    local conn
    conn = tw.Completed:Connect(function(state)
        if conn then conn:Disconnect() end
        if liveTweens[obj] == tw then liveTweens[obj] = nil end
        if onDone then onDone(state) end
    end)
    tw:Play()
    return tw
end

local function connectOnce(signal, fn)
    local conn
    conn = signal:Connect(function(...)
        if conn then conn:Disconnect() end
        fn(...)
    end)
    return conn
end

-- Touch / click feedback: the pressed button lightens (or darkens) briefly
local function addPressFeedback(button, bag, target)
    target = target or button
    local base = target.BackgroundColor3
    local luminance = (base.R + base.G + base.B) / 3
    local pressed = base:Lerp((luminance > 0.5) and Color3.new(0, 0, 0) or Color3.new(1, 1, 1), 0.18)
    bag.add(button.InputBegan:Connect(function(input)
        if not S.TouchFeedback then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            playTween(target, {BackgroundColor3 = pressed}, 0.08)
        end
    end))
    bag.add(button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            playTween(target, {BackgroundColor3 = base}, 0.12)
        end
    end))
end

-- Extra swipe-speed multiplier for a ScrollingFrame (touch only)
local function attachScrollSensitivity(frame, getMultiplier)
    track(frame.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not frame.ScrollingEnabled then return end
        local mult = getMultiplier()
        if math.abs(mult - 1) < 0.01 then return end
        local extra = -input.Delta.Y * (mult - 1)
        local maxY = math.max(0, frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y)
        frame.CanvasPosition = Vector2.new(frame.CanvasPosition.X, math.clamp(frame.CanvasPosition.Y + extra, 0, maxY))
    end))
end

-- =========================================================
-- 1. التنظيف الشامل (Full cleanup, previous run + this run)
-- =========================================================
local LIGHTING_NAMES = {"VortexBlur", "VortexDoF", "VortexColor"}
local GUI_NAMES = {"VortexMainUI", "VortexSettingsUI", "VortexError"}

local function destroyNamedInstances()
    for _, n in ipairs(LIGHTING_NAMES) do
        local o = Lighting:FindFirstChild(n); if o then o:Destroy() end
    end
    for _, n in ipairs(GUI_NAMES) do
        local o = parent:FindFirstChild(n); if o then o:Destroy() end
    end
end

-- If an older Vortex session is still alive, shut it down cleanly first
if env.__VortexCleanup then pcall(env.__VortexCleanup) end
destroyNamedInstances()
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)

-- Destroys everything: connections, tweens, threads' work, lighting effects, GUIs
local function destroyAll()
    alive = false
    mainBag.clear()
    pageBag.clear()
    for obj, tw in pairs(liveTweens) do
        pcall(function() tw:Cancel() end)
        liveTweens[obj] = nil
    end
    for _, fn in ipairs(cleanupTasks) do pcall(fn) end
    table.clear(cleanupTasks)
    destroyNamedInstances()
end
env.__VortexCleanup = destroyAll

-- Full shutdown for the "Close Vortex" menu item (also restores the Roblox UI)
local function closeVortex()
    destroyAll()
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
end

-- =========================================================
-- 2. التمويه والخلفية
-- =========================================================
local blur = Instance.new("BlurEffect"); blur.Name = "VortexBlur"; blur.Size = 56; blur.Parent = Lighting
local dof = Instance.new("DepthOfFieldEffect"); dof.Name = "VortexDoF"; dof.FarIntensity = 1; dof.FocusDistance = 0; dof.InFocusRadius = 1; dof.NearIntensity = 1; dof.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect"); cc.Name = "VortexColor"; cc.Brightness = -0.25; cc.Contrast = 1.4; cc.Saturation = 0.1; cc.Parent = Lighting

local mainGui = Instance.new("ScreenGui")
mainGui.Name = "VortexMainUI"; mainGui.IgnoreGuiInset = true; mainGui.ResetOnSpawn = false
-- one step below the Settings layer so the hamburger/menu/settings always sit above the hub
mainGui.DisplayOrder = 2147483645
mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Global; mainGui.Parent = parent

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1); backdrop.BackgroundColor3 = Color3.fromRGB(255, 255, 255); backdrop.BorderSizePixel = 0; backdrop.ZIndex = 1; backdrop.Parent = mainGui
local backdropGrad = Instance.new("UIGradient")
backdropGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 28, 30)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 62, 65)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(105, 95, 80))
})
backdropGrad.Rotation = 145; backdropGrad.Parent = backdrop

-- =========================================================
-- 3. حركة شعار codeR
-- =========================================================
local textContainer = Instance.new("Frame")
textContainer.Position = UDim2.new(0, 40, 0, 40); textContainer.Size = UDim2.new(0, 200, 0, 60)
textContainer.BackgroundTransparency = 1; textContainer.ZIndex = 2; textContainer.Parent = mainGui

local word = "codeR"
local letterSpacing = 35
for i = 1, #word do
    local char = string.sub(word, i, i)
    local lbl = Instance.new("TextLabel")
    lbl.Text = char; lbl.Font = Enum.Font.GothamBlack; lbl.TextSize = 48; lbl.TextColor3 = Color3.fromRGB(220, 210, 195)
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(0, 40, 0, 60); lbl.AnchorPoint = Vector2.new(0.5, 0.5)
    lbl.ZIndex = 3; lbl.Parent = textContainer

    local finalX = (i - 1) * letterSpacing + 20
    local finalY = 30
    lbl.Position = UDim2.new(0, finalX + math.random(-100, 100), 0, finalY + math.random(-100, 100))
    lbl.Rotation = math.random(-180, 180); lbl.TextTransparency = 1

    task.delay(0.1 + (i * 0.05), function()
        if not alive then return end
        TS:Create(lbl, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, finalX, 0, finalY), Rotation = 0, TextTransparency = 0}):Play()
    end)
end

-- =========================================================
-- 4. زر التشغيل (Run)
-- =========================================================
local runBtn = Instance.new("TextButton")
runBtn.Position = UDim2.new(0, 40, 0, 110); runBtn.Size = UDim2.new(0, 120, 0, 40)
runBtn.BackgroundColor3 = Color3.fromRGB(150, 140, 120); runBtn.BackgroundTransparency = 0.2
runBtn.Text = "Run"; runBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
runBtn.TextSize = 20; runBtn.Font = Enum.Font.GothamBlack
runBtn.ZIndex = 10; runBtn.Parent = mainGui
local rbCorner = Instance.new("UICorner"); rbCorner.CornerRadius = UDim.new(0, 8); rbCorner.Parent = runBtn
local runScale = Instance.new("UIScale"); runScale.Parent = runBtn  -- driven by "Mobile Button Size"
local runBaseTransparency = 0.2

-- =========================================================
-- 5. بيانات الألعاب (تم وضع ID و Url كتجربة)
-- =========================================================
local gamesList = {
    {Name = "Blox Fruits", Id = 2753915549, Url = "https://example.com/blox.lua"},
    {Name = "Pet Simulator 99", Id = 8737899170, Url = "https://example.com/pet.lua"},
    {Name = "Arsenal", Id = 286090429, Url = "https://example.com/arsenal.lua"},
    {Name = "Doors", Id = 6516141723, Url = "https://example.com/doors.lua"},
    {Name = "Adopt Me!", Id = 920587237, Url = "https://example.com/adopt.lua"},
    {Name = "Jailbreak", Id = 606849621, Url = "https://example.com/jb.lua"},
    {Name = "BedWars", Id = 6872265039, Url = "https://example.com/bw.lua"},
    {Name = "Da Hood", Id = 2788229376, Url = "https://example.com/dahood.lua"}
}

-- =========================================================
-- 6. شريط البحث
-- =========================================================
local searchBar = Instance.new("Frame")
searchBar.AnchorPoint = Vector2.new(1, 0); searchBar.Position = UDim2.new(1, -30, 0, 40)
searchBar.Size = UDim2.new(0, 200, 0, 40); searchBar.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
searchBar.BackgroundTransparency = 0.2; searchBar.ZIndex = 20; searchBar.Parent = mainGui
local searchBaseTransparency = 0.2
local sbCorner = Instance.new("UICorner"); sbCorner.CornerRadius = UDim.new(0, 10); sbCorner.Parent = searchBar
local sbStroke = Instance.new("UIStroke"); sbStroke.Color = Color3.fromRGB(150, 140, 120); sbStroke.Thickness = 1.5; sbStroke.Transparency = 0.5; sbStroke.Parent = searchBar

local searchIcon = Instance.new("Frame")
searchIcon.Size = UDim2.new(0, 12, 0, 12); searchIcon.Position = UDim2.new(0, 15, 0.5, -6)
searchIcon.BackgroundTransparency = 1; searchIcon.ZIndex = 21; searchIcon.Parent = searchBar
local sicCorner = Instance.new("UICorner"); sicCorner.CornerRadius = UDim.new(1, 0); sicCorner.Parent = searchIcon
local sicStroke = Instance.new("UIStroke"); sicStroke.Color = Color3.fromRGB(200, 200, 200); sicStroke.Thickness = 2; sicStroke.Parent = searchIcon
local searchHandle = Instance.new("Frame")
searchHandle.Size = UDim2.new(0, 2, 0, 6); searchHandle.Position = UDim2.new(1, -1, 1, -1)
searchHandle.BackgroundColor3 = Color3.fromRGB(200, 200, 200); searchHandle.BorderSizePixel = 0
searchHandle.Rotation = -45; searchHandle.ZIndex = 21; searchHandle.Parent = searchIcon

local searchInput = Instance.new("TextBox")
searchInput.Size = UDim2.new(1, -40, 1, 0); searchInput.Position = UDim2.new(0, 35, 0, 0)
searchInput.BackgroundTransparency = 1; searchInput.PlaceholderText = "search..."
searchInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 150); searchInput.Text = ""
searchInput.TextColor3 = Color3.fromRGB(220, 210, 195); searchInput.TextSize = 16
searchInput.Font = Enum.Font.GothamMedium; searchInput.TextXAlignment = Enum.TextXAlignment.Left
searchInput.ClearTextOnFocus = false; searchInput.ZIndex = 21; searchInput.Parent = searchBar

-- =========================================================
-- 7. القائمة الجانبية
-- =========================================================
local isMenuOpen = true -- فتح القائمة افتراضياً لكي تراها
local scroll = Instance.new("ScrollingFrame")
scroll.AnchorPoint = Vector2.new(1, 0.5)
scroll.Position = UDim2.new(1, -30, 0.5, 0)
scroll.Size = UDim2.new(0, 260, 0.7, 0)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 0
scroll.ScrollingDirection = Enum.ScrollingDirection.Y; scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
scroll.CanvasSize = UDim2.new(); scroll.ZIndex = 10; scroll.Parent = mainGui
scroll.ClipsDescendants = false

local BASE_H = 60
local GAP = 45
local topPadding = 150
local cards = {}

for i, gameData in ipairs(gamesList) do
    local card = Instance.new("TextButton")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.new(0.5, 0, 0, topPadding + (i - 1) * (BASE_H + GAP))
    card.Size = UDim2.new(1, -50, 0, BASE_H)
    card.BackgroundColor3 = Color3.fromRGB(30, 30, 35); card.BackgroundTransparency = 0.4
    card.BorderSizePixel = 0; card.AutoButtonColor = false; card.Text = ""; card.ZIndex = 11; card.Parent = scroll
    card.ClipsDescendants = false

    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = card
    local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(150, 140, 120); st.Thickness = 2; st.Transparency = 0.6; st.Parent = card

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -20, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0); lbl.BackgroundTransparency = 1
    lbl.Text = gameData.Name; lbl.TextColor3 = Color3.fromRGB(220, 210, 195); lbl.TextSize = 18
    lbl.Font = Enum.Font.GothamBold; lbl.TextXAlignment = Enum.TextXAlignment.Center; lbl.ZIndex = 12; lbl.Parent = card

    local scale = Instance.new("UIScale"); scale.Parent = card
    cards[i] = {Frame = card, Label = lbl, Stroke = st, Scale = scale, Data = gameData}
end

scroll.CanvasSize = UDim2.new(0, 0, 0, topPadding * 2 + (#gamesList - 1) * (BASE_H + GAP) + BASE_H)

-- السهم
local arrowContainer = Instance.new("Frame")
arrowContainer.AnchorPoint = Vector2.new(0.5, 0.5); arrowContainer.Position = UDim2.new(1, -310, 0.5, 0)
arrowContainer.Size = UDim2.new(0, 30, 0, 30); arrowContainer.BackgroundTransparency = 1; arrowContainer.ZIndex = 20; arrowContainer.Parent = mainGui
arrowContainer.Rotation = 180 -- مقلوب لأن القائمة مفتوحة

local arrowTop = Instance.new("Frame")
arrowTop.Size = UDim2.new(0, 18, 0, 4); arrowTop.Position = UDim2.new(0.5, -9, 0.5, -6)
arrowTop.BackgroundColor3 = Color3.fromRGB(220, 210, 195); arrowTop.BorderSizePixel = 0; arrowTop.Rotation = 45; arrowTop.ZIndex = 21; arrowTop.Parent = arrowContainer

local arrowBottom = Instance.new("Frame")
arrowBottom.Size = UDim2.new(0, 18, 0, 4); arrowBottom.Position = UDim2.new(0.5, -9, 0.5, 6)
arrowBottom.BackgroundColor3 = Color3.fromRGB(220, 210, 195); arrowBottom.BorderSizePixel = 0; arrowBottom.Rotation = -45; arrowBottom.ZIndex = 21; arrowBottom.Parent = arrowContainer

local arrowClickArea = Instance.new("TextButton")
arrowClickArea.Size = UDim2.fromScale(1.5, 1.5); arrowClickArea.Position = UDim2.new(-0.25, 0, -0.25, 0)
arrowClickArea.BackgroundTransparency = 1; arrowClickArea.Text = ""; arrowClickArea.ZIndex = 22; arrowClickArea.Parent = arrowContainer

-- Every element that belongs to the "hub" (used by Hide/Show Hub and the toggle key)
local hubElements = {backdrop, textContainer, runBtn, searchBar, scroll, arrowContainer}

-- =========================================================
-- 8. منطق التحديث (المُحسّن)
-- =========================================================
local sound = Instance.new("Sound"); sound.SoundId = "rbxassetid://116080744084010"; sound.Volume = 0.5; sound.Parent = SoundService
cleanupTasks[#cleanupTasks + 1] = function() sound:Destroy() end
local lastSelectedIndex = -1
local lastPlayedIndex = 1
local lastY = 0
local cardTweens = {}
local isSnapping = false
local currentSnapTween = nil
cleanupTasks[#cleanupTasks + 1] = function()
    if currentSnapTween then currentSnapTween:Cancel() end
    for i, list in pairs(cardTweens) do
        for _, t in ipairs(list) do t:Cancel() end
        cardTweens[i] = nil
    end
end

local function updateVisuals(forceUpdate)
    if not isMenuOpen then return end
    local viewH = scroll.AbsoluteSize.Y
    local centerY = scroll.CanvasPosition.Y + viewH / 2
    local closestIdx = 1
    local minDist = math.huge

    for i, obj in ipairs(cards) do
        local dist = math.abs(obj.Frame.Position.Y.Offset - centerY)
        if dist < minDist then minDist = dist; closestIdx = i end
    end

    if closestIdx ~= lastPlayedIndex then
        lastPlayedIndex = closestIdx
        local currentY = scroll.CanvasPosition.Y
        local deltaY = math.abs(currentY - lastY)
        lastY = currentY
        sound.PlaybackSpeed = math.clamp(1 + (deltaY / 150), 0.8, 2.5)
        sound:Play()
    end

    if closestIdx == lastSelectedIndex and not forceUpdate then return end
    lastSelectedIndex = closestIdx

    -- Settings-driven behavior: no tweens in low performance mode, culling of far cards
    local instant = S.LowPerformanceMode or S.ReduceUIAnimations
    local cull = S.UIOptimization or S.LowPerformanceMode

    for i, obj in ipairs(cards) do
        local d = math.abs(i - closestIdx)
        local tScale, tTrans
        if d == 0 then tScale, tTrans = 1.15, 0
        elseif d == 1 then tScale, tTrans = 0.95, 0.2
        elseif d == 2 then tScale, tTrans = 0.85, 0.39
        else tScale, tTrans = 0.75, 0.7 end

        local visible = (not cull) or d <= 3
        obj.Frame.Visible = visible

        if cardTweens[i] then
            for _, t in ipairs(cardTweens[i]) do t:Cancel() end
            cardTweens[i] = nil
        end

        if instant or not visible then
            obj.Scale.Scale = tScale
            obj.Frame.BackgroundTransparency = tTrans
            obj.Label.TextTransparency = tTrans
            obj.Stroke.Transparency = tTrans + 0.1
        else
            local ti = TweenInfo.new(animDur(0.15), Enum.EasingStyle.Quint)
            local t1 = TS:Create(obj.Scale, ti, {Scale = tScale})
            local t2 = TS:Create(obj.Frame, ti, {BackgroundTransparency = tTrans})
            local t3 = TS:Create(obj.Label, ti, {TextTransparency = tTrans})
            local t4 = TS:Create(obj.Stroke, ti, {Transparency = tTrans + 0.1})
            t1:Play(); t2:Play(); t3:Play(); t4:Play()
            cardTweens[i] = {t1, t2, t3, t4}
        end
    end
end

local function snapToCenter()
    if not alive or not isMenuOpen then return end
    isSnapping = true
    local viewH = scroll.AbsoluteSize.Y
    local centerY = scroll.CanvasPosition.Y + viewH / 2
    local closestIdx = 1
    local minDist = math.huge

    for i, obj in ipairs(cards) do
        local dist = math.abs(obj.Frame.Position.Y.Offset - centerY)
        if dist < minDist then minDist = dist; closestIdx = i end
    end

    if currentSnapTween then currentSnapTween:Cancel() end
    currentSnapTween = TS:Create(scroll, TweenInfo.new(animDur(0.2), Enum.EasingStyle.Quint), {CanvasPosition = Vector2.new(0, cards[closestIdx].Frame.Position.Y.Offset - (viewH / 2))})
    currentSnapTween:Play()
    connectOnce(currentSnapTween.Completed, function(playbackState)
        if playbackState == Enum.PlaybackState.Completed then
            isSnapping = false; updateVisuals(true)
        end
    end)
end

track(scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function() if not isSnapping then updateVisuals(false) end end))

-- فتح القائمة لأول مرة (توسيط العنصر الأول)
task.delay(0.3, function()
    if not alive then return end
    if scroll.AbsoluteSize.Y > 0 then
        local targetY = cards[1].Frame.Position.Y.Offset - (scroll.AbsoluteSize.Y / 2)
        scroll.CanvasPosition = Vector2.new(0, targetY)
        updateVisuals(true)
    end
end)

-- =========================================================
-- 9. البحث الذكي
-- =========================================================
track(searchInput:GetPropertyChangedSignal("Text"):Connect(function()
    local query = string.lower(searchInput.Text)
    if query == "" then return end

    for i, obj in ipairs(cards) do
        local gameName = string.lower(obj.Data.Name)
        if string.find(gameName, query, 1, true) then
            local viewH = scroll.AbsoluteSize.Y
            local targetY = obj.Frame.Position.Y.Offset - (viewH / 2)
            if currentSnapTween then currentSnapTween:Cancel() end
            TS:Create(scroll, TweenInfo.new(animDur(0.3), Enum.EasingStyle.Quint), {CanvasPosition = Vector2.new(0, targetY)}):Play()
            break
        end
    end
end))

-- =========================================================
-- 10. زر التشغيل (Run)
-- =========================================================
track(runBtn.MouseButton1Click:Connect(function()
    local currentGameId = game.PlaceId
    local foundGame = nil

    for _, gameData in ipairs(gamesList) do
        if gameData.Id == currentGameId then
            foundGame = gameData
            break
        end
    end

    if foundGame then
        destroyAll()
        task.wait(0.1)
        local success, err = pcall(function()
            loadstring(game:HttpGet(foundGame.Url))()
        end)
        if not success then
            print("Script load error: " .. tostring(err))
        end
    else
        -- شاشة الخطأ (Game not found)
        local errorGui = Instance.new("ScreenGui")
        errorGui.Name = "VortexError"
        errorGui.IgnoreGuiInset = true
        errorGui.DisplayOrder = 2147483647
        errorGui.Parent = parent

        local errorFrame = Instance.new("Frame")
        errorFrame.Size = UDim2.fromScale(1, 1)
        errorFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
        errorFrame.BorderSizePixel = 0
        errorFrame.Parent = errorGui

        local errorText = Instance.new("TextLabel")
        errorText.Size = UDim2.new(1, 0, 1, 0)
        errorText.BackgroundTransparency = 1
        errorText.Text = "Game not found in training list"
        errorText.TextColor3 = Color3.fromRGB(255, 255, 255)
        errorText.TextSize = 24
        errorText.Font = Enum.Font.GothamBlack
        errorText.Parent = errorFrame

        local closeErr = Instance.new("TextButton")
        closeErr.Size = UDim2.new(0, 50, 0, 50)
        closeErr.Position = UDim2.new(1, -60, 0, 10)
        closeErr.BackgroundTransparency = 1
        closeErr.Text = "X"
        closeErr.TextColor3 = Color3.fromRGB(255, 50, 50)
        closeErr.TextSize = 24
        closeErr.Font = Enum.Font.GothamBlack
        closeErr.Parent = errorFrame
        closeErr.MouseButton1Click:Connect(function()
            errorGui:Destroy()
        end)
    end
end))

-- =========================================================
-- 11. فتح وإغلاق القائمة
-- =========================================================
local function toggleMenu()
    isMenuOpen = not isMenuOpen
    if isMenuOpen then
        TS:Create(scroll, TweenInfo.new(animDur(0.3), Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.new(1, -30, 0.5, 0)}):Play()
        TS:Create(arrowContainer, TweenInfo.new(animDur(0.3), Enum.EasingStyle.Quint), {Rotation = 180, Position = UDim2.new(1, -310, 0.5, 0)}):Play()
    else
        TS:Create(scroll, TweenInfo.new(animDur(0.3), Enum.EasingStyle.Quint, Enum.EasingDirection.In), {Position = UDim2.new(1, 300, 0.5, 0)}):Play()
        TS:Create(arrowContainer, TweenInfo.new(animDur(0.3), Enum.EasingStyle.Quint), {Rotation = 0, Position = UDim2.new(1, -50, 0.5, 0)}):Play()
    end
end

track(arrowClickArea.MouseButton1Click:Connect(toggleMenu))

track(scroll.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if currentSnapTween then currentSnapTween:Cancel() end
        isSnapping = false
    end
end))

track(scroll.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        task.delay(0.05, snapToCenter)
    end
end))

-- Touch Control Sensitivity: swipe speed of the game list
attachScrollSensitivity(scroll, function() return S.TouchSensitivity end)

-- =========================================================
-- 12. SETTINGS SYSTEM  (hamburger menu + Settings control center)
--     Lives in its own ScreenGui (Sibling ZIndex mode) above the hub.
-- =========================================================

-- ---------- 12.1 UI construction helpers ----------
local function make(className, props, parentObj)
    local inst = Instance.new(className)
    for k, v in pairs(props) do inst[k] = v end
    if parentObj then inst.Parent = parentObj end
    return inst
end

local function addCorner(inst, radius)
    return make("UICorner", {CornerRadius = UDim.new(0, radius)}, inst)
end

local function addStroke(inst, color, thickness, transparency)
    return make("UIStroke", {
        Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, inst)
end

local function addPadding(inst, left, top, right, bottom)
    return make("UIPadding", {
        PaddingLeft = UDim.new(0, left), PaddingTop = UDim.new(0, top),
        PaddingRight = UDim.new(0, right), PaddingBottom = UDim.new(0, bottom),
    }, inst)
end

local function makeLabel(props, parentObj)
    local p = {
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = COL.text, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true, BorderSizePixel = 0,
    }
    for k, v in pairs(props) do p[k] = v end
    return make("TextLabel", p, parentObj)
end

local function makeButton(props, parentObj)
    local p = {
        AutoButtonColor = false, BorderSizePixel = 0, Text = "", Font = Enum.Font.GothamBold,
        TextSize = 14, TextColor3 = COL.text, BackgroundColor3 = COL.btn,
    }
    for k, v in pairs(props) do p[k] = v end
    return make("TextButton", p, parentObj)
end

local uiGui = make("ScreenGui", {
    Name = "VortexSettingsUI", IgnoreGuiInset = true, ResetOnSpawn = false,
    DisplayOrder = 2147483646, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, parent)

local function getViewport()
    local size = uiGui.AbsoluteSize
    if size.X < 50 or size.Y < 50 then return Vector2.new(640, 360) end
    return size
end

-- ---------- 12.2 State & forward declarations ----------
local hubVisible = true
local menuOpen = false
local panelOpen = false
local currentTab = nil
local activeDrag = nil
local listeningForKey = false
local pendingConfirm = nil
local previewRef = nil
local importBoxRef = nil
local infoEntries = {}
local controlSync = {}
local fps, fpsKnown = 60, false
local monitorConn = nil
local frameCount, accum = 0, 0
local lowStreak, highStreak, autoLowApplied = 0, 0, false
local diagTick = 0
local toastToken = 0
local saveScheduled = false
local httpStatus = "Not tested"

local setSetting, syncControls, refreshInfos, toast, confirm
local openSettings, closeSettings, showTab, applyAllSettings
local openMenu, closeMenu, refreshMonitor, updateStatsOverlay

local function isSensitiveHidden() return S.PrivacyMode or S.HideSensitive end
local function isPreviewHidden() return S.PrivacyMode or S.HidePreview end

-- ---------- 12.3 Effects, hub visibility, performance ----------
local function applyEffects()
    local low = S.LowPerformanceMode
    local flat = S.ReduceVisualEffects or low
    blur.Enabled = hubVisible and S.BlurEffect and not low
    dof.Enabled = hubVisible and S.BlurEffect and not flat
    cc.Enabled = hubVisible and not flat
    blur.Size = S.ReduceVisualEffects and 24 or 56
    -- Reduce Visual Effects: flat dark background instead of the gradient
    backdropGrad.Enabled = not flat
    backdrop.BackgroundColor3 = flat and Color3.fromRGB(38, 40, 42) or Color3.fromRGB(255, 255, 255)
end

local function applyPerf()
    local cull = S.UIOptimization or S.LowPerformanceMode
    if not cull then
        for _, obj in ipairs(cards) do obj.Frame.Visible = true end
    else
        updateVisuals(true)
    end
end

local function setHubVisible(visible)
    hubVisible = visible
    for _, el in ipairs(hubElements) do el.Visible = visible end
    applyEffects()
end

-- ---------- 12.4 Toast + confirmation dialog ----------
local toastLabel = makeLabel({
    Name = "Toast", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18),
    Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY,
    BackgroundColor3 = Color3.fromRGB(32, 32, 36), BackgroundTransparency = 1,
    TextColor3 = COL.white, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center, Visible = false, ZIndex = 30,
}, uiGui)
addCorner(toastLabel, 12)
addPadding(toastLabel, 16, 10, 16, 10)
make("UISizeConstraint", {MaxSize = Vector2.new(360, 240)}, toastLabel)

function toast(message)
    if not alive then return end
    toastToken = toastToken + 1
    local mine = toastToken
    toastLabel.Text = tostring(message)
    toastLabel.Visible = true
    playTween(toastLabel, {BackgroundTransparency = 0.05, TextTransparency = 0}, 0.15)
    task.delay(2.4, function()
        if alive and mine == toastToken then
            playTween(toastLabel, {BackgroundTransparency = 1, TextTransparency = 1}, 0.25, nil, nil, function()
                if alive and mine == toastToken then toastLabel.Visible = false end
            end)
        end
    end)
end

local dialogDim = makeButton({
    Name = "ConfirmDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0.45, Visible = false, ZIndex = 20,
}, uiGui)
local dialog = make("Frame", {
    Name = "ConfirmDialog", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.9, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Color3.fromRGB(22, 22, 26), BorderSizePixel = 0, Active = true,
}, dialogDim)
addCorner(dialog, 16)
addStroke(dialog, Color3.fromRGB(90, 90, 96), 1.5, 0.2)
make("UISizeConstraint", {MaxSize = Vector2.new(340, 10000)}, dialog)
addPadding(dialog, 18, 18, 18, 18)
make("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10)}, dialog)
local dialogTitle = makeLabel({
    Name = "Title", Font = Enum.Font.GothamBlack, TextSize = 18, Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
}, dialog)
local dialogMsg = makeLabel({
    Name = "Message", TextSize = 14, TextColor3 = COL.sub, Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
}, dialog)
local dialogButtons = make("Frame", {
    Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, BorderSizePixel = 0,
}, dialog)
make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, dialogButtons)
local dialogCancel = makeButton({
    Name = "Cancel", LayoutOrder = 1, Size = UDim2.new(0.5, -5, 1, 0), Text = "Cancel", BackgroundColor3 = COL.btn,
}, dialogButtons)
addCorner(dialogCancel, 10)
local dialogYes = makeButton({
    Name = "Confirm", LayoutOrder = 2, Size = UDim2.new(0.5, -5, 1, 0), Text = "Confirm",
    BackgroundColor3 = COL.white, TextColor3 = COL.black,
}, dialogButtons)
addCorner(dialogYes, 10)
addPressFeedback(dialogCancel, mainBag)
addPressFeedback(dialogYes, mainBag)

local function closeConfirm()
    pendingConfirm = nil
    dialogDim.Visible = false
end

function confirm(title, message, confirmText, onYes)
    pendingConfirm = onYes
    dialogTitle.Text = title
    dialogMsg.Text = message
    dialogYes.Text = confirmText or "Confirm"
    dialogDim.BackgroundTransparency = 1
    dialogDim.Visible = true
    playTween(dialogDim, {BackgroundTransparency = 0.45}, 0.18)
end

track(dialogCancel.MouseButton1Click:Connect(closeConfirm))
track(dialogDim.MouseButton1Click:Connect(closeConfirm))
track(dialogYes.MouseButton1Click:Connect(function()
    local fn = pendingConfirm
    closeConfirm()
    if fn then
        local ok, err = pcall(fn)
        if not ok then
            logError("Confirm action", err)
            toast("Error: " .. tostring(err))
        end
    end
end))

-- ---------- 12.5 Hamburger button (TOP of the interface) ----------
local HAM_TOP = 38
local HAM_SIZE = 44
local HAM_RIGHT = 30 + 200 + 10   -- sits just left of the search bar (right margin 30 + width 200 + gap 10)

local hamburger = makeButton({
    Name = "HamburgerButton", AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -HAM_RIGHT, 0, HAM_TOP), Size = UDim2.new(0, HAM_SIZE, 0, HAM_SIZE),
    BackgroundColor3 = Color3.fromRGB(22, 22, 26), BackgroundTransparency = 0.15, ZIndex = 8,
}, uiGui)
addCorner(hamburger, 12)
addStroke(hamburger, Color3.fromRGB(120, 120, 126), 1.5, 0.45)
local hamburgerScale = make("UIScale", {Scale = 1}, hamburger)

local barClosedY = {-7, 0, 7}
local bars = {}
for i = 1, 3 do
    bars[i] = make("Frame", {
        Name = "Bar" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, barClosedY[i]),
        Size = UDim2.new(0, 20, 0, 3), BackgroundColor3 = COL.white, BorderSizePixel = 0,
    }, hamburger)
    addCorner(bars[i], 2)
end

-- The three lines morph into an "X" while the dropdown is open
local function setHamburgerIcon(open)
    if open then
        playTween(bars[1], {Position = UDim2.new(0.5, 0, 0.5, 0), Rotation = 45}, 0.25)
        playTween(bars[2], {BackgroundTransparency = 1}, 0.2)
        playTween(bars[3], {Position = UDim2.new(0.5, 0, 0.5, 0), Rotation = -45}, 0.25)
    else
        playTween(bars[1], {Position = UDim2.new(0.5, 0, 0.5, barClosedY[1]), Rotation = 0}, 0.25)
        playTween(bars[2], {BackgroundTransparency = 0}, 0.2)
        playTween(bars[3], {Position = UDim2.new(0.5, 0, 0.5, barClosedY[3]), Rotation = 0}, 0.25)
    end
end

-- ---------- 12.6 Dropdown menu (opens TOP -> BOTTOM below the hamburger) ----------
local MENU_ENTRIES = {
    {id = "home", text = "Home"},
    {id = "settings", text = "Settings"},
    {id = "hub", text = "Hide Hub"},
    {id = "save", text = "Save Configuration"},
    {id = "about", text = "About"},
    {id = "close", text = "Close Vortex"},
}
local MENU_PAD, MENU_GAP = 6, 4

-- invisible full-screen layer: tapping anywhere outside the menu closes it
local menuCatcher = makeButton({
    Name = "MenuCatcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 6,
}, uiGui)

local menuGroup = make("CanvasGroup", {
    Name = "DropdownMenu", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0, 300, 0, 90),
    Size = UDim2.new(0, 200, 0, 0), BackgroundColor3 = COL.panel, BorderSizePixel = 0,
    GroupTransparency = 1, Visible = false, ZIndex = 7, Active = true,
}, uiGui)
addCorner(menuGroup, 14)
addStroke(menuGroup, COL.rowStroke, 1.5, 0.2)
local menuScale = make("UIScale", {Scale = 1}, menuGroup)
addPadding(menuGroup, MENU_PAD, MENU_PAD, MENU_PAD, MENU_PAD)
make("UIListLayout", {Padding = UDim.new(0, MENU_GAP), SortOrder = Enum.SortOrder.LayoutOrder}, menuGroup)

local menuButtons = {}

-- Computes size/position so the menu always stays inside the screen
local function layoutMenu()
    local vp = getViewport()
    local sc = S.UIScale
    local btnScale = S.MobileButtonSize
    local top = HAM_TOP + HAM_SIZE * btnScale + 6
    local count = #MENU_ENTRIES
    local itemH = math.floor(44 * btnScale)
    local available = (vp.Y - top - 8) / sc
    local needed = count * itemH + (count - 1) * MENU_GAP + MENU_PAD * 2
    if needed > available then
        itemH = math.max(30, math.floor((available - (count - 1) * MENU_GAP - MENU_PAD * 2) / count))
        needed = count * itemH + (count - 1) * MENU_GAP + MENU_PAD * 2
    end
    for _, b in ipairs(menuButtons) do b.Size = UDim2.new(1, 0, 0, itemH) end
    local baseW = math.min(220, (vp.X - 16) / sc)
    local rightEdge = math.clamp(vp.X - HAM_RIGHT, baseW * sc + 8, vp.X - 8)
    menuScale.Scale = sc
    menuGroup.Position = UDim2.new(0, rightEdge, 0, top)
    return needed, baseW
end

function openMenu()
    if menuOpen then return end
    menuOpen = true
    local targetH, baseW = layoutMenu()
    menuButtons[3].Text = hubVisible and "Hide Hub" or "Show Hub"
    menuCatcher.Visible = true
    menuGroup.Visible = true
    menuGroup.GroupTransparency = 1
    menuGroup.Size = UDim2.new(0, baseW, 0, 0)
    setHamburgerIcon(true)
    playTween(menuGroup, {Size = UDim2.new(0, baseW, 0, targetH), GroupTransparency = S.UITransparency}, 0.28)
end

function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    menuCatcher.Visible = false
    setHamburgerIcon(false)
    playTween(menuGroup, {Size = UDim2.new(0, menuGroup.Size.X.Offset, 0, 0), GroupTransparency = 1}, 0.2,
        Enum.EasingStyle.Quint, Enum.EasingDirection.In, function()
            if alive and not menuOpen then menuGroup.Visible = false end
        end)
end

local function onMenuSelect(id)
    closeMenu()
    if id == "home" then
        closeSettings()
        setHubVisible(true)
    elseif id == "settings" then
        openSettings()
    elseif id == "hub" then
        setHubVisible(not hubVisible)
        toast(hubVisible and "Hub shown" or "Hub hidden")
    elseif id == "save" then
        local _, msg = saveConfig()
        toast(msg)
    elseif id == "about" then
        openSettings("ABOUT")
    elseif id == "close" then
        confirm("Close Vortex?", "This removes the interface, restores the Roblox UI and stops all Vortex tasks.", "Close", closeVortex)
    end
end

for i, entry in ipairs(MENU_ENTRIES) do
    local btn = makeButton({
        Name = "Item_" .. entry.id, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Color3.fromRGB(30, 30, 34), Text = entry.text, TextSize = 15,
        Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
    }, menuGroup)
    addCorner(btn, 10)
    addPadding(btn, 14, 0, 10, 0)
    addPressFeedback(btn, mainBag)
    menuButtons[i] = btn
    track(btn.MouseButton1Click:Connect(function() onMenuSelect(entry.id) end))
end

track(hamburger.MouseButton1Click:Connect(function()
    if menuOpen then closeMenu() else openMenu() end
end))
track(menuCatcher.MouseButton1Click:Connect(closeMenu))
addPressFeedback(hamburger, mainBag)
addPressFeedback(runBtn, mainBag)

-- ---------- 12.7 Settings window ----------
local dim = makeButton({
    Name = "SettingsDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 1, Visible = false, ZIndex = 10,
}, uiGui)

local panel = make("CanvasGroup", {
    Name = "SettingsPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0, 560, 0, 320), BackgroundColor3 = COL.panel, BorderSizePixel = 0,
    GroupTransparency = 1, Visible = false, ZIndex = 11, Active = true,
}, uiGui)
addCorner(panel, 18)
addStroke(panel, Color3.fromRGB(70, 70, 76), 1.5, 0.15)
local panelScale = make("UIScale", {Scale = 1}, panel)

local header = make("Frame", {Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), BorderSizePixel = 0}, panel)
makeLabel({
    Name = "Title", Text = "SETTINGS", Font = Enum.Font.GothamBlack, TextSize = 20, TextWrapped = false,
    Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -80, 0, 24),
}, header)
makeLabel({
    Name = "Subtitle", Text = "Vortex Hub v" .. VERSION .. "  |  by codeR", TextSize = 12, TextColor3 = COL.sub,
    TextWrapped = false, Position = UDim2.new(0, 16, 0, 33), Size = UDim2.new(1, -80, 0, 16),
}, header)

local closeBtn = makeButton({
    Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
    Size = UDim2.new(0, 44, 0, 44), BackgroundColor3 = COL.btn,
}, header)
addCorner(closeBtn, 12)
for _, rot in ipairs({45, -45}) do
    local line = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 20, 0, 3),
        Rotation = rot, BackgroundColor3 = COL.white, BorderSizePixel = 0,
    }, closeBtn)
    addCorner(line, 2)
end
addPressFeedback(closeBtn, mainBag)

make("Frame", {Name = "Divider", Position = UDim2.new(0, 0, 0, 56), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = COL.rowStroke, BorderSizePixel = 0}, panel)

local tabsFrame = make("ScrollingFrame", {
    Name = "Tabs", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 58),
    Size = UDim2.new(1, 0, 0, 50), CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0,
    ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
}, panel)
make("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
    VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
}, tabsFrame)
addPadding(tabsFrame, 12, 0, 12, 0)

local tabButtons = {}
local TAB_IDLE_BG = Color3.fromRGB(36, 36, 40)
local TAB_IDLE_TEXT = Color3.fromRGB(200, 200, 204)
for i, tab in ipairs(TABS) do
    local b = makeButton({
        Name = "Tab_" .. tab.id, LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 0, 38), Text = tab.label, TextSize = 12,
        BackgroundColor3 = TAB_IDLE_BG, TextColor3 = TAB_IDLE_TEXT,
    }, tabsFrame)
    addCorner(b, 19)
    addPadding(b, 14, 0, 14, 0)
    tabButtons[tab.id] = b
    track(b.MouseButton1Click:Connect(function() showTab(tab.id) end))
end

local content = make("ScrollingFrame", {
    Name = "Content", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 110),
    Size = UDim2.new(1, 0, 1, -110), CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
    ScrollBarImageColor3 = Color3.fromRGB(110, 110, 116), ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
}, panel)
make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, content)
addPadding(content, 12, 6, 12, 16)

-- Drag Sensitivity: swipe speed of the Settings page
attachScrollSensitivity(content, function() return S.DragSensitivity end)

-- Fits the window to the screen at any UI scale
local function layoutPanel()
    local vp = getViewport()
    local sc = S.UIScale
    local w = math.min(620, (vp.X - 20) / sc)
    local h = math.min(460, (vp.Y - 20) / sc)
    panel.Size = UDim2.new(0, math.floor(w), 0, math.floor(h))
    panelScale.Scale = sc
end

-- ---------- 12.8 Page row builders ----------
local rowOrder = 0

local function newRow()
    rowOrder = rowOrder + 1
    local row = make("Frame", {
        BackgroundColor3 = COL.row, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = rowOrder,
    }, content)
    addCorner(row, 12)
    addStroke(row, COL.rowStroke, 1, 0.35)
    return row
end

local function newInner(row, horizontal)
    local inner = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
    }, row)
    addPadding(inner, 12, 10, 12, 10)
    make("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, horizontal and 10 or 6),
        FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, inner)
    return inner
end

local function addTextPair(parentObj, title, desc, widthOffset, layoutOrder)
    local holder = make("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, widthOffset, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = layoutOrder or 1, BorderSizePixel = 0,
    }, parentObj)
    make("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2)}, holder)
    makeLabel({
        Name = "Title", Text = title, Font = Enum.Font.GothamBold, TextSize = 15,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
    }, holder)
    if desc and desc ~= "" then
        makeLabel({
            Name = "Desc", Text = desc, TextSize = 12, TextColor3 = COL.sub,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
        }, holder)
    end
    return holder
end

local function addSection(text)
    rowOrder = rowOrder + 1
    makeLabel({
        Name = "Section", Text = text, Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = COL.sub,
        TextWrapped = false, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = rowOrder,
        TextYAlignment = Enum.TextYAlignment.Bottom,
    }, content)
end

local function addToggle(key, title, desc)
    local row = newRow()
    local inner = newInner(row, true)
    addTextPair(inner, title, desc, -62, 1)
    local switch = make("Frame", {
        Name = "Switch", LayoutOrder = 2, Size = UDim2.new(0, 52, 0, 30), BackgroundColor3 = COL.trackOff, BorderSizePixel = 0,
    }, inner)
    addCorner(switch, 15)
    local knob = make("Frame", {
        Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24), BackgroundColor3 = Color3.fromRGB(160, 160, 166), BorderSizePixel = 0,
    }, switch)
    addCorner(knob, 12)

    local function render(animate)
        local on = S[key] == true
        local trackColor = on and COL.white or COL.trackOff
        local knobColor = on and COL.black or Color3.fromRGB(160, 160, 166)
        local knobPos = on and UDim2.new(0, 25, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        if animate then
            playTween(switch, {BackgroundColor3 = trackColor}, 0.15)
            playTween(knob, {Position = knobPos, BackgroundColor3 = knobColor}, 0.15)
        else
            switch.BackgroundColor3 = trackColor
            knob.BackgroundColor3 = knobColor
            knob.Position = knobPos
        end
    end
    render(false)
    controlSync[key] = function() render(false) end

    -- the whole row is the touch target (large, easy to hit on phones)
    local hit = makeButton({Name = "Hit", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3}, row)
    addPressFeedback(hit, pageBag, row)
    pageBag.add(hit.MouseButton1Click:Connect(function()
        if key == "LowPerformanceMode" then autoLowApplied = false end
        setSetting(key, not S[key])
        render(true)
    end))
end

local function addSlider(key, title, desc, fmt, deferApply)
    local def = SCHEMA[key]
    local row = newRow()
    local inner = newInner(row, false)
    local headerRow = make("Frame", {Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, BorderSizePixel = 0}, inner)
    makeLabel({Name = "Title", Text = title, Font = Enum.Font.GothamBold, TextSize = 15, TextWrapped = false, Size = UDim2.new(0.7, 0, 1, 0)}, headerRow)
    local valueLbl = makeLabel({
        Name = "Value", Font = Enum.Font.GothamBold, TextSize = 14, TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.3, 0, 1, 0),
    }, headerRow)
    if desc then
        makeLabel({
            Name = "Desc", Text = desc, TextSize = 12, TextColor3 = COL.sub,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
        }, inner)
    end
    local hit = makeButton({Name = "SliderHit", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1}, inner)
    local trackBar = make("Frame", {
        Name = "Track", Position = UDim2.new(0, 12, 0.5, -3), Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = COL.trackOff, BorderSizePixel = 0,
    }, hit)
    addCorner(trackBar, 3)
    local fill = make("Frame", {Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COL.white, BorderSizePixel = 0}, trackBar)
    addCorner(fill, 3)
    local knob = make("Frame", {
        Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24), BackgroundColor3 = COL.white, BorderSizePixel = 0, ZIndex = 2,
    }, trackBar)
    addCorner(knob, 12)
    addStroke(knob, COL.black, 2, 0.2)

    local function render(v)
        local rel = math.clamp((v - def.min) / (def.max - def.min), 0, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valueLbl.Text = fmt(v)
    end
    render(S[key])
    controlSync[key] = function() render(S[key]) end

    local pendingValue = S[key]
    local function setFromX(x)
        local width = trackBar.AbsoluteSize.X
        if width <= 0 then return end
        local rel = math.clamp((x - trackBar.AbsolutePosition.X) / width, 0, 1)
        local v = sanitizeValue(key, def.min + rel * (def.max - def.min))
        if v == nil then return end
        pendingValue = v
        render(v)
        if deferApply then
            if previewRef then previewRef.refresh(v) end
        else
            setSetting(key, v)
        end
    end

    pageBag.add(hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeDrag = {
                input = input,
                update = setFromX,
                commit = deferApply and function() setSetting(key, pendingValue) end or nil,
            }
            content.ScrollingEnabled = false
            setFromX(input.Position.X)
        end
    end))
end

-- style: "primary" (white) or "dark"
local function addButton(title, desc, buttonText, callback, style)
    local row = newRow()
    local inner = newInner(row, true)
    addTextPair(inner, title, desc, -114, 1)
    local primary = style ~= "dark"
    local b = makeButton({
        Name = "Action", LayoutOrder = 2, Size = UDim2.new(0, 104, 0, 44), Text = buttonText,
        BackgroundColor3 = primary and COL.white or COL.btn, TextColor3 = primary and COL.black or COL.text,
    }, inner)
    addCorner(b, 10)
    if not primary then addStroke(b, Color3.fromRGB(110, 110, 116), 1, 0.3) end
    addPressFeedback(b, pageBag)
    pageBag.add(b.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback, b)
        if not ok then
            logError(title, err)
            toast("Error: " .. tostring(err))
        end
    end))
    return b
end

local function updateInfoEntry(entry)
    local ok, val = pcall(entry.getter)
    local text = ok and tostring(val) or "n/a"
    if entry.label.Text ~= text then entry.label.Text = text end
end

function refreshInfos()
    for _, entry in ipairs(infoEntries) do
        if entry.label.Parent then updateInfoEntry(entry) end
    end
end

local function addInfo(title, getter)
    local row = newRow()
    local inner = newInner(row, true)
    makeLabel({
        Name = "Title", Text = title, TextSize = 14, Size = UDim2.new(0.42, -5, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, TextYAlignment = Enum.TextYAlignment.Center,
    }, inner)
    local valueLbl = makeLabel({
        Name = "Value", Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(0.58, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
        TextColor3 = COL.white, TextYAlignment = Enum.TextYAlignment.Center,
    }, inner)
    local entry = {label = valueLbl, getter = getter}
    infoEntries[#infoEntries + 1] = entry
    updateInfoEntry(entry)
end

-- body can be a string or a function returning a string (refreshed live)
local function addTextBlock(title, body)
    local row = newRow()
    local inner = newInner(row, false)
    makeLabel({
        Name = "Title", Text = title, Font = Enum.Font.GothamBold, TextSize = 15,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
    }, inner)
    local bodyLbl = makeLabel({
        Name = "Body", TextSize = 12, TextColor3 = COL.sub, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
    }, inner)
    if type(body) == "function" then
        local entry = {label = bodyLbl, getter = body}
        infoEntries[#infoEntries + 1] = entry
        updateInfoEntry(entry)
    else
        bodyLbl.Text = tostring(body)
    end
end

-- Tap to expand / collapse (Changelog, Credits)
local function addExpandRow(title, body)
    local row = newRow()
    local inner = newInner(row, false)
    local headerRow = make("Frame", {Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, BorderSizePixel = 0}, inner)
    makeLabel({
        Name = "Title", Text = title, Font = Enum.Font.GothamBold, TextSize = 15, TextWrapped = false,
        TextYAlignment = Enum.TextYAlignment.Center, Size = UDim2.new(0.8, 0, 1, 0),
    }, headerRow)
    local chevron = makeLabel({
        Name = "Chevron", Text = "+", Font = Enum.Font.GothamBlack, TextSize = 22, TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Center,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.2, 0, 1, 0),
    }, headerRow)
    local bodyLbl = makeLabel({
        Name = "Body", Text = body, TextSize = 13, TextColor3 = COL.sub, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Visible = false,
    }, inner)
    local hit = makeButton({Name = "Hit", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3}, row)
    addPressFeedback(hit, pageBag, row)
    pageBag.add(hit.MouseButton1Click:Connect(function()
        bodyLbl.Visible = not bodyLbl.Visible
        chevron.Text = bodyLbl.Visible and "-" or "+"
    end))
end

local function addKeyRow()
    local row = newRow()
    local inner = newInner(row, true)
    addTextPair(inner, "Change Toggle Key", "Tap the button, then press a key to show or hide Vortex. Esc cancels. Needs a keyboard.", -134, 1)
    local b = makeButton({
        Name = "KeyButton", LayoutOrder = 2, Size = UDim2.new(0, 124, 0, 44), Text = S.ToggleKey,
        BackgroundColor3 = COL.btn, TextSize = 13,
    }, inner)
    addCorner(b, 10)
    addStroke(b, Color3.fromRGB(110, 110, 116), 1, 0.3)
    addPressFeedback(b, pageBag)
    local function render()
        b.Text = listeningForKey and "Press a key..." or S.ToggleKey
    end
    controlSync.ToggleKey = render
    pageBag.add(b.MouseButton1Click:Connect(function()
        if not UIS.KeyboardEnabled then
            toast("No keyboard detected on this device")
            return
        end
        listeningForKey = not listeningForKey
        render()
    end))
end

local function addPreviewRow()
    local row = newRow()
    local inner = newInner(row, false)
    makeLabel({
        Name = "Title", Text = "Live UI Preview", Font = Enum.Font.GothamBold, TextSize = 15,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
    }, inner)
    local box = make("Frame", {
        Name = "PreviewBox", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 100),
        BackgroundColor3 = Color3.fromRGB(12, 12, 14), BorderSizePixel = 0, ClipsDescendants = true,
    }, inner)
    addCorner(box, 10)
    local card = make("CanvasGroup", {
        Name = "PreviewCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 170, 0, 52), BackgroundColor3 = Color3.fromRGB(34, 34, 38), BorderSizePixel = 0,
    }, box)
    addCorner(card, 14)
    addStroke(card, Color3.fromRGB(150, 150, 156), 1.5, 0.4)
    local cardScale = make("UIScale", {Scale = 1}, card)
    makeLabel({
        Text = "Vortex Card", Font = Enum.Font.GothamBold, TextSize = 16, TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    }, card)
    local hiddenLbl = makeLabel({
        Text = "Preview hidden by privacy settings", TextColor3 = COL.sub, Visible = false,
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    }, box)
    local note = makeLabel({
        Name = "Note", TextSize = 12, TextColor3 = COL.sub, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3,
    }, inner)
    local testBtn = makeButton({
        Name = "TestAnim", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 44), Text = "Play Animation", BackgroundColor3 = COL.btn,
    }, inner)
    addCorner(testBtn, 10)
    addStroke(testBtn, Color3.fromRGB(110, 110, 116), 1, 0.3)
    addPressFeedback(testBtn, pageBag)

    local function refresh(overrideScale)
        local hidden = isPreviewHidden()
        row.Visible = S.LivePreview
        card.Visible = not hidden
        hiddenLbl.Visible = hidden
        cardScale.Scale = overrideScale or S.UIScale
        card.GroupTransparency = S.UITransparency
        note.Text = string.format("Scale %d%%  |  Transparency %d%%  |  Speed %.1fx  |  Blur %s  |  Effects %s",
            math.floor(S.UIScale * 100 + 0.5), math.floor(S.UITransparency * 100 + 0.5), S.AnimationSpeed,
            S.BlurEffect and "On" or "Off", (S.ReduceVisualEffects or S.LowPerformanceMode) and "Reduced" or "Full")
    end
    previewRef = {refresh = refresh}
    refresh()

    pageBag.add(testBtn.MouseButton1Click:Connect(function()
        if isPreviewHidden() then
            toast("Preview is hidden by privacy settings")
            return
        end
        cardScale.Scale = S.UIScale * 0.8
        card.GroupTransparency = 0.8
        playTween(cardScale, {Scale = S.UIScale}, 0.4, Enum.EasingStyle.Back)
        playTween(card, {GroupTransparency = S.UITransparency}, 0.4)
    end))
end

local function addImportRow()
    local row = newRow()
    local inner = newInner(row, false)
    addTextPair(inner, "Import Configuration", "Paste exported configuration text below, then tap Import. Invalid values are ignored.", 0, 1)
    local box = make("TextBox", {
        Name = "ImportBox", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(12, 12, 14),
        BorderSizePixel = 0, ClearTextOnFocus = false, Text = "", PlaceholderText = "Paste configuration here",
        PlaceholderColor3 = COL.sub, TextColor3 = COL.text, Font = Enum.Font.GothamMedium, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, ClipsDescendants = true,
    }, inner)
    addCorner(box, 10)
    addPadding(box, 12, 0, 12, 0)
    addStroke(box, COL.rowStroke, 1, 0.2)
    importBoxRef = box
    local importBtn = makeButton({
        Name = "ImportButton", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 44), Text = "Import",
        BackgroundColor3 = COL.white, TextColor3 = COL.black,
    }, inner)
    addCorner(importBtn, 10)
    addPressFeedback(importBtn, pageBag)
    return importBtn, box
end

-- ---------- 12.9 Monitoring (FPS / memory / auto performance) ----------
local statsLabel = makeLabel({
    Name = "StatsOverlay", Position = UDim2.new(0, 40, 0, 178), Size = UDim2.new(0, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
    TextSize = 13, Font = Enum.Font.GothamBold, TextWrapped = false, TextYAlignment = Enum.TextYAlignment.Center,
    Visible = false, ZIndex = 4,
}, uiGui)
addCorner(statsLabel, 8)
addPadding(statsLabel, 10, 6, 10, 6)

local function getMemory()
    local clientMb, luaMb = 0, 0
    pcall(function() clientMb = Stats:GetTotalMemoryUsageMb() end)
    pcall(function() luaMb = collectgarbage("count") / 1024 end)
    return math.floor(clientMb + 0.5), math.floor(luaMb * 10 + 0.5) / 10
end

function updateStatsOverlay()
    local show = (S.FPSDisplay or S.MemoryDiagnostics) and not S.PrivacyMode
    if statsLabel.Visible ~= show then statsLabel.Visible = show end
    if not show then return end
    local text = ""
    if S.FPSDisplay then text = "FPS " .. (fpsKnown and tostring(fps) or "--") end
    if S.MemoryDiagnostics then
        local clientMb, luaMb = getMemory()
        if text ~= "" then text = text .. "  |  " end
        text = text .. "MEM " .. clientMb .. " MB  LUA " .. luaMb .. " MB"
    end
    if statsLabel.Text ~= text then statsLabel.Text = text end
end

local function autoAdjust()
    if fps < 28 then
        lowStreak = lowStreak + 1; highStreak = 0
    elseif fps >= 50 then
        highStreak = highStreak + 1; lowStreak = 0
    else
        lowStreak = 0; highStreak = 0
    end
    if lowStreak >= 4 and not S.LowPerformanceMode then
        autoLowApplied = true
        lowStreak = 0
        setSetting("LowPerformanceMode", true)
        syncControls()
        toast("Auto adjust: Low Performance Mode enabled")
    elseif autoLowApplied and S.LowPerformanceMode and highStreak >= 20 then
        autoLowApplied = false
        highStreak = 0
        setSetting("LowPerformanceMode", false)
        syncControls()
        toast("Auto adjust: performance recovered, Low Performance Mode off")
    end
end

local function onHeartbeat(dt)
    frameCount = frameCount + 1
    accum = accum + dt
    if accum < 0.5 then return end
    fps = math.floor(frameCount / accum + 0.5)
    fpsKnown = true
    frameCount, accum = 0, 0
    updateStatsOverlay()
    if S.AutoPerformanceAdjust then autoAdjust() end
    if panelOpen and (currentTab == "PERFORMANCE" or currentTab == "ADVANCED") then
        diagTick = diagTick + 1
        if diagTick >= 2 then
            diagTick = 0
            refreshInfos()
        end
    end
end

local function monitorNeeded()
    if S.FPSDisplay or S.MemoryDiagnostics or S.AutoPerformanceAdjust then return true end
    return panelOpen and (currentTab == "PERFORMANCE" or currentTab == "ADVANCED")
end

-- The Heartbeat connection exists ONLY while something needs it
function refreshMonitor()
    if not alive then return end
    if monitorNeeded() then
        if not monitorConn then
            frameCount, accum = 0, 0
            monitorConn = RunService.Heartbeat:Connect(onHeartbeat)
        end
    elseif monitorConn then
        monitorConn:Disconnect()
        monitorConn = nil
    end
end
cleanupTasks[#cleanupTasks + 1] = function()
    if monitorConn then
        monitorConn:Disconnect()
        monitorConn = nil
    end
end

-- ---------- 12.10 Info getters & configuration actions ----------
local function maskValue(v)
    if isSensitiveHidden() then return "********" end
    return tostring(v)
end

local function getExecutorName()
    local name = "Unknown"
    if type(identifyexecutor) == "function" then
        pcall(function() name = tostring((identifyexecutor())) end)
    end
    return name
end

local function getPing()
    local ping = "n/a"
    pcall(function()
        ping = string.format("%d ms", math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5))
    end)
    return ping
end

local function getRobloxConnection()
    local lp = Players.LocalPlayer
    if lp and lp.Parent == Players then return "Connected" end
    return "Disconnected"
end

local function countConnected(bag)
    local n = 0
    for _, c in ipairs(bag.list) do
        if c.Connected then n = n + 1 end
    end
    return n
end

local function countTweens()
    local n = 0
    for _ in pairs(liveTweens) do n = n + 1 end
    return n
end

local function countInstances()
    local n = 0
    pcall(function() n = #uiGui:GetDescendants() + #mainGui:GetDescendants() end)
    return n
end

local function formatUptime()
    local total = math.floor(os.clock() - startClock)
    return string.format("%02d:%02d:%02d", math.floor(total / 3600), math.floor((total % 3600) / 60), total % 60)
end

local function testHttp()
    httpStatus = "Testing..."
    refreshInfos()
    task.spawn(function()
        local ok, res = pcall(function() return game:HttpGet("https://example.com") end)
        if not alive then return end
        if ok and type(res) == "string" and #res > 0 then
            httpStatus = "Online (HTTP OK)"
        else
            httpStatus = "Failed"
            logError("HTTP test", res)
        end
        refreshInfos()
    end)
end

function syncControls()
    for _, fn in pairs(controlSync) do pcall(fn) end
end

local function describeApply(count)
    return "Applied " .. count .. " setting" .. (count == 1 and "" or "s")
end

local function scheduleAutoSave()
    if not S.AutoSave or saveScheduled then return end
    saveScheduled = true
    task.delay(0.6, function()
        saveScheduled = false
        if alive and S.AutoSave then saveConfig() end
    end)
end

local function applyJsonText(text, sourceLabel)
    local ok, decoded = pcall(function() return HttpService:JSONDecode(text) end)
    if not ok or type(decoded) ~= "table" then
        logError(sourceLabel, "Invalid configuration data")
        toast("Invalid configuration data")
        return false
    end
    local count = applyDecoded(decoded)
    if count == 0 then
        toast("No valid settings found")
        return false
    end
    applyAllSettings()
    syncControls()
    refreshInfos()
    scheduleAutoSave()
    toast(sourceLabel .. ": " .. describeApply(count))
    return true
end

local function actionSave()
    local ok, msg = saveConfig()
    toast(msg)
    return ok
end

local function actionLoad()
    local raw = readStoredConfig()
    if not raw then
        toast("No saved configuration found")
        return
    end
    applyJsonText(raw, "Loaded")
end

local function actionExport()
    local okEnc, json = pcall(serializeSettings)
    if not okEnc then
        logError("Export", json)
        toast("Could not export settings")
        return
    end
    if copyToClipboard(json) then
        toast("Configuration copied to clipboard")
    else
        if importBoxRef then importBoxRef.Text = json end
        toast("Clipboard unavailable: configuration placed in the box")
    end
end

local function actionImport(text)
    text = string.gsub(text or "", "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then
        toast("Paste a configuration first")
        return
    end
    applyJsonText(text, "Imported")
end

local function performReset(wipeStorage)
    resetSettingsToDefaults()
    autoLowApplied = false
    if wipeStorage then deleteStoredConfig() end
    applyAllSettings()
    syncControls()
    refreshInfos()
    if wipeStorage then
        toast("All settings reset and saved configuration deleted")
    else
        scheduleAutoSave()
        toast("Defaults restored")
    end
end

local function requestReset(wipeStorage)
    local function go() performReset(wipeStorage) end
    if S.ConfirmBeforeReset then
        if wipeStorage then
            confirm("Reset all settings?", "Every setting returns to its default and the saved configuration is deleted.", "Reset", go)
        else
            confirm("Restore defaults?", "Every setting returns to its default value.", "Restore", go)
        end
    else
        go()
    end
end

local function cleanTemporaryObjects()
    local removed = 0
    local errGui = parent:FindFirstChild("VortexError")
    if errGui then errGui:Destroy(); removed = removed + 1 end
    toastLabel.Visible = false
    closeConfirm()
    local before = select(1, getMemory())
    pcall(function() collectgarbage("collect") end)
    local after = select(1, getMemory())
    refreshInfos()
    toast("Cleanup done. Removed " .. removed .. " temporary object(s), freed about " .. math.max(0, before - after) .. " MB")
end

-- ---------- 12.11 Pages ----------
local function pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
local function times(v) return string.format("%.1fx", v) end

local Pages = {}

Pages.GENERAL = function()
    addSection("GENERAL")
    addToggle("AutoSave", "Auto Save Settings", "Saves your settings automatically a moment after every change.")
    addToggle("RememberLastTab", "Remember Last Tab", "Reopen Settings on the page you used last.")
    addToggle("OpenOnExecution", "Open UI on Execution", "When off, Vortex starts hidden. Use the menu or the toggle key to show it.")
    addToggle("ConfirmBeforeReset", "Confirm Before Reset", "Ask for confirmation before resetting or restoring defaults.")
    addButton("Reset All Settings", "Restores every setting and deletes the saved configuration.", "Reset", function() requestReset(true) end, "dark")
end

Pages.APPEARANCE = function()
    addSection("APPEARANCE")
    addSlider("UIScale", "UI Scale", "Scales the Settings window and the dropdown menu.", pct, true)
    addSlider("UITransparency", "UI Transparency", "Makes the Settings window, menu and buttons more see-through.", pct)
    addSlider("AnimationSpeed", "Animation Speed", "Speed of every interface animation.", times)
    addToggle("BlurEffect", "Blur Effect", "Background blur and depth of field while the hub is visible.")
    addToggle("ReduceVisualEffects", "Reduce Visual Effects", "Flat background, lighter blur and no color grading.")
    addToggle("LivePreview", "Live UI Preview", "Show a preview that reacts to the settings above.")
    addPreviewRow()
end

Pages.PERFORMANCE = function()
    addSection("PERFORMANCE")
    addToggle("LowPerformanceMode", "Low Performance Mode", "Turns off blur and color effects and updates the game list without tweens.")
    addToggle("ReduceUIAnimations", "Reduce UI Animations", "Makes every interface animation almost instant.")
    addToggle("UIOptimization", "UI Optimization", "Hides game cards far from the center to save rendering work.")
    addToggle("FPSDisplay", "FPS Display", "Shows a small FPS counter on screen.")
    addToggle("MemoryDiagnostics", "Memory Diagnostics", "Adds client and script memory to the counter.")
    addToggle("AutoPerformanceAdjust", "Automatic Performance Adjustment", "Enables Low Performance Mode when FPS stays low and disables it again when FPS recovers.")
    addInfo("Current FPS", function() return fpsKnown and tostring(fps) or "measuring..." end)
    addInfo("Memory (client / script)", function()
        local clientMb, luaMb = getMemory()
        return clientMb .. " MB / " .. luaMb .. " MB"
    end)
end

Pages.PRIVACY = function()
    addSection("PRIVACY")
    addToggle("PrivacyMode", "Privacy Mode", "Master switch: hides sensitive information, the preview and the FPS overlay.")
    addToggle("HideSensitive", "Hide Sensitive Information", "Masks username, IDs and server info inside Vortex.")
    addToggle("HidePreview", "Hide UI Preview", "Never shows the Live UI Preview.")
    addInfo("Sensitive info", function() return isSensitiveHidden() and "Hidden" or "Visible" end)
    addInfo("UI preview", function() return (isPreviewHidden() or not S.LivePreview) and "Hidden" or "Visible" end)
end

Pages.CONTROLS = function()
    addSection("CONTROLS")
    addKeyRow()
    addSlider("TouchSensitivity", "Touch Control Sensitivity", "Swipe speed of the game list.", times)
    addSlider("DragSensitivity", "Drag Sensitivity", "Swipe speed of this Settings page.", times)
    addSlider("MobileButtonSize", "Mobile Button Size", "Size of the hamburger button, the Run button and menu items.", pct)
    addToggle("TouchFeedback", "Touch Feedback", "Buttons light up briefly while pressed.")
end

Pages.CONFIGURATION = function()
    addSection("CONFIGURATION")
    addButton("Save Configuration", "Writes your settings to storage now.", "Save", actionSave)
    addButton("Load Configuration", "Loads the last saved configuration.", "Load", actionLoad)
    addButton("Export Configuration", "Copies your settings to the clipboard.", "Export", actionExport)
    local importBtn, importBox = addImportRow()
    pageBag.add(importBtn.MouseButton1Click:Connect(function() actionImport(importBox.Text) end))
    addButton("Restore Defaults", "Returns every setting to its default value.", "Restore", function() requestReset(false) end, "dark")
    addInfo("Storage", function() return canUseFiles() and "File" or "Memory only" end)
end

Pages.ADVANCED = function()
    addSection("UI DIAGNOSTICS")
    addInfo("FPS", function() return fpsKnown and tostring(fps) or "measuring..." end)
    addInfo("UI instances", countInstances)
    addInfo("Active tweens", countTweens)
    addInfo("Active connections", function() return countConnected(mainBag) + countConnected(pageBag) + (monitorConn and 1 or 0) end)
    addInfo("Effects", function()
        return (blur.Enabled and "Blur on" or "Blur off") .. ", " .. ((S.ReduceVisualEffects or S.LowPerformanceMode) and "reduced" or "full")
    end)

    addSection("ERROR INFORMATION")
    addInfo("Logged errors", function() return #errorLog end)
    addTextBlock("Recent errors", function()
        if #errorLog == 0 then return "No errors logged this session." end
        local lines = {}
        for i = math.max(1, #errorLog - 5), #errorLog do
            lines[#lines + 1] = string.sub(errorLog[i], 1, 110)
        end
        return table.concat(lines, "\n")
    end)
    addButton("Copy Error Log", "Copies the full error log to the clipboard.", "Copy", function()
        if #errorLog == 0 then toast("Nothing to copy"); return end
        if copyToClipboard(table.concat(errorLog, "\n")) then toast("Error log copied") else toast("Clipboard unavailable") end
    end)
    addButton("Clear Error Log", "Removes all stored error messages.", "Clear", function()
        table.clear(errorLog)
        refreshInfos()
        toast("Error log cleared")
    end, "dark")

    addSection("CONNECTION STATUS")
    addInfo("Roblox session", getRobloxConnection)
    addInfo("Server ping", getPing)
    addInfo("HTTP access", function() return httpStatus end)
    addButton("Test Connection", "Sends a small HTTP request to check internet access.", "Test", testHttp)

    addSection("SESSION INFORMATION")
    addInfo("Username", function() local lp = Players.LocalPlayer; return maskValue(lp and lp.Name or "n/a") end)
    addInfo("User ID", function() local lp = Players.LocalPlayer; return maskValue(lp and lp.UserId or "n/a") end)
    addInfo("Place ID", function() return maskValue(game.PlaceId) end)
    addInfo("Job ID", function() return maskValue(game.JobId ~= "" and game.JobId or "none") end)
    addInfo("Executor", getExecutorName)
    addInfo("Session uptime", formatUptime)

    addSection("INTERFACE LIFECYCLE")
    addInfo("Hub", function() return hubVisible and "Visible" or "Hidden" end)
    local visBtn
    visBtn = addButton("Hub Visibility", "Show or hide the hub. The hamburger button always stays available.", hubVisible and "Hide" or "Show", function(b)
        setHubVisible(not hubVisible)
        b.Text = hubVisible and "Hide" or "Show"
        refreshInfos()
    end)
    addButton("Refresh Interface", "Re-applies every setting and the layout.", "Refresh", function()
        applyAllSettings()
        layoutPanel()
        syncControls()
        refreshInfos()
        toast("Interface refreshed")
    end)
    addButton("Clean Temporary Objects", "Removes leftover temporary UI and frees memory.", "Clean", cleanTemporaryObjects)
    addButton("Destroy Vortex", "Removes the interface, disconnects everything and restores the Roblox UI.", "Destroy", function()
        confirm("Destroy Vortex?", "The interface and all Vortex tasks will be removed.", "Destroy", closeVortex)
    end, "dark")
end

Pages.ABOUT = function()
    addSection("ABOUT")
    addInfo("Vortex Version", function() return "v" .. VERSION end)
    addInfo("Developer", function() return "codeR" end)
    addExpandRow("Changelog",
        "v2.0.0\n- Top hamburger dropdown menu\n- Complete Settings control center with 8 categories\n- Save, load, export and import configuration\n- FPS, memory and connection diagnostics\n- Automatic performance adjustment\n- Mobile-first layout and touch tuning\n- Safe cleanup of every connection and instance\n\nv1.0.0\n- Game cards, smart search, Run button and animations")
    addExpandRow("Credits",
        "Vortex Hub by codeR.\nSettings system, dropdown menu and diagnostics engineered on Roblox TweenService, UserInputService and RunService.\nThank you for using Vortex.")
end

-- ---------- 12.12 Opening / closing / switching ----------
local function clearPage()
    pageBag.clear()
    activeDrag = nil
    content.ScrollingEnabled = true
    listeningForKey = false
    previewRef = nil
    importBoxRef = nil
    table.clear(infoEntries)
    table.clear(controlSync)
    for _, child in ipairs(content:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    rowOrder = 0
end

function showTab(id, silent)
    if not isValidTab(id) then id = "GENERAL" end
    currentTab = id
    for tid, b in pairs(tabButtons) do
        local active = (tid == id)
        b.BackgroundColor3 = active and COL.white or TAB_IDLE_BG
        b.TextColor3 = active and COL.black or TAB_IDLE_TEXT
    end
    clearPage()
    local ok, err = pcall(Pages[id])
    if not ok then
        logError("Page " .. id, err)
        addTextBlock("Page error", "This page failed to load: " .. tostring(err))
    end
    content.CanvasPosition = Vector2.new(0, 0)

    pcall(function()
        local btn = tabButtons[id]
        local rel = btn.AbsolutePosition.X - tabsFrame.AbsolutePosition.X + tabsFrame.CanvasPosition.X
        local maxX = math.max(0, tabsFrame.AbsoluteCanvasSize.X - tabsFrame.AbsoluteWindowSize.X)
        playTween(tabsFrame, {CanvasPosition = Vector2.new(math.clamp(rel - 12, 0, maxX), 0)}, 0.2)
    end)

    refreshMonitor()
    if not silent then setSetting("LastTab", id) end
end

function openSettings(tabId)
    if not alive then return end
    closeMenu()
    if panelOpen then
        if tabId then showTab(tabId) end
        return
    end
    panelOpen = true
    layoutPanel()
    dim.Visible = true
    panel.Visible = true
    panel.GroupTransparency = 1
    panelScale.Scale = S.UIScale * 0.94
    dim.BackgroundTransparency = 1
    playTween(dim, {BackgroundTransparency = 0.5}, 0.25)
    playTween(panel, {GroupTransparency = S.UITransparency}, 0.25)
    playTween(panelScale, {Scale = S.UIScale}, 0.3)
    local startTab = tabId
    if not startTab then
        startTab = S.RememberLastTab and S.LastTab or "GENERAL"
    end
    showTab(startTab, true)
end

function closeSettings()
    if not panelOpen then return end
    panelOpen = false
    activeDrag = nil
    listeningForKey = false
    content.ScrollingEnabled = true
    playTween(dim, {BackgroundTransparency = 1}, 0.2)
    playTween(panelScale, {Scale = S.UIScale * 0.94}, 0.2)
    playTween(panel, {GroupTransparency = 1}, 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In, function()
        if alive and not panelOpen then
            panel.Visible = false
            dim.Visible = false
            clearPage()   -- frees every row instance and page connection
            refreshMonitor()
        end
    end)
    refreshMonitor()
end

track(closeBtn.MouseButton1Click:Connect(closeSettings))
track(dim.MouseButton1Click:Connect(closeSettings))

-- ---------- 12.13 Appliers (setting -> real effect) ----------
local function applyScaleAndSize()
    hamburgerScale.Scale = S.MobileButtonSize
    runScale.Scale = S.MobileButtonSize
    menuScale.Scale = S.UIScale
    layoutPanel()
end

local function applyTransparency()
    local t = S.UITransparency
    hamburger.BackgroundTransparency = math.clamp(0.15 + t, 0, 1)
    runBtn.BackgroundTransparency = math.clamp(runBaseTransparency + t, 0, 1)
    searchBar.BackgroundTransparency = math.clamp(searchBaseTransparency + t, 0, 1)
    if panelOpen then panel.GroupTransparency = t end
    if menuOpen then menuGroup.GroupTransparency = t end
    if previewRef then previewRef.refresh() end
end

local function applyPrivacy()
    updateStatsOverlay()
    if previewRef then previewRef.refresh() end
    refreshInfos()
end

local function applyMonitor()
    refreshMonitor()
    updateStatsOverlay()
end

local function refreshPreview()
    if previewRef then previewRef.refresh() end
end

local appliers = {
    UIScale = function() applyScaleAndSize(); refreshPreview() end,
    MobileButtonSize = applyScaleAndSize,
    UITransparency = applyTransparency,
    AnimationSpeed = refreshPreview,
    BlurEffect = function() applyEffects(); refreshPreview() end,
    ReduceVisualEffects = function() applyEffects(); refreshPreview() end,
    LivePreview = refreshPreview,
    LowPerformanceMode = function() applyEffects(); applyPerf(); refreshPreview() end,
    UIOptimization = applyPerf,
    FPSDisplay = applyMonitor,
    MemoryDiagnostics = applyMonitor,
    AutoPerformanceAdjust = function()
        lowStreak, highStreak = 0, 0
        applyMonitor()
    end,
    PrivacyMode = applyPrivacy,
    HideSensitive = applyPrivacy,
    HidePreview = applyPrivacy,
}

function applyAllSettings()
    applyScaleAndSize()
    applyTransparency()
    applyEffects()
    applyPerf()
    applyMonitor()
    applyPrivacy()
end

-- Single entry point for changing a setting from the UI
function setSetting(key, value)
    local v = sanitizeValue(key, value)
    if v == nil then return false end
    if S[key] == v then return true end
    S[key] = v
    local fn = appliers[key]
    if fn then
        local ok, err = pcall(fn)
        if not ok then logError("Apply " .. key, err) end
    end
    if key == "AutoSave" then
        saveConfig()
    else
        scheduleAutoSave()
    end
    return true
end

-- ---------- 12.14 Global input (ONE connection per event, no duplicates) ----------
local function endDrag()
    local drag = activeDrag
    activeDrag = nil
    content.ScrollingEnabled = true
    if drag and drag.commit then
        local ok, err = pcall(drag.commit)
        if not ok then logError("Slider commit", err) end
    end
end

track(UIS.InputChanged:Connect(function(input)
    if not activeDrag then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or (input.UserInputType == Enum.UserInputType.Touch and input == activeDrag.input) then
        activeDrag.update(input.Position.X)
    end
end))

track(UIS.InputEnded:Connect(function(input)
    if activeDrag and (input.UserInputType == Enum.UserInputType.MouseButton1 or input == activeDrag.input) then
        endDrag()
    end
end))

track(UIS.InputBegan:Connect(function(input, gameProcessed)
    if listeningForKey then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            listeningForKey = false
            if input.KeyCode ~= Enum.KeyCode.Escape then
                setSetting("ToggleKey", input.KeyCode.Name)
                toast("Toggle key set to " .. input.KeyCode.Name)
            end
            if controlSync.ToggleKey then controlSync.ToggleKey() end
        end
        return
    end
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == S.ToggleKey then
        setHubVisible(not hubVisible)
    end
end))

-- Keep everything inside the screen when the viewport changes (rotation, resize)
track(uiGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    layoutPanel()
    if menuOpen then closeMenu() end
end))

-- =========================================================
-- 13. STARTUP: apply saved settings to the whole interface
-- =========================================================
applyAllSettings()
if not S.OpenOnExecution then
    setHubVisible(false)
end
