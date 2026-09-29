--------------------------------------------------------------------------------
-- core/aurarow.lua
-- One row of aura icons on a Blizzard AuraContainer, for either addon.
--
-- The container (12.1, CustomAuraContainerTemplate) tracks, filters and sorts
-- in secure C and hands back each button through initializeFrame; the caller
-- supplies the regions and never reads aura data. That is what keeps a row
-- drawing in combat, where aura data is secret and a Lua read throws.
--
-- Work splits in two tiers (unitframesz/auras.lua has the history):
--   Tier 1, always legal: the container's anchors, Show/Hide/SetEnabled, the
--     group's filter string, frame cap and layout, UpdateAllAuras.
--   Tier 2, the button tree: legal only inside initializeFrame, or while
--     AuraRow.CanDoStructuralWork() holds. Refused work goes through
--     AuraRow.Defer and runs on the next lift.
--
-- Contracts this relies on, from the 12.1 UI source and Unit Frames Z's field
-- passes:
--   * SetUnit last, after the group exists, or UNIT_AURA never registers.
--   * A hidden container drops its event registrations; Configure re-shows
--     and kicks, so a subject change must run through it.
--   * The flow layout reserves elementWidth/elementHeight but does not size
--     the button; the caller's wire sizes it.
--   * Every region handed to a Set*/Add* binding must be a descendant of its
--     button.
--   * A grouped container's rect is secret. Stack rows by anchoring one
--     container to another, never by measuring.
--
-- Unit Frames Z predates this file and still carries its own copy of this
-- code, which is yet to move onto it.
--------------------------------------------------------------------------------

local addonName, addon = ...

local AuraRow = {}
addon.AuraRow = AuraRow

-- Engine enums that live as plain globals, not under Enum. The fallbacks are
-- Blizzard's own values, so a missing global degrades instead of erroring.
local FLOW_AXIS = AnchorUtil and AnchorUtil.FlowLayoutAxis
local FLOW_DIR = AnchorUtil and AnchorUtil.FlowDirection
local DISPEL_STYLE = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
local STEALABLE = Enum and Enum.CustomAuraButtonDispelTypeStealableFilter

AuraRow.SORT_DEFAULT = (AuraContainerSortMethod and AuraContainerSortMethod.Default) or 0
AuraRow.SORT_NORMAL = (AuraContainerSortDirection and AuraContainerSortDirection.Normal) or 0
AuraRow.AXIS_HORIZONTAL = (FLOW_AXIS and FLOW_AXIS.Horizontal) or 0
AuraRow.DIR_RIGHT = (FLOW_DIR and FLOW_DIR.Right) or 1
AuraRow.DIR_DOWN = (FLOW_DIR and FLOW_DIR.Down) or -1
AuraRow.DIR_UP = (FLOW_DIR and FLOW_DIR.Up) or 1
AuraRow.DISPEL_PRESERVE = (DISPEL_STYLE and DISPEL_STYLE.PreserveAsset) or 3
AuraRow.STEALABLE_ONLY = (STEALABLE and STEALABLE.Stealable) or 1

-- The last outcome of each step, keyed by the caller's tag, for a debug window.
AuraRow.results = {}

local function record(tag, step, ok, err)
    if not tag then return end
    local text = "ok"
    if not ok then
        text = "FAILED: " .. (issecretvalue(err) and "<secret>" or tostring(err))
    end
    AuraRow.results[tag .. "." .. step] = text
end

--------------------------------------------------------------------------------
-- The structural-work gate
--------------------------------------------------------------------------------

--- True when the button tree can be touched. Aura secrecy and combat lockdown
--- are separate conditions: an encounter can restrict auras with no lockdown.
function AuraRow.CanDoStructuralWork()
    if InCombatLockdown() then return false end
    if addon.AurasSecretNow() then return false end
    return true
end

-- key -> fn. One entry per key, so a setting dragged ten times in combat runs
-- once at the lift.
local pending = {}

--- Run fn now if the tree can be touched, or at the next lift. Returns true
--- when it ran.
function AuraRow.Defer(key, fn)
    if AuraRow.CanDoStructuralWork() then
        pending[key] = nil
        fn()
        return true
    end
    pending[key] = fn
    return false
end

function AuraRow.PendingCount()
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    return n
end

-- Aura secrecy lifts on more edges than combat ends on, so this listens to all
-- of them and re-probes rather than assuming.
local function drain()
    if not AuraRow.CanDoStructuralWork() then return end
    local queued = pending
    pending = {}
    for _, fn in pairs(queued) do
        local ok, err = pcall(fn)
        if not ok then record("drain", "run", false, err) end
    end
end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
                         "ENCOUNTER_END", "ZONE_CHANGED_NEW_AREA" }) do
    addon.Events.On("AuraRow", event, drain)
end

--------------------------------------------------------------------------------
-- Dispel colors
--------------------------------------------------------------------------------

-- The long-stable literals, for a client without DebuffTypeColor.
local DISPEL_FALLBACK = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    Bleed   = { 1.00, 0.20, 0.20 },
    None    = { 0.80, 0.00, 0.00 },
}

--- A customDispelColorMap for AddDispelTypeTexture. It has to be explicit:
--- PreserveAsset with no map resolves "None" to a color that renders black.
--- Keys match the engine's own, auraData.dispelName or "None". The values are
--- Color objects because the engine calls GetRGBA on them.
function AuraRow.DispelColorMap()
    local live = rawget(_G, "DebuffTypeColor")
    local map = {}
    for key, rgb in pairs(DISPEL_FALLBACK) do
        local c = live and live[key ~= "None" and key or "none"]
        if type(c) == "table" and type(c.r) == "number" then
            map[key] = CreateColor(c.r, c.g, c.b, 1)
        else
            map[key] = CreateColor(rgb[1], rgb[2], rgb[3], 1)
        end
    end
    return map
end

--------------------------------------------------------------------------------
-- A row
--------------------------------------------------------------------------------

--- Build one row. Tier 2: call it where AuraRow.CanDoStructuralWork() holds.
--- opts = {
---     tag,                    a name for AuraRow.results
---     unit, group, filter, max,
---     layout = { elementSpacing, lineSpacing, elementWidth, elementHeight },
---     wire = fn(button),      runs inside initializeFrame, once per button
--- }
--- Returns the row, { container, group, buttons }, or nil.
function AuraRow.Build(parent, opts)
    local tag = opts.tag
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    record(tag, "container", ok and container ~= nil, container)
    if not ok or not container then return nil end

    -- The engine lays out from an OnUpdate and needs a rect from the first
    -- dirty mark; it replaces the size on every pass.
    container:SetSize(1, 1)
    container:Hide()

    local row = { container = container, group = opts.group, buttons = {}, tag = tag }
    local gOk, gErr = pcall(container.AddAuraGroup, container, opts.group, opts.filter, {
        maxFrameCount = opts.max,
        sortMethod = AuraRow.SORT_DEFAULT,
        sortDirection = AuraRow.SORT_NORMAL,
        -- Never candidateFilters.maxDuration: any value hides permanent auras.
        initializeFrame = function(button)
            if button.scootWired then return end
            button.scootWired = true
            row.buttons[#row.buttons + 1] = button
            local wOk, wErr = pcall(opts.wire, button)
            record(tag, "wire", wOk, wErr)
        end,
        layout = opts.layout,
    })
    record(tag, "group", gOk, gErr)
    if not gOk then return row end

    local uOk, uErr = pcall(container.SetUnit, container, opts.unit)
    record(tag, "unit", uOk, uErr)
    pcall(container.UpdateAllAuras, container)
    return row
end

--- The flow layout and the icon slot size. Tier 1.
--- opts = { anchorPoint, growY, maxLineSize, layout }
function AuraRow.SetLayout(row, opts)
    local c = row.container
    pcall(c.SetFlowLayoutAxis, c, AuraRow.AXIS_HORIZONTAL)
    pcall(c.SetFlowLayoutAnchorPoint, c, opts.anchorPoint)
    pcall(c.SetFlowLayoutGrowthDirection, c, AuraRow.DIR_RIGHT, opts.growY)
    pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0)
    pcall(c.SetFlowLayoutMaximumLineSize, c, opts.maxLineSize)
    pcall(c.SetAuraGroupLayout, c, row.group, opts.layout)
end

--- Anchor the container. Tier 1, but AddAuraGroup stamps an aspect that makes
--- a refusal possible, so it is guarded and recorded.
function AuraRow.SetPoint(row, point, relTo, relPoint, x, y)
    local c = row.container
    local ok, err = pcall(function()
        c:ClearAllPoints()
        c:SetPoint(point, relTo, relPoint, x, y)
    end)
    record(row.tag, "anchor", ok, err)
end

--- Filter, cap and visibility, then a kick. Tier 1, so it is the path for every
--- subject change: a new unit needs the kick, and a row hidden while the frame
--- had no unit needs the re-show.
function AuraRow.Configure(row, filter, max, shown)
    local c = row.container
    pcall(c.SetAuraGroupFilterString, c, row.group, filter)
    pcall(c.SetAuraGroupMaxFrameCount, c, row.group, max)
    pcall(c.SetEnabled, c, shown)
    if shown then
        pcall(c.Show, c)
        pcall(c.UpdateAllAuras, c)
    else
        pcall(c.Hide, c)
    end
end

--- Re-read the unit's auras. Tier 1; for a unit the client sends no UNIT_AURA
--- for, such as targettarget.
function AuraRow.Kick(row)
    pcall(row.container.UpdateAllAuras, row.container)
end
