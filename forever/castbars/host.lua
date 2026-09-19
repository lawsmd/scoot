--------------------------------------------------------------------------------
-- forever/castbars/host.lua
-- Camelot's host for the cast bar engine (core/components/castbarz/engine.lua).
--
-- The engine asks its host for the bars, the settings, the position store and
-- the master switch; this file answers from forever/db.lua. The draw is
-- painter.lua. Nothing here decides how a cast behaves.
--
-- Settings are flat dotted paths under `castBars.`: per-unit keys at
-- castBars.<unit>.<key>, shared keys at castBars.<key>. Positions are a layout
-- entry per bar, the shape the unit frames use:
-- layout[key] = { positions = { [layoutName] = { point, x, y } } }
--------------------------------------------------------------------------------

local addonName, addon = ...

local CBZ = addon.CastBarZ
local DB = addon.DB

DB.RegisterModule("castBars", true)
DB.RegisterDefaults({
    ["castBars.player.enabled"]      = true,
    ["castBars.player.barWidth"]     = 195,
    ["castBars.player.barHeight"]    = 13,
    ["castBars.player.scale"]        = 100,
    ["castBars.player.positionMode"] = "free",
    ["castBars.player.frameStyle"]   = "classic",
    ["castBars.player.frameColor"]   = "forever",
    ["castBars.showSpark"]           = true,
    -- The cast time readout. Off: it adds an element beside the bar rather than
    -- restyling one, so it is opt-in. castTimeFont carries no default on purpose
    -- -- nil there means "follow the spell name", and a default would leave no
    -- nil to say it with. castTimeColor carries none either, because the
    -- resolver in casttime.lua owns its own.
    ["castBars.castTime"]            = false,
    ["castBars.castTimeReadout"]     = "remaining",
    ["castBars.castTimeSize"]        = 12,
    -- 10 is Blizzard's own gap for the same element.
    ["castBars.castTimeGap"]         = 10,
    ["castBars.castTimeOffsetY"]     = 0,
    ["castBars.player.castTimeSide"] = "right",
})

-- What the readout falls back to with no Font Style stored, the same style
-- painter.lua gives the spell name. Cast Bar Z keeps its own house default.
CBZ.CAST_TIME_FALLBACK_STYLE = "SHADOW"

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

CBZ.UNITS = { "Player" }
CBZ.UNIT_LABELS = { Player = "Player" }
CBZ.NUM_BOSS_BARS = 0

-- defaultPosition is vanilla's own anchor for CastingBarFrame
-- (Blizzard_CastingBar/Vanilla/CastingBarFrame.xml, 1.15.8: BOTTOM 0, 55).
-- anchorFrame is Blizzard's frame for the unit, which the engine falls back to
-- for a snapped bar; _ResolveCustomAnchorFrame below answers first.
CBZ.BARS = {
    {
        barKey = "Player", unitKey = "Player", token = "player",
        anchorFrame = "PlayerFrame", ufKey = "player", layoutKey = "castBarPlayer",
        frameName = "CamelotPlayerCastBar",
        -- Beta stand-in in center-origin coordinates; vanilla's is above.
        defaultPosition = { point = "CENTER", x = 0, y = -300 },
    },
}

CBZ.NAV_KEY = "castBarPlayer"

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function CBZ._IsModuleEnabled()
    return DB.IsModuleEnabled("castBars")
end

function CBZ._GetSetting(key)
    return DB.Get("castBars." .. key)
end

-- The engine reads and writes a unit's config as a table (cfg.positionMode,
-- cfg[snapOffsetKey] = n). One proxy per unit maps that onto the dotted paths.
local unitConfigs = {}

function CBZ._GetUnitConfig(unitKey)
    local cfg = unitConfigs[unitKey]
    if cfg then return cfg end
    if not CBZ._RowForUnitKey(unitKey) then return nil end

    local prefix = "castBars." .. unitKey:lower() .. "."
    cfg = setmetatable({}, {
        __index = function(_, key) return DB.Get(prefix .. key) end,
        __newindex = function(_, key, value) DB.Set(prefix .. key, value) end,
    })
    unitConfigs[unitKey] = cfg
    return cfg
end

-- Held for the session: the Features page changes it at the reload.
function CBZ._IsUnitEnabled(unitKey)
    if not CBZ._RowForUnitKey(unitKey) then return false end
    return DB.SessionGet("castBars." .. unitKey:lower() .. ".enabled") == true
end

-- The Features page rows (forever/features.lua).
for _, unitKey in ipairs(CBZ.UNITS) do
    addon.Features.Register({ group = "castBars", groupLabel = "Cast Bars",
        id = unitKey:lower(), label = CBZ.UNIT_LABELS[unitKey],
        path = "castBars." .. unitKey:lower() .. ".enabled" })
end

--------------------------------------------------------------------------------
-- Position store
--------------------------------------------------------------------------------

local function layoutKeyFor(barKey)
    local row = CBZ._RowForBarKey(barKey)
    return row and row.layoutKey
end

--- The bar's scale as a factor. A frame's scale multiplies its own SetPoint
--- offsets, so the painter and the position store both read this one number.
function CBZ._GetBarScale(unitKey)
    local cfg = CBZ._GetUnitConfig(unitKey)
    local pct = tonumber(cfg and cfg.scale) or 100
    return math.max(50, math.min(150, pct)) / 100
end

local function scaleFor(barKey)
    local row = CBZ._RowForBarKey(barKey)
    return row and CBZ._GetBarScale(row.unitKey) or 1
end

-- Offsets are stored in UIParent units and handed out in the bar's own, which
-- is what SetPoint takes and GetPoint reports. A change of scale then leaves
-- the anchor point where it was on screen.
CBZ._PositionStore = {
    get = function(barKey, layoutName)
        local key = layoutKeyFor(barKey)
        local entry = key and DB.GetLayout(key)
        local pos = entry and entry.positions and entry.positions[layoutName]
        -- The default answers for a layout with nothing stored, so it gets the
        -- same conversion. Applied raw, CENTER 0, -300 at 150% is off the screen.
        if not pos then
            local row = CBZ._RowForBarKey(barKey)
            pos = row and row.defaultPosition
        end
        if not pos then return nil end
        local s = scaleFor(barKey)
        return { point = pos.point, x = (pos.x or 0) / s, y = (pos.y or 0) / s }
    end,
    set = function(barKey, layoutName, point, x, y)
        local key = layoutKeyFor(barKey)
        if not key or not layoutName then return end
        local s = scaleFor(barKey)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x * s, y = y * s }
        DB.SetLayout(key, entry)
    end,
}

--------------------------------------------------------------------------------
-- Snap anchor
--------------------------------------------------------------------------------

--- A snapped bar attaches to Camelot's own unit frame. `owned` is true whenever
--- Camelot draws that unit, built or not: Blizzard's frame is parked then, and a
--- parked frame keeps a rect at its old position, so falling back to it would
--- snap a visible bar to an invisible frame.
function CBZ._ResolveCustomAnchorFrame(row)
    local UF = addon.UnitFrames
    if not (UF and row.ufKey and UF.IsEnabled and UF.IsEnabled(row.ufKey)) then
        return nil, false
    end
    local inst = UF.Frames and UF.Frames[row.ufKey]
    return inst and inst.frame or nil, true
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- CBZ._Reconcile is the one entry point: login, a profile switch, and every
-- setter on the settings page.

addon.Profiles.RegisterApplyStep("camelotCastBars", function(_, ctx)
    if ctx.initial then return end
    CBZ._Reconcile()
end, 20)

addon.Events.OnWorldEntered(function()
    CBZ._Reconcile()
end)
