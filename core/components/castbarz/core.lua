--------------------------------------------------------------------------------
-- castbarz/core.lua
-- Cast Bar Z: Scoot-owned cast bars with a clipped-column text-fill fill effect.
-- Namespace, per-unit DB, and component registration.
--
-- Z owns its frames outright, so unlike Cast Bar X it never fights Blizzard's
-- StatusBar for a pixel. The trade is that it drives everything itself: events,
-- progress, and text.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.CastBarZ = {}
local CBZ = addon.CastBarZ

-- Three identifiers, deliberately distinct, because Boss is one configuration
-- driving five bars:
--
--   unitKey  "Boss"   DB config, selector strip, Edit Mode pageState, line color
--   barKey   "Boss3"  the _bars index, the frame name, the stored position
--   unit     "boss3"  every API call -- ramp resolution, cast state, events
--
-- Boss shares one config the same way Cast Bar X does (db.unitFrames.Boss.castBar
-- is common to all five). It also keeps the selector strip at
-- five buttons; nine would overflow the settings content area.
--
-- UNITS is the config / selector list -- five entries, not nine, because Boss is
-- one configuration. ToT and ToF are deliberately absent: those tokens receive no
-- UNIT_SPELLCAST_* events at all, so a bar for them could never fill.
CBZ.UNITS = { "Player", "Target", "Focus", "Pet", "Boss" }
CBZ.UNIT_LABELS = {
    Player = "Player", Target = "Target", Focus = "Focus",
    Pet = "Pet", Boss = "Boss",
}

CBZ.NUM_BOSS_BARS = addon.NUM_BOSS_FRAMES

-- One row per BAR. `changeEvent` is the event after which this bar's unit may be a
-- different creature entirely, and is what triggers a hard reset + resync.
-- `changeEventUnit` is set only when that event is a genuine unit event whose unit
-- argument is NOT this bar's token.
--
-- Anchor frame names are paths verified in the frame stack -- never
-- guessed. They are unused until anchoring.lua resolves them, but belong here.
CBZ.BARS = {
    { barKey = "Player", unitKey = "Player", token = "player",
      anchorFrame = "PlayerFrame" },
    { barKey = "Target", unitKey = "Target", token = "target",
      anchorFrame = "TargetFrame", changeEvent = "PLAYER_TARGET_CHANGED" },
    { barKey = "Focus", unitKey = "Focus", token = "focus",
      anchorFrame = "FocusFrame", changeEvent = "PLAYER_FOCUS_CHANGED" },
    -- UNIT_PET's unit argument is the pet's OWNER, not the pet, so it filters on
    -- "player". Left unfiltered it would fire on every party and raid member's pet
    -- and reset this bar in the middle of the player's own pet's cast.
    { barKey = "Pet", unitKey = "Pet", token = "pet",
      anchorFrame = "PetFrame", changeEvent = "UNIT_PET", changeEventUnit = "player" },
}

-- Boss: one config, five bars. INSTANCE_ENCOUNTER_ENGAGE_UNIT is not a unit event
-- and carries no argument to filter on, so each bar's own frame takes it plainly
-- and resyncs itself -- which is what a shared frame would have done in a loop.
for i = 1, CBZ.NUM_BOSS_BARS do
    CBZ.BARS[#CBZ.BARS + 1] = {
        barKey      = "Boss" .. i,
        unitKey     = "Boss",
        token       = "boss" .. i,
        anchorFrame = "Boss" .. i .. "TargetFrame",
        changeEvent = "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    }
end

function CBZ._RowForBarKey(barKey)
    for _, row in ipairs(CBZ.BARS) do
        if row.barKey == barKey then return row end
    end
    return nil
end

--- The first bar belonging to a config. For everything but Boss that is the only
--- one; for Boss it is boss1, which is what the settings preview should model.
function CBZ._RowForUnitKey(unitKey)
    for _, row in ipairs(CBZ.BARS) do
        if row.unitKey == unitKey then return row end
    end
    return nil
end

-- Runtime state (not persisted)
CBZ._bars = {}          -- [barKey] = bar frame, built lazily by _EnsureBar
CBZ._comp = nil
CBZ._initialized = false

--------------------------------------------------------------------------------
-- Per-Unit DB
--------------------------------------------------------------------------------
-- Split follows the Damage Meters Y precedent: things that genuinely differ per
-- instance live in their own profile table, everything cosmetic lives in the
-- component's `settings` and is shared. A boss bar wants a different width than
-- the player bar; it does not want a different font.

local UNIT_DEFAULTS_SHARED = {
    enabled      = false,   -- zero-touch: nothing is created until the user says so
    barWidth     = 200,
    positionMode = "free",  -- "free" | "above" | "below" | "left" | "right"
                            -- (resolved by anchoring.lua)
    -- Snap offsets are NOT declared here: they are lazy flat keys per
    -- (direction, anchor variant) -- snapOffset_<mode>_<X|Z>_<x|y>, absent = 0
    -- (anchoring.lua). Declaring 16 zeros per unit would be gap-fill noise.

    -- Which side of the bar the cast time readout sits on. Per unit rather than
    -- shared because it is a property of where the bar SITS, not of how it looks:
    -- a bar snapped to the left of its unit frame wants its readout on the left,
    -- or the number lands on the frame.
    castTimeSide = "right", -- "right" | "left"
}
table.freeze(UNIT_DEFAULTS_SHARED)

local UNIT_DEFAULTS = {
    -- Player is on once the module itself is on. The module toggle is the
    -- zero-touch gate: a fresh profile never reaches this table at all, and a
    -- user who explicitly enables Cast Bars should see one without hunting for a
    -- second switch. Every other unit stays off.
    Player = { barWidth = 260, enabled = true },

    -- Narrower because five of them are on screen at once, and because Blizzard's
    -- own boss spell bar is the narrowest of its templates (120, BossSpellBarTemplate).
    -- positionMode is set now although nothing reads it until step 6: a profile
    -- created in between then starts with the mode Boss is going to be coerced to
    -- anyway, rather than one that has to be migrated.
    --
    -- castTimeSide follows from positionMode: "left" puts the bar's RIGHT edge
    -- against the boss frame's LEFT edge, so a right-side readout would sit on top
    -- of the boss frame the bar belongs to.
    Boss = { barWidth = 150, positionMode = "left", castTimeSide = "left" },
}
table.freeze(UNIT_DEFAULTS)

function CBZ._EnsureUnitDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.castBarZUnits then
        profile.castBarZUnits = {}
    end
    local units = profile.castBarZUnits

    for _, unitKey in ipairs(CBZ.UNITS) do
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

        -- One-time migration: the legacy shared offsetX/offsetY
        -- pair was always tuned against the Blizzard (X) frames, so it becomes
        -- the X-variant pair of the direction it was stored with; a free bar
        -- never used it. Nil'ing the keys is what makes this run once.
        if cfg.offsetX ~= nil or cfg.offsetY ~= nil then
            local mode = cfg.positionMode
            if mode and mode ~= "free" then
                cfg["snapOffset_" .. mode .. "_X_x"] = tonumber(cfg.offsetX) or 0
                cfg["snapOffset_" .. mode .. "_X_y"] = tonumber(cfg.offsetY) or 0
            end
            cfg.offsetX = nil
            cfg.offsetY = nil
        end
    end

    return units
end

function CBZ._GetUnitConfig(unitKey)
    local units = CBZ._EnsureUnitDB()
    return units and units[unitKey]
end

--- True when this unit should have a live bar on the HUD.
function CBZ._IsUnitEnabled(unitKey)
    local cfg = CBZ._GetUnitConfig(unitKey)
    return cfg and cfg.enabled == true
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- The sub-toggle id must match the component id: addon:RegisterComponent
    -- gates on IsModuleEnabled(GetComponentCategory(id), id), so a mismatch
    -- makes the component silently never register, with no error anywhere.
    if not self:IsModuleEnabled("castBars", "castBarZ") then return end

    -- Pre-materialize the component DB so the zero-touch proxy doesn't skip
    -- ApplyStyling. Safe here: this runs behind the enabled gate.
    if self.db and self.db.profile then
        if not self.db.profile.components then
            self.db.profile.components = {}
        end
        if not self.db.profile.components["castBarZ"] then
            self.db.profile.components["castBarZ"] = {}
        end
    end

    local Component = addon.ComponentPrototype

    local comp = Component:New({
        id = "castBarZ",
        name = "Cast Bar Z",
        settings = {
            -- These defaults are the component's house look: Scoot's own face in
            -- its heaviest weight, the caret spark and the success glow. Every
            -- scalar default here must be mirrored in SETTING_FALLBACKS below,
            -- which serves a bar whose component DB is missing.
            --
            -- Zero-touch survives at the category level -- a fresh profile has no
            -- moduleEnabled.castBars key, so no bar exists until Z is selected --
            -- but not at the key level: component defaults are served through a
            -- metatable (base/core.lua:52-59), so a profile that never touched a
            -- key follows a change of default. Accepted, deliberately, for the
            -- four look-defining keys (fontFace, fontStyle, sparkStyle,
            -- completionFX). Anything that adds an element rather than restyling
            -- one -- castTime -- still starts off.

            -- Text
            fontFace   = { type = "addon", default = "ROBOTO_SEMICOND_BLACK" },
            fontSize   = { type = "addon", default = 14 },
            fontStyle  = { type = "addon", default = "SHADOWTHICKOUTLINE" },

            -- Fill
            gradient   = { type = "addon", default = true },
            lineHeight = { type = "addon", default = "medium" },
            capSize    = { type = "addon", default = "medium" },

            -- Spark. showSpark is the master switch, sparkStyle picks which art.
            showSpark  = { type = "addon", default = true },
            sparkStyle = { type = "addon", default = "caret" },

            -- Cast completion. "glow" is the success glow; "none" turns it off.
            completionFX = { type = "addon", default = "glow" },

            -- Color for both flourishes. "spellName" takes the bright end of the
            -- cast's own ramp -- the stop the last band of the name is drawn in --
            -- so on your bar it is your spec color and on a target's it is that
            -- unit's class color. The key says where the value is resolved FROM;
            -- the settings label reads "Spec Color", which is what it amounts to
            -- on the bar the user is looking at while they set it. There is no
            -- third "whatever it is now" mode: Blizzard's pip drew in its own gold
            -- and every other spark drew in the ramp, so one option covering both
            -- would have named two behaviours.
            sparkColorMode      = { type = "addon", default = "spellName" },
            sparkColor          = { type = "addon", default = { 1, 1, 1, 1 } },
            completionColorMode = { type = "addon", default = "spellName" },
            completionColor     = { type = "addon", default = { 1, 1, 1, 1 } },

            -- Empowered casts. On by default: this is not a flourish, it is the
            -- only way an empowered bar can say which tier you are about to
            -- release at. Off falls back to a plain filling bar, which is what
            -- Phase 1 drew.
            empoweredTiers = { type = "addon", default = true },

            -- Cast time readout. Off by default: it adds an element beside the bar
            -- rather than restyling one, so it stays opt-in. It gets
            -- its own size (smaller, so it cannot compete with the name it sits
            -- beside) and its own face; style stays shared, since a readout in a
            -- different weight to the name beside it reads as a mistake.
            --
            -- castTimeFont is declared with NO default, deliberately. nil means
            -- "whatever Spell Name is using", so a profile that never opens the
            -- tab tracks the shared font exactly as it did before this setting
            -- existed -- and a default here would be returned by the settings
            -- metatable (base/core.lua:52-59) and pin the face on every profile
            -- at once. It must still be DECLARED or ResetComponentSettings
            -- (base/core.lua:497-501) would wipe it as an unknown key.
            castTime        = { type = "addon", default = false },
            castTimeReadout = { type = "addon", default = "remaining" },
            castTimeFont    = { type = "addon" },
            castTimeSize    = { type = "addon", default = 12 },
            castTimeColor   = { type = "addon", default = { 0.85, 0.85, 0.85, 1 } },
            -- 10 is Blizzard's own gap for the same element
            -- (CastingBarFrame.xml:336-340).
            castTimeGap     = { type = "addon", default = 10 },
            castTimeOffsetY = { type = "addon", default = 0 },
        },

        ApplyStyling = function(self)
            CBZ._ApplyStyling(self)
        end,
    })

    self:RegisterComponent(comp)
    CBZ._comp = comp

    -- Bootstrap on the first PLAYER_ENTERING_WORLD. The component system's
    -- ApplyStyling gate can skip it on a fresh profile, so Z self-bootstraps
    -- once DB linking is complete (mirrors damagemetersY/core.lua).
    addon.Events.OnWorldEntered(function()
        if comp.db then
            CBZ._ApplyStyling(comp)
        end
    end)
end, "castBars")

--------------------------------------------------------------------------------
-- ApplyStyling
--------------------------------------------------------------------------------

function CBZ._ApplyStyling(comp)
    comp = comp or CBZ._comp
    if not comp then return end

    -- Guard for profile switches: the component stays registered for the
    -- session, so this can be reached with Z turned off.
    if not addon:IsModuleEnabled("castBars", "castBarZ") then
        if CBZ._initialized then
            for _, bar in pairs(CBZ._bars) do
                bar:Hide()
            end
        end
        -- Hand Blizzard's bars back. Safe on a profile that never enabled Z: this
        -- only ever writes to a frame Z itself suppressed.
        CBZ._ApplySuppression()
        return
    end

    if not CBZ._initialized then
        CBZ._Initialize(comp)
    end

    for _, row in ipairs(CBZ.BARS) do
        if CBZ._IsUnitEnabled(row.unitKey) then
            CBZ._EnsureBar(row.barKey)
        end
        CBZ._ApplyBar(row.barKey, comp)
    end

    -- Last, and covering every bar in one pass rather than per row: Boss is five
    -- bars behind one enable, and this is the only place that knows the whole
    -- picture. Writes only on a change, so a slider drag costs nothing here.
    CBZ._ApplySuppression()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function CBZ._Initialize(comp)
    if CBZ._initialized then return end
    CBZ._initialized = true

    CBZ._EnsureUnitDB()

    -- Bars themselves are built lazily by _EnsureBar; only the machinery that has
    -- to exist before any of them do is set up here.
    CBZ._InitializeEvents(comp)
    CBZ._InitializeEditMode()
end

--- Build a bar the first time its unit is switched on.
---
--- Nine bars x 12 bands x 2 copies is 216 FontStrings, and a profile with only the
--- Player enabled wants none of them. A disabled unit costs nothing and correctly
--- does not appear in Edit Mode; it starts existing the moment it is enabled, and
--- is never torn down again for the session.
function CBZ._EnsureBar(barKey)
    local existing = CBZ._bars[barKey]
    if existing then return existing end

    local row = CBZ._RowForBarKey(barKey)
    if not row then return nil end

    local bar = CBZ._CreateBar(row, CBZ._comp)
    CBZ._bars[barKey] = bar

    CBZ._RegisterBarEvents(bar, row)
    CBZ._RegisterBarEditMode(bar, row)

    -- The unit may already be casting -- enabling a bar mid-cast is the obvious way
    -- to test one. Deferred so the caller's _ApplyBar has laid the frame out first;
    -- syncing into an unlaid bar would paint a name across a zero-width band set.
    C_Timer.After(0, function()
        CBZ._SyncCastState(row.barKey)
    end)

    return bar
end

--------------------------------------------------------------------------------
-- Shared setting accessors
--------------------------------------------------------------------------------
-- Every caller reads settings through these so a missing component DB degrades
-- to the documented default instead of erroring mid-cast.

local SETTING_FALLBACKS = {
    fontFace = "ROBOTO_SEMICOND_BLACK", fontSize = 14, fontStyle = "SHADOWTHICKOUTLINE",
    gradient = true, lineHeight = "medium", capSize = "medium", showSpark = true,
    sparkStyle = "caret", completionFX = "glow", empoweredTiers = true,
    sparkColorMode = "spellName", completionColorMode = "spellName",
    castTime = false, castTimeReadout = "remaining", castTimeSize = 12,
    castTimeGap = 10, castTimeOffsetY = 0,
    -- Deliberately absent: every table-valued setting -- castTimeColor, sparkColor,
    -- completionColor. This table is frozen, so one handed out as a fallback would
    -- be shared by every caller and would throw the moment one wrote to it. Each
    -- resolver owns its own default instead: _GetCastTimeColor (casttime.lua),
    -- _ResolveSparkColor and _ResolveFinishColor (effects.lua).
}
table.freeze(SETTING_FALLBACKS)

function CBZ._GetSetting(key)
    local comp = CBZ._comp
    local db = comp and comp.db
    local value = db and db[key]
    if value == nil then return SETTING_FALLBACKS[key] end
    return value
end

-- Three-step sizes, stored as names rather than raw numbers so the DB says what
-- the user picked and a future re-tune of the pixel values does not silently
-- reinterpret saved profiles.
CBZ.LINE_HEIGHTS = { thin = 1, medium = 2, thick = 4 }
CBZ.CAP_SIZES    = { short = 8, medium = 10, tall = 14 }
table.freeze(CBZ.LINE_HEIGHTS)
table.freeze(CBZ.CAP_SIZES)

function CBZ._GetLineHeight()
    return CBZ.LINE_HEIGHTS[CBZ._GetSetting("lineHeight")] or 2
end

function CBZ._GetCapSize()
    return CBZ.CAP_SIZES[CBZ._GetSetting("capSize")] or 10
end
