-- unitframesz/core.lua - Unit Frames Z: namespace, per-unit DB, registration
--
-- The Z-tier unit frame: Scoot owns every frame outright, and the frame is
-- text-first -- no health bar, no portrait, no frame art. The engine was built
-- and certified in the healthtext debug harness, then promoted here whole;
-- this file is the component wrapper around it.
--
-- Mode model (three states per unit, one active at a time):
--   OFF  moduleEnabled.unitFrames.<unit> == false and unitFramesZ.<unit> == false
--   X    moduleEnabled.unitFrames.<unit> == true   (Scoot styles Blizzard's frame)
--   Z    moduleEnabled.unitFramesZ.<unit> == true  (this component; Blizzard's
--        frame is parked whole via addon.NativeFrame -- suppression.lua)
--
-- The Features page's per-unit mode cycle is the writer of that state; the
-- initializer below re-asserts the exclusion for imported/hand-edited profiles.

local addonName, addon = ...

addon.UnitFramesZ = addon.UnitFramesZ or {}
local UFZ = addon.UnitFramesZ

--------------------------------------------------------------------------------
-- Units and frames: three identifiers, not one
--------------------------------------------------------------------------------
-- Boss is five frames driven by ONE configuration, so the single unitKey that
-- served Player and Target has to split -- the same collision Cast Bar Z hit
-- and solved the same way (castbarz/core.lua:16-30):
--
--   unitKey   "Boss"    DB config, settings page, nav key, Copy From, sub-toggle
--   frameKey  "Boss3"   the instance, the frame name, the stack index
--   token     "boss3"   every unit API call (inst.unit; NOT a config value)
--
-- For Player and Target all three coincide (modulo case), so nothing about
-- those two changes in practice.
--
-- Extension point: Focus/Pet/ToT/FocusTarget land by adding rows to both lists
-- here, a sub-toggle + modeCycle in modules.lua, per-unit default overrides
-- below, a default Edit Mode position (editmode.lua), a suppression target
-- (suppression.lua) and a nav/renderer pair.

UFZ.UNITS = { "Player", "Target", "Boss" }   -- config keys
UFZ.NUM_BOSS_FRAMES = addon.NUM_BOSS_FRAMES

UFZ.FRAMES = {
    { frameKey = "Player", unitKey = "Player", token = "player" },
    { frameKey = "Target", unitKey = "Target", token = "target" },
}

-- Boss: one config, five frames. They stack vertically off a shared anchor
-- (stack.lua); stackIndex is that anchor's ordering.
for i = 1, UFZ.NUM_BOSS_FRAMES do
    UFZ.FRAMES[#UFZ.FRAMES + 1] = {
        frameKey   = "Boss" .. i,
        unitKey    = "Boss",
        token      = "boss" .. i,
        stackIndex = i,
    }
end

function UFZ._RowForFrameKey(frameKey)
    for _, row in ipairs(UFZ.FRAMES) do
        if row.frameKey == frameKey then return row end
    end
    return nil
end

--- Every frame row belonging to a config key. One row for Player and Target,
--- five for Boss -- which is what makes GetAPI a fan-out and the settings page
--- indifferent to how many frames sit behind it.
---
--- Built once: UFZ.FRAMES is static, and this is on the settings-change path.
--- Callers must treat the result as read-only.
local rowsByUnitKey = {}
for _, row in ipairs(UFZ.FRAMES) do
    local rows = rowsByUnitKey[row.unitKey]
    if not rows then
        rows = {}
        rowsByUnitKey[row.unitKey] = rows
    end
    rows[#rows + 1] = row
end

local EMPTY_ROWS = {}

function UFZ._RowsForUnitKey(unitKey)
    return rowsByUnitKey[unitKey] or EMPTY_ROWS
end

UFZ._instances = {}   -- [frameKey] = inst
UFZ._comp = nil
UFZ._initialized = false

--------------------------------------------------------------------------------
-- Per-Unit DB
--------------------------------------------------------------------------------
-- Everything is per unit -- the debug harness ran the two instances on fully
-- independent configs and the promotion keeps that shape (unlike Cast Bar Z,
-- which shares its cosmetics). Flat scalar keys ONLY: Reset and GetConfig rely
-- on shallow copies, and a nested table would survive Reset.
--
-- Keys not surfaced in the settings UI (digits, digitSize1/3, center,
-- centerOffset, descent, stretch, symbolSize, align, color, round, usePredicted,
-- chrome, width, height, valFace, pctSize, nameFit, nameMinSize) are the
-- certified-look tuning constants from the harness; they ride along as declared
-- defaults so a future setting can surface any of them without a migration.
-- (style was on that list until the Font Style dropdowns landed; it is now the
-- health block's style, with nameStyle/powerStyle/levelStyle beside it.)
--
-- The unit token is NOT here. It used to live as cfg.unit, which cannot work
-- once five boss frames share one config table -- it is now structural, minted
-- from the frame row into inst.unit. Profiles saved before that change
-- keep a harmless orphan `unit` key.

local UNIT_DEFAULTS_SHARED = {
    -- Anton Wide 1.5x: the settled shipping bake.
    face         = "ANTON_WIDE_150",
    -- Font Style, per text block: style is the health block's (percent, '%',
    -- value and absorb rows); the other three cover the name, both power texts
    -- and the level pair. All four ship Deep Shadow (house default since
    -- 2026-08-30, migration V9): every UFZ text is a Scoot-created FontString
    -- fed by Lua SetText, which is what the companion copy needs.
    style        = "DEEPSHADOWTHICKOUTLINE",
    nameStyle    = "DEEPSHADOWTHICKOUTLINE",
    powerStyle   = "DEEPSHADOWTHICKOUTLINE",
    levelStyle   = "DEEPSHADOWTHICKOUTLINE",
    pctSize      = 32,               -- digits-off static percent size
    valSize      = 10,
    valFace      = "follow",         -- value row face: "follow" = track cfg.face
    gap          = 0,                -- px between the percent row and the value row
    -- Digit mode: the percent's point size follows its digit count (1-3), counted
    -- blind via the SetAlphaGradient oracle on an invisible ruler (probeDigits).
    digits       = true,
    digitSize1   = 38,
    digitSize2   = 32,
    digitSize3   = 26,
    -- Centered column: both number rows share a vertical centerline.
    center       = true,
    centerOffset = 65,               -- px from the anchored frame edge to the centerline
    -- Ink-bottom compensation, RELATIVE to the 2-digit master size. 0.28 measured
    -- for Anton Wide 1.5x by two-point screenshot calibration.
    -- Per-font: recalibrate if the face changes.
    descent      = 0.28,
    stretch      = 1.0,              -- width-only render stretch (1 = off)
    symbol       = true,             -- the small '%' glyph (its own FontString)
    symbolSize   = 0,                -- 0 = auto: a fifth of the percent's current point size
    symbolGap    = -2,               -- px between digits and '%'; negative tucks into the side bearing
    align        = "right",          -- right (player-style) | left (target-style)
    color        = "curve",          -- curve | dark | white
    round        = "floor",          -- floor | round (floor: never 100 until full)
    usePredicted = true,
    chrome       = false,
    width        = 140,
    height       = 64,               -- box only; text may overhang it
    scale        = 1.0,              -- whole-frame SetScale ("Overall Scale"; mirrored in Edit Mode)
    -- The name row: nameSize is the blind-fit CEILING -- the fit only ever
    -- shrinks from it.
    nameSize     = 26,
    nameFace     = "ANTON_WIDE_150",
    nameOffset   = 0,                -- X offset from the tuned baseline (NAME_BASE_X)
    nameY        = 0,                -- Y offset from the tuned baseline (NAME_BASE_Y); + = up
    nameColorMode = "gradient",      -- gradient (class ramp) | custom
    nameColorR   = 1,
    nameColorG   = 1,
    nameColorB   = 1,
    nameColorA   = 1,
    -- The certified blind fit (core/blindfit.lua): largest passing size in
    -- nameMinSize..nameSize against a nameMaxWidth x nameMaxLines box.
    nameFit      = true,
    nameMaxWidth = 150,
    nameMaxLines = 2,
    nameMinSize  = 10,
    -- Power texts: primary + alternate resource, name-relative locations.
    powerShow         = true,
    powerLoc          = "bottomright",  -- bottomleft|bottomright|topleft|topright|nameside
    powerSize         = 10,
    powerX            = 0,
    powerY            = 0,
    powerColorMode    = "power",        -- power (resource color) | custom
    powerColorR       = 1,
    powerColorG       = 1,
    powerColorB       = 1,
    powerColorA       = 1,
    altPowerShow      = true,
    altPowerLoc       = "bottomleft",
    altPowerSize      = 10,
    altPowerX         = 0,
    altPowerY         = 0,
    altPowerColorMode = "power",
    altPowerColorR    = 1,
    altPowerColorG    = 1,
    altPowerColorB    = 1,
    altPowerColorA    = 1,
    -- The small '%' companion on percent-rendered power (mana, either row).
    powerSymbol       = true,
    -- Absorb shield text: shares the value row's font settings by design; the
    -- halo look is fixed constants in the engine. Hide-at-zero is ALWAYS ON.
    absorbShow     = true,
    absorbX        = 0,
    absorbY        = 0,
    -- Level text: "lvl 90" in baked light gray. The ONE toggle is hide-at-max.
    levelHideMax   = false,
    levelLoc       = "topleft",         -- bottomleft|bottomright|topleft|topright|nameside
    levelSize      = 8,
    levelX         = 0,
    levelY         = 0,
    -- Aura icon rows (auras.lua). Per-row show/placement/limit; the shared
    -- styling block mirrors the UFX Target "Buffs & Debuffs" section. Unboxed:
    -- these keys never feed computeEnvelope -- the rows hang outside the frame.
    auraBuffsShow        = false,
    auraBuffsLoc         = "bottom",    -- top | bottom
    auraBuffsMax         = 16,          -- 1-32
    auraDebuffsShow      = false,
    auraDebuffsLoc       = "bottom",
    auraDebuffsMax       = 8,           -- 1-16
    auraOffsetY          = 0,           -- -60..60, + = up; moves BOTH rows from the snug default
    auraIconScale        = 100,         -- percent, 20-200
    auraTallWideRatio    = 0,           -- -67..67 (IconRatio crop; 0 = square)
    auraBorderEnable     = false,
    auraBorderStyle      = "square",
    auraBorderThickness  = 1,           -- 1-8, half steps
    auraBorderTintEnable = false,
    auraBorderTintR      = 1,
    auraBorderTintG      = 1,
    auraBorderTintB      = 1,
    auraBorderTintA      = 1,
    auraOnlyPlayerBuffs  = false,       -- buff row filter: HELPFUL|PLAYER
    auraTooltips         = true,        -- hover tooltips: motion-only mouse, clicks still pass through
    -- Dead indicator: a skull replacing BOTH health numbers (and the '%') on a
    -- dead or ghost unit. UnitIsDeadOrGhost is a PLAIN read in 12.0 -- no
    -- SecretReturns annotation in UnitDocumentation.lua -- so this branches
    -- normally. Always on (two stacked zeros are a
    -- rendering fault to the eye, so there is nothing to opt out of), fixed
    -- position, one style. Sized off the number stack it replaces; no envelope
    -- contribution, because it lives inside a span the numbers box reserves.
    deadIconAtlas  = "raidmarker",      -- key into DEAD_ICONS (engine.lua)
    deadIconScale  = 100,               -- percent of DEAD_ICON_BASE x stack height, 50-200
    -- Elite/rare classification icon: Blizzard's own nameplate art, on the
    -- name-relative location system the power/level texts use. Never shown on
    -- the player (hard early-out in the engine; the page hides the tab).
    -- Vertically fixed by the engine's classifySeatY -- no offset keys.
    classifyShow   = true,
    classifyLoc    = "topright",        -- bottomleft|bottomright|topleft|topright|nameside
    classifySize   = 20,                -- px, 8-48
}
table.freeze(UNIT_DEFAULTS_SHARED)

-- The mirrored target block: align "left" is the whole geometry difference
-- and nothing else changes between units, plus the
-- power/level locations, which mirror so each text keeps the same relationship
-- to the numbers on both frames.
local UNIT_DEFAULTS = {
    -- Visibility opacity is Player-only by design (strict UFX parity,
    -- the X Target page offers none either). Percent 0-100;
    -- priority With Target > In Combat > Out of Combat. Keys here and NOT in
    -- SHARED so the Target DB never carries them.
    Player = {
        opacityOutOfCombat = 100,
        opacityInCombat    = 100,
        opacityWithTarget  = 100,
    },
    Target = {
        align = "left",
        powerLoc = "bottomleft", altPowerLoc = "bottomright",
        -- topright is the clean mirror of the player's topleft, and it shares
        -- the corner with the classification icon on purpose: the icon steps
        -- aside (engine classifyShiftReserved) wherever the two coincide, which
        -- is a better answer than the earlier dodge of defaulting the level
        -- to the one free corner. Restored, so fresh profiles now
        -- look like every Target DB saved before that dodge.
        levelLoc = "topright",
    },
    -- Boss: styling identical to Target (Target, Focus and Boss all put the
    -- health block left of the name; nothing else changes between units), with
    -- one key different -- five stacked frames at Target's size is a lot of
    -- screen, so they ship smaller and the user raises the existing slider.
    Boss = {
        align = "left",
        powerLoc = "bottomleft", altPowerLoc = "bottomright",
        levelLoc = "topright",  -- shares the corner with the icon; see Target
        scale = 0.7,
        -- Stack layout. Unit-only keys -- absent from SHARED, so only the Boss
        -- DB carries them and CopyUnitFrameZSettings (a SHARED walk) can never
        -- touch them. Same construction as the Player opacity trio.
        --
        -- 0 is not "frames touching": stack.lua steps over the envelope's
        -- unused name-line reservation first, so 0 is as close as the content
        -- allows and the slider goes negative from there into real overlap.
        stackSpacing = 0,       -- px between frames, -20..40
        stackGrowth  = "down",  -- down | up: which end of the box Boss1 sits at
    },
}
table.freeze(UNIT_DEFAULTS)

UFZ._UNIT_DEFAULTS_SHARED = UNIT_DEFAULTS_SHARED
UFZ._UNIT_DEFAULTS = UNIT_DEFAULTS

function UFZ._EnsureUnitDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.unitFramesZUnits then
        profile.unitFramesZUnits = {}
    end
    local units = profile.unitFramesZUnits

    for _, unitKey in ipairs(UFZ.UNITS) do
        local cfg = units[unitKey]
        if not cfg then
            cfg = {}
            units[unitKey] = cfg
        end
        local override = UNIT_DEFAULTS[unitKey]
        for key, value in pairs(UNIT_DEFAULTS_SHARED) do
            if cfg[key] == nil then
                if override and override[key] ~= nil then
                    cfg[key] = override[key]
                else
                    cfg[key] = value
                end
            end
        end
        -- Unit-only keys (present in the override, absent from SHARED --
        -- e.g. the Player opacity trio) gap-fill here.
        if override then
            for key, value in pairs(override) do
                if cfg[key] == nil then cfg[key] = value end
            end
        end
    end

    return units
end

function UFZ._GetUnitConfig(unitKey)
    local units = UFZ._EnsureUnitDB()
    return units and units[unitKey]
end

--- Wipe a unit's config back to defaults (engine Reset). The table object is
--- kept (instances hold a reference to it); only its keys are replaced.
function UFZ._ResetUnitDB(unitKey)
    local cfg = UFZ._GetUnitConfig(unitKey)
    if not cfg then return nil end
    for k in pairs(cfg) do cfg[k] = nil end
    UFZ._EnsureUnitDB()
    return cfg
end

-- Copy From (settings panel header dropdown): styling only. Identity and the
-- mirrored handedness keys stay the destination's own, matching the X copy's
-- preserve-positioning approach.
local COPY_EXCLUDE = {
    -- Overall Scale sits on the positioning side of that line, not the styling
    -- side: it is the ONE setting the Edit Mode mirror carries, for the reason
    -- editmode.lua states -- it is judged by looking at the frame in place.
    -- Excluded when Boss shipped at a smaller default and "copy my
    -- Target look onto Boss" would otherwise have flattened it every time.
    scale = true,
    align = true,
    powerLoc = true,
    altPowerLoc = true,
    levelLoc = true,
    auraBuffsLoc = true,
    auraDebuffsLoc = true,
    auraOffsetY = true,  -- tuned against this frame's own satellite slack
    classifyLoc = true,  -- arrangement stays per-frame, like every other Loc
}

--- Copy one unit's Z settings onto another. Whitelist walk over
--- UNIT_DEFAULTS_SHARED (flat scalars, plain assignment): unit-only keys such
--- as the Player opacity trio are outside the shared table, so they neither
--- land on the destination nor get wiped from it, and frame positions live in
--- unitFramesZPositions -- untouched by construction.
function addon.CopyUnitFrameZSettings(sourceUnit, destUnit)
    if sourceUnit == destUnit then return false end
    local units = UFZ._EnsureUnitDB()
    local srcCfg = units and units[sourceUnit]
    local dstCfg = units and units[destUnit]
    if not srcCfg or not dstCfg then return false end

    for key in pairs(UNIT_DEFAULTS_SHARED) do
        if not COPY_EXCLUDE[key] and srcCfg[key] ~= nil then
            dstCfg[key] = srcCfg[key]
        end
    end

    -- Same cache nils as the other wholesale-change paths (reset, profile
    -- switch), then the full component pass: apply + visibility + suppression
    -- + the Cast Bar Z re-snap (a copied width/height moves the envelope).
    -- Every frame on the destination config, so a copy onto Boss reaches all
    -- five rather than just the first.
    for _, row in ipairs(UFZ._RowsForUnitKey(destUnit)) do
        local inst = UFZ._instances[row.frameKey]
        if inst then
            inst.lastDigitCount = nil
            inst.nameFitSize = nil
        end
    end
    UFZ._ApplyStyling()
    return true
end

--- True when this unit is in Z mode. State lives in moduleEnabled only -- the
--- per-unit table carries cosmetics, never the mode.
function UFZ._IsUnitEnabled(unitKey)
    return addon:IsModuleEnabled("unitFramesZ", unitKey)
end

--- The first instance a config key drives, or nil. The only instance for Player
--- and Target; the stack head for Boss. Anything that needs "an instance for
--- this config" -- the combat queue, a cache nil -- wants this one.
function UFZ._HeadInstance(unitKey)
    local rows = UFZ._RowsForUnitKey(unitKey)
    local row = rows[1]
    return row and UFZ._instances[row.frameKey] or nil
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- Master gate: OR of the per-unit sub-toggles (noMasterToggle table form).
    -- The component id is deliberately NOT in COMPONENT_TO_CATEGORY -- the
    -- RegisterComponent gate would probe IsModuleEnabled("unitFramesZ",
    -- "unitFramesZ"), which no sub key ever satisfies -- so this inline gate is
    -- the only one.
    if not self:IsModuleEnabled("unitFramesZ") then return end

    -- X/Z exclusion, re-asserted for imported or hand-edited profiles: Z wins,
    -- because a unitFramesZ key can only exist by explicit choice. Runs before
    -- init.lua builds the session module snapshot, so the nav never sees both.
    for _, unitKey in ipairs(UFZ.UNITS) do
        if self:IsModuleEnabled("unitFramesZ", unitKey)
            and self:IsModuleEnabled("unitFrames", unitKey) then
            self:SetModuleEnabled("unitFrames", unitKey, false)
        end
    end

    -- Pre-materialize the component DB so the zero-touch proxy doesn't skip
    -- ApplyStyling. Safe here: this runs behind the enabled gate.
    if self.db and self.db.profile then
        if not self.db.profile.components then
            self.db.profile.components = {}
        end
        if not self.db.profile.components["unitFramesZ"] then
            self.db.profile.components["unitFramesZ"] = {}
        end
    end

    local Component = addon.ComponentPrototype

    local comp = Component:New({
        id = "unitFramesZ",
        name = "Unit Frames Z",
        -- Everything user-facing is per unit (profile.unitFramesZUnits); the
        -- component DB exists so the apply pipeline runs, and so a genuinely
        -- shared setting has a declared home when one appears.
        settings = {},

        ApplyStyling = function(self)
            UFZ._ApplyStyling(self)
        end,
    })

    self:RegisterComponent(comp)
    UFZ._comp = comp

    -- Bootstrap on the first PLAYER_ENTERING_WORLD (mirrors castbarz/core.lua:
    -- the component system's ApplyStyling gate can skip this on a fresh profile).
    addon.Events.OnWorldEntered(function()
        if comp.db then
            UFZ._ApplyStyling(comp)
        end
    end)
end, "unitFramesZ")

--------------------------------------------------------------------------------
-- ApplyStyling
--------------------------------------------------------------------------------

function UFZ._ApplyStyling(comp)
    comp = comp or UFZ._comp
    if not comp then return end

    -- Guard for profile switches: the component stays registered for the
    -- session, so this can be reached with Z turned off everywhere.
    if not addon:IsModuleEnabled("unitFramesZ") then
        for _, inst in pairs(UFZ._instances) do
            -- Through the resolver, never a bare Hide: the frame's visibility
            -- is combat-protected (secure click child), and the resolver also
            -- retires the unit watch that would fight the hide.
            if inst.frame then UFZ._UpdateVisibility(inst) end
        end
        -- Retires the boss stack's Edit Mode anchor along with the frames.
        UFZ._ApplyStack("Boss")
        -- Hand Blizzard's frames back. Safe on a profile that never enabled Z:
        -- this only ever writes to a frame Z itself suppressed.
        UFZ._ApplySuppression()
        return
    end

    if not UFZ._initialized then
        UFZ._Initialize(comp)
    end

    for _, row in ipairs(UFZ.FRAMES) do
        if UFZ._IsUnitEnabled(row.unitKey) then
            local inst = UFZ._EnsureInstance(row)
            if inst then UFZ._ApplyAll(inst) end
        end
        local inst = UFZ._instances[row.frameKey]
        if inst then UFZ._UpdateVisibility(inst) end
    end

    -- The boss stack, once every frame it chains exists and has its envelope.
    UFZ._ApplyStack("Boss")

    -- Last, in one pass: this is the only place that knows the whole picture.
    -- Writes only on a transition, so a slider drag costs nothing here.
    UFZ._ApplySuppression()

    -- A cast bar snapped to Player or Target re-resolves its anchor through
    -- CBZ._ResolveAnchorFrame (the seam below), so re-assert the snap now that
    -- the Z frames exist / moved between X and Z.
    local CBZ = addon.CastBarZ
    if CBZ and CBZ._bars and CBZ._ApplySnap then
        for _, bar in pairs(CBZ._bars) do
            CBZ._ApplySnap(bar)
        end
    end
end

function UFZ._Initialize(comp)
    if UFZ._initialized then return end
    UFZ._initialized = true

    UFZ._EnsureUnitDB()
    UFZ._InitializeEditMode()
end

--------------------------------------------------------------------------------
-- The Cast Bar Z anchor seam
--------------------------------------------------------------------------------
-- castbarz/anchoring.lua calls this (nil-checked) before falling back to the
-- Blizzard root: a snapped cast bar follows whichever frame represents
-- the unit. Z mode -> the Scoot-owned frame; X or OFF -> nil -> Blizzard's.
--
-- Resolved per BAR, not per unit config. Boss is five bars sharing unitKey
-- "Boss", so a unitKey lookup would land all five on one frame; row.barKey is
-- the per-bar identity and equals unitKey for every non-boss row, so this one
-- lookup is correct universally.
--
-- The second return says "Z owns this unit" independently of whether the frame
-- exists yet. It matters because Z SUPPRESSES the Blizzard frame it replaces:
-- a parked frame keeps a valid rect at its old position, so falling back to it
-- would snap a visible cast bar to an invisible frame. Ownership without a
-- frame means "do not snap", not "snap to Blizzard".

local CBZ = addon.CastBarZ
if CBZ then
    function CBZ._ResolveCustomAnchorFrame(row)
        local unitKey = row and row.unitKey
        if not unitKey then return nil end
        if not addon:IsModuleEnabled("unitFramesZ", unitKey) then return nil end
        local inst = UFZ._instances[row.barKey]
        return (inst and inst.frame) or nil, true
    end
end
