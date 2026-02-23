local addonName, addon = ...

local TB = addon.TB
local Util = addon.ComponentsUtil
local resolveCDMColor = addon.ResolveCDMColor

--------------------------------------------------------------------------------
-- Default Mode: Bar Overlay Creation
--------------------------------------------------------------------------------

local function createBarOverlay(blizzBarItem)
    local barFrame = (blizzBarItem.GetBarFrame and blizzBarItem:GetBarFrame()) or blizzBarItem.Bar
    if not barFrame then return nil end

    local overlay = CreateFrame("Frame", nil, barFrame)
    overlay:SetAllPoints(barFrame)
    overlay:SetFrameLevel(barFrame:GetFrameLevel())
    overlay:EnableMouse(false)

    overlay.barBg = overlay:CreateTexture(nil, "BACKGROUND", nil, -1)
    overlay.barBg:SetAllPoints(overlay)
    overlay.barBg:Hide()

    overlay.barFill = overlay:CreateTexture(nil, "BORDER", nil, -1)
    overlay.barFill:Hide()

    overlay:Hide()
    return overlay
end

local function getOrCreateBarOverlay(blizzBarItem)
    local existing = TB.trackedBarOverlays[blizzBarItem]
    if existing then return existing end
    local overlay = createBarOverlay(blizzBarItem)
    if overlay then
        TB.trackedBarOverlays[blizzBarItem] = overlay
    end
    return overlay
end
TB.getOrCreateBarOverlay = getOrCreateBarOverlay

local function anchorFillOverlay(overlay, barFrame)
    if not overlay or not overlay.barFill or not barFrame then return end
    local fill = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
    if not fill then return end
    overlay.barFill:ClearAllPoints()
    overlay.barFill:SetAllPoints(fill)
end

local function hideBarOverlay(blizzBarItem)
    local overlay = TB.trackedBarOverlays[blizzBarItem]
    if not overlay then return end
    overlay:Hide()
    if overlay.barFill then overlay.barFill:Hide() end
    if overlay.barBg then overlay.barBg:Hide() end
end
TB.hideBarOverlay = hideBarOverlay

--------------------------------------------------------------------------------
-- Default Mode: Overlay-Based Styling
--------------------------------------------------------------------------------

function addon.ApplyTrackedBarVisualsForChild(component, child)
    if not component or not child then return end
    if component.id ~= "trackedBars" then return end
    local barFrame = (child.GetBarFrame and child:GetBarFrame()) or child.Bar
    local iconFrame = (child.GetIconFrame and child:GetIconFrame()) or child.Icon
    if not barFrame or not iconFrame then return end

    local db = component.db

    local function getSettingValue(key)
        if not db then return nil end
        return db[key]
    end

    -- Calculate icon dimensions from ratio
    local iconRatio = tonumber(getSettingValue("iconTallWideRatio")) or 0
    local iconWidth, iconHeight
    if addon.IconRatio then
        iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent("trackedBars", iconRatio)
    else
        iconWidth, iconHeight = 30, 30
    end
    if iconWidth and iconHeight and iconFrame.SetSize then
        iconWidth = math.max(8, math.min(32, iconWidth))
        iconHeight = math.max(8, math.min(32, iconHeight))
        iconFrame:SetSize(iconWidth, iconHeight)
        local tex = iconFrame.Icon or (child.GetIconTexture and child:GetIconTexture())
        if tex and tex.SetAllPoints then tex:SetAllPoints(iconFrame) end
        local mask = iconFrame.Mask or iconFrame.IconMask
        if mask and mask.SetAllPoints then mask:SetAllPoints(iconFrame) end
    end

    local desiredPad = tonumber(db.iconBarPadding) or 0
    desiredPad = tonumber(desiredPad) or 0

    local currentGap
    if barFrame.GetLeft and iconFrame.GetRight then
        local bl = barFrame:GetLeft()
        local ir = iconFrame:GetRight()
        if bl and ir then currentGap = bl - ir end
    end

    local deltaPad = (currentGap and (desiredPad - currentGap)) or 0

    if barFrame.ClearAllPoints and barFrame.SetPoint then
        local rightPoint, rightRelTo, rightRelPoint, rx, ry
        if barFrame.GetNumPoints and barFrame.GetPoint then
            local n = barFrame:GetNumPoints()
            for i = 1, n do
                local p, rt, rp, ox, oy = barFrame:GetPoint(i)
                if p == "RIGHT" then rightPoint, rightRelTo, rightRelPoint, rx, ry = p, rt, rp, ox, oy break end
            end
        end
        barFrame:ClearAllPoints()
        if rightPoint and rightRelTo then
            barFrame:SetPoint("RIGHT", rightRelTo, rightRelPoint or "RIGHT", (rx or 0) + deltaPad, ry or 0)
        else
            barFrame:SetPoint("RIGHT", child, "RIGHT", deltaPad, 0)
        end
        local anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = iconFrame, "RIGHT", "RIGHT"
        if iconFrame.IsShown and not iconFrame:IsShown() then
            anchorLeftTo, anchorLeftPoint, anchorLeftRelPoint = child, "LEFT", "LEFT"
        end
        barFrame:SetPoint("LEFT", anchorLeftTo, anchorLeftPoint, desiredPad, 0)
    end

    -- Overlay-based bar texture styling
    do
        local useCustom = (db and db.styleEnableCustom) ~= false
        if useCustom then
            local overlay = getOrCreateBarOverlay(child)
            if overlay then
                anchorFillOverlay(overlay, barFrame)

                -- Foreground texture + color
                local fg = db.styleForegroundTexture
                local fgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(fg)
                if fgPath then
                    overlay.barFill:SetTexture(fgPath)
                else
                    overlay.barFill:SetColorTexture(1, 0.5, 0.25, 1)
                end
                local fgColorMode = (db and db.styleForegroundColorMode) or "default"
                local fgTint = (db and db.styleForegroundTint) or {1,1,1,1}
                local r, g, b, a = TB.resolveBarColor(fgColorMode, fgTint, 1.0, 0.5, 0.25, 1.0)
                overlay.barFill:SetVertexColor(r, g, b, a)
                overlay.barFill:Show()

                -- Background texture + color + opacity
                local bg = db.styleBackgroundTexture
                local bgPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(bg)
                if bgPath then
                    overlay.barBg:SetTexture(bgPath)
                else
                    overlay.barBg:SetColorTexture(0, 0, 0, 1)
                end
                local bgColorMode = (db and db.styleBackgroundColorMode) or "default"
                local bgTint = (db and db.styleBackgroundTint) or {0,0,0,1}
                local br, bg2, bb, ba = TB.resolveBarColor(bgColorMode, bgTint, 0, 0, 0, 1)
                overlay.barBg:SetVertexColor(br, bg2, bb, ba)
                local bgOpacity = db.styleBackgroundOpacity or 50
                local opacityVal = tonumber(bgOpacity) or 50
                opacityVal = math.max(0, math.min(100, opacityVal)) / 100
                overlay.barBg:SetAlpha(opacityVal)
                overlay.barBg:Show()

                -- Show overlay only if item is visible, active, and not suppressed
                if not (TB.isItemSuppressed and TB.isItemSuppressed(child)) then
                    if not child.IsShown or child:IsShown() then
                        local ok, isInactive = pcall(function() return child.isActive == false end)
                        if not (ok and not issecretvalue(isInactive) and isInactive) then
                            pcall(function() child:SetAlpha(1) end)
                            overlay:Show()
                        end
                    end
                end

                -- Hide Blizzard fill texture so the overlay shows through
                local blizzFill = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
                if blizzFill then pcall(blizzFill.SetAlpha, blizzFill, 0) end
                if barFrame.BarBG then pcall(barFrame.BarBG.SetAlpha, barFrame.BarBG, 0) end
            end
        else
            -- No custom textures: hide overlay, restore Blizzard defaults
            hideBarOverlay(child)
            local blizzFill = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
            if blizzFill then
                if blizzFill.SetAlpha then pcall(blizzFill.SetAlpha, blizzFill, 1.0) end
                if blizzFill.SetAtlas then pcall(blizzFill.SetAtlas, blizzFill, "UI-HUD-CoolDownManager-Bar", true) end
                if blizzFill.SetVertexColor then pcall(blizzFill.SetVertexColor, blizzFill, 1.0, 0.5, 0.25, 1.0) end
                if blizzFill.SetTexCoord then pcall(blizzFill.SetTexCoord, blizzFill, 0, 1, 0, 1) end
            end
            if barFrame.SetStatusBarAtlas then pcall(barFrame.SetStatusBarAtlas, barFrame, "UI-HUD-CoolDownManager-Bar") end
            if barFrame.BarBG then pcall(barFrame.BarBG.SetAlpha, barFrame.BarBG, 1.0) end
            Util.HideDefaultBarTextures(barFrame, true)
        end
    end

    -- Bar border
    local wantBorder = db and db.borderEnable
    local styleKey = db and db.borderStyle or "square"
    if wantBorder then
        local thickness = tonumber(db.borderThickness) or 1
        if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
        local tintEnabled = db.borderTintEnable and type(db.borderTintColor) == "table"
        local color
        if tintEnabled then
            local c = db.borderTintColor
            color = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
        else
            if styleDef then
                color = {1, 1, 1, 1}
            else
                color = {0, 0, 0, 1}
            end
        end

        local handled = false
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            local insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or 0
            local insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or 0
            handled = addon.BarBorders.ApplyToBarFrame(barFrame, styleKey, {
                color = color,
                thickness = thickness,
                insetH = insetH,
                insetV = insetV,
            })
        end

        if handled then
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
            Util.HideDefaultBarTextures(barFrame)
        else
            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
            if addon.Borders and addon.Borders.ApplySquare then
                addon.Borders.ApplySquare(barFrame, {
                    size = thickness,
                    color = color,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    levelOffset = 5,
                    containerParent = barFrame,
                    expandX = 1,
                    expandY = 2,
                })
            end
            Util.HideDefaultBarTextures(barFrame, true)
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(barFrame) end
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(barFrame) end
        Util.HideDefaultBarTextures(barFrame, true)
    end

    -- Icon border
    local function shouldShowIconBorder()
        local mode = tostring(getSettingValue("displayMode") or "both")
        if mode == "name" then return false end
        if iconFrame.IsShown and not iconFrame:IsShown() then return false end
        return true
    end

    local iconBorderEnabled = not not getSettingValue("iconBorderEnable")
    local iconStyle = tostring(getSettingValue("iconBorderStyle") or "none")
    local iconThickness = tonumber(getSettingValue("iconBorderThickness")) or 1
    iconThickness = math.max(1, math.min(16, iconThickness))
    local iconBorderInsetH = tonumber(getSettingValue("iconBorderInsetH")) or tonumber(getSettingValue("iconBorderInset")) or 0
    local iconBorderInsetV = tonumber(getSettingValue("iconBorderInsetV")) or tonumber(getSettingValue("iconBorderInset")) or 0
    local iconTintEnabled = not not getSettingValue("iconBorderTintEnable")
    local tintRaw = getSettingValue("iconBorderTintColor")
    local tintColor = {1, 1, 1, 1}
    if type(tintRaw) == "table" then
        tintColor = { tintRaw[1] or 1, tintRaw[2] or 1, tintRaw[3] or 1, tintRaw[4] or 1 }
    end

    if iconBorderEnabled and shouldShowIconBorder() then
        Util.ToggleDefaultIconOverlay(iconFrame, false)
        addon.ApplyIconBorderStyle(iconFrame, iconStyle, {
            thickness = iconThickness,
            insetH = iconBorderInsetH,
            insetV = iconBorderInsetV,
            color = iconTintEnabled and tintColor or nil,
            tintEnabled = iconTintEnabled,
            db = db,
            thicknessKey = "iconBorderThickness",
            tintColorKey = "iconBorderTintColor",
            defaultThickness = component.settings and component.settings.iconBorderThickness and component.settings.iconBorderThickness.default or 1,
        })
    else
        Util.ToggleDefaultIconOverlay(iconFrame, true)
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(iconFrame) end
    end

    -- Text styling
    local defaultFace = (select(1, GameFontNormal:GetFont()))

    local function promoteFontLayer(font)
        if font and font.SetDrawLayer then
            font:SetDrawLayer("OVERLAY", 5)
        end
    end
    promoteFontLayer((child.GetNameLabel and child:GetNameLabel()) or child.Name or child.Text or child.Label)
    promoteFontLayer((child.GetDurationLabel and child:GetDurationLabel()) or child.Duration or child.DurationText or child.Timer or child.TimerText)

    local function findFontStringByNameHint(root, hint)
        local target = nil
        local function scan(obj)
            if not obj or target then return end
            if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                local nm = obj.GetName and obj:GetName() or ""
                if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                    target = obj; return
                end
            end
            if obj.GetRegions then
                local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                for i = 1, n do
                    local r = select(i, obj:GetRegions())
                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                        local nm = r.GetName and r:GetName() or ""
                        if type(nm) == "string" and string.find(string.lower(nm), string.lower(hint), 1, true) then
                            target = r; return
                        end
                    end
                end
            end
            if obj.GetChildren then
                local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
                for i = 1, m do
                    local c = select(i, obj:GetChildren())
                    scan(c)
                    if target then return end
                end
            end
        end
        scan(root)
        return target
    end

    local function findFontStringOn(obj)
        if not obj then return nil end
        if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
        if obj.GetRegions then
            local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
            for i = 1, n do
                local r = select(i, obj:GetRegions())
                if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
            end
        end
        if obj.GetChildren then
            local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
            for i = 1, m do
                local c = select(i, obj:GetChildren())
                local found = findFontStringOn(c)
                if found then return found end
            end
        end
    end

    local nameFS = (barFrame and barFrame.Name) or findFontStringByNameHint(barFrame or child, "Bar.Name") or findFontStringByNameHint(child, "Name")
    local durFS  = (barFrame and barFrame.Duration) or findFontStringByNameHint(barFrame or child, "Bar.Duration") or findFontStringByNameHint(child, "Duration")

    if nameFS and nameFS.SetFont then
        local cfg = db.textName or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        pcall(nameFS.SetDrawLayer, nameFS, "OVERLAY", 10)
        TB.applyTextStyling(nameFS, cfg, defaultFace)
        if nameFS.SetJustifyH then pcall(nameFS.SetJustifyH, nameFS, "LEFT") end
        local ox = (cfg.offset and cfg.offset.x) or 0
        local oy = (cfg.offset and cfg.offset.y) or 0
        if (ox ~= 0 or oy ~= 0) and nameFS.ClearAllPoints and nameFS.SetPoint then
            nameFS:ClearAllPoints()
            local anchorTo = barFrame or child
            nameFS:SetPoint("LEFT", anchorTo, "LEFT", ox, oy)
        end
    end

    if durFS and durFS.SetFont then
        local cfg = db.textDuration or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        pcall(durFS.SetDrawLayer, durFS, "OVERLAY", 10)
        TB.applyTextStyling(durFS, cfg, defaultFace)
        if durFS.SetJustifyH then pcall(durFS.SetJustifyH, durFS, "RIGHT") end
        local ox = (cfg.offset and cfg.offset.x) or 0
        local oy = (cfg.offset and cfg.offset.y) or 0
        if (ox ~= 0 or oy ~= 0) and durFS.ClearAllPoints and durFS.SetPoint then
            durFS:ClearAllPoints()
            local anchorTo = barFrame or child
            durFS:SetPoint("RIGHT", anchorTo, "RIGHT", ox, oy)
        end
    end

    local stacksFS
    if iconFrame and iconFrame.Applications then
        if iconFrame.Applications.GetObjectType and iconFrame.Applications:GetObjectType() == "FontString" then
            stacksFS = iconFrame.Applications
        else
            stacksFS = findFontStringOn(iconFrame.Applications)
        end
    end
    if not stacksFS and iconFrame then
        stacksFS = findFontStringByNameHint(iconFrame, "Applications")
    end
    if not stacksFS then
        stacksFS = findFontStringByNameHint(child, "Applications")
    end

    if stacksFS and stacksFS.SetFont then
        local cfg = db.textStacks or { size = 14, offset = { x = 0, y = 0 }, style = "OUTLINE", color = {1,1,1,1} }
        pcall(stacksFS.SetDrawLayer, stacksFS, "OVERLAY", 10)
        TB.applyTextStyling(stacksFS, cfg, defaultFace)
        if stacksFS.SetJustifyH then pcall(stacksFS.SetJustifyH, stacksFS, "CENTER") end
        local ox = (cfg.offset and cfg.offset.x) or 0
        local oy = (cfg.offset and cfg.offset.y) or 0
        if stacksFS.ClearAllPoints and stacksFS.SetPoint then
            stacksFS:ClearAllPoints()
            local anchorTo = iconFrame or child
            stacksFS:SetPoint("CENTER", anchorTo, "CENTER", ox, oy)
        end
    end

    -- Trace: overlay state after styling
    if TB.tbTraceEnabled then
        local overlay = TB.trackedBarOverlays[child]
        local oShown = overlay and overlay:IsShown()
        local bgShown = overlay and overlay.barBg and overlay.barBg:IsShown()
        local bgAlpha = overlay and overlay.barBg and overlay.barBg:GetAlpha()
        local ok, iActive = pcall(function() return child.isActive end)
        TB.tbTrace("Styled: childShown=%s isActive=%s overlay=%s barBg=%s bgAlpha=%s",
            tostring(child:IsShown()),
            ok and tostring(iActive) or "ERR",
            tostring(oShown), tostring(bgShown), tostring(bgAlpha))
    end
end
