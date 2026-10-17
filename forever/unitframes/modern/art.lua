--------------------------------------------------------------------------------
-- forever/unitframes/modern/art.lua
-- What the Modern unit frame specs share: the atlas family each frame draws
-- from, the names the state code writes at runtime, and the manifest that
-- /camelot art and /camelot state read to say which names this client has.
--
-- The Modern style is retail's frame, transcribed from the live 12.1.5 source
-- the Forever client inherits. Every piece of art is an atlas member by
-- retail's name and nothing is bundled: Forever ships its own bronze behind
-- the same names, so the frames take the client's look with no file of
-- Camelot's. A name Forever's sheets lack hides its region, and the manifest
-- is how that is found out before a frame is judged.
--
-- The painter's readers for the Modern fields (a string atlas, snap, an atlas
-- mask, a flipbook, atlasByState, a bar's atlas and mask, a power bar's
-- atlasPrefix) are in art.lua and frame.lua beside this folder; the specs
-- here only name things.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art

local Modern = {}
Art.Modern = Modern

-- Each frame type's family: "UI-HUD-UnitFrame-<Type>-PortraitOn", which the
-- XML and UnitFrameManaBar_UpdateType complete with "-Bar-Health",
-- "-Bar-<Power>", "-InCombat", "-Status" and the rest.
Modern.FAMILY = {
    Player = "UI-HUD-UnitFrame-Player-PortraitOn",
    Target = "UI-HUD-UnitFrame-Target-PortraitOn",
    TargetofTarget = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
    Party = "UI-HUD-UnitFrame-Party-PortraitOn",
}

-- The names the state code writes at runtime, the same on every frame type.
Modern.Shared = {
    leaderIcon = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
    guideIcon = "UI-HUD-UnitFrame-Player-Group-GuideIcon",
    pvpFFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
    pvpHorde = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",
    pvpAlliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
    roleTank = "roleicon-tiny-tank",
    roleHealer = "roleicon-tiny-healer",
    roleDamage = "roleicon-tiny-dps",
}

-- The power fills a family can draw: the family's "-Bar-" with the member
-- each power's colour row names (core/colors.lua, GetPowerAtlasElement).
-- Forever's classes draw the first four; the fifth is listed so the manifest
-- says whether the sheet carries it.
Modern.POWER_ELEMENTS = { "Mana", "Rage", "Focus", "Energy", "RunicPower" }

--------------------------------------------------------------------------------
-- Manifest
--------------------------------------------------------------------------------
-- Every name a Modern spec or its state code can ask for, in the order the
-- swatch window draws them. The shared names first; each spec appends its
-- own as it registers.

Modern.Manifest = {}
local listed = {}

function Modern.Register(names)
    for _, name in ipairs(names) do
        if not listed[name] then
            listed[name] = true
            Modern.Manifest[#Modern.Manifest + 1] = name
        end
    end
end

--- The family's power fills, for a spec's manifest.
function Modern.PowerFills(family)
    local names = {}
    for _, element in ipairs(Modern.POWER_ELEMENTS) do
        names[#names + 1] = family .. "-Bar-" .. element
    end
    return names
end

do
    local shared = {}
    for _, name in pairs(Modern.Shared) do shared[#shared + 1] = name end
    table.sort(shared)
    Modern.Register(shared)
end

--- The manifest with each name's answer, for the dumps: a list of
--- { name, resolved }.
function Modern.Report()
    local rows = {}
    for _, name in ipairs(Modern.Manifest) do
        rows[#rows + 1] = { name = name, resolved = Art.AtlasResolves(name) }
    end
    return rows
end
