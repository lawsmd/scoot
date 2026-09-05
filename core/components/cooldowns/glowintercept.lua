-- glowintercept.lua - Cooldown Manager: Blizzard proc-glow interception
-- Hooks ActionButtonSpellAlertManager to resize the lazily created proc alert
-- on sized CDM icons and to replace Blizzard glows with configured ones.
local addonName, addon = ...

local SS = addon.SecretSafe
local Overlays = addon.CDMOverlays
local CDM_VIEWER_NAMES = addon.CDM_VIEWERS

-- ABE (ActionBarsEnhanced) interop: when loaded, ABE manages its own proc animations
local abeLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ActionBarsEnhanced")

-- Proc start style -> animation ID mapping
local PROC_START_ANIM_IDS = {
    flashPulse = "procStartFlashPulse",
    scaleBurst = "procStartScaleBurst",
    ringExpand = "procStartRingExpand",
    crossFlare = "procStartCrossFlare",
    diamondBurst = "procStartDiamondBurst",
    starburst = "procStartStarburst",
    pixelScatter = "procStartPixelScatter",
    spinFade = "procStartSpinFade",
    cornerBrackets = "procStartCornerBrackets",
    doubleRing = "procStartDoubleRing",
}

-- Hook ActionButtonSpellAlertManager:ShowAlert to resize proc glow on custom-sized icons.
-- The alert is created lazily on first proc, so ApplyIconSize can't catch it at init time.
local procGlowHooked = false
local function hookProcGlowResizing()
    if procGlowHooked then return end
    if not ActionButtonSpellAlertManager then return end

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton)
        -- actionButton keys the shared _sizedIcons weak table
        actionButton = SS.plainFrame(actionButton)
        if not actionButton then return end
        local sizeInfo = Overlays._sizedIcons[actionButton]
        if sizeInfo then
            Overlays._ResizeProcGlow(actionButton, sizeInfo.width, sizeInfo.height)
        end
        -- Hide ProcStart / start pixel glow — must run regardless of custom sizing
        if not abeLoaded then
            pcall(function()
                local alert = actionButton.SpellActivationAlert
                if not alert then return end

                local viewerFrame = actionButton:GetParent()
                if not viewerFrame or not viewerFrame.GetName then return end
                local componentId = CDM_VIEWER_NAMES[viewerFrame:GetName()]
                if not componentId then return end
                local component = addon.Components and addon.Components[componentId]
                if not component or not component.db then return end

                local loopStyle = component.db.procLoopStyle
                local useCustomLoop = loopStyle and loopStyle ~= "default" and addon.PixelGlow

                -- Determine proc start behavior
                local procStartStyle = component.db.procStartStyle
                if procStartStyle == nil then
                    procStartStyle = component.db.hideProcStart and "none" or "default"
                end

                -- Handle proc start (isolated pcall — must never break proc loop)
                -- Only play on the FIRST ShowAlert call, not repeated calls while proc is active
                local existingGlow = addon.PixelGlow and addon.PixelGlow.GetForIcon(actionButton)
                local isRepeatedCall = existingGlow and existingGlow:IsPlaying()

                if procStartStyle ~= "default" then
                    pcall(function()
                        -- Suppress Blizzard's ProcStart
                        if alert.ProcStartFlipbook then
                            alert.ProcStartFlipbook:Hide()
                        end
                        if alert.ProcStartAnim then
                            alert.ProcStartAnim:Stop()
                        end

                        -- Play custom proc start only on initial proc (not repeated ShowAlert)
                        if not isRepeatedCall then
                            local animId = PROC_START_ANIM_IDS[procStartStyle]
                            if animId and addon.ProcStart then
                                addon.ProcStart.PlayForIcon(actionButton, {
                                    style = animId,
                                    colorMode = component.db.procStartColor or "custom",
                                    customColor = component.db.procStartCustomColor or {1, 1, 1, 1},
                                    scale = component.db.procStartScale or 1,
                                    iconW = sizeInfo and sizeInfo.width,
                                    iconH = sizeInfo and sizeInfo.height,
                                })
                            end
                        end
                    end)
                end

                -- Handle proc loop (always runs regardless of proc start outcome)
                if useCustomLoop then
                    alert.ProcStartAnim:Stop()
                    alert:Hide()
                    local config = {
                        style = (loopStyle == "pixelDots") and "dots" or "dashes",
                        colorMode = component.db.procLoopColor or "custom",
                        customColor = component.db.procLoopCustomColor or {1, 0.84, 0, 1},
                        speed = component.db.procLoopSpeed or 25,
                        iconW = sizeInfo and sizeInfo.width,
                        iconH = sizeInfo and sizeInfo.height,
                        insetH = component.db.procLoopInsetH or 0,
                        insetV = component.db.procLoopInsetV or 0,
                    }
                    local existingGlow = addon.PixelGlow.GetForIcon(actionButton)
                    if not existingGlow or not existingGlow:IsPlaying() then
                        addon.PixelGlow.StartForIcon(actionButton, config)
                    end
                end
            end)
        end
    end)

    -- Hook HideAlert to clean up pixel glows and proc start overlays
    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, actionButton)
        actionButton = SS.plainFrame(actionButton)
        if not actionButton then return end
        if addon.PixelGlow then
            addon.PixelGlow.RemovePending(actionButton)
            addon.PixelGlow.ReleaseForIcon(actionButton)
        end
        if addon.ProcStart then
            addon.ProcStart.StopForIcon(actionButton)
        end
    end)

    procGlowHooked = true
end
Overlays._HookProcGlowResizing = hookProcGlowResizing

-- Retroactive scan: find CDM icons where a Blizzard proc glow is active but
-- should be replaced by a pixel glow (or vice-versa after profile switch).
-- Covers the reload timing race (ShowAlert fires before the hook is installed)
-- and profile switches where active procs need glow-type changes.
local function scanAndReplaceActiveBlizzardGlows()
    if abeLoaded then return end
    if not addon.PixelGlow then return end

    for viewerName, componentId in pairs(CDM_VIEWER_NAMES) do
        if componentId ~= "trackedBuffs" then
            local viewer = _G[viewerName]
            if viewer and viewer.IsShown and viewer:IsShown() then
                local component = addon.Components and addon.Components[componentId]
                if component and component.db then
                    local style = component.db.procLoopStyle
                    local children = { viewer:GetChildren() }

                    for _, child in ipairs(children) do
                        pcall(function()
                            if not child then return end

                            -- Detect active proc via visual state
                            local alert = child.SpellActivationAlert
                            local blizzardGlowActive = alert and alert.IsShown and alert:IsShown()
                            local existingGlow = addon.PixelGlow.GetForIcon(child)
                            local scootGlowActive = existingGlow and existingGlow:IsPlaying()

                            if not blizzardGlowActive and not scootGlowActive then return end

                            if style and style ~= "default" then
                                -- Custom style: suppress Blizzard glow, ensure pixel glow
                                if blizzardGlowActive and alert then
                                    alert.ProcStartAnim:Stop()
                                    alert:Hide()
                                end
                                if not scootGlowActive then
                                    local sizeInfo = Overlays._sizedIcons[child]
                                    local config = {
                                        style = (style == "pixelDots") and "dots" or "dashes",
                                        colorMode = component.db.procLoopColor or "custom",
                                        customColor = component.db.procLoopCustomColor or {1, 0.84, 0, 1},
                                        speed = component.db.procLoopSpeed or 25,
                                        iconW = sizeInfo and sizeInfo.width,
                                        iconH = sizeInfo and sizeInfo.height,
                                        insetH = component.db.procLoopInsetH or 0,
                                        insetV = component.db.procLoopInsetV or 0,
                                    }
                                    addon.PixelGlow.StartForIcon(child, config)
                                end
                            else
                                -- Default style: release pixel glow, restore Blizzard glow
                                if scootGlowActive then
                                    addon.PixelGlow.ReleaseForIcon(child)
                                    if alert then
                                        alert:Show()
                                        if alert.ProcLoop and not alert.ProcLoop:IsPlaying() then
                                            alert.ProcLoop:Play()
                                        end
                                        if alert.ProcLoopFlipbook then
                                            alert.ProcLoopFlipbook:Show()
                                        end
                                    end
                                end
                            end
                        end)
                    end
                end
            end
        end
    end
end
Overlays._ScanAndReplaceActiveBlizzardGlows = scanAndReplaceActiveBlizzardGlows
