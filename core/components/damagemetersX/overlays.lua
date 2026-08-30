local addonName, addon = ...

-- damagemetersX/overlays.lua — Entry overlay frame creation, Blizzard content
-- hiding/restoring, all overlay-level styling and data updates.

local DMX = addon.DamageMetersX

-- Local aliases for frequently used namespace functions
local SafeSetAlpha = DMX._SafeSetAlpha
local GetClassColor = DMX._GetClassColor
local GetJiberishIcons = DMX._GetJiberishIcons

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local OVERLAY_DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local OVERLAY_DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local OVERLAY_DEFAULT_FONT_SIZE = 12
local OVERLAY_DEFAULT_FONT_FLAGS = "OUTLINE"

--------------------------------------------------------------------------------
-- Overlay Value Text Formatting
--------------------------------------------------------------------------------

-- Replicate Blizzard's DamageMeterEntryMixin:GetValueText using safe table reads
local function FormatOverlayValueText(entry)
    if not entry then return "" end

    -- Early bail if key values are secret (can't format secret numbers)
    local val = entry.value
    if issecretvalue(val) then return "" end

    local primary, secondary
    local vps = entry.valuePerSecond
    local showVPS = entry.showsValuePerSecondAsPrimary
    if not issecretvalue(vps) and not issecretvalue(showVPS) and vps and showVPS then
        primary = vps
        secondary = val
    else
        primary = val or 0
        secondary = (not issecretvalue(vps)) and vps or nil
    end

    if type(primary) ~= "number" then primary = 0 end
    if secondary and type(secondary) ~= "number" then secondary = nil end

    local abbrev = AbbreviateLargeNumbers or function(n) return tostring(math.floor(n)) end
    local round = Round or function(n) return math.floor(n + 0.5) end

    local ndt = entry.numberDisplayType
    if issecretvalue(ndt) then ndt = 1 end
    ndt = ndt or 1
    local DMN = Enum.DamageMeterNumbers

    if DMN and ndt == DMN.Complete then
        local pct = 0
        local stv = entry.sessionTotalValue
        if not issecretvalue(stv) and type(val) == "number"
           and type(stv) == "number" and stv > 0 then
            pct = round((val / stv) * 100)
        end
        local fmt = _G.DAMAGE_METER_ENTRY_FORMAT_COMPLETE
        if fmt then
            return fmt:format(abbrev(primary), abbrev(secondary or 0), pct)
        end
        return string.format("%s (%s, %d%%)", abbrev(primary), abbrev(secondary or 0), pct)
    elseif DMN and ndt == DMN.Compact then
        local fmt = _G.DAMAGE_METER_ENTRY_FORMAT_COMPACT
        if fmt then
            return fmt:format(abbrev(primary), abbrev(secondary or 0))
        end
        return string.format("%s (%s)", abbrev(primary), abbrev(secondary or 0))
    else
        local fmt = _G.DAMAGE_METER_ENTRY_FORMAT_MINIMAL
        if fmt then
            return fmt:format(abbrev(primary))
        end
        return abbrev(primary)
    end
end

--------------------------------------------------------------------------------
-- Frame Creation
--------------------------------------------------------------------------------

-- Create a per-window clip frame anchored to the ScrollBox
local function CreateClipFrame(sessionWindow)
    local scrollBox = sessionWindow and sessionWindow.ScrollBox
    if not scrollBox then return nil end

    local clipFrame = CreateFrame("Frame", nil, UIParent)
    clipFrame:SetClipsChildren(true)
    clipFrame:SetAllPoints(scrollBox)
    -- Match strata to session window (typically MEDIUM); frame levels handle z-ordering above entries
    local ok1, strata = pcall(sessionWindow.GetFrameStrata, sessionWindow)
    if ok1 and type(strata) == "string" then
        clipFrame:SetFrameStrata(strata)
    end
    local ok2, sbLevel = pcall(scrollBox.GetFrameLevel, scrollBox)
    if ok2 and type(sbLevel) == "number" then clipFrame:SetFrameLevel(sbLevel) end

    return clipFrame
end

-- Create an entry overlay frame hierarchy
local function CreateEntryOverlay(parentFrame)
    local overlay = CreateFrame("Frame", nil, parentFrame)
    overlay:EnableMouse(false)
    -- Frame level set dynamically in PopulateEntryOverlay per-entry (handles ScrollBox recycling)

    -- Bar overlay (StatusBar) for the fill
    local barOverlay = CreateFrame("StatusBar", nil, overlay)
    barOverlay:SetStatusBarTexture(OVERLAY_DEFAULT_BAR_TEXTURE)

    -- Opaque base behind bar (hides Blizzard StatusBar content)
    local bgBase = barOverlay:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgBase:SetAllPoints(barOverlay)
    bgBase:SetColorTexture(0, 0, 0, 1)

    -- Background texture (behind bar fill, user-configurable alpha)
    local bgTexture = barOverlay:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetAllPoints(barOverlay)
    bgTexture:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- BackgroundEdge replica (thin dark border for default style)
    local bgEdge = barOverlay:CreateTexture(nil, "BORDER")
    bgEdge:SetAllPoints(barOverlay)
    bgEdge:SetColorTexture(0, 0, 0, 0.4)
    bgEdge:Hide()

    -- Name FontString (left-aligned on bar)
    local nameFS = barOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    nameFS:SetFont(OVERLAY_DEFAULT_FONT, OVERLAY_DEFAULT_FONT_SIZE, OVERLAY_DEFAULT_FONT_FLAGS)
    nameFS:SetTextColor(1, 1, 1, 1)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)

    -- Value FontString (right-aligned on bar)
    local valueFS = barOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    valueFS:SetFont(OVERLAY_DEFAULT_FONT, OVERLAY_DEFAULT_FONT_SIZE, OVERLAY_DEFAULT_FONT_FLAGS)
    valueFS:SetTextColor(1, 1, 1, 1)
    valueFS:SetJustifyH("RIGHT")
    valueFS:SetWordWrap(false)

    -- Icon frame (anchored to entry.Icon later)
    local iconFrame = CreateFrame("Frame", nil, overlay)
    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(iconFrame)

    -- Opaque base behind icon (hides Blizzard Icon content)
    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    iconBg:SetAllPoints(iconFrame)
    iconBg:SetColorTexture(0, 0, 0, 0)
    iconBg:Hide()

    overlay.bgBase = bgBase
    overlay.barOverlay = barOverlay
    overlay.bgTexture = bgTexture
    overlay.iconBg = iconBg
    overlay.bgEdge = bgEdge
    overlay.nameFS = nameFS
    overlay.valueFS = valueFS
    overlay.iconFrame = iconFrame
    overlay.iconTexture = iconTexture

    return overlay
end

--------------------------------------------------------------------------------
-- Blizzard Content Hiding/Restoring
--------------------------------------------------------------------------------

-- Hide Blizzard's visual content on a DM entry (overlay replaces it)
local function HideBlizzardEntryContent(entry)
    if not entry then return end
    -- SetAlpha(0) on parent frame hides all children (Name, Value, Background, fill)
    if entry.StatusBar then pcall(entry.StatusBar.SetAlpha, entry.StatusBar, 0) end
    if entry.Icon then pcall(entry.Icon.SetAlpha, entry.Icon, 0) end
end

-- Restore Blizzard's visual content (cleanup when overlays removed)
local function RestoreBlizzardEntryContent(entry)
    if not entry then return end
    if entry.StatusBar then pcall(entry.StatusBar.SetAlpha, entry.StatusBar, 1) end
    if entry.Icon then pcall(entry.Icon.SetAlpha, entry.Icon, 1) end
end

--------------------------------------------------------------------------------
-- Overlay Styling Helpers
--------------------------------------------------------------------------------

-- Apply icon to overlay (spec icon or JiberishIcons)
local function ApplyOverlayIcon(overlay, entry, db)
    if not overlay or not entry then return end

    local showIcons = entry.showBarIcons
    if issecretvalue(showIcons) then showIcons = true end
    if db.showSpecIcon == false then showIcons = false end

    if not showIcons then
        overlay.iconFrame:Hide()
        return
    end

    overlay.iconFrame:Show()

    -- JiberishIcons integration
    if db.jiberishIconsEnabled then
        local JI = GetJiberishIcons()
        local classToken = entry.classFilename
        if issecretvalue(classToken) then classToken = nil end
        if JI and classToken then
            local classData = JI.dataHelper and JI.dataHelper.class and JI.dataHelper.class[classToken]
            if classData and classData.texCoords then
                local styleName = db.jiberishIconsStyle or "fabled"
                local mergedStyles = JI.mergedStylePacks and JI.mergedStylePacks.class
                if mergedStyles then
                    local styleData = mergedStyles.styles and mergedStyles.styles[styleName]
                    local basePath = (styleData and styleData.path) or mergedStyles.path
                    if basePath then
                        overlay.iconTexture:SetTexture(basePath .. styleName)
                        overlay.iconTexture:SetTexCoord(unpack(classData.texCoords))
                        overlay.iconTexture:Show()
                        return
                    end
                end
            end
        end
    end

    -- Default: spec icon from entry properties
    local iconID = entry.specIconID
    if issecretvalue(iconID) then iconID = nil end
    if not iconID then
        iconID = entry.iconTexture
        if issecretvalue(iconID) then iconID = nil end
    end
    if iconID then
        overlay.iconTexture:SetTexture(iconID)
        overlay.iconTexture:SetTexCoord(0, 1, 0, 1)
        overlay.iconTexture:Show()
    else
        overlay.iconTexture:Hide()
    end
end

-- Apply bar borders to overlay (all calls on Scoot-owned frames)
local function ApplyOverlayBorders(overlay, db, sessionWindow, isBorderedStyle)
    if not overlay or not db then return end

    -- Bordered edit mode style has Blizzard's border baked into the atlas.
    -- Clear any active Scoot borders and return.
    if isBorderedStyle then
        overlay.bgEdge:Hide()
        addon.Borders.HideAll(overlay.barOverlay)
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(overlay.barOverlay)
        end
        return
    end

    local borderStyle = db.barBorderStyle or "default"
    local barOverlay = overlay.barOverlay

    local thickness = db.barBorderThickness or 1
    local r, g, b, a = 0, 0, 0, 1
    if db.barBorderTintEnabled and rawget(db, "barBorderTintColor") then
        local c = rawget(db, "barBorderTintColor")
        r = c.r or c[1] or 0
        g = c.g or c[2] or 0
        b = c.b or c[3] or 0
        a = c.a or c[4] or 1
    end

    -- bgEdge: visible only for "default" border style
    if borderStyle == "default" then
        overlay.bgEdge:Show()
    else
        overlay.bgEdge:Hide()
    end

    -- Square border edges. hiddenEdges is deliberately not passed: this
    -- component has never honored barBorderHiddenEdges on the square style.
    if borderStyle == "square" then
        addon.Borders.ApplySquare(barOverlay, {
            size = thickness,
            color = { r, g, b, a },
            layer = "OVERLAY",
            layerSublevel = 5,
            skipDimensionCheck = true,
        })
    else
        addon.Borders.HideAll(barOverlay)
    end

    -- Textured borders (BarBorders system) — holder parented to barOverlay (inherits strata/visibility)
    if borderStyle ~= "default" and borderStyle ~= "none" and borderStyle ~= "square" then
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            addon.BarBorders.ApplyToBarFrame(barOverlay, borderStyle, {
                thickness = thickness,
                color = { r, g, b, a },
                hiddenEdges = db.barBorderHiddenEdges or {},
            })
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(barOverlay)
        end
    end
end

-- Scratch color for ApplyOverlayIconBorder; the dispatcher reads it synchronously.
local iconBorderColor = { 0, 0, 0, 1 }

-- Apply icon border to overlay. Always square; insets here have always been
-- inward-positive, matching the shared dispatcher, so they pass through as-is.
local function ApplyOverlayIconBorder(overlay, db)
    if not overlay or not db then return end

    local iconFrame = overlay.iconFrame

    if not db.iconBorderEnable or not iconFrame:IsShown() then
        if addon.Borders and addon.Borders.HideAll then
            addon.Borders.HideAll(iconFrame)
        end
        return
    end

    local r, g, b, a = 0, 0, 0, 1
    if db.iconBorderTintEnable and db.iconBorderTintColor then
        local c = db.iconBorderTintColor
        r = c.r or c[1] or 0
        g = c.g or c[2] or 0
        b = c.b or c[3] or 0
        a = c.a or c[4] or 1
    end
    iconBorderColor[1], iconBorderColor[2], iconBorderColor[3], iconBorderColor[4] = r, g, b, a

    addon.ApplyIconBorderStyle(iconFrame, "square", {
        thickness = db.iconBorderThickness or 1,
        insetH = tonumber(db.iconBorderInsetH) or 0,
        insetV = tonumber(db.iconBorderInsetV) or 2,
        tintEnabled = true,
        color = iconBorderColor,
    })
end

-- Update bar foreground color on Scoot-owned overlay (combat-safe, no taint)
local function UpdateOverlayBarColor(overlay, entry, db)
    if not overlay or not entry or not db then return end

    local showClassColor = db.showClassColor
    local colorMode = db.barForegroundColorMode or "default"
    local classToken = entry.classFilename
    if issecretvalue(classToken) then classToken = nil end

    if showClassColor and classToken then
        local cr, cg, cb = GetClassColor(classToken)
        overlay.barOverlay:SetStatusBarColor(cr, cg, cb, 1)
    elseif colorMode == "custom" and rawget(db, "barForegroundTint") then
        local c = rawget(db, "barForegroundTint")
        overlay.barOverlay:SetStatusBarColor(c.r or c[1] or 1, c.g or c[2] or 0.8, c.b or c[3] or 0, c.a or c[4] or 1)
    else
        -- Default: use entry's status bar color if available
        local sbc = entry.statusBarColor
        if issecretvalue(sbc) then sbc = nil end
        local isClassColor = entry.isClassColorDesired
        if issecretvalue(isClassColor) then isClassColor = nil end
        if sbc and type(sbc) == "table" then
            overlay.barOverlay:SetStatusBarColor(sbc.r or sbc[1] or 0.8, sbc.g or sbc[2] or 0.8, sbc.b or sbc[3] or 0.8, 1)
        elseif isClassColor and classToken then
            local cr, cg, cb = GetClassColor(classToken)
            overlay.barOverlay:SetStatusBarColor(cr, cg, cb, 1)
        else
            overlay.barOverlay:SetStatusBarColor(0.8, 0.8, 0.8, 1)
        end
    end
end

--------------------------------------------------------------------------------
-- Full Overlay Population
--------------------------------------------------------------------------------

-- Full overlay population (styling + data) — all calls on Scoot-owned frames
local function PopulateEntryOverlay(overlay, entry, db, sessionWindow)
    if not overlay or not entry or not db then return end

    -- Anchor overlay to entry (anchoring TO system frame = safe, no taint)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(entry)

    -- Match strata to entry's native strata; frame level +3 handles z-ordering within same strata
    local ok1, strata = pcall(entry.GetFrameStrata, entry)
    if ok1 and type(strata) == "string" then
        overlay:SetFrameStrata(strata)
    end
    local ok2, entryLevel = pcall(entry.GetFrameLevel, entry)
    if ok2 and type(entryLevel) == "number" then
        overlay:SetFrameLevel(entryLevel + 3)
    end

    -- Hide Blizzard's original content (overlay replaces it visually)
    HideBlizzardEntryContent(entry)
    overlay._lastEntry = entry

    -- Detect entry style (Thin/Bordered/Default) for style-specific layout
    local entryStyle = entry.style
    if issecretvalue(entryStyle) then entryStyle = nil end
    local isThinStyle = (entryStyle == Enum.DamageMeterStyle.Thin)
    local isBorderedStyle = (entryStyle == Enum.DamageMeterStyle.Bordered)

    -- Anchor bar overlay to entry's StatusBar
    local statusBar = entry.StatusBar or entry.bar
    local barAnchor = statusBar or overlay
    overlay.barOverlay:ClearAllPoints()
    if not isThinStyle and not isBorderedStyle then
        -- Default style: inset left edge so bar doesn't butt against transparent icons
        overlay.barOverlay:SetPoint("TOPLEFT", barAnchor, "TOPLEFT", 5, 0)
        overlay.barOverlay:SetPoint("BOTTOMRIGHT", barAnchor, "BOTTOMRIGHT", 0, 0)
    else
        overlay.barOverlay:SetAllPoints(barAnchor)
    end

    -- Anchor icon to entry's Icon frame
    if entry.Icon then
        overlay.iconFrame:ClearAllPoints()
        overlay.iconFrame:SetAllPoints(entry.Icon)
    end

    -- Bar texture
    if db.barTexture and db.barTexture ~= "default" then
        local resolved = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(db.barTexture)
        if resolved then
            overlay.barOverlay:SetStatusBarTexture(resolved)
        end
    else
        overlay.barOverlay:SetStatusBarTexture(OVERLAY_DEFAULT_BAR_TEXTURE)
    end

    -- Bar foreground color
    UpdateOverlayBarColor(overlay, entry, db)

    -- Bar fill values (StatusBar:SetMinMaxValues/SetValue accept secrets — AllowedWhenTainted)
    pcall(overlay.barOverlay.SetMinMaxValues, overlay.barOverlay, 0, entry.maxValue)
    pcall(overlay.barOverlay.SetValue, overlay.barOverlay, entry.value)

    -- Background color
    local bgColorMode = db.barBackgroundColorMode or "default"
    if bgColorMode == "custom" and rawget(db, "barBackgroundTint") then
        local c = rawget(db, "barBackgroundTint")
        overlay.bgTexture:SetColorTexture(c.r or c[1] or 0.1, c.g or c[2] or 0.1, c.b or c[3] or 0.1, c.a or c[4] or 0.8)
    else
        local bgAlpha = entry.backgroundAlpha
        if issecretvalue(bgAlpha) or type(bgAlpha) ~= "number" then bgAlpha = 0.8 end
        overlay.bgTexture:SetColorTexture(0.1, 0.1, 0.1, bgAlpha)
    end

    -- Bordered style: use Blizzard's bordered atlas (border baked into texture)
    if isBorderedStyle then
        overlay.bgTexture:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        overlay.bgTexture:SetAlpha(1)
        overlay.bgTexture:ClearAllPoints()
        overlay.bgTexture:SetPoint("TOPLEFT", overlay.barOverlay, "TOPLEFT", -2, 2)
        overlay.bgTexture:SetPoint("BOTTOMRIGHT", overlay.barOverlay, "BOTTOMRIGHT", 6, -7)
    else
        overlay.bgTexture:ClearAllPoints()
        overlay.bgTexture:SetAllPoints(overlay.barOverlay)
    end

    -- Name text + styling
    -- entry.nameText includes rank prefix ("1. Wyrm"); entry.sourceName does not ("Wyrm")
    -- When nameText is secret (combat context), forward directly — SetText(secret) is AllowedWhenTainted
    local nameText = entry.nameText
    local nameIsSecret = issecretvalue(nameText)
    if nameIsSecret then
        pcall(overlay.nameFS.SetText, overlay.nameFS, nameText)
    elseif nameText then
        overlay.nameFS:SetText(nameText)
    else
        local srcName = entry.sourceName
        if issecretvalue(srcName) then
            pcall(overlay.nameFS.SetText, overlay.nameFS, srcName)
        elseif srcName then
            overlay.nameFS:SetText(srcName)
        elseif entry.StatusBar and entry.StatusBar.Name then
            local ok, text = pcall(entry.StatusBar.Name.GetText, entry.StatusBar.Name)
            if ok then pcall(overlay.nameFS.SetText, overlay.nameFS, text) else overlay.nameFS:SetText("") end
        else
            overlay.nameFS:SetText("")
        end
    end
    if rawget(db, "textNames") then
        local cfg = rawget(db, "textNames")
        if cfg.fontFace and addon and addon.ResolveFontFace then
            local face = addon.ResolveFontFace(cfg.fontFace)
            local baseFontSize = cfg.fontSize or OVERLAY_DEFAULT_FONT_SIZE
            local editModeScale = (db.textSize or 100) / 100
            local addonScale = cfg.scaleMultiplier or 1.0
            addon.ApplyFontStyle(overlay.nameFS, face, baseFontSize * editModeScale * addonScale, cfg.fontStyle or OVERLAY_DEFAULT_FONT_FLAGS)
        end
        if cfg.colorMode == "custom" and cfg.color then
            local c = cfg.color
            overlay.nameFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            overlay.nameFS:SetTextColor(1, 1, 1, 1)
        end
    end
    -- Value text + styling (must anchor before nameFS since name anchors to value)
    local fmtOk, fmtText = pcall(FormatOverlayValueText, entry)
    if fmtOk and fmtText and fmtText ~= "" then
        overlay.valueFS:SetText(fmtText)
    elseif entry.StatusBar and entry.StatusBar.Value then
        local ok, text = pcall(entry.StatusBar.Value.GetText, entry.StatusBar.Value)
        if ok then pcall(overlay.valueFS.SetText, overlay.valueFS, text) else overlay.valueFS:SetText("") end
    else
        overlay.valueFS:SetText("")
    end
    if rawget(db, "textNumbers") then
        local cfg = rawget(db, "textNumbers")
        if cfg.fontFace and addon and addon.ResolveFontFace then
            local face = addon.ResolveFontFace(cfg.fontFace)
            local baseFontSize = cfg.fontSize or OVERLAY_DEFAULT_FONT_SIZE
            local editModeScale = (db.textSize or 100) / 100
            local addonScale = cfg.scaleMultiplier or 1.0
            addon.ApplyFontStyle(overlay.valueFS, face, baseFontSize * editModeScale * addonScale, cfg.fontStyle or OVERLAY_DEFAULT_FONT_FLAGS)
        end
        if cfg.colorMode == "custom" and cfg.color then
            local c = cfg.color
            overlay.valueFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            overlay.valueFS:SetTextColor(1, 1, 1, 1)
        end
    end
    overlay.valueFS:ClearAllPoints()
    if isThinStyle then
        -- Thin: text at top of entry, bar beneath; nudge down 2px to avoid top clipping
        overlay.valueFS:SetPoint("TOP", overlay, "TOP", 0, -2)
        overlay.valueFS:SetPoint("RIGHT", overlay, "RIGHT", -8, 0)
    else
        -- Default/Bordered: text vertically centered on bar, nudged down 2px
        overlay.valueFS:SetPoint("RIGHT", overlay.barOverlay, "RIGHT", -4, 0)
        overlay.valueFS:SetPoint("TOP", overlay.barOverlay, "TOP", 0, -2)
        overlay.valueFS:SetPoint("BOTTOM", overlay.barOverlay, "BOTTOM", 0, -2)
    end

    -- Name text anchoring
    overlay.nameFS:ClearAllPoints()
    if isThinStyle then
        overlay.nameFS:SetPoint("TOP", overlay, "TOP", 0, -2)
        overlay.nameFS:SetPoint("LEFT", overlay.barOverlay, "LEFT", 4, 0)
        overlay.nameFS:SetPoint("RIGHT", overlay.valueFS, "LEFT", -4, 0)
    else
        overlay.nameFS:SetPoint("LEFT", overlay.barOverlay, "LEFT", 4, 0)
        overlay.nameFS:SetPoint("RIGHT", overlay.valueFS, "LEFT", -4, 0)
        overlay.nameFS:SetPoint("TOP", overlay.barOverlay, "TOP", 0, -2)
        overlay.nameFS:SetPoint("BOTTOM", overlay.barOverlay, "BOTTOM", 0, -2)
    end

    -- Icon (spec or JiberishIcons)
    ApplyOverlayIcon(overlay, entry, db)

    -- Borders
    ApplyOverlayBorders(overlay, db, sessionWindow, isBorderedStyle)
    ApplyOverlayIconBorder(overlay, db)

    -- Store identity fields on Scoot-owned overlay for recycling detection
    local idClassToken = entry.classFilename
    if issecretvalue(idClassToken) then idClassToken = nil end
    overlay._classToken = idClassToken

    local idSpecIcon = entry.specIconID
    if issecretvalue(idSpecIcon) then idSpecIcon = nil end
    overlay._specIconID = idSpecIcon

    local idSourceName = entry.sourceName
    if issecretvalue(idSourceName) then idSourceName = nil end
    overlay._sourceName = idSourceName

    overlay:Show()
end

--------------------------------------------------------------------------------
-- Data-Only Update (Combat-Safe)
--------------------------------------------------------------------------------

-- Data-only update for overlays (safe during combat — only updates bar fill + text)
-- Detects frame recycling (rankings change) and refreshes icon/color when needed
local function UpdateEntryOverlayData(overlay, entry, db)
    if not overlay or not entry then return end

    -- StatusBar:SetMinMaxValues/SetValue accept secrets (AllowedWhenTainted)
    pcall(overlay.barOverlay.SetMinMaxValues, overlay.barOverlay, 0, entry.maxValue)
    pcall(overlay.barOverlay.SetValue, overlay.barOverlay, entry.value)

    -- Name: forward from Blizzard's FontString (SetText(secret) is AllowedWhenTainted)
    -- Don't boolean-test `text` — it may be a secret value (12.0); forward it directly
    if entry.StatusBar and entry.StatusBar.Name then
        local ok, text = pcall(entry.StatusBar.Name.GetText, entry.StatusBar.Name)
        if ok then
            pcall(overlay.nameFS.SetText, overlay.nameFS, text)
        end
    end

    -- Value: forward from Blizzard's FontString (SetText(secret) is AllowedWhenTainted)
    if entry.StatusBar and entry.StatusBar.Value then
        local ok, text = pcall(entry.StatusBar.Value.GetText, entry.StatusBar.Value)
        if ok then
            pcall(overlay.valueFS.SetText, overlay.valueFS, text)
        end
    end

    -- Recycling detection: when rankings change, Blizzard reuses the same frame
    -- for a different player. Detect this and refresh icon + bar color.
    if db then
        local recycled = false

        local curClass = entry.classFilename
        if issecretvalue(curClass) then curClass = nil end
        if curClass and curClass ~= overlay._classToken then
            recycled = true
        end

        if not recycled then
            local curSpecIcon = entry.specIconID
            if issecretvalue(curSpecIcon) then curSpecIcon = nil end
            if curSpecIcon and curSpecIcon ~= overlay._specIconID then
                recycled = true
            end
        end

        if not recycled then
            local curSourceName = entry.sourceName
            if issecretvalue(curSourceName) then curSourceName = nil end
            if curSourceName and curSourceName ~= overlay._sourceName then
                recycled = true
            end
        end

        if recycled then
            ApplyOverlayIcon(overlay, entry, db)
            UpdateOverlayBarColor(overlay, entry, db)

            -- Update stored identity
            local newClass = entry.classFilename
            if issecretvalue(newClass) then newClass = nil end
            overlay._classToken = newClass

            local newSpecIcon = entry.specIconID
            if issecretvalue(newSpecIcon) then newSpecIcon = nil end
            overlay._specIconID = newSpecIcon

            local newSourceName = entry.sourceName
            if issecretvalue(newSourceName) then newSourceName = nil end
            overlay._sourceName = newSourceName
        end
    end

    -- Keep cleanup reference current
    overlay._lastEntry = entry
end

--------------------------------------------------------------------------------
-- Namespace Promotion
--------------------------------------------------------------------------------

DMX._CreateClipFrame = CreateClipFrame
DMX._CreateEntryOverlay = CreateEntryOverlay
DMX._HideBlizzardEntryContent = HideBlizzardEntryContent
DMX._RestoreBlizzardEntryContent = RestoreBlizzardEntryContent
DMX._UpdateEntryOverlayData = UpdateEntryOverlayData
DMX._PopulateEntryOverlay = PopulateEntryOverlay
