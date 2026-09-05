-- viewerhooks.lua - Cooldown Manager: viewer hook registration
-- Installs the OnAcquireItemFrame, OnReleaseItemFrame, RefreshLayout, and
-- Layout hooks that style icons as Blizzard acquires and lays them out.
local addonName, addon = ...

local Overlays = addon.CDMOverlays

local hookedViewers = {}
Overlays._hookedViewers = hookedViewers

function Overlays.HookViewer(viewerFrameName, componentId)
    if hookedViewers[viewerFrameName] then return true end

    local viewer = _G[viewerFrameName]
    if not viewer then return false end

    if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
            Overlays._InvalidateChildrenCache(viewerFrameName)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if not Overlays._IsValidCDMItemFrame(itemFrame) then return end
                    if not Overlays._IsFrameVisible(itemFrame) then return end

                    local component = addon.Components and addon.Components[componentId]
                    if not component or not component.db then return end

                    -- Apply icon sizing if configured via ratio
                    local ratio = tonumber(component.db.tallWideRatio) or 0
                    local zoom = tonumber(component.db.iconZoom) or 0
                    if ratio ~= 0 and addon.IconRatio then
                        local iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
                        if iconWidth and iconHeight then
                            Overlays.ApplyIconSize(itemFrame, {
                                width = iconWidth,
                                height = iconHeight,
                                iconZoom = zoom,
                                swipeInset = tonumber(component.db.swipeInset) or 0,
                            })
                        end
                    elseif zoom > 0 then
                        local iconTexture = itemFrame.icon or itemFrame.Icon
                        if iconTexture then
                            local l, r, t, b = addon.CalculateIconTexCoords(1.0, zoom, 0)
                            pcall(function() iconTexture:SetTexCoord(l, r, t, b) end)
                        end
                        Overlays._zoomedIcons[itemFrame] = true
                    end

                    -- Square cooldown swipe
                    if component.db.squareCooldownSwipe then
                        Overlays.ApplySquareSwipe(itemFrame)
                    end

                    -- Hide decorative ring
                    if component.db.hideDecorativeRing then
                        Overlays.HideIconRing(itemFrame)
                    end

                    if component.db.borderEnable and not Overlays._HasBlizzardDebuffBorder(itemFrame) then
                        Overlays.ApplyBorder(itemFrame, {
                            enable = true,
                            style = component.db.borderStyle or "square",
                            thickness = tonumber(component.db.borderThickness) or 1,
                            insetH = tonumber(component.db.borderInsetH) or tonumber(component.db.borderInset) or -1,
                            insetV = tonumber(component.db.borderInsetV) or tonumber(component.db.borderInset) or -1,
                            color = component.db.borderTintEnable and component.db.borderTintColor or {0, 0, 0, 1},
                            tintEnabled = component.db.borderTintEnable,
                            tintColor = component.db.borderTintColor,
                        })
                    elseif Overlays._HasBlizzardDebuffBorder(itemFrame) then
                        -- Hide Scoot border when Blizzard's DebuffBorder is visible
                        Overlays.HideBorder(itemFrame)
                    end

                    local hasTextConfig = component.db.textCooldown or component.db.textStacks
                    if hasTextConfig then
                        Overlays.ApplyText(itemFrame, {
                            cooldown = component.db.textCooldown,
                            stacks = component.db.textStacks,
                        })
                    end

                    -- Apply keybind text if enabled
                    if component.db.textBindings and component.db.textBindings.enabled and addon.SpellBindings then
                        local kbOverlay = Overlays.GetOrCreateForIcon(itemFrame)
                        if kbOverlay then
                            addon.SpellBindings.ApplyToIcon(itemFrame, component.db.textBindings)
                        end
                    end
                end)
            end
        end)
    end

    if viewer.OnReleaseItemFrame then
        hooksecurefunc(viewer, "OnReleaseItemFrame", function(_, itemFrame)
            Overlays._InvalidateChildrenCache(viewerFrameName)
            -- Clear keybind spell cache for released icon
            if addon.SpellBindings and addon.SpellBindings.ClearIconCache then
                addon.SpellBindings.ClearIconCache(itemFrame)
            end
            -- Remove from tracking immediately to prevent catch-up ticker resurrection.
            -- The overlay and Overlays._activeOverlays table are Scoot-owned, so this is taint-safe.
            local overlay = Overlays._activeOverlays[itemFrame]
            if overlay then
                Overlays._activeOverlays[itemFrame] = nil
                overlay:Hide()
            end
            -- Defer heavy cleanup (reparent, pool return) to break Blizzard's call stack
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if overlay then Overlays._overlayPool:Release(overlay) end
                    Overlays.ResetIconSize(itemFrame)
                    Overlays.ResetSwipe(itemFrame)
                    Overlays.RestoreIconRing(itemFrame)
                end)
            else
                if overlay then Overlays._overlayPool:Release(overlay) end
                Overlays.ResetIconSize(itemFrame)
                Overlays.ResetSwipe(itemFrame)
                Overlays.RestoreIconRing(itemFrame)
            end
        end)
    end

    if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", function()
            Overlays._InvalidateChildrenCache(viewerFrameName)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    Overlays.ApplyToViewer(viewerFrameName, componentId)
                end)
            end
        end)
    end

    -- Hook Layout to apply centering synchronously (no deferral needed for cosmetic APIs).
    -- Eliminates the visible "jerk" on spell transforms where icons briefly appear
    -- at Blizzard's default grid position before snapping to centered position.
    if viewer.Layout then
        hooksecurefunc(viewer, "Layout", function()
            Overlays._CenterIconsInViewer(viewer, componentId)
        end)
    end

    -- Diagnostic record for /scoot debug cdm: which methods existed at hook time
    -- (RefreshData/OnCooldownDataChanged are recorded but not hooked)
    Overlays._hookState = Overlays._hookState or {}
    Overlays._hookState[viewerFrameName] = string.format(
        "OnAcquireItemFrame=%s OnReleaseItemFrame=%s RefreshLayout=%s Layout=%s RefreshData=%s OnCooldownDataChanged=%s",
        tostring(viewer.OnAcquireItemFrame ~= nil),
        tostring(viewer.OnReleaseItemFrame ~= nil),
        tostring(viewer.RefreshLayout ~= nil),
        tostring(viewer.Layout ~= nil),
        tostring(viewer.RefreshData ~= nil),
        tostring(viewer.OnCooldownDataChanged ~= nil))

    hookedViewers[viewerFrameName] = true
    return true
end
