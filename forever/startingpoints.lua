--------------------------------------------------------------------------------
-- forever/startingpoints.lua
-- Where a profile starts: Camelot's own setup, or one of Blizzard's Edit Mode
-- presets.
--
-- The shared profile engine records where each new layout came from
-- (core/profiles/core.lua, "Where a new profile comes from") and calls the
-- create hook below. A layout made with "New Layout" starts as Camelot; a
-- layout copied from a preset, or saved from an edited one, starts as that
-- preset, and so does the preset's own profile. A preset start is two things:
-- the preset's value set (DB.RegisterPreset beside each feature's defaults),
-- written into the new profile once, and the preset's positions, which are
-- never stored. Each frame's default position is read off Blizzard's preset
-- data for the frame Camelot replaces, so a Classic profile puts the player
-- frame where Blizzard's Classic preset puts PlayerFrame.
--
-- The profile records its start in `startingPoint`, the preset's name as the
-- client gives it ("Modern", "Classic", "Gamepad"); absent is Camelot. Beside
-- it, `startingPointSet` names the value set the start was seeded from
-- (DB.PresetSet). Forever's gamepad preset has no set or spots of its own: it
-- reads Classic's set and Classic's positions, until a gamepad arrangement
-- exists. A profile whose recorded set is no longer the one its start reads
-- is re-seeded once at login (Reseed).
--------------------------------------------------------------------------------

local _, addon = ...

local DB = addon.DB
local Profiles = addon.Profiles

local StartingPoints = {}
addon.StartingPoints = StartingPoints

--------------------------------------------------------------------------------
-- Counterparts
--------------------------------------------------------------------------------
-- The Blizzard Edit Mode system each positionable stands in for, by key. Names,
-- never numbers: Forever renumbers Enum.EditModeSystem. A key not listed keeps
-- Camelot's default under every start. The minimap is not listed: its own
-- default reads minimap.defaultAnchor, which the preset sets write, and
-- captures Blizzard's live spot (forever/minimap/editmode.lua).

local COUNTERPARTS = {
    player = { system = "UnitFrame", index = "Player" },
    target = { system = "UnitFrame", index = "Target" },
    focus = { system = "UnitFrame", index = "Focus" },
    -- The presets' pet anchor is the screen's center, never applied: Blizzard
    -- manages PetFrame off the player frame. Both small frames stand off
    -- their leader, as Camelot's own do.
    pet = { follows = "player" },
    targettarget = { follows = "target" },
    objectiveTracker = { system = "ObjectiveTracker" },
    personalResourceDisplay = { system = "PersonalResourceDisplay" },
    -- The presets anchor the status bars to UIParent on Modern and to
    -- StatusTrackingBarManager on Classic, so both starts read Modern's
    -- constants, kept beside the bars' own defaults.
    statusBar1 = { stock = function() return addon.StatusBars.Style.STOCK_POSITIONS[1] end },
    statusBar2 = { stock = function() return addon.StatusBars.Style.STOCK_POSITIONS[2] end },
}

-- Systems the position preset lacks read this one. The gamepad map lacks the
-- PRD, but a gamepad start reads Classic's spots (positionPreset), which has
-- it.
local FALLBACK_PRESET = "Modern"

local function presetLayouts()
    local manager = _G.EditModePresetLayoutManager
    local ok, layouts = pcall(function() return manager:GetCopyOfPresetLayouts() end)
    return ok and type(layouts) == "table" and layouts or {}
end

--- The client's name for a preset, matched without case ("classic" reads
--- "Classic"), or nil when the client has none by that name.
function StartingPoints.PresetName(name)
    if type(name) ~= "string" then return nil end
    for _, layout in ipairs(presetLayouts()) do
        if type(layout.layoutName) == "string" and layout.layoutName:lower() == name:lower() then
            return layout.layoutName
        end
    end
    return nil
end

local function systemAnchor(presetName, counterpart)
    local systemId = Enum.EditModeSystem and Enum.EditModeSystem[counterpart.system]
    if not systemId then return nil end
    local index
    if counterpart.index then
        local indices = Enum.EditModeUnitFrameSystemIndices
        index = indices and indices[counterpart.index]
        if not index then return nil end
    end
    for _, layout in ipairs(presetLayouts()) do
        if layout.layoutName == presetName then
            for _, info in ipairs(layout.systems or {}) do
                if info.system == systemId and (index == nil or info.systemIndex == index) then
                    return info.anchorInfo
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------
-- LibEditMode's Reset To Default Position calls SetPoint(point, x, y), the
-- same point on the frame and on UIParent, and every Camelot apply does the
-- same. A preset anchors point P of the frame to point R of UIParent; the same
-- spot as a P-to-P record is R's place minus P's place on UIParent, plus the
-- offset. Offsets are in the frame's own scale, so they divide by the frame's
-- scale against UIParent, read at the time of the sync.

local function fractions(point)
    local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local fy = point:find("TOP") and 1 or point:find("BOTTOM") and 0 or 0.5
    return fx, fy
end

local function relativeScale(frame)
    local parent = UIParent:GetEffectiveScale()
    local own = frame and frame:GetEffectiveScale()
    if not (own and own > 0 and parent > 0) then return 1 end
    return own / parent
end

-- The center, from UIParent's bottom left, of a frame placed by a same-point
-- record whose offsets are already in UIParent units.
local function centerOf(frame, point, x, y)
    local w, h = UIParent:GetSize()
    local fx, fy = fractions(point)
    local scale = relativeScale(frame)
    local fw, fh = (frame:GetWidth() or 0) * scale, (frame:GetHeight() or 0) * scale
    return fx * w + x - (fx - 0.5) * fw, fy * h + y - (fy - 0.5) * fh
end

-- A preset's anchor as a same-point record in UIParent units; nil when it is
-- not anchored to UIParent.
local function samePoint(anchor)
    if type(anchor) ~= "table" or type(anchor.point) ~= "string" then return nil end
    local relativeTo = anchor.relativeTo
    if relativeTo ~= nil and relativeTo ~= "UIParent" and relativeTo ~= UIParent then return nil end
    local w, h = UIParent:GetSize()
    local px, py = fractions(anchor.point)
    local rx, ry = fractions(anchor.relativePoint or anchor.point)
    return {
        point = anchor.point,
        x = (rx - px) * w + (tonumber(anchor.offsetX) or 0),
        y = (ry - py) * h + (tonumber(anchor.offsetY) or 0),
    }
end

-- framesByKey[key] = { [frame] = true }: every registered frame under a key
-- (a unit has one per frame style). camelotDefaults[frame] holds the default
-- the feature registered, before any sync rewrote the table in place.
local framesByKey = {}
local camelotDefaults = {}
local registeredTables = setmetatable({}, { __mode = "k" })

local function anyFrame(key)
    local frames = framesByKey[key]
    if frames then return next(frames) end
    return nil
end

-- The preset whose anchors a start reads: its own for Modern and Classic,
-- Classic for the gamepad preset, the same mapping as its value set.
local function positionPreset(presetName)
    local set = DB.PresetSet(presetName)
    return (set and StartingPoints.PresetName(set)) or presetName
end

-- The UIParent-unit record for key under presetName.
local function presetRecord(key, presetName)
    local counterpart = COUNTERPARTS[key]
    if not counterpart then return nil end

    if counterpart.stock then
        local p = counterpart.stock()
        return { point = p.point, x = p.x, y = p.y }
    end

    if counterpart.follows then
        -- Camelot's own offset from the followed frame's center to this one's,
        -- set beside the followed frame's preset spot.
        local leader = anyFrame(counterpart.follows)
        local own = anyFrame(key)
        local leaderRecord = presetRecord(counterpart.follows, presetName)
        local leaderCamelot, ownCamelot = leader and camelotDefaults[leader], own and camelotDefaults[own]
        if not (leaderRecord and leaderCamelot and ownCamelot and leader) then return nil end
        local w, h = UIParent:GetSize()
        local leaderScale = relativeScale(leader)
        local centerX, centerY = centerOf(leader, leaderRecord.point, leaderRecord.x, leaderRecord.y)
        local leaderX, leaderY = centerOf(leader, leaderCamelot.point,
            leaderCamelot.x * leaderScale, leaderCamelot.y * leaderScale)
        local ownScale = relativeScale(own)
        local ownX, ownY = centerOf(own, ownCamelot.point, ownCamelot.x * ownScale, ownCamelot.y * ownScale)
        return {
            point = "CENTER",
            x = centerX - w / 2 + (ownX - leaderX),
            y = centerY - h / 2 + (ownY - leaderY),
        }
    end

    return samePoint(systemAnchor(positionPreset(presetName), counterpart))
        or samePoint(systemAnchor(FALLBACK_PRESET, counterpart))
end

--- The default record for one frame under a start: Camelot's own for
--- "camelot" or an unknown name, else the preset's spot in the frame's scale.
function StartingPoints.Default(key, frame, start)
    local camelot = frame and camelotDefaults[frame]
    local presetName = StartingPoints.PresetName(start)
    local record = presetName and presetRecord(key, presetName)
    if not record then return camelot end
    local scale = relativeScale(frame)
    return { point = record.point, x = record.x / scale, y = record.y / scale }
end

--- The same for a key, read off any frame registered under it; nil for a key
--- with no counterpart or no frame yet.
function StartingPoints.DefaultFor(key, start)
    local frame = COUNTERPARTS[key] and anyFrame(key)
    if not frame then return nil end
    return StartingPoints.Default(key, frame, start)
end

--------------------------------------------------------------------------------
-- Sync
--------------------------------------------------------------------------------
-- The default table a feature registers is the one LibEditMode and the
-- positionable registry both hold, so it is rewritten in place, as the
-- minimap's own SyncDefault does. Then the frame is restored: a frame with a
-- stored position keeps it, and one without lands on the new default.

local function syncFrame(key, frame, restore)
    local lib = addon._LEM or (LibStub and LibStub("LibEditMode", true))
    local target = lib and lib.GetFrameDefaultPosition and lib:GetFrameDefaultPosition(frame)
    if type(target) ~= "table" then return end
    local record = StartingPoints.Default(key, frame, DB.StartingPoint())
    if not record then return end
    target.point, target.x, target.y = record.point, record.x, record.y
    if target.relPoint ~= nil then target.relPoint = record.point end
    if restore and addon.EditMode and addon.EditMode.RestorePositionable then
        addon.EditMode.RestorePositionable(frame)
    end
end

function StartingPoints.SyncAll()
    for key, frames in pairs(framesByKey) do
        for frame in pairs(frames) do syncFrame(key, frame, true) end
    end
end

-- Every positionable passes through here; the ones with a counterpart are
-- remembered, with the default they brought, and synced at once.
if addon.EditMode and addon.EditMode.RegisterPositionable then
    hooksecurefunc(addon.EditMode, "RegisterPositionable", function(frame, opts)
        local key = type(opts) == "table" and opts.key
        if type(key) ~= "string" or not COUNTERPARTS[key] or not frame then return end
        local default = opts.default
        if type(default) ~= "table" then return end
        -- Two frames may share one definition's table, which the first sync
        -- has already rewritten: the copy is taken once per table.
        local original = registeredTables[default]
        if not original then
            original = { point = default.point, x = default.x, y = default.y }
            registeredTables[default] = original
        end
        camelotDefaults[frame] = camelotDefaults[frame] or original
        framesByKey[key] = framesByKey[key] or {}
        framesByKey[key][frame] = true
        local restore = DB.StartingPoint() ~= "camelot"
        syncFrame(key, frame, restore)
        -- A frame that follows this one could not place itself before it.
        for other, counterpart in pairs(COUNTERPARTS) do
            if counterpart.follows == key and framesByKey[other] then
                for follower in pairs(framesByKey[other]) do syncFrame(other, follower, restore) end
            end
        end
    end)
end

-- After the frames re-read a switched profile, and when UIParent changes size.
Profiles.RegisterApplyStep("camelotStartingPoints", function(_, ctx)
    if ctx.initial then return end
    StartingPoints.SyncAll()
end, 20)

addon.Events.On("StartingPoints", "DISPLAY_SIZE_CHANGED", function() StartingPoints.SyncAll() end)
addon.Events.On("StartingPoints", "UI_SCALE_CHANGED", function() StartingPoints.SyncAll() end)

--------------------------------------------------------------------------------
-- Seeding
--------------------------------------------------------------------------------

local function copyValue(value)
    return type(value) == "table" and CopyTable(value) or value
end

--- Writes a preset's set into a profile table. A path the profile already
--- stores is kept unless `overwrite`, so a preset profile from before this
--- file keeps what the player set on it.
function StartingPoints.Seed(profile, presetName, overwrite)
    if type(profile) ~= "table" or not DB.PresetSet(presetName) then return end
    DB.EnsureContainers(profile)
    profile.startingPoint = presetName
    profile.startingPointSet = DB.PresetSet(presetName)
    DB.EachPreset(presetName, function(path, value)
        if overwrite or profile.settings[path] == nil then
            profile.settings[path] = copyValue(value)
        end
    end)
    DB.EachPresetDocument(presetName, function(key)
        if overwrite or profile.documents[key] == nil then
            profile.documents[key] = DB.PresetDocument(presetName, key)
        end
    end)
end

--- Moves a profile from the set it was seeded with to the set its start reads
--- now. The old set's paths and documents are cleared first, because a path
--- only the old set names has nothing in the new set to overwrite it; then the
--- new set is written over what remains. A value the player stored on a path
--- either set names is lost; every other setting, every position and every
--- record stays.
function StartingPoints.Reseed(profile, presetName)
    if type(profile) ~= "table" then return end
    DB.EnsureContainers(profile)
    local old = profile.startingPointSet
    if old then
        DB.EachPreset(old, function(path) profile.settings[path] = nil end)
        DB.EachPresetDocument(old, function(key) profile.documents[key] = nil end)
    end
    StartingPoints.Seed(profile, presetName, true)
end

local function wipeProfile(profile)
    for k in pairs(profile) do profile[k] = nil end
    DB.EnsureContainers(profile)
end

Profiles.RegisterCreateHook("camelot", function(_, origin, profile)
    if not origin then return end
    if origin.kind == "new" then
        wipeProfile(profile)
        profile.pendingTooltip = true
    elseif origin.kind == "preset" then
        wipeProfile(profile)
        StartingPoints.Seed(profile, StartingPoints.PresetName(origin.preset) or origin.preset, true)
    end
end)

-- A copied or renamed layout's positions are stored under the old name.
Profiles.RegisterRenameHook("camelot", function(profile, oldName, newName)
    if type(profile.layout) ~= "table" then return end
    for _, entry in pairs(profile.layout) do
        local positions = type(entry) == "table" and entry.positions
        if type(positions) == "table" and positions[oldName] and positions[newName] == nil then
            positions[newName] = positions[oldName]
            if oldName ~= newName then positions[oldName] = nil end
        end
    end
end)

-- A preset's profile made before this file has no start; it takes its
-- preset's set, over nothing the player stored. Any profile whose recorded
-- set is no longer the one its start reads is re-seeded once (Reseed): the
-- gamepad preset's own profile and every layout copied from it, when the
-- set it reads moves.
addon.Events.On("StartingPoints", "PLAYER_ENTERING_WORLD", function()
    local profiles = addon.db and addon.db.profiles
    if not profiles then return end
    local seeded
    for _, layout in ipairs(presetLayouts()) do
        local profile = profiles[layout.layoutName]
        if type(profile) == "table" and profile.startingPoint == nil then
            StartingPoints.Seed(profile, layout.layoutName, false)
            seeded = seeded or profile == addon.db.profile
        end
    end
    for _, profile in pairs(profiles) do
        local start = type(profile) == "table" and profile.startingPoint
        local wanted = type(start) == "string" and DB.PresetSet(start)
        if wanted and profile.startingPointSet ~= wanted then
            StartingPoints.Reseed(profile, start)
            seeded = seeded or profile == addon.db.profile
        elseif wanted then
            -- A path added to the set since the profile was seeded. DB.Set
            -- stores what it is given, so an absent path is one the player
            -- never set, and without this it would read Camelot's default.
            StartingPoints.Seed(profile, start, false)
        end
    end
    if seeded then StartingPoints.SyncAll() end
end)

--------------------------------------------------------------------------------
-- The tooltip
--------------------------------------------------------------------------------
-- Blizzard's tooltip stays Blizzard's: GameTooltip_SetDefaultAnchor puts it on
-- GameTooltipDefaultContainer, the HudTooltip system, whose spot is part of
-- the Edit Mode layout and not of the profile. A new Camelot profile marks
-- itself (pendingTooltip), and the first time its layout is the active one,
-- out of combat and outside Edit Mode, the system is moved through
-- LibEditModeOverride and saved, the owner's spot of 22 October 2026. After
-- that the spot is the player's, in Edit Mode, as any system's is.
--
-- "New Layout" switches profiles inside Edit Mode, and every apply pass until
-- the next reload runs there or in the second after it closes, where a write
-- would be lost. A pass that finds Edit Mode in the way tries again after the
-- close; one that finds the profile and layout apart tries a few more times.

local TOOLTIP_SPOT = { point = "BOTTOM", x = 700, y = 300 }
local TOOLTIP_RETRIES = 5
local tooltipRetries = 0

local seedTooltip

local function retryTooltip()
    if tooltipRetries >= TOOLTIP_RETRIES then return end
    tooltipRetries = tooltipRetries + 1
    C_Timer.After(2, seedTooltip)
end

function seedTooltip()
    local profile = addon.db and addon.db.profile
    if type(profile) ~= "table" or not profile.pendingTooltip then return end
    local EM = addon.EditMode
    local container = _G.GameTooltipDefaultContainer
    if not (EM and EM.ProfileMatchesActiveLayout and EM.ReanchorFrame and container) then return end
    -- The exit callback below picks it up.
    if EM.IsEditing and EM.IsEditing() then return end
    EM.LoadLayouts()
    if not EM.ProfileMatchesActiveLayout() or EM.IsEditModeActiveOrOpening() then
        retryTooltip()
        return
    end
    if InCombatLockdown() then
        addon.Events.RunOutOfCombat(seedTooltip, "StartingPoints.tooltip")
        return
    end
    -- A refusal (a preset active, layouts not loaded) keeps the mark for the
    -- next pass.
    local s = TOOLTIP_SPOT
    if pcall(EM.ReanchorFrame, container, s.point, UIParent, s.point, s.x, s.y) then
        profile.pendingTooltip = nil
        EM.SaveOnly()
    end
end

Profiles.RegisterApplyStep("camelotTooltipSeed", function() seedTooltip() end, 90)
addon.Events.On("StartingPoints.Tooltip", "PLAYER_ENTERING_WORLD", function()
    tooltipRetries = 0
    C_Timer.After(2, seedTooltip)
end)
-- After the one-second close window IsEditModeActiveOrOpening keeps.
if addon.EditMode and addon.EditMode.OnEditMode then
    addon.EditMode.OnEditMode("StartingPoints.Tooltip", {
        exit = function()
            tooltipRetries = 0
            C_Timer.After(1.5, seedTooltip)
        end,
    })
end
