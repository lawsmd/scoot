-- classauras/regions.lua - Region creation and engine bindings for slot buttons
--
-- Every visual element lives under the engine-managed button so its secret
-- show/hide propagates natively; the addon never branches on aura presence.
-- Elements reuse the exact table shape the legacy path builds (type, widget,
-- barFill, barBg, def), so styling.lua and layout.lua work on them unchanged.
local addonName, addon = ...

local CA = addon.ClassAuras
local Engine = CA.Engine

local GetDB = CA._GetDB
local SafeToString = Engine._SafeToString
local SetResult = Engine._SetResult

local DIR_ELAPSED = (Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime) or 0
local DIR_REMAINING = (Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime) or 1

--------------------------------------------------------------------------------
-- Region creation (runs inside the slot's initializeFrame)
--------------------------------------------------------------------------------

-- Pre-create the icon border frame structure ApplyBorders expects, parented to
-- the button (ApplyBorders would otherwise lazily parent it to the Scoot
-- frame, where it would not hide with the button).
local function PreCreateIconBorder(elem, button)
    if elem.type ~= "texture" or elem.borderFrame then return end
    local bf = CreateFrame("Frame", nil, button)
    bf:SetFrameLevel(button:GetFrameLevel() + 2)
    bf.borderEdges = {
        Top = bf:CreateTexture(nil, "OVERLAY", nil, 1),
        Bottom = bf:CreateTexture(nil, "OVERLAY", nil, 1),
        Left = bf:CreateTexture(nil, "OVERLAY", nil, 1),
        Right = bf:CreateTexture(nil, "OVERLAY", nil, 1),
    }
    for _, tex in pairs(bf.borderEdges) do tex:Hide() end
    bf.atlasBorder = bf:CreateTexture(nil, "OVERLAY", nil, 2)
    bf.atlasBorder:Hide()
    elem.borderFrame = bf
end

-- Builds state.elements/state.textFrame under the button. Called from
-- initializeFrame, where the button tree is guaranteed touchable.
function Engine.WireButton(aura, state, entry, button)
    button:ClearAllPoints()
    button:SetAllPoints(state.container)

    -- Text draws above bar fills, mirroring the legacy textFrame arrangement.
    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints(button)
    textHost:SetFrameLevel(button:GetFrameLevel() + 4)
    state.textFrame = textHost

    local creators = CA._elementCreators
    local elements = {}
    local hasBar = false
    for _, elemDef in ipairs(aura.elements or {}) do
        local creator = creators[elemDef.type]
        if creator then
            local elem = creator(button, elemDef, textHost)
            PreCreateIconBorder(elem, button)
            table.insert(elements, elem)
        end
        if elemDef.type == "bar" then hasBar = true end
    end
    if hasBar then
        table.insert(elements, creators.text(button,
            { type = "text", key = "name", source = "name", baseSize = 10 }, textHost))
    end
    state.elements = elements

    -- Def-specific under-button extras (DK dot swipe cooldown + square edges).
    -- Runs inside initializeFrame, so the button tree is touchable here.
    if aura.onEngineWire then
        aura.onEngineWire(aura, state, entry, button)
    end
end

--------------------------------------------------------------------------------
-- Engine bindings per display mode
--------------------------------------------------------------------------------

local function CallBinding(aura, button, methodName, region, options)
    local fn = button[methodName]
    if not fn then
        SetResult("bind." .. aura.id .. "." .. methodName, "method missing")
        return false
    end
    local ok, err
    if options ~= nil then
        ok, err = pcall(fn, button, region, options)
    elseif region ~= nil then
        ok, err = pcall(fn, button, region)
    else
        ok, err = pcall(fn, button)
    end
    SetResult("bind." .. aura.id .. "." .. methodName, ok and "ok" or ("FAILED: " .. SafeToString(err)))
    return ok
end

-- Binds or clears each element against the button per the current display
-- mode. Caller must hold the structural-work gate (ApplyAll does).
function Engine.BindForMode(aura, state)
    local entry = Engine._entries[aura.id]
    if not entry or not entry.button then return end
    local db = GetDB(aura)
    if not db then return end
    local button = entry.button

    local mode = db.mode or "icon"
    local showIcon = (mode == "icon" or mode == "iconbar") and (db.iconMode or "default") ~= "hidden"
    local showBar = (mode == "bar" or mode == "iconbar")
    local showText = not db.hideText
    local showName = showBar and not db.hideNameText

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            if aura.customIconHandling then
                -- The def's engineApply hook owns this texture (DK dots paint
                -- squares/desaturation); the engine must not stamp aura icons.
                CallBinding(aura, button, "ClearIcon")
            elseif showIcon and (db.iconMode or "default") == "default" then
                CallBinding(aura, button, "SetIcon", elem.widget)
            else
                -- Custom/hidden icon modes keep the texture Scoot-owned; it
                -- still hides with the button.
                CallBinding(aura, button, "ClearIcon")
            end
        elseif elem.type == "text" then
            local source = elem.def.source
            if source == "duration" then
                if showText then
                    CallBinding(aura, button, "SetDurationText", elem.widget, {})
                else
                    CallBinding(aura, button, "ClearDurationText")
                end
            elseif source == "applications" then
                if showText then
                    CallBinding(aura, button, "SetApplicationCount", elem.widget)
                else
                    CallBinding(aura, button, "ClearApplicationCount")
                end
            elseif source == "name" then
                if showName then
                    CallBinding(aura, button, "SetSpellName", elem.widget)
                else
                    CallBinding(aura, button, "ClearSpellName")
                end
            end
        elseif elem.type == "bar" then
            if showBar then
                if elem.def.source == "applications" then
                    CallBinding(aura, button, "ClearDurationBar")
                    CallBinding(aura, button, "SetApplicationBar", elem.barFill)
                else
                    CallBinding(aura, button, "ClearApplicationBar")
                    local direction = (elem.def.fillMode == "fill") and DIR_ELAPSED or DIR_REMAINING
                    CallBinding(aura, button, "SetDurationBar", elem.barFill, { direction = direction })
                end
            else
                CallBinding(aura, button, "ClearDurationBar")
                CallBinding(aura, button, "ClearApplicationBar")
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Edit Mode preview (Scoot-side art; engine buttons cannot fake auras)
--------------------------------------------------------------------------------

local function ResolveForegroundColor(aura, db)
    local colorMode = db.barForegroundColorMode or "custom"
    if colorMode == "original" then
        return 1, 1, 1, 1
    elseif colorMode == "class" then
        local classColor = RAID_CLASS_COLORS[CA._playerClassToken]
        if classColor then return classColor.r, classColor.g, classColor.b, 1 end
        return 1, 1, 1, 1
    end
    local c = db.barForegroundTint or aura.defaultBarColor or { 1, 1, 1, 1 }
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

function Engine.ShowEditModePreview(aura, state)
    local db = GetDB(aura)
    if not db or not state.container then return end

    -- Custom-art auras (DK dots) preview through their own always-built layers
    -- (inactive art + static exclamation via onEditModeEnter); the generic
    -- icon/bar/text mock would double-draw over them.
    if aura.customIconHandling then
        if state.previewFrame then state.previewFrame:Hide() end
        return
    end

    local pv = state.previewFrame
    if not pv then
        pv = CreateFrame("Frame", nil, state.container)
        pv:SetFrameLevel(state.container:GetFrameLevel() + 10)
        pv.barBg = pv:CreateTexture(nil, "BACKGROUND")
        pv.barFill = pv:CreateTexture(nil, "ARTWORK")
        pv.icon = pv:CreateTexture(nil, "ARTWORK", nil, 1)
        pv.text = pv:CreateFontString(nil, "OVERLAY")
        state.previewFrame = pv
    end
    pv:ClearAllPoints()
    pv:SetAllPoints(state.container)

    local mode = db.mode or "icon"
    local showIcon = (mode == "icon" or mode == "iconbar") and (db.iconMode or "default") ~= "hidden"
    local showBar = (mode == "bar" or mode == "iconbar")
    local barW = tonumber(db.barWidth) or 120
    local barH = tonumber(db.barHeight) or 12

    if showIcon then
        local iconPath
        local ok, tex = pcall(C_Spell.GetSpellTexture, aura.auraSpellId)
        if ok and tex and not issecretvalue(tex) then iconPath = tex end
        for _, elemDef in ipairs(aura.elements or {}) do
            if elemDef.type == "texture" and (db.iconMode == "custom" or not iconPath) and elemDef.customPath then
                iconPath = elemDef.customPath
            end
        end
        if iconPath then pv.icon:SetTexture(iconPath) end
        pv.icon:ClearAllPoints()
        pv.icon:SetAllPoints(pv)
        pv.icon:Show()
    else
        pv.icon:Hide()
    end

    if showBar then
        local fgPath = addon.Media.ResolveBarTexturePath(db.barForegroundTexture or "bevelled")
        pv.barBg:ClearAllPoints()
        pv.barFill:ClearAllPoints()
        if showIcon then
            -- Bar sits beside the icon, mirroring the layout engine's placement.
            local barPos = db.barPosition or "LEFT"
            if barPos == "LEFT" then
                pv.barBg:SetPoint("RIGHT", pv, "LEFT", -2, 0)
            else
                pv.barBg:SetPoint("LEFT", pv, "RIGHT", 2, 0)
            end
            pv.barBg:SetSize(barW, barH)
        else
            pv.barBg:SetAllPoints(pv)
        end
        if fgPath then
            pv.barBg:SetTexture(fgPath)
            pv.barFill:SetTexture(fgPath)
        else
            pv.barBg:SetColorTexture(1, 1, 1, 1)
            pv.barFill:SetColorTexture(1, 1, 1, 1)
        end
        local bg = db.barBackgroundTint or { 0, 0, 0, 1 }
        pv.barBg:SetVertexColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, (db.barBackgroundOpacity or 50) / 100)
        pv.barFill:SetVertexColor(ResolveForegroundColor(aura, db))
        pv.barFill:SetPoint("TOPLEFT", pv.barBg, "TOPLEFT", 0, 0)
        pv.barFill:SetPoint("BOTTOMLEFT", pv.barBg, "BOTTOMLEFT", 0, 0)
        pv.barFill:SetWidth(math.max(barW * 0.6, 1))
        pv.barBg:Show()
        pv.barFill:Show()
    else
        pv.barBg:Hide()
        pv.barFill:Hide()
    end

    if not db.hideText then
        local fontFace = addon.ResolveFontFace(db.textFont or "FRIZQT__")
        addon.ApplyFontStyle(pv.text, fontFace, db.textSize or 24, db.textStyle or "OUTLINE")
        local c = db.textColor or { 1, 1, 1, 1 }
        pv.text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        local sample = "8.3"
        for _, elemDef in ipairs(aura.elements or {}) do
            if elemDef.type == "text" and elemDef.source == "applications" then
                sample = "#"
                break
            end
        end
        pv.text:SetText(sample)
        pv.text:ClearAllPoints()
        if showBar and not showIcon then
            pv.text:SetPoint("RIGHT", pv.barBg, "RIGHT", -2, 0)
        else
            pv.text:SetPoint("CENTER", pv, "CENTER", 0, 0)
        end
        pv.text:Show()
    else
        pv.text:Hide()
    end

    pv:Show()
end

function Engine.HideEditModePreview(state)
    if state and state.previewFrame then
        state.previewFrame:Hide()
    end
end

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

Engine._CallBinding = CallBinding
