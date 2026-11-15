--------------------------------------------------------------------------------
-- forever/qualityoflife/animations.lua
-- The Animations page's three settings: small bars over the character while
-- eating, drinking and sitting at a Welcoming Campfire, with icons rising
-- above them (animationsdisplay.lua). Every one ships on: the bars are
-- Camelot's own frame and touch nothing of Blizzard's.
--
-- Loads on both clients for the page; the display is Forever only and the
-- page's rows call it when it exists.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.QualityOfLife = addon.QualityOfLife or {}
local Animations = {}
addon.QualityOfLife.Animations = Animations

Animations.NAV_KEY = "qolAnimations"

-- In stack order, top to bottom. The campfire runs longest, so it sits
-- lowest, nearest the head.
Animations.KINDS = { "food", "drink", "campfire" }

Animations.PATHS = {
    food = "qol.animFood",
    drink = "qol.animDrink",
    campfire = "qol.animCampfire",
}

-- The bars' scale, in percent: a stage inside the holder
-- (animationsdisplay.lua), so the stored point keeps its units.
Animations.SCALE_PATH = "qol.animScale"
Animations.SCALE = { min = 50, max = 200, step = 5, default = 100 }

DB.RegisterDefaults({
    [Animations.PATHS.food] = true,
    [Animations.PATHS.drink] = true,
    [Animations.PATHS.campfire] = true,
    [Animations.SCALE_PATH] = Animations.SCALE.default,
})

--- 50 to 200 percent, in steps of 5.
function Animations.Scale()
    local range = Animations.SCALE
    local v = tonumber(DB.Get(Animations.SCALE_PATH)) or range.default
    v = math.max(range.min, math.min(range.max, v))
    return math.floor(v / range.step + 0.5) * range.step
end

function Animations.SetScale(value)
    DB.Set(Animations.SCALE_PATH, tonumber(value) or Animations.SCALE.default)
    -- Forever only (animationsdisplay.lua); on retail the row stores alone.
    if Animations.ApplyScale then Animations.ApplyScale() end
end

function Animations.IsOn(kind)
    return DB.Get(Animations.PATHS[kind]) and true or false
end

function Animations.SetOn(kind, on)
    DB.Set(Animations.PATHS[kind], on and true or false)
    -- Forever only (animationsdisplay.lua); on retail the row stores alone.
    if Animations.Refresh then Animations.Refresh() end
end
