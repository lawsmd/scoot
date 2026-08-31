--------------------------------------------------------------------------------
-- bars/valuecolor.lua
-- Event-driven value-based health color system for unit frame bars.
-- Handles UNIT_HEALTH, UNIT_MAXHEALTH, UNIT_HEAL_PREDICTION events to update
-- health bar colors in real-time based on remaining health percentage.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- UNIT_HEALTH event handler for value-based health bar coloring.
-- Uses UnitHealthPercent(unit, false, colorCurve) for secret-safe color computation.

do
    -- Map unit tokens to their health bar frames
    -- Returns: bar, useDark (both nil if not using value-based color mode)
    local function getHealthBarForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil

        if unit == "player" then
            local cfg = unitFrames and rawget(unitFrames, "Player") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local hb = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContent
                and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
                and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
            return hb, (colorMode == "valueDark")
        elseif unit == "target" then
            local cfg = unitFrames and rawget(unitFrames, "Target") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local hb = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            return hb, (colorMode == "valueDark")
        elseif unit == "focus" then
            local cfg = unitFrames and rawget(unitFrames, "Focus") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local hb = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            return hb, (colorMode == "valueDark")
        elseif unit:match("^boss%d$") then
            local cfg = unitFrames and rawget(unitFrames, "Boss") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local bossIndex = tonumber(unit:match("^boss(%d)$"))
            if bossIndex and bossIndex >= 1 and bossIndex <= 5 then
                local bossFrame = _G["Boss" .. bossIndex .. "TargetFrame"]
                local hb = bossFrame and bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
                return hb, (colorMode == "valueDark")
            end
        elseif unit == "targettarget" then
            local cfg = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local tot = _G.TargetFrameToT
            return (tot and tot.HealthBar or nil), (colorMode == "valueDark")
        elseif unit == "focustarget" then
            local cfg = unitFrames and rawget(unitFrames, "FocusTarget") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local fot = _G.FocusFrameToT
            return (fot and fot.HealthBar or nil), (colorMode == "valueDark")
        end
    end

    -- Helper to get the value color overlay for a bar (if active)
    local function getValueColorOverlay(bar)
        local st = bar and addon.FrameState and addon.FrameState.Get(bar)
        if st and st.rectActive and st.valueColorOverlay then
            return st.valueColorOverlay
        end
    end

    -- Apply "Color by Value" to health text FontStrings for a unit.
    -- Reuses the health color curve (same as bar coloring) for consistency.
    -- Only updates FontStrings whose colorMode is "value".
    local function applyHealthTextValueColor(unit)
        if not addon.BarsTextures or not addon.BarsTextures.applyHealthTextColor then return end

        -- Map unit token (lowercase) to unitFrames config key (capitalized)
        -- unitKey = config key in db.unitFrames ("Boss" for all boss frames)
        -- cacheKey = per-frame key in _ufHealthTextFonts ("Boss1", "Boss2", etc.)
        local unitKey, cacheKey
        if unit == "player" then unitKey = "Player"; cacheKey = "Player"
        elseif unit == "target" then unitKey = "Target"; cacheKey = "Target"
        elseif unit == "focus" then unitKey = "Focus"; cacheKey = "Focus"
        elseif unit == "pet" then unitKey = "Pet"; cacheKey = "Pet"
        elseif unit:match("^boss%d$") then
            unitKey = "Boss"
            cacheKey = "Boss" .. unit:match("^boss(%d)$")
        else return end

        local cache = addon._ufHealthTextFonts and addon._ufHealthTextFonts[cacheKey]
        if not cache then return end

        local db = addon.db and addon.db.profile
        local cfg = db and db.unitFrames and db.unitFrames[unitKey]
        if not cfg then return end

        -- Check health percent text (leftFS)
        local percentCfg = cfg.textHealthPercent
        if percentCfg and percentCfg.colorMode == "value" and cache.leftFS then
            addon.BarsTextures.applyHealthTextColor(cache.leftFS, unit)
        end

        -- Check health value text (rightFS)
        local valueCfg = cfg.textHealthValue
        if valueCfg and valueCfg.colorMode == "value" and cache.rightFS then
            addon.BarsTextures.applyHealthTextColor(cache.rightFS, unit)
        end

        -- Check center TextString (used in NUMERIC display mode)
        if valueCfg and valueCfg.colorMode == "value" and cache.textStringFS then
            addon.BarsTextures.applyHealthTextColor(cache.textStringFS, unit)
        end
    end

    -- UNIT_HEALTH event handler for value-based coloring
    -- Also register UNIT_MAXHEALTH and UNIT_HEAL_PREDICTION to catch edge cases:
    -- - UNIT_MAXHEALTH: When max health changes (buffs, potions that heal to cap)
    -- - UNIT_HEAL_PREDICTION: Incoming heal updates that may affect display
    -- Fixes "stuck colors" when healing to exactly 100% (no subsequent UNIT_HEALTH fires)
    local function onHealthEvent(event, unit)
        if not unit then return end

        local bar, useDark = getHealthBarForUnit(unit)
        if bar then
            -- Apply value-based color using the color curve
            -- Use the overlay texture if available (cleaner than modifying Blizzard's textures)
            if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                local overlay = getValueColorOverlay(bar)
                addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)

                -- Schedule safety reapply only for non-overlay bars (Player, Target, Focus, Boss)
                -- where Blizzard's native coloring may fight the custom color. Overlay-active bars (party/raid)
                -- don't need this — usePredicted=true eliminates the timing lag.
                if not overlay and addon.BarsTextures.scheduleColorValidation then
                    addon.BarsTextures.scheduleColorValidation(bar, unit, nil, useDark)
                end
            end
        end

        -- Update health text coloring (independent of bar color mode)
        applyHealthTextValueColor(unit)
    end
    addon.Events.On("UnitFrames:ValueColor", "UNIT_HEALTH", onHealthEvent)
    addon.Events.On("UnitFrames:ValueColor", "UNIT_MAXHEALTH", onHealthEvent)
    addon.Events.On("UnitFrames:ValueColor", "UNIT_HEAL_PREDICTION", onHealthEvent)

    -- Also handle PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED
    -- to apply initial color when target/focus changes
    local function onUnitChanged(event)
        if event == "PLAYER_TARGET_CHANGED" then
            local bar, useDark = getHealthBarForUnit("target")
            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                local overlay = getValueColorOverlay(bar)
                addon.BarsTextures.applyValueBasedColor(bar, "target", overlay, useDark)
            end
            applyHealthTextValueColor("target")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            local bar, useDark = getHealthBarForUnit("focus")
            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                local overlay = getValueColorOverlay(bar)
                addon.BarsTextures.applyValueBasedColor(bar, "focus", overlay, useDark)
            end
            applyHealthTextValueColor("focus")
        end
    end
    addon.Events.On("UnitFrames:ValueColor", "PLAYER_TARGET_CHANGED", onUnitChanged)
    addon.Events.On("UnitFrames:ValueColor", "PLAYER_FOCUS_CHANGED", onUnitChanged)

    -- SetValue hooks for instant color updates (bypasses UNIT_HEALTH event delay)
    -- SetValue fires immediately when health changes, providing zero-delay response.
    local function hookSetValueForValueColor(bar, unitKey, unitToken)
        if not bar or not bar.SetValue then return end
        local barState = addon.FrameState and addon.FrameState.Get(bar)
        if barState and barState.valueColorSetValueHooked then return end
        if barState then barState.valueColorSetValueHooked = true end

        hooksecurefunc(bar, "SetValue", function(self)
            local cfg = addon.db and addon.db.profile
            cfg = cfg and cfg.unitFrames and cfg.unitFrames[unitKey]
            local colorMode = cfg and cfg.healthBarColorMode
            if colorMode == "value" or colorMode == "valueDark" then
                local useDark = (colorMode == "valueDark")
                if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                    local overlay = getValueColorOverlay(self)
                    addon.BarsTextures.applyValueBasedColor(self, unitToken, overlay, useDark)
                end
            end
            -- Update health text coloring on SetValue for instant response
            applyHealthTextValueColor(unitToken)
        end)
    end

    -- Apply SetValue hooks after a short delay to ensure frames exist
    C_Timer.After(1, function()
        -- Player
        local playerHB = PlayerFrame and PlayerFrame.PlayerFrameContent
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
        if playerHB then
            hookSetValueForValueColor(playerHB, "Player", "player")
        end

        -- Target
        local targetHB = TargetFrame and TargetFrame.TargetFrameContent
            and TargetFrame.TargetFrameContent.TargetFrameContentMain
            and TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
        if targetHB then
            hookSetValueForValueColor(targetHB, "Target", "target")
        end

        -- Focus
        local focusHB = FocusFrame and FocusFrame.TargetFrameContent
            and FocusFrame.TargetFrameContent.TargetFrameContentMain
            and FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
        if focusHB then
            hookSetValueForValueColor(focusHB, "Focus", "focus")
        end

        -- Boss frames (1-5)
        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            local bossHB = bossFrame and bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            if bossHB then
                hookSetValueForValueColor(bossHB, "Boss", "boss" .. i)
            end
        end

        -- TargetOfTarget
        local totHB = TargetFrameToT and TargetFrameToT.HealthBar
        if totHB then
            hookSetValueForValueColor(totHB, "TargetOfTarget", "targettarget")
        end

        -- FocusTarget
        local fotHB = FocusFrameToT and FocusFrameToT.HealthBar
        if fotHB then
            hookSetValueForValueColor(fotHB, "FocusTarget", "focustarget")
        end

        -- Hook RefreshOpacityState to re-apply value-based colors after opacity changes.
        -- Ensures color persists through opacity transitions (e.g., 20% -> 100% when target acquired).
        if addon.RefreshOpacityState and not addon._valueColorOpacityHooked then
            addon._valueColorOpacityHooked = true
            hooksecurefunc(addon, "RefreshOpacityState", function()
                -- Slightly defer to ensure opacity change is complete
                C_Timer.After(0.01, function()
                    local unitMappings = {
                        { key = "Player", token = "player" },
                        { key = "Target", token = "target" },
                        { key = "Focus", token = "focus" },
                        { key = "TargetOfTarget", token = "targettarget" },
                        { key = "FocusTarget", token = "focustarget" },
                    }
                    for _, mapping in ipairs(unitMappings) do
                        local cfg = addon.db and addon.db.profile
                            and addon.db.profile.unitFrames
                            and addon.db.profile.unitFrames[mapping.key]
                        local colorMode = cfg and cfg.healthBarColorMode
                        if colorMode == "value" or colorMode == "valueDark" then
                            local bar, useDark = getHealthBarForUnit(mapping.token)
                            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                local overlay = getValueColorOverlay(bar)
                                addon.BarsTextures.applyValueBasedColor(bar, mapping.token, overlay, useDark)
                            end
                        end
                    end
                    -- Boss frames
                    local bossCfg = addon.db and addon.db.profile
                        and addon.db.profile.unitFrames
                        and addon.db.profile.unitFrames.Boss
                    local bossColorMode = bossCfg and bossCfg.healthBarColorMode
                    if bossColorMode == "value" or bossColorMode == "valueDark" then
                        local useDark = (bossColorMode == "valueDark")
                        for i = 1, 5 do
                            local bar = getHealthBarForUnit("boss" .. i)
                            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                local overlay = getValueColorOverlay(bar)
                                addon.BarsTextures.applyValueBasedColor(bar, "boss" .. i, overlay, useDark)
                            end
                        end
                    end
                end)
            end)
        end

    end)
end
