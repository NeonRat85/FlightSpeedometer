-- Minimal WoW API stub so the addon can actually be executed and driven.
-- Not a fidelity emulator: just enough surface to catch runtime errors,
-- nil indexing, and wrong arithmetic in the addon's own logic.

local ADDON_PATH = ...
assert(ADDON_PATH, "usage: luajit harness.lua <path to FlightSpeedometer.lua>")

local failures, checks = 0, 0
local function check(label, got, want)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL  %s\n          got:  %s\n          want: %s",
            label, tostring(got), tostring(want)))
    else
        print(string.format("  ok    %s  (%s)", label, tostring(got)))
    end
end

--------------------------------------------------------------------------------
-- Widget mocks
--------------------------------------------------------------------------------

local framesByName, allFrames = {}, {}

local function newRegion(kind)
    local r = { __kind = kind, _text = "" }
    function r:SetText(t) self._text = tostring(t or "") end
    function r:GetText() return self._text end
    function r:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
    function r:SetFontObject(o) self._fontObject = o end
    function r:SetFont(p, s, fl) self._font = { p, s, fl } end
    setmetatable(r, { __index = function(t, k)
        local f = function() return t end
        rawset(t, k, f); return f
    end })
    return r
end

local function newFrame(kind, name, parent, template)
    local fr = {
        __kind = kind, __name = name, __template = template,
        _scripts = {}, _shown = true, _checked = false,
        _fontstrings = {}, _textures = {}, _events = {},
    }

    function fr:SetScript(h, fn) self._scripts[h] = fn end
    function fr:GetScript(h) return self._scripts[h] end
    function fr:HookScript(h, fn) self._scripts[h] = fn end
    function fr:Show() self._shown = true end
    function fr:Hide() self._shown = false end
    function fr:IsShown() return self._shown end
    function fr:SetChecked(v) self._checked = v and true or false end
    function fr:GetChecked() return self._checked end
    function fr:RegisterEvent(e) self._events[e] = true end
    function fr:UnregisterEvent(e) self._events[e] = nil end
    function fr:GetPoint() return "CENTER", UIParent, "CENTER", 0, -160 end
    function fr:SetText(t) self._text = tostring(t or "") end
    function fr:GetText() return self._text end
    function fr:CreateFontString(n, layer, tmpl)
        local fs = newRegion("FontString"); fs._template = tmpl
        table.insert(self._fontstrings, fs); return fs
    end
    function fr:CreateTexture(n, layer)
        local tx = newRegion("Texture")
        table.insert(self._textures, tx); return tx
    end

    setmetatable(fr, { __index = function(t, k)
        local f = function() return t end
        rawset(t, k, f); return f
    end })

    -- UICheckButtonTemplate ships a parentKey="Text" FontString.
    if template and template:find("CheckButton") then
        fr.Text = newRegion("FontString")
    end

    if name then framesByName[name] = fr end
    table.insert(allFrames, fr)
    return fr
end

--------------------------------------------------------------------------------
-- Globals the addon touches
--------------------------------------------------------------------------------

UIParent = newFrame("Frame", "UIParent")
function CreateFrame(kind, name, parent, template) return newFrame(kind, name, parent, template) end

GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
GameFontHighlight, GameFontNormalLarge, GameFontHighlightSmall, GameFontDisableSmall = {}, {}, {}, {}

GameTooltip = newFrame("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = { messages = {}, AddMessage = function(self, m) table.insert(self.messages, m) end }

SlashCmdList = {}

local mockSpeed, mockFlying, mockGliding, mockTaxi = 0, false, false, false
local mockGlideSpeed = 0

-- The live client returns a "secret" number for player speed in combat and
-- throws if tainted code compares or does arithmetic on it. Real secrets are a
-- VM feature we cannot construct here, so this stands in for one: a table whose
-- metamethods throw the way the real value does, paired with an issecretvalue
-- that recognises it. Any unguarded use in the addon therefore errors here in
-- exactly the place it errored in game.
local mockSecretCombat = false
local SECRET = setmetatable({}, {
    __lt  = function() error("attempt to compare a secret number value", 2) end,
    __le  = function() error("attempt to compare a secret number value", 2) end,
    __add = function() error("attempt to perform arithmetic on a secret number value", 2) end,
    __sub = function() error("attempt to perform arithmetic on a secret number value", 2) end,
    __mul = function() error("attempt to perform arithmetic on a secret number value", 2) end,
    __div = function() error("attempt to perform arithmetic on a secret number value", 2) end,
    __tostring = function() return "<secret number>" end,
})
function issecretvalue(v) return v == SECRET end

-- Mirrors the live client: GetUnitSpeed reads 0 while gliding.
function GetUnitSpeed(unit)
    if mockSecretCombat then return SECRET, 7, 21.7, 4.72 end
    if mockGliding then return 0, 7, 21.7, 4.72 end
    return mockSpeed, 7, 21.7, 4.72
end
function IsFlying() return mockFlying end
function UnitOnTaxi(unit) return mockTaxi end
C_PlayerInfo = { GetGlidingInfo = function() return mockGliding, true, mockGlideSpeed end }

local registeredCategory, openedID
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        return { ID = 42, name = name, frame = frame, GetID = function(s) return s.ID end }
    end,
    RegisterAddOnCategory = function(cat) registeredCategory = cat end,
    OpenToCategory = function(id) openedID = id end,
}

--------------------------------------------------------------------------------
-- Run
--------------------------------------------------------------------------------

print("\n[1] load + ADDON_LOADED")
local chunk = assert(loadfile(ADDON_PATH))
chunk("FlightSpeedometer")

local loader
for _, fr in ipairs(allFrames) do
    if fr._events["ADDON_LOADED"] then loader = fr end
end
assert(loader, "no frame registered ADDON_LOADED")
loader._scripts.OnEvent(loader, "ADDON_LOADED", "FlightSpeedometer")

check("SavedVariables table created", type(FlightSpeedometerDB), "table")
check("default unit", FlightSpeedometerDB.unit, "kmh")
check("options category registered", registeredCategory ~= nil, true)
check("category name", registeredCategory and registeredCategory.name, "Flight Speedometer")

local f = framesByName["FlightSpeedometerFrame"]
local speedText, subText = f._fontstrings[1], f._fontstrings[2]

-- the unnamed, unparented OnUpdate driver
local driver
for _, fr in ipairs(allFrames) do
    if fr._scripts.OnUpdate and fr ~= f then driver = fr end
end
assert(driver, "no OnUpdate driver frame found")

local function tick(n)
    for _ = 1, (n or 1) do driver._scripts.OnUpdate(driver, 0.06) end
end

print("\n[2] hidden while on the ground")
mockFlying, mockSpeed = false, 0
tick(3)
check("frame hidden on ground", f:IsShown(), false)

print("\n[3] flying, smoothing off")
SlashCmdList["FLIGHTSPEEDOMETER"]("smooth")   -- disable smoothing for exact values
mockFlying, mockSpeed = true, 7
tick(3)
check("frame shown while flying", f:IsShown(), true)
check("7 yd/s in km/h", speedText:GetText(), "23.0 km/h")
check("percent at base speed", subText:GetText():match("^%d+%%"), "100%")

print("\n[4] unit conversion")
SlashCmdList["FLIGHTSPEEDOMETER"]("mph")
tick(2)
check("7 yd/s in mph", speedText:GetText(), "14.3 mph")
SlashCmdList["FLIGHTSPEEDOMETER"]("kmh")

print("\n[5] 310% flight speed (21.7 yd/s)")
mockSpeed = 21.7
tick(2)
check("21.7 yd/s in km/h", speedText:GetText(), "71.4 km/h")
check("percent", subText:GetText():match("^%d+%%"), "310%")
check("max tracked", subText:GetText():match("max ([%d%.]+)"), "71.4")

print("\n[6] skyriding: GetUnitSpeed reads 0, forwardSpeed carries the truth")
SlashCmdList["FLIGHTSPEEDOMETER"]("clear")
mockFlying, mockGliding, mockSpeed, mockGlideSpeed = false, true, 0, 30
tick(2)
check("shown while gliding", f:IsShown(), true)
check("30 yd/s glide in km/h", speedText:GetText(), "98.8 km/h")
check("glide percent", subText:GetText():match("^%d+%%"), "429%")
check("max tracks glide speed", subText:GetText():match("max ([%d%.]+)"), "98.8")

-- 65 yd/s is the documented max dive speed
mockGlideSpeed = 65
tick(2)
check("max dive speed", speedText:GetText(), "214.0 km/h")
mockGliding, mockGlideSpeed = false, 0

print("\n[6b] ground speed still tracks max (regression from screenshots)")
SlashCmdList["FLIGHTSPEEDOMETER"]("clear")
SlashCmdList["FLIGHTSPEEDOMETER"]("always")   -- show on the ground
mockFlying, mockSpeed = false, 15.4           -- 220% ground mount
tick(2)
check("ground speed shown", speedText:GetText(), "50.7 km/h")
check("ground max no longer 0.0", subText:GetText():match("max ([%d%.]+)"), "50.7")
SlashCmdList["FLIGHTSPEEDOMETER"]("always")   -- back off
SlashCmdList["FLIGHTSPEEDOMETER"]("clear")

print("\n[6c] secret speed in combat must not throw")
SlashCmdList["FLIGHTSPEEDOMETER"]("clear")
SlashCmdList["FLIGHTSPEEDOMETER"]("always")   -- as the reporter had it configured
mockFlying, mockGliding, mockSpeed = false, false, 15.4
tick(2)
local lastGood = speedText:GetText()
check("live reading before combat", lastGood, "50.7 km/h")

mockSecretCombat = true
local combatOk, combatErr = pcall(tick, 5)   -- 5 ticks, as the client would
check("no error on secret speed", combatOk and "ok" or tostring(combatErr), "ok")
check("last good value held", speedText:GetText(), lastGood)
check("sub-line marks it stale", subText:GetText(), "hidden in combat")
check("still visible in combat", f:IsShown(), true)

mockSecretCombat = false
tick(2)
check("recovers after combat", speedText:GetText(), "50.7 km/h")
check("sub-line restored", subText:GetText():match("^%d+%%") ~= nil, true)
SlashCmdList["FLIGHTSPEEDOMETER"]("always")   -- back off
SlashCmdList["FLIGHTSPEEDOMETER"]("clear")

print("\n[7] taxi detection")
mockTaxi, mockSpeed = true, 10
tick(2)
check("shown on flight path", f:IsShown(), true)
mockTaxi = false

print("\n[8] slash commands")
for _, cmd in ipairs({ "", "help", "lock", "unlock", "always", "percent", "max",
                       "smooth", "scale 1.5", "scale 99", "reset", "clear", "garbage" }) do
    local ok, err = pcall(SlashCmdList["FLIGHTSPEEDOMETER"], cmd)
    if not ok then failures = failures + 1; print("  FAIL  /fspeed " .. cmd .. " -> " .. tostring(err)) end
    checks = checks + 1
end
check("scale clamped (99 rejected)", FlightSpeedometerDB.scale, 1)
check("records cleared", FlightSpeedometerDB.best, 0)
check("right-click opened options", (function()
    f._scripts.OnMouseUp(f, "RightButton"); return openedID end)(), 42)

print("\n[9] options panel widgets")
local panel = framesByName["FlightSpeedometerOptionsPanel"]
check("panel exists", panel ~= nil, true)
local ok, err = pcall(panel._scripts.OnShow, panel)
check("panel OnShow refresh", ok and "ok" or err, "ok")
ok, err = pcall(panel.OnRefresh); check("panel.OnRefresh", ok and "ok" or err, "ok")
ok, err = pcall(panel.OnCommit);  check("panel.OnCommit",  ok and "ok" or err, "ok")
ok, err = pcall(panel.OnDefault); check("panel.OnDefault", ok and "ok" or err, "ok")

local clicked = 0
for _, fr in ipairs(allFrames) do
    if fr.__kind == "CheckButton" and fr._scripts.OnClick then
        fr:SetChecked(not fr:GetChecked())
        local ok2, err2 = pcall(fr._scripts.OnClick, fr)
        checks = checks + 1
        if not ok2 then failures = failures + 1; print("  FAIL  checkbox OnClick -> " .. tostring(err2)) end
        clicked = clicked + 1
    end
end
check("checkboxes wired", clicked, 6)

local buttons = 0
for _, fr in ipairs(allFrames) do
    if fr.__kind == "Button" and fr._scripts.OnClick then
        local ok2, err2 = pcall(fr._scripts.OnClick, fr)
        checks = checks + 1
        if not ok2 then failures = failures + 1; print("  FAIL  button OnClick -> " .. tostring(err2)) end
        buttons = buttons + 1
    end
end
check("buttons wired", buttons, 4)

print("\n[10] tooltip handler")
ok, err = pcall(f._scripts.OnEnter, f)
check("speedometer OnEnter", ok and "ok" or err, "ok")

print(string.format("\n===== %d checks, %d failures =====", checks, failures))
os.exit(failures == 0 and 0 or 1)
