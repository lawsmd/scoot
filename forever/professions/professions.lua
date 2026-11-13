--------------------------------------------------------------------------------
-- forever/professions/professions.lua
-- The Professions page's settings and their defaults, for its two features:
--
--   The Professions Tracker (tracker.lua): one bar per profession the player
--   knows, filled by progress through the current 75-point rank band.
--
--   Skill Up Notifications (skillups.lua): a toast on each skill point, the
--   profession's icon beside a number that rolls from the old level to the
--   new one. It is a notification source, registered here so the
--   Notifications page lists it on both clients.
--
-- Both ship off, an added element's default. data.lua reads the professions.
--
-- Loads on both clients for the page; the three files above are Forever
-- only, and the setters call into them when they exist.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB
local Notifications = addon.Notifications

local Professions = {}
addon.Professions = Professions

Professions.NAV_KEY = "qolProfessions"
Professions.SOURCE = "professionSkillUp"

local TRACKER = "professions.tracker."
local SKILL_UPS = "professions.skillUps."

Professions.WIDTH = { min = 100, max = 320, step = 1, default = 160 }
Professions.BAR_HEIGHT = { min = 4, max = 24, step = 1, default = 10 }
Professions.ICON_SIZE = { min = 12, max = 48, step = 1, default = 22 }
Professions.SPACING = { min = 0, max = 30, step = 1, default = 6 }

Professions.ORDER = {
    values = { lowFirst = "Lowest Level at the Top", highFirst = "Highest Level at the Top" },
    order = { "lowFirst", "highFirst" },
}

-- Vanilla's skill bar blue (SkillStatusBarTemplate's BarColor), the fill
-- while no color is chosen.
Professions.BAR_COLOR = { 0.25, 0.25, 0.75, 1 }
-- Vanilla's bar stands on a dark pane and backs its fill with a faint
-- white; over the world the back is black at this opacity.
Professions.BACKGROUND_OPACITY = 50
-- The toast's number while no color is chosen: the gold of a level.
Professions.NUMBER_COLOR = { 1, 0.82, 0, 1 }
-- The tracker's name and level while no style is chosen: Crisp Thick Outline.
-- A client without the vector text renderer draws it as the thick outline
-- (core/fonts.lua).
Professions.TEXT_STYLE = "THICKOUTLINESLUG"

-- The two states the tracker's opacity answers to, under the catalog's names
-- (core/opacity.lua). Out of combat with no target the tracker is at full
-- opacity, so there is no Out of Combat value.
Professions.OPACITY_KEYS = {
    combat = addon.Opacity.Keys.InCombat.combat,
    target = addon.Opacity.Keys.InCombat.target,
}

DB.RegisterDefaults({
    [TRACKER .. "enabled"] = false,
    [TRACKER .. "width"] = Professions.WIDTH.default,
    [TRACKER .. "barHeight"] = Professions.BAR_HEIGHT.default,
    [TRACKER .. "iconSize"] = Professions.ICON_SIZE.default,
    [TRACKER .. "spacing"] = Professions.SPACING.default,
    [TRACKER .. "order"] = "lowFirst",
    [TRACKER .. "secondary"] = true,
    [TRACKER .. "showIcon"] = true,
    [TRACKER .. "icon.borderEnable"] = true,
    [TRACKER .. "icon.borderStyle"] = "blizzard",
    [TRACKER .. "bar.bgOpacity"] = Professions.BACKGROUND_OPACITY,
    [TRACKER .. "textName.style"] = Professions.TEXT_STYLE,
    [TRACKER .. "textLevel.style"] = Professions.TEXT_STYLE,
    [TRACKER .. Professions.OPACITY_KEYS.combat] = 100,
    [TRACKER .. Professions.OPACITY_KEYS.target] = 100,
    [TRACKER .. "mouseoverMode"] = false,
    -- The bar's texture and colors and the two texts' face, size and color
    -- carry no default: nil is vanilla's skill bar art and the font object's
    -- own face, size and color.

    [SKILL_UPS .. "enabled"] = false,
    [SKILL_UPS .. "showIcon"] = true,
    [SKILL_UPS .. "roll"] = true,
    [SKILL_UPS .. "secondary"] = true,
    -- color carries no default: nil is NUMBER_COLOR.
})

--------------------------------------------------------------------------------
-- The tracker's settings
--------------------------------------------------------------------------------

function Professions.TrackerPath(key)
    return TRACKER .. key
end

function Professions.TrackerGet(key)
    return DB.Get(TRACKER .. key)
end

function Professions.TrackerSet(key, value)
    DB.Set(TRACKER .. key, value)
    -- Forever only (data.lua, tracker.lua); on retail the row stores alone.
    -- Nothing reads the professions while both features are off, so the
    -- switch takes them again as it turns on.
    if key == "enabled" and value and Professions.Data then Professions.Data.Refresh() end
    if Professions.RefreshTracker then Professions.RefreshTracker() end
end

function Professions.TrackerOn()
    return DB.Get(TRACKER .. "enabled") == true
end

--- A stored number held inside its range.
function Professions.Clamp(value, range)
    value = tonumber(value) or range.default
    if value < range.min then return range.min end
    if value > range.max then return range.max end
    return value
end

-- The font object each of the tracker's texts starts on, vanilla's own for
-- a skill bar's name and its level.
Professions.TEXT_OBJECTS = {
    textName = "GameFontNormalSmall",
    textLevel = "GameFontHighlightSmall",
}

--- A text's font object: its face, its size and its color, r, g, b.
function Professions.TextObject(key)
    local object = _G[Professions.TEXT_OBJECTS[key]] or _G.GameFontNormalSmall
    local face, size = object:GetFont()
    local r, g, b = object:GetTextColor()
    return face, math.floor((tonumber(size) or 10) + 0.5), r or 1, g or 1, b or 1
end

--------------------------------------------------------------------------------
-- The skill-up toast's settings
--------------------------------------------------------------------------------

function Professions.SkillUpsGet(key)
    return DB.Get(SKILL_UPS .. key)
end

function Professions.SkillUpsSet(key, value)
    DB.Set(SKILL_UPS .. key, value)
    -- The levels a gain is measured from, taken as the switch turns on
    -- (data.lua, Forever only).
    if key == "enabled" and value and Professions.Data then Professions.Data.Refresh() end
end

function Professions.SkillUpsOn()
    return DB.Get(SKILL_UPS .. "enabled") == true
end

--- The number's color, r, g, b: the stored one or the gold.
function Professions.NumberColor()
    local color = DB.Get(SKILL_UPS .. "color")
    if type(color) ~= "table" then color = Professions.NUMBER_COLOR end
    return color[1] or 1, color[2] or 1, color[3] or 1
end

Notifications.RegisterSource({
    id = Professions.SOURCE,
    label = "Skill Up Notifications",
    where = "Quality of Life > Professions",
    navKey = Professions.NAV_KEY,
    isEnabled = Professions.SkillUpsOn,
})
