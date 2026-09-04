-- Helpers.lua - Shared helpers for Group Frame TUI renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.GroupFrames = addon.UI.GroupFrames or {}
local GF = addon.UI.GroupFrames

--------------------------------------------------------------------------------
-- Edit Mode Frame Getter
--------------------------------------------------------------------------------

-- frameKey is "party" or "raid" throughout this file; it doubles as the
-- groupFrames db key and as addon.ApplyGroupFrame*For's argument.
local FRAME_PREFIX = { party = "Party", raid = "Raid" }

function GF.getFrame(frameKey)
    return addon.GetEditModeUnitFrame(FRAME_PREFIX[frameKey])
end

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

function GF.ensureDB(frameKey)
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    db.groupFrames = db.groupFrames or {}
    db.groupFrames[frameKey] = db.groupFrames[frameKey] or {}
    return db.groupFrames[frameKey]
end

local OUTSIDE_TO_INSIDE_ANCHOR = {
    TOPLEFT     = "TOPLEFT",
    TOP         = "TOP",
    TOPRIGHT    = "TOPRIGHT",
    RIGHT       = "RIGHT",
    BOTTOMRIGHT = "BOTTOMRIGHT",
    BOTTOM      = "BOTTOM",
    BOTTOMLEFT  = "BOTTOMLEFT",
    LEFT        = "LEFT",
}

local ALL_ANCHORS = addon.Catalogs.Anchor9.order

function GF.ensureAuraTrackingDB()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    db.groupFrames = db.groupFrames or {}
    db.groupFrames.auraTracking = db.groupFrames.auraTracking or {}
    db.groupFrames.auraTracking.spells = db.groupFrames.auraTracking.spells or {}

    local at = db.groupFrames.auraTracking

    -- 12.0.5 drops every legacy buff-hiding field. Blizzard moved CompactUnitFrame
    -- buff rendering into a protected C-side system addons can't hide or shrink.
    at.auraScale = nil
    at.hideBlizzardBuffs = nil

    -- 12.1 retires the replacementStyle overlay system: the raidFramesDisplayBuffs
    -- CVar now hides Blizzard's buff icons outright. Users who had chosen an overlay
    -- style wanted those icons neutralized, so they convert to the hide toggle.
    -- NOTE: the new field must stay named hideBlizzardBuffIcons; the legacy drop
    -- above nukes hideBlizzardBuffs on every call. A copy of this conversion runs
    -- at login in core/profiles/core.lua (ApplyGroupBuffIconsHiddenForActiveProfile)
    -- because profile apply fires before any UI code calls this helper; both copies
    -- are idempotent, keep them in sync.
    if at.replacementStyle ~= nil then
        if at.replacementStyle ~= "none" and at.hideBlizzardBuffIcons == nil then
            at.hideBlizzardBuffIcons = true
        end
        at.replacementStyle = nil
    end

    -- The 12.1 AuraContainer port drops animDurationMode. Shrink, descend and
    -- ascend all drove an animated icon from a plain remaining/total ratio, and
    -- that number no longer exists outside the engine: 12.1 binds durations to
    -- StatusBar, Cooldown and FontString only, and nothing binds scale or
    -- position. Animated styles keep animating; duration is the drain swipe.
    at.animDurationMode = nil

    -- Per-spell migration: the dual-selector `position` ("inside"/"outside")
    -- field is replaced by a single inside-frame anchor, and ranks are
    -- assigned by the auto-slot helpers. `offsetX` / `offsetY` live on as a
    -- per-icon fine-tune applied on top of the auto-placed position.
    for _, spell in pairs(at.spells) do
        if type(spell) == "table" then
            if spell.position == "outside" and type(spell.anchor) == "string" then
                spell.anchor = OUTSIDE_TO_INSIDE_ANCHOR[spell.anchor] or spell.anchor
            end
            spell.position = nil
            -- Leave rank nil for disabled auras; for enabled auras the next block
            -- assigns contiguous 1..N sequential ranks per anchor.
        end
    end

    -- Migration: positionGroupSpacing scalar → per-anchor table. If an older
    -- profile recorded a single value (the previous global slider), spread it
    -- to every anchor so users don't lose their tuning.
    if type(at.positionGroupSpacing) == "number" then
        local prev = at.positionGroupSpacing
        at.positionGroupSpacing = {}
        for _, anchor in ipairs(ALL_ANCHORS) do
            at.positionGroupSpacing[anchor] = prev
        end
    end

    -- Rank re-sequencing: for each (anchor, class), sort enabled auras by
    -- (rank asc, spellId asc) and assign ranks 1..N contiguously. Scoping by
    -- class prevents cross-class leakage — a Druid's BOTTOMRIGHT list and a
    -- Shaman's BOTTOMRIGHT list are independent 1..N sequences. Fixes older
    -- profiles where enabled auras shared rank=1 from the pre-auto-slot
    -- default AND cleans up cross-class rank collisions from the earlier
    -- single-list model.
    local HA = addon.AuraTracking
    local spellToClass = HA and HA.SPELL_TO_CLASS or nil
    if spellToClass then
        local bucketsByKey = {}
        for spellId, spell in pairs(at.spells) do
            if type(spell) == "table" and spell.enabled then
                local anchor = spell.anchor or "BOTTOMRIGHT"
                local cls = spellToClass[spellId] or "__unknown__"
                local key = anchor .. "|" .. cls
                bucketsByKey[key] = bucketsByKey[key] or {}
                table.insert(bucketsByKey[key], { spellId = spellId, cfg = spell })
            end
        end
        for _, bucket in pairs(bucketsByKey) do
            table.sort(bucket, function(a, b)
                local ra = tonumber(a.cfg.rank) or 0
                local rb = tonumber(b.cfg.rank) or 0
                if ra ~= rb then return ra < rb end
                return a.spellId < b.spellId
            end)
            for i, entry in ipairs(bucket) do
                entry.cfg.rank = i
            end
        end
    end

    return at
end

function GF.ensureTextDB(frameKey, textKey)
    local t = GF.ensureDB(frameKey)
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

-- Read-only accessors (no materialization — used in get callbacks)

function GF.getDB(frameKey)
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local gf = rawget(db, "groupFrames")
    return gf and rawget(gf, frameKey) or nil
end

function GF.getTextDB(frameKey, textKey)
    local t = GF.getDB(frameKey)
    return t and rawget(t, textKey) or nil
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

-- Restyle one frame family instead of running addon:ApplyStyles, so the
-- frames don't refresh when unrelated settings change. The chain keys in
-- core/refresh.lua are the frame keys.
function GF.applyStyles(frameKey)
    addon.Refresh.Run(frameKey)
end

-- A text change restyles the whole family; there is no text-only chain.
function GF.applyText(frameKey)
    GF.applyStyles(frameKey)
end

function GF.applyRoleIcons(frameKey)
    local fn = addon["Apply" .. FRAME_PREFIX[frameKey] .. "RoleIcons"]
    if fn then fn() end
end

function GF.applyGroupLeadIcons(frameKey)
    local fn = addon["Apply" .. FRAME_PREFIX[frameKey] .. "GroupLeadIcons"]
    if fn then fn() end
end

function GF.applyHealthBarBorders(frameKey)
    local fn = addon["Apply" .. FRAME_PREFIX[frameKey] .. "FrameHealthBarBorders"]
    if fn then fn() end
end

--------------------------------------------------------------------------------
-- Composite Text Accessors
--------------------------------------------------------------------------------

-- get/set closure pair speaking AddTextStyleBlock's field vocabulary for a
-- frame's text sub-table (textPlayerName, textGroupNumbers, ...). The hide
-- flag lives inside the text table (s.hide); offsetX/offsetY map to the
-- nested offset.x/offset.y pair. get is read-only; set materializes.
function GF.textAccessors(frameKey, textKey)
    local function get(field)
        local s = GF.getTextDB(frameKey, textKey)
        if not s then return nil end
        if field == "hidden" then return s.hide end
        if field == "offsetX" or field == "offsetY" then
            local o = s.offset
            return o and o[field == "offsetX" and "x" or "y"]
        end
        return s[field]
    end
    local function set(field, value)
        local s = GF.ensureTextDB(frameKey, textKey)
        if not s then return end
        if field == "hidden" then
            s.hide = value
        elseif field == "offsetX" or field == "offsetY" then
            s.offset = s.offset or {}
            s.offset[field == "offsetX" and "x" or "y"] = value
        else
            s[field] = value
        end
    end
    return get, set
end

-- Accessors for a bar's prefixed key family (healthBarTexture,
-- healthBarBorderInsetH, ...) on the frame table, as AddBarStyleBlock and
-- AddBarBorderBlock consume them. Reads never materialize.
function GF.barAccessors(frameKey, barPrefix, opts)
    local Helpers = addon.UI.Settings.Helpers
    return Helpers.CreateBarAccessors(
        function() return GF.getDB(frameKey) end,
        function() return GF.ensureDB(frameKey) end,
        barPrefix, opts)
end

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

-- Per-frame helpers bound by GF.BindFrame; each takes frameKey first.
local BIND_NAMES = {
    "ensureDB", "ensureTextDB", "getDB", "getTextDB", "getFrame",
    "applyStyles", "applyText", "applyRoleIcons", "applyGroupLeadIcons",
    "applyHealthBarBorders", "textAccessors", "barAccessors",
}

-- Returns a table with the helpers above bound to frameKey, plus Edit Mode
-- setting accessors resolving the frame on each call. Replaces the wrapper
-- preambles in the party/raid renderers.
function GF.BindFrame(frameKey)
    local B = {}
    for _, name in ipairs(BIND_NAMES) do
        local fn = GF[name]
        B[name] = function(...)
            return fn(frameKey, ...)
        end
    end
    B.getEditModeSetting = function(settingId)
        return GF.getEditModeSetting(GF.getFrame(frameKey), settingId)
    end
    B.setEditModeSetting = function(settingId, value, options)
        GF.setEditModeSetting(GF.getFrame(frameKey), settingId, value, options)
    end
    return B
end

--------------------------------------------------------------------------------
-- Edit Mode Helpers
--------------------------------------------------------------------------------

function GF.getEditModeSetting(frame, settingId)
    if not frame or not settingId then return nil end
    if addon and addon.EditMode and addon.EditMode.GetSetting then
        return addon.EditMode.GetSetting(frame, settingId)
    end
end

function GF.setEditModeSetting(frame, settingId, value, options)
    if not frame or not settingId then return end
    if addon and addon.EditMode and addon.EditMode.WriteSetting then
        addon.EditMode.WriteSetting(frame, settingId, value, options or {})
    end
end

--------------------------------------------------------------------------------
-- Selector/Dropdown Options
--------------------------------------------------------------------------------

-- Font style options; the catalog in core/fonts.lua is the source of truth.
-- The paired order adds the Deep Shadow keys for dropdowns whose targets are
-- all Scoot-created FontStrings (aura tracking stacks).
GF.fontStyleValues = addon.FontStyles.values
GF.fontStyleOrder = addon.FontStyles.order
GF.fontStyleOrderPaired = addon.FontStyles.orderPaired

-- Dropdown option catalogs. core/catalogs.lua is the source of truth; these
-- names are aliases by reference so existing renderer reads stay put.
local Catalogs = addon.Catalogs

-- 9-way alignment anchor options
GF.anchorValues = Catalogs.Anchor9.values
GF.anchorOrder = Catalogs.Anchor9.order

-- Role icon position selectors: the nine points behind a "Default" entry
local roleAnchor = Catalogs.WithLeading(Catalogs.Anchor9, "default", "Default")
GF.roleAnchorValues = roleAnchor.values
GF.roleAnchorOrder = roleAnchor.order

-- Health bar color mode options
GF.healthColorValues = Catalogs.ColorMode.Health.values
GF.healthColorOrder = Catalogs.ColorMode.Health.order
GF.healthColorInfoIcons = Catalogs.ColorMode.Health.infoIcons

-- Background color mode options
GF.bgColorValues = Catalogs.ColorMode.Background.values
GF.bgColorOrder = Catalogs.ColorMode.Background.order

-- Party Frame: Sort By options
GF.partySortByValues = {
    [0] = "Role",
    [1] = "Group",
    [2] = "Alphabetical",
}
GF.partySortByOrder = { 0, 1, 2 }

-- Raid Frame: Groups display type options
GF.raidGroupsValues = {}
GF.raidGroupsOrder = {}
do
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
    if RGD then
        GF.raidGroupsValues = {
            [RGD.SeparateGroupsVertical] = "Separate Groups (Vertical)",
            [RGD.SeparateGroupsHorizontal] = "Separate Groups (Horizontal)",
            [RGD.CombineGroupsVertical] = "Combine Groups (Vertical)",
            [RGD.CombineGroupsHorizontal] = "Combine Groups (Horizontal)",
        }
        GF.raidGroupsOrder = {
            RGD.SeparateGroupsVertical,
            RGD.SeparateGroupsHorizontal,
            RGD.CombineGroupsVertical,
            RGD.CombineGroupsHorizontal,
        }
    end
end

-- Raid Frame: Sort By options (same values as party)
GF.raidSortByValues = GF.partySortByValues
GF.raidSortByOrder = GF.partySortByOrder

-- Role Icon Set selector options (built from Utils registry)
GF.roleIconSetValues = {}
GF.roleIconSetOrder = {}
do
    local sets = addon.BarsUtils and addon.BarsUtils.ROLE_ICON_SETS or {}
    for _, entry in ipairs(sets) do
        GF.roleIconSetValues[entry.key] = entry.label
        table.insert(GF.roleIconSetOrder, entry.key)
    end
end

--------------------------------------------------------------------------------
-- Conditional Helpers
--------------------------------------------------------------------------------

-- Check if party is in Raid-Style mode
function GF.isRaidStyleParty()
    local frame = GF.getFrame("party")
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    if not (frame and EM and EM.UseRaidStylePartyFrames) then return false end
    local v = GF.getEditModeSetting(frame, EM.UseRaidStylePartyFrames)
    return v and v ~= 0
end

-- Check if raid is in Separate Groups mode
function GF.isRaidSeparateGroups()
    local frame = GF.getFrame("raid")
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
    if not (frame and EM and RGD and EM.RaidGroupDisplayType) then return false end
    local v = GF.getEditModeSetting(frame, EM.RaidGroupDisplayType)
    return v == RGD.SeparateGroupsVertical or v == RGD.SeparateGroupsHorizontal
end

-- Check if raid is in Combine Groups mode
function GF.isRaidCombineGroups()
    return not GF.isRaidSeparateGroups()
end

--------------------------------------------------------------------------------
-- Info Icon Tooltips
--------------------------------------------------------------------------------

GF.TOOLTIPS = {
    raidStyleParty = {
        title = "Raid-Style Party Frames",
        text = "When enabled, party frames use the compact raid frame style. This enables additional customization options like frame width/height, borders, and sorting.",
    },
    displayBorder = {
        title = "Display Border",
        text = "Shows Blizzard's default border around each group. Only available when using Separate Groups layout.",
    },
    displayBorderRaid = {
        title = "Display Border",
        text = "Shows Blizzard's default border around each raid GROUP. Only available when Groups is set to 'Separate Groups'.",
    },
    sortBy = {
        title = "Sort By",
        text = "Determines how players are sorted within the combined groups view. Only available when Groups is set to 'Combine Groups'.",
    },
    columnSize = {
        title = "Column Size",
        text = "Number of frames per row or column in the combined groups view. Only available when Groups is set to 'Combine Groups'.",
    },
    groupTitleNumbersOnly = {
        title = "Show Groups as Numbers Only",
        text = "Display just the number instead of 'Group N'. Auto-centers beside-the-row (horizontal) or above-the-column (vertical).",
    },
}
