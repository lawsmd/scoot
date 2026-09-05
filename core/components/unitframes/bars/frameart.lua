--------------------------------------------------------------------------------
-- bars/frameart.lua
-- Blizzard frame art suppression behind Use Custom Borders (and Hide Border for
-- the FrameTexture): the stock frame texture, the Target prestige art, the
-- Player alternate and vehicle textures, the ReputationColor strips, and the
-- threat Flash regions. Each region gets its alpha written and an enforcer
-- that holds it (bars/alpha.lua).
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.BarsFrameArt = addon.BarsFrameArt or {}
local FrameArt = addon.BarsFrameArt

local Resolvers = addon.BarsResolvers
local Alpha = addon.BarsAlpha

local getUnitFrameFor = Resolvers.getUnitFrameFor
local resolveUnitFrameFrameTexture = Resolvers.resolveUnitFrameFrameTexture
local applyAlpha = Alpha.applyAlpha
local hookAlphaEnforcer = Alpha.hookAlphaEnforcer

-- Target and Focus ReputationColor, run by applyForUnit (bars.lua) before the
-- health and power passes: alpha now, an enforcer, and a deferred re-hide in
-- case Blizzard recreated the texture.
function FrameArt.applyEarly(unit)

    -- Target/Focus frames can be updated/rebuilt by Blizzard during combat (rapid target swaps, faction updates, etc.).
    -- Protected StatusBars/layout must NEVER be touched during combat, but visual-only overlays CAN safely be enforced
    -- (like ReputationColor) via SetAlpha + alpha enforcers. Do this BEFORE the combat early-return so the element
    -- stays hidden even if Blizzard recreates the region during combat.
    --
    -- IMPORTANT: Blizzard may recreate the ReputationColor texture during rapid target changes.
    -- Always apply alpha + install enforcer + schedule a follow-up re-hide to catch late updates.
    if unit == "Target" or unit == "Focus" then
        local function computeUseCustomBordersAlpha()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
            if not cfg2 then return nil end -- config unreadable: skip (fail closed)
            return cfg2.useCustomBorders and 0 or 1
        end

        local reputationColor
        if unit == "Target" and _G.TargetFrame then
            reputationColor = _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        elseif unit == "Focus" and _G.FocusFrame then
            reputationColor = _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        end

        if reputationColor then
            -- Always apply current alpha, regardless of hook state
            local desiredAlpha = computeUseCustomBordersAlpha()
            applyAlpha(reputationColor, desiredAlpha)
            hookAlphaEnforcer(reputationColor, computeUseCustomBordersAlpha)

            -- Belt-and-suspenders: schedule a follow-up re-hide after Blizzard's updates complete
            -- Catches cases where Blizzard resets alpha after the initial hide
            _G.C_Timer.After(0, function()
                -- Re-resolve in case the texture object changed
                local repColor2
                if unit == "Target" and _G.TargetFrame then
                    repColor2 = _G.TargetFrame.TargetFrameContent
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    repColor2 = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if repColor2 and repColor2.SetAlpha then
                    local alpha2 = computeUseCustomBordersAlpha()
                    -- nil = config unreadable at this tick: skip the write
                    -- (never restore visible from a transient window)
                    if alpha2 ~= nil then
                        pcall(repColor2.SetAlpha, repColor2, alpha2)
                    end
                    -- Install enforcer on the (possibly new) object
                    hookAlphaEnforcer(repColor2, computeUseCustomBordersAlpha)
                end
            end)
        end
    end
end

-- Run by applyForUnit (bars.lua) after the health and power passes for Player,
-- Target, and Focus.
function FrameArt.apply(unit, cfg)

    -- Stock frame art (includes the health bar border)
    do
        local ft = resolveUnitFrameFrameTexture(unit)
        if ft then
            local function compute()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                return (cfg2.useCustomBorders or cfg2.healthBarHideBorder) and 0 or 1
            end
            applyAlpha(ft, compute())
            hookAlphaEnforcer(ft, compute)
        end
    end

    -- Target-specific prestige elements (PvP badge/portrait)
    if unit == "Target" then
        local contextual = _G.TargetFrame
            and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentContextual
        if contextual then
            local prestigePortrait = contextual.PrestigePortrait
            if prestigePortrait then
                local function computePrestigeAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                    if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                    return cfg2.useCustomBorders and 0 or 1
                end
                applyAlpha(prestigePortrait, computePrestigeAlpha())
                hookAlphaEnforcer(prestigePortrait, computePrestigeAlpha)
            end
            local prestigeBadge = contextual.PrestigeBadge
            if prestigeBadge then
                local function computePrestigeAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                    if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                    return cfg2.useCustomBorders and 0 or 1
                end
                applyAlpha(prestigeBadge, computePrestigeAlpha())
                hookAlphaEnforcer(prestigeBadge, computePrestigeAlpha)
            end
            local pvpIcon = contextual.PvpIcon
            if pvpIcon then
                local function computePvpIconAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                    if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                    return cfg2.useCustomBorders and 0 or 1
                end
                applyAlpha(pvpIcon, computePvpIconAlpha())
                hookAlphaEnforcer(pvpIcon, computePvpIconAlpha)
            end
        end
    end

    -- Player-specific frame art
    if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
        local container = _G.PlayerFrame.PlayerFrameContainer
        local altTex = container.AlternatePowerFrameTexture
        local vehicleTex = container.VehicleFrameTexture

        local function compute()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
            local cfg2 = unitFrames2 and rawget(unitFrames2, "Player") or nil
            if not cfg2 then return nil end -- config unreadable: skip (fail closed)
            return cfg2.useCustomBorders and 0 or 1
        end

        if altTex then
            applyAlpha(altTex, compute())
            hookAlphaEnforcer(altTex, compute)
        end
        if vehicleTex then
            applyAlpha(vehicleTex, compute())
            hookAlphaEnforcer(vehicleTex, compute)
        end
    end

    -- Hide static visual elements when Use Custom Borders is enabled.
    -- Rationale: These elements (ReputationColor for Target/Focus, FrameFlash for Player, Flash for Target) have
    -- fixed positions that cannot be adjusted. Since Scoot allows users to reposition and
    -- resize health/power bars independently, these static overlays would remain in their original
    -- positions while the bars they're meant to surround/backdrop move elsewhere, causing
    -- visual confusion. Disabled when custom borders are active.

    -- Hide ReputationColor frame for Target/Focus when Use Custom Borders is enabled
    if (unit == "Target" or unit == "Focus") and cfg.useCustomBorders then
        local frame = getUnitFrameFor(unit)
        if frame then
            local reputationColor
            if unit == "Target" and _G.TargetFrame then
                reputationColor = _G.TargetFrame.TargetFrameContent
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            elseif unit == "Focus" and _G.FocusFrame then
                reputationColor = _G.FocusFrame.TargetFrameContent
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            end
            if reputationColor then
                local function computeAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                    return cfg2.useCustomBorders and 0 or 1
                end
                applyAlpha(reputationColor, 0)
                hookAlphaEnforcer(reputationColor, computeAlpha)
            end
        end
    elseif (unit == "Target" or unit == "Focus") then
        -- Restore ReputationColor when Use Custom Borders is disabled
        local frame = getUnitFrameFor(unit)
        if frame then
            local reputationColor
            if unit == "Target" and _G.TargetFrame then
                reputationColor = _G.TargetFrame.TargetFrameContent
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            elseif unit == "Focus" and _G.FocusFrame then
                reputationColor = _G.FocusFrame.TargetFrameContent
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            end
            if reputationColor then
                local function computeAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    if not cfg2 then return nil end -- config unreadable: skip (fail closed)
                    return cfg2.useCustomBorders and 0 or 1
                end
                applyAlpha(reputationColor, 1)
                hookAlphaEnforcer(reputationColor, computeAlpha)
            end
        end
    end

    -- Hide FrameFlash (aggro/threat glow) for Player when Use Custom Borders is enabled
    if unit == "Player" then
        if _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
            local frameFlash = _G.PlayerFrame.PlayerFrameContainer.FrameFlash
            if frameFlash then
                local function computeAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfgP = unitFrames2 and rawget(unitFrames2, "Player") or nil
                    if not cfgP then return nil end -- config unreadable: skip (fail closed)
                    return cfgP.useCustomBorders and 0 or 1
                end
                applyAlpha(frameFlash, computeAlpha())
                hookAlphaEnforcer(frameFlash, computeAlpha)
            end
        end
    end

    -- Hide Flash (aggro/threat glow) for Target when Use Custom Borders is enabled
    if unit == "Target" then
        if _G.TargetFrame and _G.TargetFrame.TargetFrameContainer then
            local targetFlash = _G.TargetFrame.TargetFrameContainer.Flash
            if targetFlash then
                local function computeAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfgT = unitFrames2 and rawget(unitFrames2, "Target") or nil
                    if not cfgT then return nil end -- config unreadable: skip (fail closed)
                    return cfgT.useCustomBorders and 0 or 1
                end
                applyAlpha(targetFlash, computeAlpha())
                hookAlphaEnforcer(targetFlash, computeAlpha)
            end
        end
    end

    -- Hide Flash (aggro/threat glow) for Focus when Use Custom Borders is enabled
    if unit == "Focus" then
        if _G.FocusFrame and _G.FocusFrame.TargetFrameContainer then
            local focusFlash = _G.FocusFrame.TargetFrameContainer.Flash
            if focusFlash then
                local function computeAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfgF = unitFrames2 and rawget(unitFrames2, "Focus") or nil
                    if not cfgF then return nil end -- config unreadable: skip (fail closed)
                    return cfgF.useCustomBorders and 0 or 1
                end
                applyAlpha(focusFlash, computeAlpha())
                hookAlphaEnforcer(focusFlash, computeAlpha)
            end
        end
    end
end

return FrameArt
