--------------------------------------------------------------------------------
-- text/health.lua
-- Health text kind descriptor and forks for the shared text pipeline
-- (text/pipeline.lua): bar and FontString resolvers, the health color half,
-- and the DeadText/UnconsciousText font inheritance.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Health text opts for ResolveColorRGBA. The sniff pair keeps the historical
-- behavior: nil mode or an explicit "default" with a stored non-white color
-- applies that color; no barKind, so a class miss stays white, not green
local ufHealthTextColorOpts = { legacySniff = true, legacySniffDefault = true }

-- Font half and Zero-Touch gate opts for this file's value texts
local ufTextFontOpts = { size = 14 }
local ufTextCustomizationOpts = { alignment = true, alignmentMode = true }

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

-- Shared frame resolvers (core/frames.lua)
local Frames = addon.Frames

-- Cross-file import: the shared text pipeline builder (text/pipeline.lua, loaded first in TOC)
local buildTextPipeline = addon.UnitFrameText._BuildTextPipeline

--Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Hide-enforcement hooks (core/enforce.lua). The hidden flag stays in
-- FrameState, where the profile-switch reset in base/core.lua also clears it;
-- the keys read it live. Show and SetText re-assert at once, SetAlpha after a
-- stack break; every hook bails while Edit Mode is open.
local HEALTH_TEXT_OPTS = {
    methods = { "Show", "SetAlpha", "SetText" },
    timing = { SetAlpha = "defer" },
    skipInEditMode = true,
    when = function(fs) return FS.IsHidden(fs, "healthText") end,
}
local HEALTH_TEXT_CENTER_OPTS = {
    methods = { "SetText" },
    skipInEditMode = true,
    when = function(fs) return FS.IsHidden(fs, "healthTextCenter") end,
}

-- Unit Frames: Toggle Health % (LeftText) and Value (RightText) visibility per unit
do
    -- Check whether the current player can have an Alternate Power Bar.
    -- DRUID is treated as class-capable (form/talent driven, not reliably spec-gated).
    local function playerHasAlternatePowerBar()
        if not UnitClass or not GetSpecialization or not GetSpecializationInfo then
            return false
        end
        local _, classToken = UnitClass("player")
        if not classToken then
            return false
        end

        -- Class-capable fast-paths (form/talent driven; not reliably spec-gated).
        if classToken == "DRUID" then
            return true
        end

        local specIndex = GetSpecialization()
        if not specIndex then
            return false
        end
        local specID = select(1, GetSpecializationInfo(specIndex))
        if not specID then
            return false
        end

        -- Map of class -> set of specIDs that use the global AlternatePowerBar.
        local altSpecsByClass = {
            PRIEST = { [258] = true },  -- Shadow
            MONK   = { [268] = true },  -- Brewmaster
            SHAMAN = { [262] = true },  -- Elemental
        }

        local classSpecs = altSpecsByClass[classToken]
        return classSpecs and classSpecs[specID] or false
    end

    -- Expose for UI modules (builders.lua) to gate the Alternate Power Bar section.
    addon.UnitFrames_PlayerHasAlternatePowerBar = playerHasAlternatePowerBar

    -- Targeted zero-touch check for DeadText/UnconsciousText: only fontFace and style matter
    -- (color, alignment, offset are irrelevant: Blizzard's original values are kept).
    -- Deliberately narrower than addon.HasTextCustomization.
    local function hasFontFaceOrStyle(styleCfg)
        if not styleCfg then return false end
        if styleCfg.fontFace ~= nil and styleCfg.fontFace ~= "" and styleCfg.fontFace ~= "FRIZQT__" then
            return true
        end
        if styleCfg.style ~= nil then
            return true
        end
        return false
    end

    -- Apply font face and outline style to DeadText/UnconsciousText FontStrings,
    -- inheriting from the user's Health Bar > Value Text settings.
    -- Preserves Blizzard's original size and color.
    local function applyDeadTextFontInheritance(fs, styleCfg)
        if not fs or not styleCfg then return end
        if not hasFontFaceOrStyle(styleCfg) then return end

        -- Read current font size to preserve it
        local ok, currentFont, currentSize, currentFlags = pcall(fs.GetFont, fs)
        if not ok or type(currentSize) ~= "number" then return end

        local face = addon.ResolveFontFace(styleCfg.fontFace)
        local outline = styleCfg.style ~= nil and tostring(styleCfg.style) or (currentFlags or "")

        addon.ApplyFontStyle(fs, face, currentSize, outline)
    end

    -- Hook Show() on DeadText/UnconsciousText so font inheritance reapplies
    -- each time Blizzard's CheckDead() displays the text.
    local function hookDeadTextShow(fs, unit)
        if not fs then return end
        local fstate = FS
        if not fstate then return end
        if fstate.IsHooked(fs, "deadTextFontShow") then return end
        fstate.MarkHooked(fs, "deadTextFontShow")

        if _G.hooksecurefunc then
            -- Kept off addon.Enforce: not a hide; reapplies font inheritance when DeadText shows.
            _G.hooksecurefunc(fs, "Show", function(self)
                if isEditModeActive() then return end
                local db = addon and addon.db and addon.db.profile
                if not db then return end
                local unitFrames = rawget(db, "unitFrames")
                local cfg = unitFrames and rawget(unitFrames, unit) or nil
                if not cfg then return end
                applyDeadTextFontInheritance(self, cfg.textHealthValue or {})
            end)
        end
    end

    -- Color half of the text styling: "Color by Value" routes through the
    -- health color curve, everything else through ResolveColorRGBA.
    local function applyHealthTextColor(fs, styleCfg, baselineKey)
        local colorMode = styleCfg.colorMode or "default"
        -- Extract unit token from baselineKey (e.g., "Player:health-left" -> "player")
        local unitToken = baselineKey and baselineKey:match("^(.-):")
        if unitToken then unitToken = unitToken:lower() end
        if addon.IsValueColorMode(colorMode) then
            -- "Color by Value": use health-based color curve (secret-safe)
            if unitToken and addon.BarsTextures and addon.BarsTextures.applyHealthTextColor then
                addon.BarsTextures.applyHealthTextColor(fs, unitToken, colorMode == "valueDark")
            elseif fs.SetTextColor then
                pcall(fs.SetTextColor, fs, 0, 1, 0, 1) -- fallback green
            end
        else
            ufHealthTextColorOpts.unitForClass = unitToken or "player"
            local cr, cg, cb, ca = addon.ResolveColorRGBA(colorMode, styleCfg.color, ufHealthTextColorOpts)
            if fs.SetTextColor then
                pcall(fs.SetTextColor, fs, cr, cg, cb, ca)
            end
        end
    end

    -- First-rung left/right FontString paths (no scanning); the pipeline falls
    -- back to the hint scan when these miss.
    local function directHealthTexts(frame, unit)
        local leftFS, rightFS
        if unit == "Pet" then
            leftFS = _G.PetFrameHealthBarTextLeft
            rightFS = _G.PetFrameHealthBarTextRight
        end
        leftFS = leftFS or (frame and frame.HealthBarsContainer and frame.HealthBarsContainer.LeftText)
        rightFS = rightFS or (frame and frame.HealthBarsContainer and frame.HealthBarsContainer.RightText)
        return leftFS, rightFS
    end

    -- DeadText / UnconsciousText: inherit font face + style from Health Value text settings.
    -- Only Target and Focus have these (Player/Pet do not).
    local function applyDeadTextForUnit(unit, cfg)
        if unit == "Target" or unit == "Focus" then
            local hbContainer = Frames.resolveHealthContainer(nil, unit)
            if hbContainer then
                local valueCfg = cfg.textHealthValue or {}
                applyDeadTextFontInheritance(hbContainer.DeadText, valueCfg)
                hookDeadTextShow(hbContainer.DeadText, unit)
                applyDeadTextFontInheritance(hbContainer.UnconsciousText, valueCfg)
                hookDeadTextShow(hbContainer.UnconsciousText, unit)
            end
        end
    end

    -- The same inheritance for a Boss health bar container
    local function applyBossDeadText(container, cfg)
        local valueCfg = cfg.textHealthValue or {}
        applyDeadTextFontInheritance(container.DeadText, valueCfg)
        hookDeadTextShow(container.DeadText, "Boss")
        applyDeadTextFontInheritance(container.UnconsciousText, valueCfg)
        hookDeadTextShow(container.UnconsciousText, "Boss")
    end

    local P = buildTextPipeline({
        resource = "Health",
        slug = "health",
        fontCache = "_ufHealthTextFonts",
        baselineTable = "_ufTextBaselines",
        hookMarker = "healthBarUpdateTextString",
        visibilityForName = "ApplyUnitFrameHealthTextVisibilityFor",
        hiddenKey = "healthText",
        hiddenCenterKey = "healthTextCenter",
        appliedProp = "healthTextAppliedHidden",
        keys = {
            percentHidden = "healthPercentHidden",
            valueHidden = "healthValueHidden",
            percentStyle = "textHealthPercent",
            valueStyle = "textHealthValue",
        },
        textOpts = HEALTH_TEXT_OPTS,
        centerOpts = HEALTH_TEXT_CENTER_OPTS,
        fontOpts = ufTextFontOpts,
        customizationOpts = ufTextCustomizationOpts,
        barResolver = Frames.resolveHealthBar,
        directTexts = directHealthTexts,
        hints = {
            left  = { "HealthBarsContainer.LeftText",  ".LeftText",  "HealthBarTextLeft" },
            right = { "HealthBarsContainer.RightText", ".RightText", "HealthBarTextRight" },
        },
        centerResolver = Frames.resolveHealthCenterText,
        bossContainer = Frames.resolveBossHealthBarsContainer,
        bossBar = function(container) return container.HealthBar end,
        bossCenter = function(container) return container.HealthBarText end,
        colorApplier = applyHealthTextColor,
        applyForUnitExtras = applyDeadTextForUnit,
        bossExtras = applyBossDeadText,
    })

    addon.ApplyBossHealthTextStyling = P.applyBossStyling
    addon.ApplyUnitFrameHealthTextVisibilityFor = P.applyVisibilityFor
    addon.ApplyAllUnitFrameHealthTextVisibility = P.applyAll
end
