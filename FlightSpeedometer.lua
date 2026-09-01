-- Flight Speedometer
-- Converts GetUnitSpeed() (WoW yards/second) into real-world km/h or mph
-- and shows it while you are flying.

local ADDON_NAME = ...

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- 1 yard = 0.9144 m, so yards/sec -> km/h is (* 0.9144 * 3.6)
local YD_TO_KMH      = 0.9144 * 3.6   -- 3.29184
local YD_TO_MPH      = 3600 / 1760    -- 2.0454545 (1 mile = 1760 yards)
local BASE_RUN_SPEED = 7              -- yards/sec == "100% speed" in WoW

local UPDATE_INTERVAL = 0.05          -- seconds between refreshes
local SMOOTH_WINDOW   = 0.15          -- seconds for the display to catch up

local PREFIX = "|cff33ccffFlight Speedometer:|r "

--------------------------------------------------------------------------------
-- Saved settings
--------------------------------------------------------------------------------

local defaults = {
    unit        = "kmh",   -- "kmh" or "mph"
    locked      = false,
    showAlways  = false,   -- show on the ground too
    showPercent = true,
    showMax     = true,
    smooth      = true,
    scale       = 1,
    point       = "CENTER",
    relPoint    = "CENTER",
    x           = 0,
    y           = -160,
    best        = 0,       -- personal best, in yards/sec
}

local db
local displaySpeed = 0     -- smoothed value, yards/sec
local sessionMax   = 0     -- yards/sec

local OpenOptions          -- filled in once the options panel is built

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Convert(yps)
    if db.unit == "mph" then
        return yps * YD_TO_MPH
    end
    return yps * YD_TO_KMH
end

local function UnitLabel()
    return (db.unit == "mph") and "mph" or "km/h"
end

-- White at normal run speed, warming to gold and then orange-red as you go faster.
local function SpeedColor(pct)
    if pct <= 100 then
        return 1, 1, 1
    elseif pct <= 400 then
        local t = (pct - 100) / 300
        return 1, 1 - 0.18 * t, 1 - 0.75 * t
    elseif pct < 800 then
        local t = (pct - 400) / 400
        return 1, 0.82 - 0.47 * t, 0.25
    end
    return 1, 0.35, 0.25
end

-- GetUnitSpeed reports 0 while skyriding, so the glide velocity has to come
-- from GetGlidingInfo's third return instead. That value is also yards/sec:
-- roughly 65 at max dive, up to about 100 with abilities.
-- Returns: speed in yards/sec, and whether the player is currently gliding.
local function GetPlayerSpeed()
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
        if isGliding and forwardSpeed then
            return forwardSpeed, true
        end
    end
    return GetUnitSpeed("player"), false
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

--------------------------------------------------------------------------------
-- Display frame
--------------------------------------------------------------------------------

local fontPath = GameFontNormal:GetFont()

local f = CreateFrame("Frame", "FlightSpeedometerFrame", UIParent)
f:SetSize(160, 48)
f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:Hide()

local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.45)

local speedText = f:CreateFontString(nil, "OVERLAY")
speedText:SetFont(fontPath, 22, "OUTLINE")
speedText:SetPoint("TOP", f, "TOP", 0, -5)
speedText:SetText("0.0 km/h")

local subText = f:CreateFontString(nil, "OVERLAY")
subText:SetFont(fontPath, 11, "OUTLINE")
subText:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
subText:SetTextColor(0.75, 0.75, 0.75)

f:SetScript("OnDragStart", function(self)
    if not db.locked then self:StartMoving() end
end)

f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end)

f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and OpenOptions then
        OpenOptions()
    end
end)

f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Flight Speedometer")
    GameTooltip:AddLine(string.format("Personal best: %.1f %s", Convert(db.best), UnitLabel()), 1, 1, 1)
    GameTooltip:AddLine(db.locked and "Locked - unlock in the options to move" or "Drag to move", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

f:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ApplySettings()
    f:ClearAllPoints()
    f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    f:SetScale(db.scale)
end

--------------------------------------------------------------------------------
-- Options panel (Game Menu -> Options -> AddOns)
--------------------------------------------------------------------------------

local refreshers = {}      -- widgets that need their state pushed from db
local checkCount = 0

local function AddHeader(panel, text, x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    fs:SetText(text)

    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", panel, "RIGHT", -30, 0)

    return fs
end

local function AddCheckbox(panel, x, y, label, tooltip, get, set)
    checkCount = checkCount + 1

    local cb = CreateFrame("CheckButton", "FlightSpeedometerCheck" .. checkCount, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)

    -- UICheckButtonTemplate ships its own label as parentKey "Text"
    -- (GameFontNormalSmall); widen it to the standard white options font.
    cb.Text:SetFontObject(GameFontHighlight)
    cb.Text:SetText(label)

    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)

    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(label)
        if tooltip then
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    table.insert(refreshers, function() cb:SetChecked(get()) end)

    return cb
end

local function AddButton(panel, x, y, width, label, tooltip, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)

    if tooltip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return b
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "FlightSpeedometerOptionsPanel", UIParent)
    panel.name = "Flight Speedometer"
    panel:SetSize(600, 500)
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Flight Speedometer")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -30, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    subtitle:SetText("Shows your speed in real-world units while flying. Base run speed (100%) is 23.0 km/h.")

    local y = -80

    AddHeader(panel, "Units", 16, y)
    y = y - 26

    AddCheckbox(panel, 16, y,
        "Use mph instead of km/h",
        "Miles per hour rather than kilometres per hour.",
        function() return db.unit == "mph" end,
        function(v) db.unit = v and "mph" or "kmh" end)
    y = y - 40

    AddHeader(panel, "Display", 16, y)
    y = y - 26

    AddCheckbox(panel, 16, y,
        "Show percentage of base speed",
        "Adds your speed as a percentage of normal run speed (7 yards/sec = 100%).",
        function() return db.showPercent end,
        function(v) db.showPercent = v end)
    y = y - 28

    AddCheckbox(panel, 16, y,
        "Show session maximum",
        "Tracks the fastest speed reached since you logged in.",
        function() return db.showMax end,
        function(v) db.showMax = v end)
    y = y - 28

    AddCheckbox(panel, 16, y,
        "Smooth the readout",
        "Eases the number between updates so it does not jitter during hard accelerations.",
        function() return db.smooth end,
        function(v) db.smooth = v end)
    y = y - 28

    AddCheckbox(panel, 16, y,
        "Always show, even on the ground",
        "Normally the display only appears while flying, gliding, or on a flight path.",
        function() return db.showAlways end,
        function(v) db.showAlways = v end)
    y = y - 28

    AddCheckbox(panel, 16, y,
        "Lock in place",
        "Prevents the display from being dragged with the mouse.",
        function() return db.locked end,
        function(v) db.locked = v end)
    y = y - 44

    AddHeader(panel, "Size and position", 16, y)
    y = y - 30

    local scaleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    scaleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 4)

    local function UpdateScaleLabel()
        scaleLabel:SetText(string.format("Scale: %.2f", db.scale))
    end

    local function StepScale(delta)
        local n = math.max(0.5, math.min(3, db.scale + delta))
        db.scale = math.floor(n * 100 + 0.5) / 100
        ApplySettings()
        UpdateScaleLabel()
    end

    AddButton(panel, 110, y, 30, "-", "Make the display smaller.", function() StepScale(-0.05) end)
    AddButton(panel, 144, y, 30, "+", "Make the display larger.", function() StepScale(0.05) end)
    AddButton(panel, 184, y, 100, "Reset", "Return the display to its default size and position.", function()
        db.scale = 1
        db.point, db.relPoint, db.x, db.y = "CENTER", "CENTER", 0, -160
        ApplySettings()
        UpdateScaleLabel()
    end)

    table.insert(refreshers, UpdateScaleLabel)
    y = y - 44

    AddHeader(panel, "Records", 16, y)
    y = y - 30

    local bestLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    bestLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 4)

    local function UpdateBestLabel()
        bestLabel:SetText(string.format("Personal best: |cffffd100%.1f %s|r", Convert(db.best), UnitLabel()))
    end

    AddButton(panel, 220, y, 120, "Clear records", "Resets both the session maximum and your personal best.", function()
        sessionMax, db.best = 0, 0
        UpdateBestLabel()
    end)

    table.insert(refreshers, UpdateBestLabel)
    y = y - 44

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
    hint:SetText("Tip: right-click the speedometer to reopen this panel, or type /fspeed.")

    local function Refresh()
        for _, fn in ipairs(refreshers) do
            fn()
        end
    end

    panel:SetScript("OnShow", Refresh)

    -- The Settings canvas API calls these if they exist.
    panel.OnRefresh = Refresh
    panel.OnCommit  = function() end
    panel.OnDefault = function() end

    -- Register: modern Settings API first, legacy interface options as a fallback.
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        -- Keep the auto-assigned numeric ID: SettingsCategoryListMixin:GetCategory
        -- matches on category:GetID() at lookup time, so overwriting it only risks
        -- colliding with another addon that hardcodes the same string.
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)

        OpenOptions = function()
            if Settings.OpenToCategory then
                Settings.OpenToCategory(category:GetID())
            end
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)

        OpenOptions = function()
            -- Called twice on purpose: a long-standing quirk of the old panel.
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    end
end

--------------------------------------------------------------------------------
-- Update loop
-- The driver frame is unparented and always shown, so OnUpdate keeps running
-- even while the readout itself is hidden on the ground.
--------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local accum = 0

driver:SetScript("OnUpdate", function(_, elapsed)
    if not db then return end

    accum = accum + elapsed
    if accum < UPDATE_INTERVAL then return end
    local dt = accum
    accum = 0

    -- One GetGlidingInfo call serves both the speed and the airborne test.
    local yps, gliding = GetPlayerSpeed()
    local airborne = gliding or IsFlying() or UnitOnTaxi("player")

    if not (airborne or db.showAlways) then
        if f:IsShown() then f:Hide() end
        displaySpeed = 0
        return
    end

    -- Track the max whenever the readout is live, ground speed included:
    -- gating this on `airborne` left it reading 0 while showing a real speed.
    if yps > sessionMax then sessionMax = yps end
    if yps > db.best then db.best = yps end

    if db.smooth then
        displaySpeed = displaySpeed + (yps - displaySpeed) * math.min(1, dt / SMOOTH_WINDOW)
    else
        displaySpeed = yps
    end

    local pct = displaySpeed / BASE_RUN_SPEED * 100

    speedText:SetFormattedText("%.1f %s", Convert(displaySpeed), UnitLabel())
    speedText:SetTextColor(SpeedColor(pct))

    if db.showPercent or db.showMax then
        local line = ""
        if db.showPercent then
            line = string.format("%d%%", math.floor(pct + 0.5))
        end
        if db.showMax then
            if line ~= "" then line = line .. "   " end
            line = line .. string.format("max %.1f", Convert(sessionMax))
        end
        subText:SetText(line)
    else
        subText:SetText("")
    end

    if not f:IsShown() then f:Show() end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function ShowHelp()
    Print("commands:")
    Print("  |cffffd100config|r - open the options panel")
    Print("  |cffffd100kmh|r / |cffffd100mph|r / |cffffd100toggle|r - change units")
    Print("  |cffffd100lock|r / |cffffd100unlock|r - allow dragging the display")
    Print("  |cffffd100always|r - also show speed on the ground")
    Print("  |cffffd100percent|r - toggle the % of base speed line")
    Print("  |cffffd100max|r - toggle the max speed line")
    Print("  |cffffd100smooth|r - toggle smoothing of the number")
    Print("  |cffffd100scale <n>|r - set display scale, e.g. scale 1.2")
    Print("  |cffffd100reset|r - restore the default size and position")
    Print("  |cffffd100clear|r - clear session max and personal best")
end

SLASH_FLIGHTSPEEDOMETER1 = "/fspeed"
SLASH_FLIGHTSPEEDOMETER2 = "/flightspeed"

SlashCmdList["FLIGHTSPEEDOMETER"] = function(msg)
    local cmd, arg = string.match(string.lower(msg or ""), "^%s*(%S*)%s*(.-)%s*$")

    if cmd == "" or cmd == "config" or cmd == "options" or cmd == "opt" then
        if OpenOptions then
            OpenOptions()
        else
            ShowHelp()
        end
    elseif cmd == "kmh" or cmd == "km" then
        db.unit = "kmh"
        Print("units set to km/h.")
    elseif cmd == "mph" or cmd == "mi" then
        db.unit = "mph"
        Print("units set to mph.")
    elseif cmd == "toggle" or cmd == "unit" or cmd == "units" then
        db.unit = (db.unit == "kmh") and "mph" or "kmh"
        Print("units set to " .. UnitLabel() .. ".")
    elseif cmd == "lock" then
        db.locked = true
        Print("display locked.")
    elseif cmd == "unlock" then
        db.locked = false
        Print("display unlocked - drag it with the left mouse button.")
    elseif cmd == "always" then
        db.showAlways = not db.showAlways
        Print(db.showAlways and "showing speed at all times." or "showing speed only while flying.")
    elseif cmd == "percent" then
        db.showPercent = not db.showPercent
        Print("percent line " .. (db.showPercent and "on." or "off."))
    elseif cmd == "max" then
        db.showMax = not db.showMax
        Print("max line " .. (db.showMax and "on." or "off."))
    elseif cmd == "smooth" then
        db.smooth = not db.smooth
        Print("smoothing " .. (db.smooth and "on." or "off."))
    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 3 then
            db.scale = n
            ApplySettings()
            Print(string.format("scale set to %.2f.", n))
        else
            Print("usage: /fspeed scale <0.5 - 3>")
        end
    elseif cmd == "reset" then
        -- Matches the options panel's Reset button: size and position both.
        db.scale = 1
        db.point, db.relPoint, db.x, db.y = "CENTER", "CENTER", 0, -160
        ApplySettings()
        Print("size and position reset.")
    elseif cmd == "clear" then
        sessionMax, db.best = 0, 0
        Print("max speed records cleared.")
    else
        ShowHelp()
    end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end

    FlightSpeedometerDB = FlightSpeedometerDB or {}
    db = FlightSpeedometerDB
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end

    ApplySettings()
    CreateOptionsPanel()

    self:UnregisterEvent("ADDON_LOADED")
end)
