--------------------------------------------------------------------------------
-- core/percent.lua
-- A unit's health or power percentage as a string, from getters that return
-- secrets. addon.Percent, on both TOCs.
--
-- UnitHealth and UnitPower are secret from addon code, and a secret cannot
-- be divided or formatted in Lua. The engine does both: a numeric curve from
-- (0, 0) to (1, 100) handed to UnitHealthPercent or UnitPowerPercent, which
-- evaluate the secret fraction through it and return a secret number in 0
-- to 100, then C_StringUtil.FloorToNearestString (or RoundToNearestString),
-- allowed when tainted, which returns the secret string. SetText accepts
-- it; nothing else can read it, and ClearText is the one call that releases
-- it from a FontString.
--
-- Each call returns the string and "ok", or nil and the reason, the verdict
-- a debug window prints. Callers own SetText and ClearText. Unit Frames Z,
-- ScootAuras' class power and Camelot's Personal Resource Display feed
-- their percent strings through here.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Percent = {}
addon.Percent = Percent

local curve

--- The shared curve. Curves are stateless evaluators, so one serves every
--- caller. nil when the client has no C_CurveUtil.
function Percent.Curve()
    if curve then return curve end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return nil end
    if c.SetType and Enum and Enum.LuaCurveType then
        pcall(c.SetType, c, Enum.LuaCurveType.Linear)
    end
    -- The getters feed the curve the normalized 0-1 fraction; the two points
    -- map it to 0-100 so the formatter sees a percent.
    pcall(c.AddPoint, c, 0, 0)
    pcall(c.AddPoint, c, 1, 100)
    curve = c
    return c
end

--- True when the client has the curve, both getters and the formatter.
function Percent.Available()
    return Percent.Curve() ~= nil and UnitHealthPercent ~= nil and UnitPowerPercent ~= nil
        and C_StringUtil ~= nil and C_StringUtil.FloorToNearestString ~= nil
end

-- round is "round" for RoundToNearestString; anything else floors, so the
-- display never claims 100 before the pool is full.
local function format(num, round)
    local fmt = (round == "round") and C_StringUtil.RoundToNearestString
        or C_StringUtil.FloorToNearestString
    if not fmt then return nil, "C_StringUtil formatter missing" end
    local ok, str = pcall(fmt, num)
    if not ok or type(str) ~= "string" then
        return nil, ok and ("formatter returned " .. type(str)) or ("formatter error: " .. tostring(str))
    end
    return str, "ok"
end

--- The health percentage of a unit as a secret string. usePredicted is
--- UnitHealthPercent's own second argument.
function Percent.Health(unit, usePredicted, round)
    local c = Percent.Curve()
    if not (c and UnitHealthPercent and C_StringUtil) then
        return nil, "percent API missing (C_CurveUtil / UnitHealthPercent / C_StringUtil)"
    end
    local ok, num = pcall(UnitHealthPercent, unit, usePredicted, c)
    if not ok or type(num) ~= "number" then
        return nil, ok and ("UnitHealthPercent returned " .. type(num))
            or ("UnitHealthPercent error: " .. tostring(num))
    end
    return format(num, round)
end

-- The color-by-value curves: red at 0, yellow at half, green at full; the
-- dark one turns dark gray at exactly full. Unit Frames X (bars/textures.lua)
-- and Z (engine.lua) each still build a private copy of these points.
local colorCurves = {}

local function colorCurve(dark)
    local key = dark and "dark" or "plain"
    if colorCurves[key] then return colorCurves[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    if c.SetType and Enum and Enum.LuaCurveType then
        pcall(c.SetType, c, Enum.LuaCurveType.Linear)
    end
    pcall(c.AddPoint, c, 0.0, CreateColor(1, 0, 0, 1))
    pcall(c.AddPoint, c, 0.5, CreateColor(1, 1, 0, 1))
    if dark then
        pcall(c.AddPoint, c, 0.9999, CreateColor(0, 1, 0, 1))
        pcall(c.AddPoint, c, 1.0, CreateColor(0.23, 0.23, 0.23, 1))
    else
        pcall(c.AddPoint, c, 1.0, CreateColor(0, 1, 0, 1))
    end
    colorCurves[key] = c
    return c
end

--- A unit's color-by-value health color as r, g, b, or nil when the client
--- cannot evaluate it. The engine returns a Color object whose channels can
--- go straight to a color setter.
function Percent.HealthColor(unit, dark)
    local c = colorCurve(dark)
    if not (c and UnitHealthPercent) then return nil end
    local ok, color = pcall(UnitHealthPercent, unit, true, c)
    if not ok or type(color) ~= "table" or not color.GetRGB then return nil end
    return color:GetRGB()
end

--- The power percentage of a unit as a secret string. powerType nil is the
--- displayed power; the maximum is the modified one, what a bar shows.
function Percent.Power(unit, powerType, round)
    local c = Percent.Curve()
    if not (c and UnitPowerPercent and C_StringUtil) then
        return nil, "percent API missing (C_CurveUtil / UnitPowerPercent / C_StringUtil)"
    end
    local ok, num = pcall(UnitPowerPercent, unit, powerType, false, c)
    if not ok or type(num) ~= "number" then
        return nil, ok and ("UnitPowerPercent returned " .. type(num))
            or ("UnitPowerPercent error: " .. tostring(num))
    end
    return format(num, round)
end
