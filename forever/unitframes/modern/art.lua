--------------------------------------------------------------------------------
-- forever/unitframes/modern/art.lua
-- What the Modern unit frame specs share: the atlas family each frame draws
-- from, the names the state code writes at runtime, and the manifest that
-- /camelot art and /camelot state read to say which names this client has.
--
-- The Modern style is the frame this client draws itself: retail's XML under
-- Forever's own override layer, which moves the level into a circle, centres
-- the name and shifts the bars, transcribed from the Forever build's files.
-- Every piece of art is an atlas member by Blizzard's name and nothing is
-- bundled: Forever ships its own bronze behind retail's names, so the frames
-- take the client's look with no file of Camelot's. A name the client's
-- sheets lack hides its region, and the manifest is how that is found out
-- before a frame is judged.
--
-- The painter's readers for the Modern fields (a string atlas, snap, an atlas
-- mask, a flipbook, atlasByState, a bar's atlas and mask, a power bar's
-- atlasPrefix) are in art.lua and frame.lua beside this folder; the specs
-- here only name things. The one piece of state here is the PvP badge,
-- which every Modern frame sets the same way.
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
-- The level sits in a small circle on this client's frames, and the PvP
-- badge is that circle with a faction crest, at four fifths; the free-for-all
-- badge keeps retail's own icon. The circle members are listed under the
-- client's own art set alone, which Art.ResolveAtlasName reaches.
Modern.Shared = {
    leaderIcon = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
    guideIcon = "UI-HUD-UnitFrame-Player-Group-GuideIcon",
    levelCircle = "UI-HUD-UnitFrame-SmallCircle",
    pvpFFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
    pvpHorde = "UI-HUD-UnitFrame-SmallCircle-Horde",
    pvpAlliance = "UI-HUD-UnitFrame-SmallCircle-Alliance",
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

--------------------------------------------------------------------------------
-- The PvP badge
--------------------------------------------------------------------------------

local function plain(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

-- The badge's three members by the writer's own map keys, resolved to the
-- names this client answers to, since the writer looks each name up itself
-- and takes an unknown one for a file path.
local function badgeMap()
    return {
        pvpIconFreeForAll = Art.ResolveAtlasName(Modern.Shared.pvpFFA),
        pvpIconHorde = Art.ResolveAtlasName(Modern.Shared.pvpHorde),
        pvpIconAlliance = Art.ResolveAtlasName(Modern.Shared.pvpAlliance),
    }
end

--- The PvP badge on an instance's pvpIcon region, the way the client's
--- player and target frames set theirs. Blizzard's own writer first, on a
--- texture Camelot owns: behind a secure delegate it reads the faction, the
--- free-for-all flag and the honor badge, hides the badge under the client's
--- own game rule, and writes the atlas and the shown state, secret-wrapped
--- where the unit's identity is. The elements table is the one the client's
--- overrides hand it, the badge alone, which the writer tolerates, and the
--- texture map names the circle's crests, so the writer draws the badge the
--- template names rather than retail's own icons. checkMercenary is the
--- writer's third argument, true on the player's own frame as the client
--- passes it. A client without the writer, or a refusal, takes the plain
--- path below with the same three names, as the Classic target frame does
--- with the vanilla files.
function Modern.ApplyPvP(inst, checkMercenary)
    local icon = inst.regions and inst.regions.pvpIcon
    if not icon then return end
    if inst.previewStandIn then
        icon:Hide()
        return
    end
    local util = _G.UnitFrameUtil
    if type(util) == "table" and util.UpdateUnitPvPIndicator then
        if pcall(util.UpdateUnitPvPIndicator, { pvpIcon = icon }, inst.unit, checkMercenary, badgeMap()) then
            return
        end
    end

    local rules = _G.C_GameRules
    local rule = _G.Enum and _G.Enum.GameRule and _G.Enum.GameRule.UnitFramePvPContextualDisabled
    if rules and rule and plain(rules.IsGameRuleActive, rule) == true then
        icon:Hide()
        return
    end
    local name
    if plain(UnitIsPVPFreeForAll, inst.unit) == true then
        name = Modern.Shared.pvpFFA
    else
        local faction = plain(UnitFactionGroup, inst.unit)
        if (faction == "Horde" or faction == "Alliance") and plain(UnitIsPVP, inst.unit) == true then
            if checkMercenary and plain(UnitIsMercenary, inst.unit) == true then
                faction = faction == "Horde" and "Alliance" or "Horde"
            end
            name = faction == "Horde" and Modern.Shared.pvpHorde or Modern.Shared.pvpAlliance
        end
    end
    if name and Art.AtlasResolves(name) then
        if icon.camelotAtlas ~= name then Art.SetAtlas(icon, name, true) end
        icon:Show()
    else
        icon:Hide()
    end
end
