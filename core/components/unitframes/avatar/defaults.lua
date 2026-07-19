-- defaults.lua - neutral fallback identity and default avatar settings.
-- Used when race/sex/class cannot be resolved (secret/forbidden), and to seed
-- editor defaults. Keeps the avatar showing something sensible instead of nothing.
local addonName, addon = ...

addon.AvatarDefaults = {
    fallbackRace = "Human",
    fallbackSex = "Male",
    defaultResolution = 96, -- single canonical asset size (no longer user-selectable)
    defaultSide = "left",
    defaultGap = 2,
    defaultOffsetX = 0,
    defaultOffsetY = 0,
    defaultScalePct = 100,
    baseDisplaySize = 48, -- on-screen px at 100% scale, beside the player portrait
}
