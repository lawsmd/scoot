--------------------------------------------------------------------------------
-- forever/auras/host.lua
-- Camelot's host for the aura tracker (core/components/scootauras/).
--
-- The tracker reads addon.AurasHost at the moment of use and, with none set,
-- falls back to the other addon's keys. This file holds the values and
-- nothing else: where the account-wide store lives, where the editor window
-- keeps its position, and the two tokens the saved keys carry.
--
-- The store is CamelotDB.global.auras, one table for every aura on the
-- account; forever/db.lua creates it empty at DB.Initialize beside
-- global.media, and the tracker fills its sub-tables on the first write.
-- Where an aura loads is its spec list, never its profile, so nothing of it
-- sits under a profile; the one per-profile value is the Features switch,
-- auras.enabled, which forever/components.lua registers from the category
-- below.
--
-- A tracker's styling table is keyed aura_<id> and nests inside the store
-- through the component layer's owned-storage rule, so it never lands at a
-- flat settings path.
--
-- StartingValues gives a new tracker Camelot's look: an icon drawn as an
-- action button (its frame, the countdown's Friz Quadrata, the count's Arial
-- Narrow) and a bar drawn as the Personal Resource Display's (the Cooldown
-- Manager bar atlas, its framed background, TextStatusBarText's face). These
-- are starting values, written once into keys the player has not set, and
-- taken back off a shape change while still untouched, as the tracker's own
-- stamps are (SAU.StartingValueStamps).
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

-- Blizzard's ActionButtonTemplate: the frame atlas (IconBorders' "blizzard"
-- style, which rounds the icon under it), the countdown in Friz Quadrata and
-- the count on NumberFontNormal, Arial Narrow outlined.
local ICON_LOOK = {
    borderStyle    = "blizzard",
    textFont       = "FRIZQT__",
    textStyle      = "OUTLINE",
    stackTextFont  = "ARIALN",
    stackTextStyle = "OUTLINE",
}

-- forever/personalresourcedisplay: a 200 by 15 bar, the Cooldown Manager
-- atlas fill over its framed background at full alpha and no border of its
-- own, and every string on TextStatusBarText, Friz Quadrata 10 outlined.
-- A segmented bar's ticks are Blizzard's empowered cast bar stage mark
-- (ui-castingbar-empower-pip): 2 px of black at 82/255 alpha, so the frame's
-- dark interior shows through between segments.
local BAR_LOOK = {
    barWidth               = 200,
    barHeight              = 15,
    barForegroundTexture   = "blizzardCooldownManager",
    barBackgroundTexture   = "blizzardCooldownManager",
    barBackgroundColorMode = "original",
    barBackgroundOpacity   = 100,
    barBorderStyle         = "none",
    tickThickness          = 2,
    tickColor              = { 0, 0, 0, 0.32 },
    textFont               = "FRIZQT__",
    textStyle              = "OUTLINE",
    textSize               = 10,
    stackTextFont          = "FRIZQT__",
    stackTextStyle         = "OUTLINE",
    nameTextFont           = "FRIZQT__",
    nameTextStyle          = "OUTLINE",
}

-- The lists are built once: the restamp on a shape change matches stamps by
-- table, so each look must be the same table every time it is asked for.
local ICON_STAMPS = { ICON_LOOK }
local BAR_STAMPS = { BAR_LOOK }
local NO_STAMPS = {}

addon.AurasHost = {
    componentPrefix = "aura_",
    moduleCategory  = "auras",

    -- A Class Resource segment's fill added over itself at this alpha
    -- (classresource.lua): the Cooldown Manager fill is a grey ramp that dulls
    -- a pale class color beside the Personal Resource Display's bars.
    segmentBrighten = 0.3,

    -- The bar look itself, read by the Personal Resource Display's combo
    -- point bar so it draws as a Class Resource tracker does. Never written.
    barLook = BAR_LOOK,

    -- The account-wide store, or nil before the database exists. `create`
    -- makes the table when a reload has left it missing.
    GetStore = function(create)
        local g = DB.Global()
        if not g then return nil end
        if create and type(g.auras) ~= "table" then g.auras = {} end
        return g.auras
    end,

    GetEditorPosition = function()
        local g = DB.Global()
        local pos = g and g.aurasEditorPosition
        return type(pos) == "table" and pos or nil
    end,

    SetEditorPosition = function(pos)
        local g = DB.Global()
        if g then g.aurasEditorPosition = pos end
    end,

    StartingValues = function(_, shape)
        if shape == "icon" then return ICON_STAMPS end
        if shape == "bar" then return BAR_STAMPS end
        -- A vertical bar ("vbar") takes no host look: the Cooldown Manager
        -- atlas is a horizontal nine-slice, so it opens on Scoot's own
        -- SAU.VerticalBarShapeStartingValues on both hosts.
        return NO_STAMPS
    end,
}
