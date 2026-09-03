-- actionbars.lua - Action bar component: opacity, hover behavior, Edit Mode integration
local addonName, addon = ...

-- Font-half opts for the button texts
local abTextFontOpts = { size = 14 }

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

-- Alpha driver: hooks SetAlpha to enforce addon opacity settings over Blizzard's visibility transitions
local actionBarState = {}  -- per-frame state (component, baseOpacity, isMousedOver, desiredAlpha)
local actionBarHooked = {} -- frames with OnEnter/OnLeave hooks
local alphaHooked = {}     -- frames with SetAlpha hooks
local settingAlpha = {}    -- recursion guard for SetAlpha calls
local iconShapedButtons = setmetatable({}, { __mode = "k" })  -- tracks buttons modified by icon shape
local lastAppliedFingerprint = {}  -- OPT-21: [componentId] = fingerprint of visual DB keys
local regionClassCache = setmetatable({}, { __mode = "k" })  -- OPT-21: [button] = { classified border/slot regions }
local fingerprintReady = false  -- OPT-21: Don't guard until Blizzard's action bar init completes

-- OPT-21: Fingerprint covers all DB keys that drive per-button visual work (lines ~200-516).
-- If you add a new DB key that affects per-button styling, add it here too.
-- Keys fingerprinted: borderStyle, borderThickness, borderInsetH, borderInsetV, borderInset,
--   borderTintEnable, borderTintColor, tallWideRatio, backdropDisable, backdropStyle,
--   backdropOpacity, backdropInset, backdropTintEnable, backdropTintColor,
--   textHotkeyHidden, textMacroHidden, textStacks, textCooldown, textHotkey, textMacro
local function textConfigFingerprint(cfg)
    if not cfg then return "" end
    return string.format("%s|%s|%s|%.2f,%.2f,%.2f,%.2f|%.1f,%.1f",
        tostring(cfg.size or ""), tostring(cfg.style or ""), tostring(cfg.fontFace or ""),
        (cfg.color and cfg.color[1]) or 1, (cfg.color and cfg.color[2]) or 1,
        (cfg.color and cfg.color[3]) or 1, (cfg.color and cfg.color[4]) or 1,
        (cfg.offset and cfg.offset.x) or 0, (cfg.offset and cfg.offset.y) or 0)
end

local function colorFingerprint(c)
    if not c or type(c) ~= "table" then return "" end
    return string.format("%.2f,%.2f,%.2f,%.2f", c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

local function buildActionBarFingerprint(db)
    if not db then return "" end
    local base = string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s",
        tostring(db.borderStyle or ""),
        tostring(db.borderThickness or ""),
        tostring(db.borderInsetH or db.borderInset or ""),
        tostring(db.borderInsetV or db.borderInset or ""),
        tostring(db.borderTintEnable or ""),
        colorFingerprint(db.borderTintColor),
        tostring(db.tallWideRatio or ""),
        tostring(db.backdropDisable or ""),
        tostring(db.backdropStyle or ""),
        tostring(db.backdropOpacity or ""),
        tostring(db.backdropInset or ""),
        tostring(db.backdropTintEnable or ""),
        colorFingerprint(db.backdropTintColor),
        tostring(rawget(db, "textHotkeyHidden") or ""),
        tostring(rawget(db, "textMacroHidden") or ""),
        textConfigFingerprint(rawget(db, "textStacks")))
    return base .. "|" .. textConfigFingerprint(rawget(db, "textCooldown"))
        .. "|" .. textConfigFingerprint(rawget(db, "textHotkey"))
        .. "|" .. textConfigFingerprint(rawget(db, "textMacro"))
end

local function getBarState(bar)
    if not actionBarState[bar] then
        actionBarState[bar] = {}
    end
    return actionBarState[bar]
end

local function setBarDesiredAlpha(bar, alpha)
    if not bar or not bar.SetAlpha then return end
    local state = getBarState(bar)
    state.desiredAlpha = alpha
    settingAlpha[bar] = true
    pcall(bar.SetAlpha, bar, alpha)
    settingAlpha[bar] = nil
end

local function hookBarAlpha(bar)
    if not bar or alphaHooked[bar] then return end
    alphaHooked[bar] = true
    hooksecurefunc(bar, "SetAlpha", function(self, alpha)
        if settingAlpha[self] then return end
        local state = actionBarState[self]
        if not state or state.desiredAlpha == nil then return end
        if math.abs(alpha - state.desiredAlpha) > 0.001 then
            settingAlpha[self] = true
            pcall(self.SetAlpha, self, state.desiredAlpha)
            settingAlpha[self] = nil
        end
    end)
end

-- OPT-21: Hoisted from inside ApplyActionBarStyling with region classification caching.
-- Region cache uses weak keys — entries are GC'd if button is collected (never happens in practice).
local function toggleDefaultButtonArt(button, restore)
    if not button or not button.GetRegions then return end
    if button.GetNormalTexture then
        local nt = button:GetNormalTexture()
        if nt and nt.SetAlpha then pcall(nt.SetAlpha, nt, restore and 1 or 0) end
    end
    local cached = regionClassCache[button]
    if not cached then
        cached = {}
        for _, r in ipairs({ button:GetRegions() }) do
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then
                local nm = r.GetName and (r:GetName() or "") or ""
                if nm:find("Border", 1, true) or nm:find("SlotArt", 1, true)
                    or nm:find("SlotBackground", 1, true) or nm:find("NormalTexture", 1, true) then
                    cached[#cached + 1] = r
                end
            end
        end
        regionClassCache[button] = cached
    end
    local alpha = restore and 1 or 0
    for _, r in ipairs(cached) do
        pcall(r.SetAlpha, r, alpha)
    end
end

-- OPT-21: Blizzard's action bar init (layout application, EDIT_MODE_LAYOUTS_UPDATED) runs
-- during/shortly after PLAYER_ENTERING_WORLD and can overwrite Scoot's per-button styling.
-- Delay fingerprint guard activation so early ApplyStyles() calls always run per-button work.
addon.Events.Once("ActionBars", "PLAYER_ENTERING_WORLD", function()
    C_Timer.After(1, function()
        fingerprintReady = true
    end)
end)

local function ApplyActionBarStyling(self)
    local bar = _G[self.frameName]
    if not bar then return end

    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if addon.IsComponentUnconfigured(self) then return end

    local baseOp = tonumber(self.db.barOpacity) or 100
    if baseOp < 0 then baseOp = 0 elseif baseOp > 100 then baseOp = 100 end
    local oocOp = tonumber(self.db.barOpacityOutOfCombat) or baseOp
    if oocOp < 0 then oocOp = 0 elseif oocOp > 100 then oocOp = 100 end
    local tgtOp = tonumber(self.db.barOpacityWithTarget) or baseOp
    if tgtOp < 0 then tgtOp = 0 elseif tgtOp > 100 then tgtOp = 100 end
    local hasTarget = (UnitExists and UnitExists("target")) and true or false
    local appliedOp = hasTarget and tgtOp or (Util.PlayerInCombat() and baseOp or oocOp)

    hookBarAlpha(bar)
    
    local mouseoverEnabled = self.db and self.db.mouseoverMode
    local state = getBarState(bar)
    
    local function enumerateButtonsForBar()
        local buttons = {}
        local prefix
        if self.frameName == "MainActionBar" then
            prefix = "ActionButton"
        elseif self.frameName == "PetActionBar" then
            prefix = "PetActionButton"
        elseif self.frameName == "StanceBar" then
            prefix = "StanceButton"
        else
            prefix = tostring(self.frameName) .. "Button"
        end
        local maxButtons = self.maxButtons or 12
        for i = 1, maxButtons do
            local btn = _G[prefix .. i]
            if btn then buttons[#buttons + 1] = btn end
        end
        return buttons
    end
    
    local function isMouseCurrentlyOverBar()
        if bar.IsMouseOver and bar:IsMouseOver() then return true end
        for _, btn in ipairs(enumerateButtonsForBar()) do
            if btn.IsMouseOver and btn:IsMouseOver() then return true end
        end
        return false
    end
    
    state.component = self
    state.baseOpacity = appliedOp / 100
    
    if mouseoverEnabled then
        local function onMouseEnter()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                s.isMousedOver = true
                setBarDesiredAlpha(bar, 1)
            end
        end
        local function onMouseLeave()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                local isOverBar = bar:IsMouseOver()
                if not isOverBar then
                    for _, btn in ipairs(enumerateButtonsForBar()) do
                        if btn.IsMouseOver and btn:IsMouseOver() then
                            isOverBar = true
                            break
                        end
                    end
                end
                if not isOverBar then
                    s.isMousedOver = false
                    setBarDesiredAlpha(bar, s.baseOpacity or 1)
                end
            end
        end

        if not actionBarHooked[bar] then
            bar:HookScript("OnEnter", onMouseEnter)
            bar:HookScript("OnLeave", onMouseLeave)
            actionBarHooked[bar] = true
        end

        for _, btn in ipairs(enumerateButtonsForBar()) do
            if not actionBarHooked[btn] then
                btn:HookScript("OnEnter", onMouseEnter)
                btn:HookScript("OnLeave", onMouseLeave)
                actionBarHooked[btn] = true
            end
        end

        if isMouseCurrentlyOverBar() then
            state.isMousedOver = true
            setBarDesiredAlpha(bar, 1)
        else
            state.isMousedOver = false
            setBarDesiredAlpha(bar, appliedOp / 100)
        end
    else
        state.isMousedOver = false
        setBarDesiredAlpha(bar, appliedOp / 100)
    end

    -- OPT-21: Skip per-button visual styling when no visual DB keys have changed.
    -- Subsumes OPT-05 epoch guard: opacity-only changes (RefreshOpacityState) don't alter
    -- visual keys, so the fingerprint naturally matches and skips.
    -- Guard is inactive during init (fingerprintReady=false) so Blizzard's layout
    -- application doesn't permanently block re-styling.
    local fingerprint = buildActionBarFingerprint(self.db)
    if fingerprintReady and lastAppliedFingerprint[self.id] == fingerprint then
        return
    end
    lastAppliedFingerprint[self.id] = fingerprint

    local function enumerateButtons()
        local buttons = {}
        local prefix
        if self.frameName == "MainActionBar" then
            prefix = "ActionButton"
        elseif self.frameName == "PetActionBar" then
            prefix = "PetActionButton"
        elseif self.frameName == "StanceBar" then
            prefix = "StanceButton"
        else
            prefix = tostring(self.frameName) .. "Button"
        end
        local maxButtons = self.maxButtons or 12
        for i = 1, maxButtons do
            local btn = _G[prefix .. i]
            if btn then buttons[#buttons + 1] = btn end
        end
        if #buttons == 0 and bar.GetChildren then
            for _, child in ipairs({ bar:GetChildren() }) do
                local t = child.GetObjectType and child:GetObjectType()
                if t == "Button" or t == "CheckButton" then
                    buttons[#buttons + 1] = child
                end
            end
        end
        return buttons
    end

    local styleKey = (self.db and self.db.borderStyle) or "off"
    if styleKey == "none" then styleKey = "square"; if self.db then self.db.borderStyle = styleKey end end
    local thickness = tonumber(self.db and self.db.borderThickness) or 1
    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
    local borderInsetH = tonumber(self.db and self.db.borderInsetH) or tonumber(self.db and self.db.borderInset) or 0
    local borderInsetV = tonumber(self.db and self.db.borderInsetV) or tonumber(self.db and self.db.borderInset) or 0
    local tintEnabled = self.db and self.db.borderTintEnable and type(self.db.borderTintColor) == "table"
    local tintColor
    if tintEnabled then
        local c = self.db.borderTintColor or {1,1,1,1}
        tintColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
    end
    
    local function getButtonIconRegion(button)
        if not button then return nil end
        local icon = button.icon or button.Icon
        if icon and icon.GetObjectType and icon:GetObjectType() == "Texture" then
            return icon
        end
        if button.GetName then
            local name = button:GetName()
            if name and _G[name .. "Icon"] then
                local tex = _G[name .. "Icon"]
                if tex and tex.GetObjectType and tex:GetObjectType() == "Texture" then
                    return tex
                end
            end
        end
    end

    -- Icon shape (non-uniform aspect ratio)
    local IconRatio = addon.IconRatio
    local tallWideRatio = tonumber(self.db and self.db.tallWideRatio) or 0
    local isStanceOrPet = (self.frameName == "StanceBar") or (self.frameName == "PetActionBar")
    local baseButtonSize = isStanceOrPet and 30 or 45

    local inCombat = InCombatLockdown and InCombatLockdown()

    for _, btn in ipairs(enumerateButtons()) do
        -- Apply icon shape FIRST (before borders/backdrops which anchor to button edges)
        -- Skip during combat: SetSize/ClearAllPoints/SetPoint on protected buttons causes ADDON_ACTION_BLOCKED
        if not inCombat and tallWideRatio ~= 0 and IconRatio then
            local btnW, btnH = IconRatio.CalculateDimensions(baseButtonSize, tallWideRatio)
            if btnW and btnH then
                pcall(btn.SetSize, btn, btnW, btnH)
                iconShapedButtons[btn] = true

                -- Crop icon texture (center-weighted) instead of stretching
                local icon = btn.icon or btn.Icon
                if icon then
                    local aspectRatio = btnW / btnH
                    local left, right, top, bottom = 0, 1, 0, 1
                    if aspectRatio > 1.0 then
                        -- Wider than tall: crop top/bottom
                        local cropAmount = 1.0 - (1.0 / aspectRatio)
                        local offset = cropAmount / 2.0
                        top = offset
                        bottom = 1.0 - offset
                    elseif aspectRatio < 1.0 then
                        -- Taller than wide: crop left/right
                        local cropAmount = 1.0 - aspectRatio
                        local offset = cropAmount / 2.0
                        left = offset
                        right = 1.0 - offset
                    end
                    pcall(icon.SetTexCoord, icon, left, right, top, bottom)

                    -- Re-anchor icon to fill resized button (implicit XML anchoring doesn't update)
                    pcall(function()
                        icon:ClearAllPoints()
                        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                    end)
                end

                -- Reanchor cooldown frame to match new button edges
                local cd = btn.cooldown or btn.Cooldown or btn.CooldownFrame
                if cd then
                    pcall(function()
                        cd:ClearAllPoints()
                        cd:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                        cd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                    end)
                end

                -- Hide mask entirely — atlas rounded shape clips non-square icons
                if btn.IconMask then
                    pcall(btn.IconMask.Hide, btn.IconMask)
                end

                -- Resize hover/checked/pushed textures to match shaped button
                for _, key in ipairs({"HighlightTexture", "CheckedTexture", "PushedTexture"}) do
                    local tex = btn[key]
                    if tex then
                        pcall(function()
                            tex:ClearAllPoints()
                            tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                            tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                        end)
                    end
                end
            end
        elseif not inCombat and tallWideRatio == 0 and iconShapedButtons[btn] then
            -- Only reset buttons that were previously shaped
            pcall(btn.SetSize, btn, baseButtonSize, baseButtonSize)

            local icon = btn.icon or btn.Icon
            if icon then
                pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
                pcall(function()
                    icon:ClearAllPoints()
                    icon:SetAllPoints(btn)
                end)
            end

            -- Restore IconMask to default (show + reset size)
            if btn.IconMask then
                pcall(btn.IconMask.Show, btn.IconMask)
                pcall(btn.IconMask.SetSize, btn.IconMask, 45, 45)
            end

            -- Restore hover/checked/pushed textures to Blizzard defaults
            for _, key in ipairs({"HighlightTexture", "CheckedTexture", "PushedTexture"}) do
                local tex = btn[key]
                if tex then
                    pcall(function()
                        tex:ClearAllPoints()
                        tex:SetPoint("TOPLEFT")
                        if isStanceOrPet then
                            tex:SetSize(31.6, 30.9)
                        else
                            tex:SetSize(46, 45)
                        end
                    end)
                end
            end

            -- Restore cooldown to Blizzard default offsets (anchored to icon)
            local cd = btn.cooldown or btn.Cooldown or btn.CooldownFrame
            if cd and icon then
                pcall(function()
                    cd:ClearAllPoints()
                    if isStanceOrPet then
                        -- SmallActionButtonMixin_OnLoad offsets (ActionButton.lua:1744-1745)
                        cd:SetPoint("TOPLEFT", icon, "TOPLEFT", 1.7, -1.7)
                        cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
                    else
                        -- ActionButtonTemplate.xml default (3px inset)
                        cd:SetPoint("TOPLEFT", icon, "TOPLEFT", 3, -3)
                        cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 3)
                    end
                end)
            end

            iconShapedButtons[btn] = nil
        end

        if styleKey == "off" then
            -- Restore Blizzard default art, remove custom borders
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(btn) end
            toggleDefaultButtonArt(btn, true)
            if btn.Count and not inCombat then addon.DemoteIconText(btn.Count) end
        elseif styleKey == "hidden" then
            -- Hide everything
            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(btn) end
            toggleDefaultButtonArt(btn, false)
            if btn.Count and not inCombat then addon.DemoteIconText(btn.Count) end
        else
            -- Apply custom border
            if styleKey == "square" and addon.Borders and addon.Borders.ApplySquare then
                if addon.Borders.HideAll then addon.Borders.HideAll(btn) end
                local col = tintEnabled and tintColor or {0, 0, 0, 1}
                local isPetButton = (self.frameName == "PetActionBar")
                local iconRegion = isPetButton and getButtonIconRegion(btn) or nil
                local shaped = tallWideRatio ~= 0
                addon.Borders.ApplySquare(btn, {
                    size = thickness,
                    color = col,
                    layer = "OVERLAY",
                    layerSublevel = 7,
                    expandX = 0 - borderInsetH,
                    expandY = 0 - borderInsetV,
                    expandTop = (shaped and 0 or 1) - borderInsetV,
                    expandBottom = (shaped and 0 or -1) - borderInsetV,
                    levelOffset = iconRegion and 5 or nil,
                    containerParent = iconRegion and btn or nil,
                    containerAnchorRegion = iconRegion,
                })
            else
                addon.ApplyIconBorderStyle(btn, styleKey, {
                    thickness = thickness,
                    color = tintColor,
                    tintEnabled = tintEnabled,
                    db = self.db,
                    thicknessKey = "borderThickness",
                    tintColorKey = "borderTintColor",
                    insetH = borderInsetH,
                    insetV = borderInsetV,
                    defaultThickness = (self.settings and self.settings.borderThickness and self.settings.borderThickness.default) or 1,
                })
            end
            toggleDefaultButtonArt(btn, false)
            -- Border art lands either on btn itself at OVERLAY 7, the ceiling, or on a
            -- container above it (the Pet bar path at levelOffset = 5). Either way the
            -- stack count has to sit on a frame above whatever got the art. Skipped in
            -- combat with the rest of the reparenting work on these protected buttons.
            if btn.Count and not inCombat then
                addon.PromoteIconText(btn.Count, btn, addon.Borders.GetSquareContainer(btn) or btn)
            end
        end

        do
            local disableBackdrop = self.db and self.db.backdropDisable
            local style = self.db.backdropStyle or "blizzardBg"
            local opacity = tonumber(self.db and self.db.backdropOpacity) or 100
            local inset = tonumber(self.db and self.db.backdropInset) or 0
            local backdropTintEnabled = self.db and self.db.backdropTintEnable and type(self.db.backdropTintColor) == "table"
            local backdropTint
            if backdropTintEnabled then
                local c = self.db.backdropTintColor or {1,1,1,1}
                backdropTint = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
            end
            if disableBackdrop then
                local bg = btn and btn.SlotBackground
                if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end
            else
                if addon and addon.ApplyIconBackdropToActionButton then
                    addon.ApplyIconBackdropToActionButton(btn, style, opacity, inset, backdropTint)
                end
            end
        end

        do
            local function applyTextToFontString(fs, cfg, justify, anchorPoint, relTo)
                if not fs or not fs.SetFont then return end
                pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
                addon.ApplyTextFont(fs, cfg, abTextFontOpts)
                local c = cfg.color or {1,1,1,1}
                if fs.SetTextColor then pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
                if justify and fs.SetJustifyH then pcall(fs.SetJustifyH, fs, justify) end
                local ox = (cfg.offset and cfg.offset.x) or 0
                local oy = (cfg.offset and cfg.offset.y) or 0
                if (ox ~= 0 or oy ~= 0) and fs.ClearAllPoints and fs.SetPoint then
                    fs:ClearAllPoints()
                    fs:SetPoint(anchorPoint or "CENTER", relTo or btn, anchorPoint or "CENTER", ox, oy)
                end
            end

            if btn.Count then
                local cfg = rawget(self.db, "textStacks")
                if cfg then
                    applyTextToFontString(btn.Count, cfg, "CENTER", "CENTER", btn)
                end
            end

            local cdOwner = btn.cooldown or btn.Cooldown or btn.CooldownFrame or nil
            local cdText
            if cdOwner then
                local function findFS(obj)
                    if not obj then return nil end
                    if obj.GetObjectType and obj:GetObjectType() == "FontString" then return obj end
                    if obj.GetRegions then
                        local n = (obj.GetNumRegions and obj:GetNumRegions(obj)) or 0
                        for i = 1, n do
                            local r = select(i, obj:GetRegions())
                            if r and r.GetObjectType and r:GetObjectType() == "FontString" then return r end
                        end
                    end
                end
                cdText = findFS(cdOwner)
            end
            if cdText then
                local cfg = rawget(self.db, "textCooldown")
                if cfg then
                    applyTextToFontString(cdText, cfg, "CENTER", "CENTER", btn)
                end
            end

            if btn.HotKey then
                local txt = (btn.HotKey.GetText and btn.HotKey:GetText()) or nil
                local rangeIndicator = (_G and _G.RANGE_INDICATOR) or "RANGE_INDICATOR"
                local isEmpty = (txt == nil or txt == "")
                local isRange = (txt == rangeIndicator or txt == "•")
                local hiddenByUser = self.db and rawget(self.db, "textHotkeyHidden")
                local shouldShow = (not hiddenByUser) and (not isEmpty) and (not isRange)
                pcall(btn.HotKey.SetShown, btn.HotKey, shouldShow)
                if shouldShow then
                    local cfg = rawget(self.db, "textHotkey")
                    if cfg then
                        applyTextToFontString(btn.HotKey, cfg, "RIGHT", "TOPRIGHT", btn)
                    end
                end
            end

            if btn.Name then
                local txt = (btn.Name.GetText and btn.Name:GetText()) or nil
                local isEmpty = (txt == nil or txt == "")
                local hiddenByUser = self.db and rawget(self.db, "textMacroHidden")
                local shouldShow = (not hiddenByUser) and (not isEmpty)
                pcall(btn.Name.SetShown, btn.Name, shouldShow)
                if shouldShow then
                    local cfg = rawget(self.db, "textMacro")
                    if cfg then
                        applyTextToFontString(btn.Name, cfg, "CENTER", "BOTTOM", btn)
                    end
                end
            end
        end
    end
end

-- Micro Bar opacity and mouseover styling function
local function ApplyMicroBarStyling(self)
    local bar = _G[self.frameName]
    if not bar then return end

    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if addon.IsComponentUnconfigured(self) then return end

    -- Keep the QueueStatusButton ("LFG eye") fully visible even when the Micro Bar opacity is reduced.
    -- This button is effectively "part of" the Micro Bar area and can inherit parent alpha.
    local function ensureQueueStatusButtonFullAlpha()
        local qsb = _G.QueueStatusButton
        if not qsb then return end
        if qsb.SetIgnoreParentAlpha then
            pcall(qsb.SetIgnoreParentAlpha, qsb, true)
        end
        if qsb.SetAlpha then
            pcall(qsb.SetAlpha, qsb, 1)
        end
    end
    ensureQueueStatusButtonFullAlpha()
    if (not _G.QueueStatusButton) and C_Timer and C_Timer.After then
        -- QueueStatusButton can be created after initial UI load; retry once next tick.
        C_Timer.After(0, ensureQueueStatusButtonFullAlpha)
    end

    -- Hook SetAlpha on this bar to intercept and correct external changes
    hookBarAlpha(bar)

    local baseOp = tonumber(self.db.barOpacity) or 100
    if baseOp < 0 then baseOp = 0 elseif baseOp > 100 then baseOp = 100 end

    local oocOp = tonumber(self.db.barOpacityOutOfCombat) or baseOp
    if oocOp < 0 then oocOp = 0 elseif oocOp > 100 then oocOp = 100 end

    local tgtOp = tonumber(self.db.barOpacityWithTarget) or baseOp
    if tgtOp < 0 then tgtOp = 0 elseif tgtOp > 100 then tgtOp = 100 end

    local hasTarget = (UnitExists and UnitExists("target")) and true or false
    local appliedOp = hasTarget and tgtOp or (Util.PlayerInCombat() and baseOp or oocOp)

    local function enumerateMicroButtons()
        local buttons = {}
        local microButtonNames = {
            "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
            "AchievementMicroButton", "QuestLogMicroButton", "GuildMicroButton",
            "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton",
            "StoreMicroButton", "MainMenuMicroButton",
        }
        for _, name in ipairs(microButtonNames) do
            local btn = _G[name]
            if btn then buttons[#buttons + 1] = btn end
        end
        if #buttons == 0 and bar.GetChildren then
            for _, child in ipairs({ bar:GetChildren() }) do
                local t = child.GetObjectType and child:GetObjectType()
                if t == "Button" or t == "CheckButton" then
                    buttons[#buttons + 1] = child
                end
            end
        end
        return buttons
    end
    
    local function isMouseCurrentlyOverBar()
        if bar.IsMouseOver and bar:IsMouseOver() then return true end
        for _, btn in ipairs(enumerateMicroButtons()) do
            if btn.IsMouseOver and btn:IsMouseOver() then return true end
        end
        return false
    end

    local state = getBarState(bar)
    state.component = self
    state.baseOpacity = appliedOp / 100
    
    local mouseoverEnabled = self.db and self.db.mouseoverMode
    
    if mouseoverEnabled then
        local function onMouseEnter()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                s.isMousedOver = true
                setBarDesiredAlpha(bar, 1)
            end
        end
        local function onMouseLeave()
            local s = actionBarState[bar]
            if s and s.component and s.component.db and s.component.db.mouseoverMode then
                local isOverBar = bar:IsMouseOver()
                if not isOverBar then
                    for _, btn in ipairs(enumerateMicroButtons()) do
                        if btn.IsMouseOver and btn:IsMouseOver() then
                            isOverBar = true
                            break
                        end
                    end
                end
                if not isOverBar then
                    s.isMousedOver = false
                    setBarDesiredAlpha(bar, s.baseOpacity or 1)
                end
            end
        end

        if not actionBarHooked[bar] then
            bar:HookScript("OnEnter", onMouseEnter)
            bar:HookScript("OnLeave", onMouseLeave)
            actionBarHooked[bar] = true
        end

        for _, btn in ipairs(enumerateMicroButtons()) do
            if not actionBarHooked[btn] then
                btn:HookScript("OnEnter", onMouseEnter)
                btn:HookScript("OnLeave", onMouseLeave)
                actionBarHooked[btn] = true
            end
        end

        if isMouseCurrentlyOverBar() then
            state.isMousedOver = true
            setBarDesiredAlpha(bar, 1)
        else
            state.isMousedOver = false
            setBarDesiredAlpha(bar, appliedOp / 100)
        end
    else
        state.isMousedOver = false
        setBarDesiredAlpha(bar, appliedOp / 100)
    end
end

addon:RegisterComponentInitializer(function(self)
    local microBar = Component:New({
        id = "microBar",
        name = "Micro Bar",
        frameName = "MicroMenuContainer",
        settings = {
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            direction = { type = "editmode", settingId = 1, default = "right", ui = {
                label = "Icon Direction", widget = "dropdown", values = { left = "Left", right = "Right", up = "Up", down = "Down" }, section = "Positioning", order = 2, dynamicValues = true
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
            }},
            menuSize = { type = "editmode", settingId = 2, default = 100, ui = {
                label = "Menu Size (Scale)", widget = "slider", min = 70, max = 200, step = 5, section = "Sizing", order = 1
            }},
            eyeSize = { type = "editmode", settingId = 3, default = 100, ui = {
                label = "Eye Size", widget = "slider", min = 50, max = 150, step = 5, section = "Sizing", order = 2
            }},
            -- Visibility / Opacity settings (section "Misc" renders as "Visibility" header)
            barOpacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 1
            }},
            barOpacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 2
            }},
            barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 3
            }},
            mouseoverMode = { type = "addon", default = false, ui = {
                label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 4
            }},
        },
        ApplyStyling = ApplyMicroBarStyling,
    })
    self:RegisterComponent(microBar)

    local stanceBar = Component:New({
        id = "stanceBar",
        name = "Stance Bar",
        frameName = "StanceBar",
        maxButtons = 10,
        settings = {
            orientation = { type = "editmode", default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            columns = { type = "editmode", default = 1, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 4, step = 1, section = "Positioning", order = 2, dynamicLabel = true
            }},
            iconPadding = { type = "editmode", default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 3
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
            }},
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            tallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2
            }},
            borderStyle = { type = "addon", default = "off", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 4
            }},
            borderInset = { type = "addon", default = 0 },
            borderInsetH = { type = "addon", default = 0 },
            borderInsetV = { type = "addon", default = 0 },
            barOpacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 99
            }},
            barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 100
            }},
            barOpacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 101
            }},
            mouseoverMode = { type = "addon", default = false, ui = {
                label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 102
            }},
        },
        ApplyStyling = ApplyActionBarStyling,
    })
    self:RegisterComponent(stanceBar)

    local function abComponent(id, name, frameName, defaultOrientation)
        return Component:New({
            id = id,
            name = name,
            frameName = frameName,
            settings = {
                orientation = { type = "editmode", settingId = 0, default = defaultOrientation, ui = {
                    label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
                }},
                columns = { type = "editmode", default = 1, ui = {
                    label = "# Columns/Rows", widget = "slider", min = 1, max = 4, step = 1, section = "Positioning", order = 2, dynamicLabel = true
                }},
                numIcons = { type = "editmode", default = 12, ui = {
                    label = "# of Icons", widget = "slider", min = 6, max = 12, step = 1, section = "Positioning", order = 3
                }},
                iconPadding = { type = "editmode", default = 2, ui = {
                    label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 4
                }},
                iconSize = { type = "editmode", default = 100, ui = {
                    label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
                }},
                tallWideRatio = { type = "addon", default = 0, ui = {
                    label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2
                }},
                borderStyle = { type = "addon", default = "off", ui = {
                    label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                    optionsProvider = function()
                        if addon.BuildIconBorderOptionsContainer then
                            return addon.BuildIconBorderOptionsContainer()
                        end
                        return {}
                    end
                }},
                borderTintEnable = { type = "addon", default = false, ui = {
                    label = "Border Tint", widget = "checkbox", section = "Border", order = 2
                }},
                borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                    label = "Tint Color", widget = "color", section = "Border", order = 3
                }},
                borderThickness = { type = "addon", default = 1, ui = {
                    label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 4
                }},
                borderInset = { type = "addon", default = 0 },
                borderInsetH = { type = "addon", default = 0 },
                borderInsetV = { type = "addon", default = 0 },
                backdropDisable = { type = "addon", default = false, ui = {
                    label = "Disable Backdrop", widget = "checkbox", section = "Backdrop", order = 1
                }},
                backdropStyle = { type = "addon", default = "blizzardBg", ui = {
                    label = "Backdrop Style", widget = "dropdown", section = "Backdrop", order = 2,
                    optionsProvider = function()
                        if addon.BuildIconBackdropOptionsContainer then
                            return addon.BuildIconBackdropOptionsContainer()
                        end
                        return {}
                    end
                }},
                backdropOpacity = { type = "addon", default = 100, ui = {
                    label = "Backdrop Opacity", widget = "slider", min = 0, max = 100, step = 1, section = "Backdrop", order = 3
                }},
                backdropTintEnable = { type = "addon", default = false, ui = {
                    label = "Backdrop Tint", widget = "checkbox", section = "Backdrop", order = 4
                }},
                backdropTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                    label = "Tint Color", widget = "color", section = "Backdrop", order = 5
                }},
                backdropInset = { type = "addon", default = 0, ui = {
                    label = "Backdrop Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Backdrop", order = 6
                }},
                textStacks = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                textCooldown = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                textHotkeyHidden = { type = "addon", default = false, ui = {
                    label = "Hide Hotkey Text", widget = "checkbox", section = "Text", order = 10
                }},
                textHotkey = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                textMacroHidden = { type = "addon", default = false, ui = {
                    label = "Hide Macro Text", widget = "checkbox", section = "Text", order = 20
                }},
                textMacro = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
                barOpacity = { type = "addon", default = 100, ui = {
                    label = "Opacity in Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 99
                }},
                barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                    label = "Opacity Out of Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 100
                }},
                barOpacityWithTarget = { type = "addon", default = 100, ui = {
                    label = "Opacity With Target", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 101
                }},
                mouseoverMode = { type = "addon", default = false, ui = {
                    label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 102
                }},
                positionX = { type = "addon", default = 0, ui = {
                    label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
                }},
                positionY = { type = "addon", default = 0, ui = {
                    label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
                }},
                supportsText = { type = "addon", default = true },
            },
            ApplyStyling = ApplyActionBarStyling,
        })
    end

    local defs = {
        { "actionBar1", "Action Bar 1", "MainActionBar",        "H", false },
        { "actionBar2", "Action Bar 2", "MultiBarBottomLeft",  "H", true },
        { "actionBar3", "Action Bar 3", "MultiBarBottomRight", "H", true },
        { "actionBar4", "Action Bar 4", "MultiBarRight",       "V", true },
        { "actionBar5", "Action Bar 5", "MultiBarLeft",        "V", true },
        { "actionBar6", "Action Bar 6", "MultiBar5",           "H", true },
        { "actionBar7", "Action Bar 7", "MultiBar6",           "H", true },
        { "actionBar8", "Action Bar 8", "MultiBar7",           "H", true },
    }

    for _, d in ipairs(defs) do
        local comp = abComponent(d[1], d[2], d[3], d[4])
        if d[5] then
            comp.settings.barVisibility = { type = "editmode", default = "always", ui = {
                label = "Bar Visible", widget = "dropdown", values = { always = "Always", combat = "In Combat", not_in_combat = "Not In Combat", hidden = "Hidden" }, section = "Misc", order = 1
            }}
            comp.settings.alwaysShowButtons = { type = "editmode", default = true, ui = {
                label = "Always Show Buttons", widget = "checkbox", section = "Misc", order = 2
            }}
        else
            comp.supportsEmptyVisibilitySection = true
            comp.settings.alwaysShowButtons = { type = "editmode", default = true, ui = {
                label = "Always Show Buttons", widget = "checkbox", section = "Misc", order = 1
            }}
            comp.settings.hideBarArt = { type = "editmode", default = false, ui = {
                label = "Hide Bar Art", widget = "checkbox", section = "Misc", order = 2
            }}
            comp.settings.hideBarScrolling = { type = "editmode", default = false, ui = {
                label = "Hide Bar Scrolling", widget = "checkbox", section = "Misc", order = 3
            }}
        end
        self:RegisterComponent(comp)
    end

    -- Pet Bar: 10 buttons, similar Edit Mode settings to Action Bars but no visibility/art/scrolling options
    local petBar = Component:New({
        id = "petBar",
        name = "Pet Bar",
        frameName = "PetActionBar",
        maxButtons = 10,
        settings = {
            orientation = { type = "editmode", settingId = 0, default = "H", ui = {
                label = "Orientation", widget = "dropdown", values = { H = "Horizontal", V = "Vertical" }, section = "Positioning", order = 1
            }},
            columns = { type = "editmode", default = 1, ui = {
                label = "# Columns/Rows", widget = "slider", min = 1, max = 4, step = 1, section = "Positioning", order = 2, dynamicLabel = true
            }},
            iconPadding = { type = "editmode", default = 2, ui = {
                label = "Icon Padding", widget = "slider", min = 2, max = 10, step = 1, section = "Positioning", order = 3
            }},
            positionX = { type = "addon", default = 0, ui = {
                label = "X Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 98
            }},
            positionY = { type = "addon", default = 0, ui = {
                label = "Y Position", widget = "slider", min = -1000, max = 1000, step = 1, section = "Positioning", order = 99
            }},
            iconSize = { type = "editmode", default = 100, ui = {
                label = "Icon Size (Scale)", widget = "slider", min = 50, max = 200, step = 10, section = "Sizing", order = 1
            }},
            tallWideRatio = { type = "addon", default = 0, ui = {
                label = "Icon Shape", widget = "slider", min = -67, max = 67, step = 1, section = "Sizing", order = 2
            }},
            borderStyle = { type = "addon", default = "off", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = function()
                    if addon.BuildIconBorderOptionsContainer then
                        return addon.BuildIconBorderOptionsContainer()
                    end
                    return {}
                end
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2
            }},
            borderTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 4
            }},
            borderInset = { type = "addon", default = 0 },
            borderInsetH = { type = "addon", default = 0 },
            borderInsetV = { type = "addon", default = 0 },
            backdropDisable = { type = "addon", default = false, ui = {
                label = "Disable Backdrop", widget = "checkbox", section = "Backdrop", order = 1
            }},
            backdropStyle = { type = "addon", default = "blizzardBg", ui = {
                label = "Backdrop Style", widget = "dropdown", section = "Backdrop", order = 2,
                optionsProvider = function()
                    if addon.BuildIconBackdropOptionsContainer then
                        return addon.BuildIconBackdropOptionsContainer()
                    end
                    return {}
                end
            }},
            backdropOpacity = { type = "addon", default = 100, ui = {
                label = "Backdrop Opacity", widget = "slider", min = 0, max = 100, step = 1, section = "Backdrop", order = 3
            }},
            backdropTintEnable = { type = "addon", default = false, ui = {
                label = "Backdrop Tint", widget = "checkbox", section = "Backdrop", order = 4
            }},
            backdropTintColor = { type = "addon", default = {1,1,1,1}, ui = {
                label = "Tint Color", widget = "color", section = "Backdrop", order = 5
            }},
            backdropInset = { type = "addon", default = 0, ui = {
                label = "Backdrop Inset", widget = "slider", min = -4, max = 4, step = 1, section = "Backdrop", order = 6
            }},
            textStacks = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            textCooldown = { type = "addon", default = { size = 16, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            textHotkeyHidden = { type = "addon", default = false, ui = {
                label = "Hide Hotkey Text", widget = "checkbox", section = "Text", order = 10
            }},
            textHotkey = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            textMacroHidden = { type = "addon", default = false, ui = {
                label = "Hide Macro Text", widget = "checkbox", section = "Text", order = 20
            }},
            textMacro = { type = "addon", default = { size = 14, style = "OUTLINE", color = {1,1,1,1}, offset = { x = 0, y = 0 }, fontFace = "FRIZQT__" }, ui = { hidden = true }},
            alwaysShowButtons = { type = "editmode", default = true, ui = {
                label = "Always Show Buttons", widget = "checkbox", section = "Misc", order = 1
            }},
            barOpacity = { type = "addon", default = 100, ui = {
                label = "Opacity in Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 99
            }},
            barOpacityOutOfCombat = { type = "addon", default = 100, ui = {
                label = "Opacity Out of Combat", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 100
            }},
            barOpacityWithTarget = { type = "addon", default = 100, ui = {
                label = "Opacity With Target", widget = "slider", min = 0, max = 100, step = 1, section = "Misc", order = 101
            }},
            mouseoverMode = { type = "addon", default = false, ui = {
                label = "Mouseover Mode", widget = "checkbox", section = "Misc", order = 102
            }},
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyActionBarStyling,
    })
    self:RegisterComponent(petBar)
end, "actionBars")

function addon.CopyActionBarSettings(sourceComponentId, destComponentId)
    if type(sourceComponentId) ~= "string" or type(destComponentId) ~= "string" then return end
    if sourceComponentId == destComponentId then return end
    local src = addon.Components and addon.Components[sourceComponentId]
    local dst = addon.Components and addon.Components[destComponentId]
    if not src or not dst then return end
    -- Source must be actionBar1-8; destination can be actionBar1-8 or petBar (destination-only)
    local srcValid = sourceComponentId:match("^actionBar%d$") ~= nil
    local dstValid = destComponentId:match("^actionBar%d$") or destComponentId == "petBar"
    if not (srcValid and dstValid) then return end

    if not src.db or not dst.db then return end

    local function deepcopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, vv in pairs(v) do out[k] = deepcopy(vv) end
        return out
    end

    for key, def in pairs(dst.settings or {}) do
        if key ~= "supportsText" and key ~= "supportsEmptyVisibilitySection" then
            local srcVal = src.db[key]
            if srcVal ~= nil then
                dst.db[key] = deepcopy(srcVal)
            end
        end
    end

    do
        local textKeys = {
            "textStacks", "textCooldown",
            "textHotkeyHidden", "textHotkey",
            "textMacroHidden",  "textMacro",
        }
        for _, key in ipairs(textKeys) do
            if src.db[key] ~= nil then
                dst.db[key] = deepcopy(src.db[key])
            end
        end
    end

    if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
        for key, def in pairs(dst.settings or {}) do
            if type(def) == "table" and def.type == "editmode" then
                pcall(addon.EditMode.SyncComponentSettingToEditMode, dst, key, { skipApply = true })
            end
        end
    end

    -- Settings persist via SaveOnly inside SyncComponentSettingToEditMode; no need for additional call.
    -- Edit Mode state syncs when user opens/closes Edit Mode.
    addon:ApplyStyles()
end

