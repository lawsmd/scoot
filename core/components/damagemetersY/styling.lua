-- damagemetersY/styling.lua - Visual styling, JiberishIcons integration, bar appearance
local _, addon = ...
local DMY = addon.DamageMetersY

-- Slash command visibility override (non-persistent, resets on reload)
DMY._slashHidden = false

--------------------------------------------------------------------------------
-- JiberishIcons helpers (reuse X's addon-level exports)
--------------------------------------------------------------------------------

local function GetJiberishIcons()
    local JIGlobal = _G.ElvUI_JiberishIcons
    if not JIGlobal or type(JIGlobal) ~= "table" then return nil end
    local JI = JIGlobal[1]
    if not JI then return nil end
    if not JI.dataHelper or not JI.dataHelper.class then return nil end
    if not JI.mergedStylePacks or not JI.mergedStylePacks.class then return nil end
    return JI
end

--------------------------------------------------------------------------------
-- Apply Icon to a bar row
--------------------------------------------------------------------------------

local function ApplyIcon(row, player, db)
    local icon = row.icon
    if not icon then return end

    -- Hide icons entirely if disabled
    if db.showIcons == false then
        icon:SetTexture(nil)
        return
    end

    local iconStyle = db.iconStyle or "default"

    -- JiberishIcons: any non-"default" style is a JI style key
    if iconStyle ~= "default" then
        local JI = GetJiberishIcons()
        if JI and player.classFilename then
            local classData = JI.dataHelper.class[player.classFilename]
            if classData and classData.texCoords then
                local styleData = JI.mergedStylePacks.class.styles and JI.mergedStylePacks.class.styles[iconStyle]
                if styleData then
                    local basePath = styleData.path or JI.mergedStylePacks.class.path or ""
                    icon:SetTexture(basePath .. iconStyle)
                    icon:SetTexCoord(unpack(classData.texCoords))
                    return
                end
            end
        end
    end

    -- Default: spec icon if available
    if player.specIconID and player.specIconID ~= 0 then
        icon:SetTexture(player.specIconID)
        icon:SetTexCoord(0, 1, 0, 1)
        return
    end

    -- Class atlas fallback
    if player.classFilename and player.classFilename ~= "" then
        local atlas = GetClassAtlas and GetClassAtlas(player.classFilename)
        if atlas then
            icon:SetAtlas(atlas)
            return
        end
    end

    -- Ultimate fallback
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0, 1, 0, 1)
end

--------------------------------------------------------------------------------
-- Apply text styling to a FontString
--------------------------------------------------------------------------------

local function ApplyTextStyle(fs, textSettings)
    if not fs or not textSettings then return end
    local face = addon.ResolveFontFace(textSettings.fontFace or "FRIZQT__")
    local size = textSettings.fontSize or 12
    local style = textSettings.fontStyle or "OUTLINE"
    addon.ApplyFontStyle(fs, face, size, style)

    if textSettings.colorMode == "custom" and textSettings.color then
        local c = textSettings.color
        fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
end

--------------------------------------------------------------------------------
-- Bar border helpers
--------------------------------------------------------------------------------

local BarBorders = addon.BarBorders

local function ResolveBorderColor(player, db)
    local mode = db.barBorderColorMode or "default"
    if mode == "class" and player and player.classFilename then
        local classColor = addon.ClassColors and addon.ClassColors[player.classFilename]
        if classColor then
            return { classColor.r or 0, classColor.g or 0, classColor.b or 0, 1 }
        end
    elseif mode == "custom" then
        local c = db.barBorderColor or { 0, 0, 0, 1 }
        return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
    end
    return { 0, 0, 0, 1 }
end

local function EnsureSquareBorder(row)
    if row._sqBorder then return row._sqBorder end
    local f = CreateFrame("Frame", nil, row)
    f:SetFrameLevel(row:GetFrameLevel() + 3)
    f:SetAllPoints(row)
    local edges = { frame = f }
    edges.top = f:CreateTexture(nil, "OVERLAY")
    edges.bottom = f:CreateTexture(nil, "OVERLAY")
    edges.left = f:CreateTexture(nil, "OVERLAY")
    edges.right = f:CreateTexture(nil, "OVERLAY")
    row._sqBorder = edges
    return edges
end

local function ApplySquareBorder(row, color, thickness)
    local edges = EnsureSquareBorder(row)
    local t = math.max(1, math.floor((tonumber(thickness) or 1) + 0.5))
    local r, g, b, a = color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1
    local bar = row.bar

    edges.top:ClearAllPoints()
    edges.top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    edges.top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    edges.top:SetHeight(t)
    edges.top:SetColorTexture(r, g, b, a)
    edges.top:Show()

    edges.bottom:ClearAllPoints()
    edges.bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    edges.bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    edges.bottom:SetHeight(t)
    edges.bottom:SetColorTexture(r, g, b, a)
    edges.bottom:Show()

    edges.left:ClearAllPoints()
    edges.left:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    edges.left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    edges.left:SetWidth(t)
    edges.left:SetColorTexture(r, g, b, a)
    edges.left:Show()

    edges.right:ClearAllPoints()
    edges.right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    edges.right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    edges.right:SetWidth(t)
    edges.right:SetColorTexture(r, g, b, a)
    edges.right:Show()

    edges.frame:Show()
end

local function HideSquareBorder(row)
    if not row._sqBorder then return end
    row._sqBorder.frame:Hide()
end

--------------------------------------------------------------------------------
-- Hollow outline helpers (tracks fill region of the StatusBar)
--------------------------------------------------------------------------------

local function EnsureHollowOutline(row)
    if row._hollowOutline then return row._hollowOutline end
    local f = CreateFrame("Frame", nil, row)
    f:SetFrameLevel(row:GetFrameLevel())
    local edges = { frame = f }
    edges.top = f:CreateTexture(nil, "ARTWORK")
    edges.bottom = f:CreateTexture(nil, "ARTWORK")
    edges.left = f:CreateTexture(nil, "ARTWORK")
    edges.right = f:CreateTexture(nil, "ARTWORK")
    row._hollowOutline = edges
    return edges
end

local function ShowHollowOutline(row, cr, cg, cb)
    local edges = EnsureHollowOutline(row)
    local barTex = row.bar:GetStatusBarTexture()
    local t = 1

    edges.top:ClearAllPoints()
    edges.top:SetPoint("TOPLEFT", row.bar, "TOPLEFT", 0, 0)
    edges.top:SetPoint("TOPRIGHT", barTex, "TOPRIGHT", 0, 0)
    edges.top:SetHeight(t)
    edges.top:SetColorTexture(cr, cg, cb, 1)
    edges.top:Show()

    edges.bottom:ClearAllPoints()
    edges.bottom:SetPoint("BOTTOMLEFT", row.bar, "BOTTOMLEFT", 0, 0)
    edges.bottom:SetPoint("BOTTOMRIGHT", barTex, "BOTTOMRIGHT", 0, 0)
    edges.bottom:SetHeight(t)
    edges.bottom:SetColorTexture(cr, cg, cb, 1)
    edges.bottom:Show()

    edges.left:ClearAllPoints()
    edges.left:SetPoint("TOPLEFT", row.bar, "TOPLEFT", 0, 0)
    edges.left:SetPoint("BOTTOMLEFT", row.bar, "BOTTOMLEFT", 0, 0)
    edges.left:SetWidth(t)
    edges.left:SetColorTexture(cr, cg, cb, 1)
    edges.left:Show()

    edges.right:ClearAllPoints()
    edges.right:SetPoint("TOPRIGHT", barTex, "TOPRIGHT", 0, 0)
    edges.right:SetPoint("BOTTOMRIGHT", barTex, "BOTTOMRIGHT", 0, 0)
    edges.right:SetWidth(t)
    edges.right:SetColorTexture(cr, cg, cb, 1)
    edges.right:Show()

    edges.frame:Show()
end

local function HideHollowOutline(row)
    if not row._hollowOutline then return end
    row._hollowOutline.frame:Hide()
end

function DMY._ApplyBarBorder(row, player, db)
    if not row or not row.bar then return end
    local styleKey = db.barBorderStyle or "none"

    if styleKey == "none" then
        HideSquareBorder(row)
        BarBorders.ClearBarFrame(row.bar)
        return
    end

    local color = ResolveBorderColor(player, db)
    local thickness = tonumber(db.barBorderThickness) or 1

    if styleKey == "square" then
        BarBorders.ClearBarFrame(row.bar)
        ApplySquareBorder(row, color, thickness)
    else
        HideSquareBorder(row)
        BarBorders.ApplyToBarFrame(row.bar, styleKey, {
            color = color,
            thickness = thickness,
            containerParent = row,
            insetH = tonumber(db.barBorderInsetH) or 0,
            insetV = tonumber(db.barBorderInsetV) or 0,
        })
    end
end

--------------------------------------------------------------------------------
-- Apply bar texture to a column cell
--------------------------------------------------------------------------------

local function ApplyBarTexture(cell, db)
    if not cell or not cell.bar then return end
    local path = addon.Media and addon.Media.ResolveBarTexturePath(db.barTexture or "default")
    if path then
        pcall(cell.bar.SetStatusBarTexture, cell.bar, path)
    else
        cell.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    end

    -- Background color
    local bgc = db.barBackgroundColor or { 0.1, 0.1, 0.1, 0.8 }
    cell.barBg:SetColorTexture(bgc[1] or 0.1, bgc[2] or 0.1, bgc[3] or 0.1, bgc[4] or 0.8)
end

--------------------------------------------------------------------------------
-- Get bar color for a player
--------------------------------------------------------------------------------

function DMY._GetBarColor(player, db)
    if db.barForegroundColorMode == "custom" then
        local c = db.barCustomColor or { 0.8, 0.7, 0.2, 1 }
        return c[1] or 0.8, c[2] or 0.7, c[3] or 0.2
    end
    -- Class color (default)
    local classColor = addon.ClassColors and addon.ClassColors[player.classFilename]
    if classColor then
        return classColor.r or 0.6, classColor.g or 0.6, classColor.b or 0.6
    end
    return 0.6, 0.6, 0.6
end

--------------------------------------------------------------------------------
-- Window border helpers
--------------------------------------------------------------------------------

-- Rounded style uses the high-res rounded-corner edge file directly. It is
-- deliberately NOT registered in BarBorders: bar-scale geometry there derives
-- edgeSize from frameHeight/18, which is wrong for a full-size window.
local WINDOW_ROUNDED_EDGE_FILE = "Interface\\AddOns\\Scoot\\media\\barborder\\roundcorners.tga"
-- edgeSize per point of Border Thickness (1-8). Source tiles are 64px, so the
-- art only ever downscales. In-game tuning knob.
local WINDOW_EDGE_SIZE_PER_THICKNESS = 4
-- Fraction of edgeSize the holder expands past the window rect so the corner
-- arc sits over (not inside) the square backdrop corner. In-game tuning knob.
local WINDOW_EDGE_EXPAND_RATIO = 0.5
-- Breathing room between the window rect and the border on the left/right/top
-- edges, where header and bar content hugs the frame; bottom stays flush.
local WINDOW_BORDER_PADDING = 3

local function EnsureWindowBorder(frame)
    if frame._winBorder then return frame._winBorder end
    local holder = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    holder:SetFrameLevel(frame:GetFrameLevel() + 10)
    local border = { frame = holder }
    border.top = holder:CreateTexture(nil, "OVERLAY")
    border.bottom = holder:CreateTexture(nil, "OVERLAY")
    border.left = holder:CreateTexture(nil, "OVERLAY")
    border.right = holder:CreateTexture(nil, "OVERLAY")
    frame._winBorder = border
    return border
end

local function HideWindowSquareEdges(border)
    border.top:Hide()
    border.bottom:Hide()
    border.left:Hide()
    border.right:Hide()
end

local function ApplyWindowSquareBorder(frame, color, thickness)
    local border = EnsureWindowBorder(frame)
    local holder = border.frame
    -- Clear any edgeFile backdrop left behind by a previous style
    if holder.SetBackdrop then pcall(holder.SetBackdrop, holder, nil) end
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", frame, "TOPLEFT", -WINDOW_BORDER_PADDING, WINDOW_BORDER_PADDING)
    holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", WINDOW_BORDER_PADDING, 0)

    -- Windows carry fractional effective scale; snap to whole physical pixels
    local t = DMY._SnapToPixels(tonumber(thickness) or 1, frame, 1)
    local r, g, b, a = color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1

    border.top:ClearAllPoints()
    border.top:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    border.top:SetHeight(t)
    border.top:SetColorTexture(r, g, b, a)
    border.top:Show()

    border.bottom:ClearAllPoints()
    border.bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(t)
    border.bottom:SetColorTexture(r, g, b, a)
    border.bottom:Show()

    -- Left/right inset vertically by t so translucent colors don't
    -- double-blend where edges would overlap at the corners
    border.left:ClearAllPoints()
    border.left:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -t)
    border.left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, t)
    border.left:SetWidth(t)
    border.left:SetColorTexture(r, g, b, a)
    border.left:Show()

    border.right:ClearAllPoints()
    border.right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -t)
    border.right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, t)
    border.right:SetWidth(t)
    border.right:SetColorTexture(r, g, b, a)
    border.right:Show()

    holder:Show()
end

local function ApplyWindowEdgeBorder(frame, texture, color, thickness)
    local border = EnsureWindowBorder(frame)
    local holder = border.frame
    HideWindowSquareEdges(border)
    if not holder.SetBackdrop then
        holder:Hide()
        return
    end

    local edgeSize = math.max(4, math.floor((tonumber(thickness) or 1) * WINDOW_EDGE_SIZE_PER_THICKNESS + 0.5))
    -- Expand outward so the corner arc encloses the square backdrop corner
    local expand = math.floor(edgeSize * WINDOW_EDGE_EXPAND_RATIO + 0.5)
    local pad = WINDOW_BORDER_PADDING
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", frame, "TOPLEFT", -(expand + pad), expand + pad)
    holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", expand + pad, -expand)

    local ok = pcall(holder.SetBackdrop, holder, {
        bgFile = nil,
        edgeFile = texture,
        tile = false,
        edgeSize = edgeSize,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if ok and holder.SetBackdropBorderColor then
        holder:SetBackdropBorderColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
        holder:Show()
    else
        holder:Hide()
    end
end

-- Cross-file: also used by the settings preview pane. Takes any plain Frame
-- plus the component db; safe to call repeatedly.
function DMY._ApplyWindowBorder(frame, db)
    if not frame then return end
    local styleKey = db.windowBorderStyle or "none"

    if styleKey == "none" then
        if frame._winBorder then frame._winBorder.frame:Hide() end
        return
    end

    local color = db.windowBorderColor or { 0, 0, 0, 1 }
    local thickness = tonumber(db.windowBorderThickness) or 1

    if styleKey == "square" then
        ApplyWindowSquareBorder(frame, color, thickness)
        return
    end

    -- edgeFile styles: "rounded" resolves to the local asset; any other key
    -- resolves through BarBorders so future styles are selector-only additions
    local texture
    if styleKey == "rounded" then
        texture = WINDOW_ROUNDED_EDGE_FILE
    else
        local style = BarBorders and BarBorders.GetStyle and BarBorders.GetStyle(styleKey)
        texture = style and style.texture
    end
    if texture then
        ApplyWindowEdgeBorder(frame, texture, color, thickness)
    elseif frame._winBorder then
        frame._winBorder.frame:Hide()
    end
end

--------------------------------------------------------------------------------
-- Full styling pass for a window
--------------------------------------------------------------------------------

function DMY._ApplyFullStyling(windowIndex, comp)
    local win = DMY._windows[windowIndex]
    if not win then return end
    local db = comp.db

    -- Window backdrop
    if db.showBackdrop == false then
        win.background:SetColorTexture(0, 0, 0, 0)
    else
        local bc = db.windowBackdropColor or { 0.06, 0.06, 0.08, 0.95 }
        -- Opacity slider wins; unset falls back to the color's stored alpha
        local alpha = db.windowBackdropOpacity and (db.windowBackdropOpacity / 100) or bc[4] or 0.95
        win.background:SetColorTexture(bc[1] or 0.06, bc[2] or 0.06, bc[3] or 0.08, alpha)
    end

    -- Frame size and scale (per-window, falls back to shared)
    local cfg = DMY._GetWindowConfig(windowIndex)
    local fw = tonumber(cfg and cfg.frameWidth or db.frameWidth) or 350
    local fh = tonumber(cfg and cfg.frameHeight or db.frameHeight) or 250
    -- Scale first: the pixel snap below reads the resulting effective scale
    win.frame:SetScale(tonumber(cfg and cfg.windowScale or db.windowScale) or 1.0)
    local snap = DMY._SnapToPixels
    win.frame:SetSize(snap(fw, win.frame), snap(fh, win.frame))

    -- Window border (after SetScale/SetSize: pixel snap reads effective scale)
    DMY._ApplyWindowBorder(win.frame, db)

    -- Title bar backdrop
    if win.header and win.header._bg then
        if db.showTitleBarBackdrop == false then
            win.header._bg:SetColorTexture(0, 0, 0, 0)
        else
            win.header._bg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
        end
    end

    -- Title and timer text styling (separate settings)
    if win.titleText then ApplyTextStyle(win.titleText, db.textTitle) end
    if win.timerText then ApplyTextStyle(win.timerText, db.textTimer or db.textTitle) end

    -- Vertical title positioning — tacked on OUTSIDE the frame's left edge
    if win.verticalTitle then
        ApplyTextStyle(win.verticalTitle, db.textTitle)
        if db.verticalTitleMode then
            win.verticalTitle:ClearAllPoints()
            win.verticalTitle:SetPoint("TOPRIGHT", win.frame, "TOPLEFT", -4, -(DMY.HEADER_HEIGHT or 24) - 4)
            win.verticalTitle:SetJustifyH("CENTER")
            -- No scroll area shift — content stays in place
        else
            win.verticalTitle:Hide()
        end
    end

    -- In vertical mode, timer moves left (adjacent to gear)
    if db.verticalTitleMode and win.timerText and win.gearBtn then
        win.timerText:ClearAllPoints()
        win.timerText:SetPoint("LEFT", win.gearBtn, "RIGHT", 4, 0)
    elseif win.timerText and win.titleText then
        win.timerText:ClearAllPoints()
        win.timerText:SetPoint("LEFT", win.titleText, "RIGHT", 4, 0)
    end

    -- Column header styling
    for c = 1, DMY.MAX_COLUMNS do
        ApplyTextStyle(win.columnHeaders[c], db.textHeaders)
    end

    -- Apply text styling to all bar rows in the pool
    local barTexPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(db.barTexture or "default") or nil
    local barMode = db.barMode or "default"
    local fillAlpha = (barMode == "hollow") and 0 or 1
    -- Rank numbers follow the Names font (one point smaller) but keep their
    -- muted color, so ApplyFontStyle directly instead of ApplyTextStyle
    local nameFace = addon.ResolveFontFace(db.textNames and db.textNames.fontFace or "FRIZQT__")
    local nameStyle = db.textNames and db.textNames.fontStyle or "OUTLINE"
    local rankSize = math.max(6, (db.textNames and db.textNames.fontSize or 12) - 1)
    for r = 1, DMY.MAX_POOL do
        local row = win.barRows[r]
        ApplyTextStyle(row.nameText, db.textNames)
        if row.rankText then addon.ApplyFontStyle(row.rankText, nameFace, rankSize, nameStyle) end
        -- Single full-width bar texture
        if row.bar and barTexPath then
            pcall(row.bar.SetStatusBarTexture, row.bar, barTexPath)
        end
        -- Reset fill alpha for mode switching
        local barTex = row.bar and row.bar:GetStatusBarTexture()
        if barTex then barTex:SetAlpha(fillAlpha) end
        -- Value texts
        for c = 1, DMY.MAX_COLUMNS do
            local vt = row.valueTexts and row.valueTexts[c]
            if vt then ApplyTextStyle(vt, db.textValues) end
        end
    end

    -- Pinned row styling
    local pinnedRow = win.pinnedRow
    ApplyTextStyle(pinnedRow.nameText, db.textNames)
    if pinnedRow.rankText then addon.ApplyFontStyle(pinnedRow.rankText, nameFace, rankSize, nameStyle) end
    if pinnedRow.bar and barTexPath then
        pcall(pinnedRow.bar.SetStatusBarTexture, pinnedRow.bar, barTexPath)
    end
    local pinnedBarTex = pinnedRow.bar and pinnedRow.bar:GetStatusBarTexture()
    if pinnedBarTex then pinnedBarTex:SetAlpha(fillAlpha) end
    for c = 1, DMY.MAX_COLUMNS do
        local vt = pinnedRow.valueTexts and pinnedRow.valueTexts[c]
        if vt then ApplyTextStyle(vt, db.textValues) end
    end

    -- Recalculate layout and refresh rows (applies borders + bar visibility)
    DMY._CalculateColumnWidths(windowIndex, comp)
    DMY._LayoutBarRows(windowIndex, comp)
    DMY._RefreshBarRows(windowIndex, comp)
end

--------------------------------------------------------------------------------
-- Apply icon + color to a populated bar row (called during refresh)
--------------------------------------------------------------------------------

function DMY._StyleBarRow(row, player, db)
    ApplyIcon(row, player, db)
    DMY._ApplyBarBorder(row, player, db)

    -- Hollow outline: show when hollow mode active
    local barMode = db.barMode or "default"
    if barMode == "hollow" then
        local cr, cg, cb = DMY._GetBarColor(player, db)
        ShowHollowOutline(row, cr, cg, cb)
    else
        HideHollowOutline(row)
    end
end

--------------------------------------------------------------------------------
-- Visibility management
--------------------------------------------------------------------------------

function DMY._UpdateVisibility(windowIndex, comp)
    local win = DMY._windows[windowIndex]
    if not win then return end

    -- Slash command override: hide all windows
    if DMY._slashHidden then
        win.frame:Hide()
        return
    end

    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg or not cfg.enabled then
        win.frame:Hide()
        return
    end

    local db = comp.db
    local vis = db.visibility or "always"

    if vis == "hidden" then
        win.frame:Hide()
    elseif vis == "incombat" then
        if InCombatLockdown() then
            win.frame:Show()
        else
            win.frame:Hide()
        end
    else -- "always"
        win.frame:Show()
    end
end

--------------------------------------------------------------------------------
-- Slash command handlers (/dmshow, /dmreset)
--------------------------------------------------------------------------------

function DMY._SlashToggleShow()
    DMY._slashHidden = not DMY._slashHidden
    local comp = DMY._comp or (addon.Components and addon.Components["damageMeterV2"])
    if comp then
        for i = 1, DMY.MAX_WINDOWS do
            DMY._UpdateVisibility(i, comp)
        end
        if not DMY._slashHidden then
            DMY._RefreshOpacity(comp)
            if not DMY._inCombat then
                DMY._FullRefreshAllWindows()
            end
        end
    end
    addon:Print(DMY._slashHidden and "Damage Meter hidden." or "Damage Meter shown.")
end

function DMY._SlashReset()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
    end
    DMY._HandleReset()
    addon:Print("Damage Meter data reset.")
end

--------------------------------------------------------------------------------
-- Session header text
--------------------------------------------------------------------------------

function DMY._UpdateSessionHeader(windowIndex, comp)
    local win = DMY._windows[windowIndex]
    if not win then return end
    local cfg = DMY._GetWindowConfig(windowIndex)
    if not cfg then return end
    local db = comp.db

    local label
    if db.titleMode == "custom" and db.customTitle and db.customTitle ~= "" then
        label = db.customTitle
    else
        label = DMY._GetSessionLabel(cfg.sessionType, cfg.sessionID, cfg._sessionName)
    end

    -- Timer is handled separately by _UpdateTimerText
    win._sessionLabel = label
end
