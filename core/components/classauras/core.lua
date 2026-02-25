-- classauras/core.lua - Shared infrastructure for Class Auras system
local addonName, addon = ...

addon.ClassAuras = addon.ClassAuras or {}
local CA = addon.ClassAuras

local Component = addon.ComponentPrototype

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

CA._registry = {}       -- [auraId] = auraDef (flat lookup)
CA._classAuras = {}     -- [classToken] = { auraDef, auraDef, ... }
CA._activeAuras = {}    -- [auraId] = { container, elements, component }

local editModeActive = false

-- CDM Borrow subsystem: "borrows" display data from Blizzard's CDM Tracked Buffs icons.
-- Instead of detecting auras ourselves (blocked by 12.0 secrets), we hook the FontStrings
-- on CDM icons that Blizzard populates in its untainted context.
-- Prerequisite: User must add the tracked spell to CDM > Tracked Buffs.
local cdmBorrow = {
    hookInstalled = false,
}
-- Weak-key map: FontString → auraId (avoids writing to Blizzard frame tables)
local fontStringAuraMap = setmetatable({}, { __mode = "k" })
-- Track which FontStrings/frames already have hooks installed (avoid double-hooking)
local hookedFontStrings = setmetatable({}, { __mode = "k" })
local hookedItemFrames = setmetatable({}, { __mode = "k" })
-- Track CDM item frames we've hidden via SetAlpha(0) — itemFrame → auraId
local hiddenItemFrames = setmetatable({}, { __mode = "k" })

-- Forward declarations (defined after Layout/Styling sections)
local FindCDMItemForSpell, BindCDMBorrowTarget, InstallMixinHooks, RescanForCDMBorrow

-- Expose for debug command
CA._cdmBorrow = cdmBorrow

function CA.RegisterAuras(classToken, auras)
    if not classToken or not auras then return end
    CA._classAuras[classToken] = CA._classAuras[classToken] or {}
    for _, aura in ipairs(auras) do
        aura.classToken = classToken
        CA._registry[aura.id] = aura
        table.insert(CA._classAuras[classToken], aura)
    end
end

--- Returns the list of aura definitions for a class token (or empty table).
function CA.GetClassAuras(classToken)
    return CA._classAuras[classToken] or {}
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local _, playerClassToken = UnitClass("player")

local function GetComponentId(aura)
    return "classAura_" .. aura.id
end

local function GetDB(aura)
    local comp = addon.Components and addon.Components[GetComponentId(aura)]
    return comp and comp.db
end

--------------------------------------------------------------------------------
-- Element Creation
--------------------------------------------------------------------------------

local function CreateTextElement(container, elemDef)
    local fs = container:CreateFontString(nil, "OVERLAY")
    local fontFace = addon.ResolveFontFace("FRIZQT__")
    addon.ApplyFontStyle(fs, fontFace, elemDef.baseSize or 24, "OUTLINE")
    if elemDef.justifyH then
        fs:SetJustifyH(elemDef.justifyH)
    end
    fs:Hide()
    return { type = "text", widget = fs, def = elemDef }
end

local function CreateTextureElement(container, elemDef)
    local tex = container:CreateTexture(nil, "ARTWORK")
    if elemDef.path then
        tex:SetTexture(elemDef.path)
    elseif elemDef.customPath then
        tex:SetTexture(elemDef.customPath)
    end
    local size = elemDef.defaultSize or { 32, 32 }
    tex:SetSize(size[1], size[2])
    tex:Hide()
    return { type = "texture", widget = tex, def = elemDef }
end

local elementCreators = {
    text = CreateTextElement,
    texture = CreateTextureElement,
}

--------------------------------------------------------------------------------
-- Layout Engine
--------------------------------------------------------------------------------

-- Anchor mapping for "inside" mode: anchor point → offset direction
local INSIDE_OFFSETS = {
    TOPLEFT     = {  2, -2 },
    TOP         = {  0, -2 },
    TOPRIGHT    = { -2, -2 },
    LEFT        = {  2,  0 },
    CENTER      = {  0,  0 },
    RIGHT       = { -2,  0 },
    BOTTOMLEFT  = {  2,  2 },
    BOTTOM      = {  0,  2 },
    BOTTOMRIGHT = { -2,  2 },
}

local GAP = 2 -- hardcoded gap between icon and text in "outside" mode

local function LayoutElements(aura, state)
    if not state or not state.elements then return end

    local db = GetDB(aura)

    -- Find text and texture elements
    local textElem, texElem
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" then textElem = elem end
        if elem.type == "texture" then texElem = elem end
    end

    -- Compute icon dimensions from settings (avoids secret-value issues from GetWidth/GetHeight)
    local iconW, iconH = 32, 32
    if texElem then
        local mode = db and db.iconMode or "default"
        if mode == "hidden" then
            iconW, iconH = 0, 0
            texElem.widget:Hide()
            texElem = nil  -- layout code skips Show() and text anchors to container
        else
            local baseW = texElem.def.defaultSize and texElem.def.defaultSize[1] or 32
            local baseH = texElem.def.defaultSize and texElem.def.defaultSize[2] or 32
            if mode == "default" then
                local ratio = tonumber(db and db.iconShape) or 0
                if ratio ~= 0 and addon.IconRatio and addon.IconRatio.CalculateDimensions then
                    iconW, iconH = addon.IconRatio.CalculateDimensions(baseW, ratio)
                else
                    iconW, iconH = baseW, baseH
                end
            else
                iconW, iconH = baseW, baseH
            end
        end
    end

    local textPosition = (db and db.textPosition) or "inside"

    if textPosition == "outside" then
        local anchor = (db and db.textOuterAnchor) or "RIGHT"
        local txOff = tonumber(db and db.textOffsetX) or 0
        local tyOff = tonumber(db and db.textOffsetY) or 0

        if texElem then
            texElem.widget:ClearAllPoints()
            texElem.widget:Show()
        end
        if textElem then
            textElem.widget:ClearAllPoints()
            textElem.widget:Show()
        end

        local textW, textH = 0, 0
        if textElem then
            local ok, w = pcall(textElem.widget.GetStringWidth, textElem.widget)
            if ok and type(w) == "number" and not issecretvalue(w) then textW = w end
            local ok2, h = pcall(textElem.widget.GetHeight, textElem.widget)
            if ok2 and type(h) == "number" and not issecretvalue(h) then textH = h end
        end

        if anchor == "RIGHT" then
            if texElem then texElem.widget:SetPoint("LEFT", state.container, "LEFT", 0, 0) end
            if textElem then
                textElem.widget:SetJustifyH("LEFT")
                if texElem then
                    textElem.widget:SetPoint("LEFT", texElem.widget, "RIGHT", GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("LEFT", state.container, "LEFT", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW + GAP + textW, 1), math.max(iconH, 1))

        elseif anchor == "LEFT" then
            if texElem then texElem.widget:SetPoint("RIGHT", state.container, "RIGHT", 0, 0) end
            if textElem then
                textElem.widget:SetJustifyH("RIGHT")
                if texElem then
                    textElem.widget:SetPoint("RIGHT", texElem.widget, "LEFT", -GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("RIGHT", state.container, "RIGHT", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(textW + GAP + iconW, 1), math.max(iconH, 1))

        elseif anchor == "ABOVE" then
            if texElem then texElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", 0, 0) end
            if textElem then
                textElem.widget:SetJustifyH("CENTER")
                if texElem then
                    textElem.widget:SetPoint("BOTTOM", texElem.widget, "TOP", txOff, GAP + tyOff)
                else
                    textElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW, 1), math.max(iconH + GAP + textH, 1))

        elseif anchor == "BELOW" then
            if texElem then texElem.widget:SetPoint("TOP", state.container, "TOP", 0, 0) end
            if textElem then
                textElem.widget:SetJustifyH("CENTER")
                if texElem then
                    textElem.widget:SetPoint("TOP", texElem.widget, "BOTTOM", txOff, -GAP + tyOff)
                else
                    textElem.widget:SetPoint("TOP", state.container, "TOP", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW, 1), math.max(iconH + GAP + textH, 1))
        end

    else -- "inside" mode
        local innerAnchor = (db and db.textInnerAnchor) or "CENTER"

        if texElem then
            texElem.widget:ClearAllPoints()
            texElem.widget:SetAllPoints(state.container)
            texElem.widget:Show()
        end

        if textElem then
            textElem.widget:ClearAllPoints()
            local offsets = INSIDE_OFFSETS[innerAnchor] or { 0, 0 }
            textElem.widget:SetPoint(innerAnchor, state.container, innerAnchor, offsets[1], offsets[2])
            textElem.widget:SetJustifyH("CENTER")
            textElem.widget:Show()
        end

        state.container:SetSize(math.max(iconW, 1), math.max(iconH, 1))
    end
end

--------------------------------------------------------------------------------
-- Styling
--------------------------------------------------------------------------------

local function ApplyIconMode(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            if mode == "hidden" then
                elem.widget:Hide()
            elseif mode == "custom" and elem.def.customPath then
                elem.widget:SetTexture(elem.def.customPath)
                elem.widget:Show()
            else
                -- "default": use the spell icon, fallback to customPath
                local ok, tex = pcall(function()
                    return C_Spell.GetSpellTexture(aura.auraSpellId)
                end)
                if ok and tex then
                    elem.widget:SetTexture(tex)
                elseif elem.def.customPath then
                    elem.widget:SetTexture(elem.def.customPath)
                end
                elem.widget:Show()
            end
        end
    end
end

local function ApplyTextStyling(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "text" then
            local fontKey = db.textFont or "FRIZQT__"
            local fontFace = addon.ResolveFontFace(fontKey)
            local fontStyle = db.textStyle or "OUTLINE"
            local size = db.textSize or elem.def.baseSize or 24
            addon.ApplyFontStyle(elem.widget, fontFace, size, fontStyle)

            local color = db.textColor
            if color and type(color) == "table" then
                elem.widget:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
            end
        end
    end
end

local function ApplyIconShape(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            local baseW = elem.def.defaultSize and elem.def.defaultSize[1] or 32
            local baseH = elem.def.defaultSize and elem.def.defaultSize[2] or 32
            if mode == "default" then
                local ratio = tonumber(db.iconShape) or 0
                if ratio ~= 0 and addon.IconRatio and addon.IconRatio.CalculateDimensions then
                    local w, h = addon.IconRatio.CalculateDimensions(baseW, ratio)
                    elem.widget:SetSize(w, h)
                else
                    elem.widget:SetSize(baseW, baseH)
                end
            else
                elem.widget:SetSize(baseW, baseH)
            end
        end
    end
end

local function ApplyBorders(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            local style = db.borderStyle or "none"

            -- Ensure border frame exists (parented to container, anchored to texture)
            if not elem.borderFrame then
                elem.borderFrame = CreateFrame("Frame", nil, state.container)
                elem.borderFrame:SetFrameLevel(state.container:GetFrameLevel() + 2)
                elem.borderFrame.borderEdges = {
                    Top = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Bottom = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Left = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Right = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                }
                for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                elem.borderFrame.atlasBorder = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 2)
                elem.borderFrame.atlasBorder:Hide()
            end

            -- Anchor border frame to texture widget
            elem.borderFrame:ClearAllPoints()
            elem.borderFrame:SetAllPoints(elem.widget)

            if mode ~= "default" or style == "none" then
                for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                elem.borderFrame.atlasBorder:Hide()
                elem.borderFrame:Hide()
            else
                elem.borderFrame:Show()
                local opts = {
                    style = style,
                    thickness = tonumber(db.borderThickness) or 1,
                    insetH = tonumber(db.borderInsetH) or 0,
                    insetV = tonumber(db.borderInsetV) or 0,
                    color = db.borderTintEnable and db.borderTintColor or {0, 0, 0, 1},
                    tintEnabled = db.borderTintEnable,
                    tintColor = db.borderTintColor,
                }

                local styleDef = nil
                if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
                    styleDef = addon.IconBorders.GetStyle(style)
                end

                if styleDef and styleDef.type == "atlas" and styleDef.atlas then
                    -- Atlas border
                    for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                    local atlasTex = elem.borderFrame.atlasBorder
                    local col = opts.tintEnabled and opts.tintColor or styleDef.defaultColor or {1, 1, 1, 1}
                    atlasTex:SetAtlas(styleDef.atlas, true)
                    atlasTex:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
                    local expandX = (styleDef.expandX or 0) - opts.insetH
                    local expandY = (styleDef.expandY or styleDef.expandX or 0) - opts.insetV
                    atlasTex:ClearAllPoints()
                    atlasTex:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -expandX - (styleDef.adjustLeft or 0), expandY + (styleDef.adjustTop or 0))
                    atlasTex:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", expandX + (styleDef.adjustRight or 0), -expandY - (styleDef.adjustBottom or 0))
                    atlasTex:Show()
                else
                    -- Square border
                    elem.borderFrame.atlasBorder:Hide()
                    local edges = elem.borderFrame.borderEdges
                    local thickness = math.max(1, opts.thickness)
                    local col = opts.color
                    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
                    for _, tex in pairs(edges) do tex:SetColorTexture(r, g, b, a) end

                    edges.Top:ClearAllPoints()
                    edges.Top:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -opts.insetH, opts.insetV)
                    edges.Top:SetPoint("TOPRIGHT", elem.borderFrame, "TOPRIGHT", opts.insetH, opts.insetV)
                    edges.Top:SetHeight(thickness)

                    edges.Bottom:ClearAllPoints()
                    edges.Bottom:SetPoint("BOTTOMLEFT", elem.borderFrame, "BOTTOMLEFT", -opts.insetH, -opts.insetV)
                    edges.Bottom:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", opts.insetH, -opts.insetV)
                    edges.Bottom:SetHeight(thickness)

                    edges.Left:ClearAllPoints()
                    edges.Left:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -opts.insetH, opts.insetV - thickness)
                    edges.Left:SetPoint("BOTTOMLEFT", elem.borderFrame, "BOTTOMLEFT", -opts.insetH, -opts.insetV + thickness)
                    edges.Left:SetWidth(thickness)

                    edges.Right:ClearAllPoints()
                    edges.Right:SetPoint("TOPRIGHT", elem.borderFrame, "TOPRIGHT", opts.insetH, opts.insetV - thickness)
                    edges.Right:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", opts.insetH, -opts.insetV + thickness)
                    edges.Right:SetWidth(thickness)

                    for _, tex in pairs(edges) do tex:Show() end
                end
            end
        end
    end
end

local function ApplyStyling(aura)
    local state = CA._activeAuras[aura.id]
    if not state then return end

    local db = GetDB(aura)
    if not db then return end

    -- Enabled check
    if not db.enabled then
        state.container:Hide()
        return
    end

    -- Scale
    local scale = (db.scale or 100) / 100
    state.container:SetScale(math.max(scale, 0.25))

    -- Icon mode
    ApplyIconMode(aura, state)

    -- Icon shape (adjusts dimensions based on ratio slider)
    ApplyIconShape(aura, state)

    -- Borders
    ApplyBorders(aura, state)

    -- Text styling
    ApplyTextStyling(aura, state)

    -- Re-layout elements
    LayoutElements(aura, state)

    -- Trigger a rescan to show/hide based on current aura state
    CA.ScanAura(aura)
end

--------------------------------------------------------------------------------
-- Aura Scanning (stub — visibility driven by CDM borrow hooks)
--------------------------------------------------------------------------------

function CA.ScanAura(aura)
    local state = CA._activeAuras[aura.id]
    if not state then return end

    local db = GetDB(aura)
    if not db or not db.enabled then
        state.container:Hide()
        return
    end

    if not UnitExists(aura.unit) then
        if not editModeActive then
            state.container:Hide()
        end
        return
    end

    -- For cdmBorrow auras, visibility is driven by CDM borrow hooks
    -- (BindCDMBorrowTarget installs Show/Hide hooks on CDM icons).
    -- For non-cdmBorrow auras (future), direct scanning would go here.
end

local function ScanAllAurasForUnit(unit)
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end
    for _, aura in ipairs(auras) do
        if aura.unit == unit and CA._activeAuras[aura.id] then
            CA.ScanAura(aura)
        end
    end
end

local function ScanAllAuras()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end
    for _, aura in ipairs(auras) do
        if CA._activeAuras[aura.id] then
            CA.ScanAura(aura)
        end
    end
end

--------------------------------------------------------------------------------
-- CDM Borrow: Hook Blizzard's CDM Tracked Buffs icons
--------------------------------------------------------------------------------
-- Prerequisite: User must add the tracked spell to CDM > Tracked Buffs.
-- We find the CDM icon for our spell, hook its FontString to forward text
-- (including secret values) to our Class Aura overlay.

FindCDMItemForSpell = function(spellId)
    local viewer = _G.BuffIconCooldownViewer
    if not viewer then return nil end
    local ok, children = pcall(function() return { viewer:GetChildren() } end)
    if not ok or not children then return nil end
    for _, child in ipairs(children) do
        -- GetBaseSpellID() is a plain Lua table read (self.cooldownInfo.spellID),
        -- populated by Blizzard's untainted code — returns real data even in combat.
        local idOk, childSpellId = pcall(function() return child:GetBaseSpellID() end)
        if idOk and childSpellId == spellId then
            return child
        end
    end
    return nil
end

BindCDMBorrowTarget = function(itemFrame, aura)
    -- Get the Applications FontString from the CDM icon
    local ok, fs = pcall(function() return itemFrame:GetApplicationsFontString() end)
    if not ok or not fs then return end

    -- Update weak mapping: this FontString forwards to this aura
    fontStringAuraMap[fs] = aura.id

    -- Hook SetText on this FontString (once per FS, never double-hook)
    if not hookedFontStrings[fs] then
        hookedFontStrings[fs] = true
        hooksecurefunc(fs, "SetText", function(self, text)
            local auraId = fontStringAuraMap[self]
            if not auraId then return end
            local state = CA._activeAuras[auraId]
            if not state then return end
            -- Blizzard sends "" for 1-stack; show "1" so the isolated aura always has a number
            local displayText = text
            if not issecretvalue(displayText) and (not displayText or displayText == "") then
                displayText = "1"
            end
            for _, elem in ipairs(state.elements) do
                if elem.type == "text" and elem.def.source == "applications" then
                    pcall(elem.widget.SetText, elem.widget, displayText)
                end
            end
        end)
    end

    -- Hook Hide/Show on the CDM item frame (once per frame, via weak table)
    if not hookedItemFrames[itemFrame] then
        hookedItemFrames[itemFrame] = true

        hooksecurefunc(itemFrame, "Hide", function(self)
            local fsOk, iFs = pcall(function() return self:GetApplicationsFontString() end)
            if not fsOk or not iFs then return end
            local auraId = fontStringAuraMap[iFs]
            if not auraId then return end
            local state = CA._activeAuras[auraId]
            if state and not editModeActive then
                state.container:Hide()
            end
        end)

        hooksecurefunc(itemFrame, "Show", function(self)
            local fsOk, iFs = pcall(function() return self:GetApplicationsFontString() end)
            if not fsOk or not iFs then return end
            local auraId = fontStringAuraMap[iFs]
            if not auraId then return end
            local auraDef = CA._registry[auraId]
            local state = CA._activeAuras[auraId]
            if state and auraDef then
                LayoutElements(auraDef, state)
                state.container:Show()
            end
            if hiddenItemFrames[self] then
                self:SetAlpha(0)
            end
        end)

        -- Hook SetShown: Blizzard's CDM uses SetShown(bool) which does NOT invoke
        -- the Lua Show/Hide hooks. This directly matches what Blizzard calls.
        hooksecurefunc(itemFrame, "SetShown", function(self, shown)
            local fsOk, iFs = pcall(function() return self:GetApplicationsFontString() end)
            if not fsOk or not iFs then return end
            local auraId = fontStringAuraMap[iFs]
            if not auraId then return end
            local state = CA._activeAuras[auraId]
            if not state then return end
            if shown then
                local auraDef = CA._registry[auraId]
                if auraDef then
                    LayoutElements(auraDef, state)
                    state.container:Show()
                end
                if hiddenItemFrames[self] then
                    self:SetAlpha(0)
                end
            elseif not editModeActive then
                state.container:Hide()
            end
        end)
    end

    -- Sync initial text state from current CDM icon
    local textOk, text = pcall(function() return fs:GetText() end)
    if textOk then
        local displayText = text
        if not issecretvalue(displayText) and (not displayText or displayText == "") then
            displayText = "1"
        end
        local state = CA._activeAuras[aura.id]
        if state then
            for _, elem in ipairs(state.elements) do
                if elem.type == "text" and elem.def.source == "applications" then
                    pcall(elem.widget.SetText, elem.widget, displayText)
                end
            end
        end
    end

    -- Hide CDM icon via alpha if hideFromCDM is enabled
    local db = GetDB(aura)
    if db and db.enabled and (db.hideFromCDM ~= false) then
        itemFrame:SetAlpha(0)
        hiddenItemFrames[itemFrame] = aura.id
    elseif hiddenItemFrames[itemFrame] then
        itemFrame:SetAlpha(1)
        hiddenItemFrames[itemFrame] = nil
    end
end

InstallMixinHooks = function()
    if cdmBorrow.hookInstalled then return end

    -- Hook RefreshData to catch icon pool recycling (spell changes on a CDM slot)
    local buffMixin = _G.CooldownViewerBuffIconItemMixin
    if buffMixin and buffMixin.RefreshData then
        hooksecurefunc(buffMixin, "RefreshData", function()
            -- Defer to avoid re-entrancy during Blizzard's refresh cycle
            C_Timer.After(0, function() RescanForCDMBorrow() end)
        end)
    end

    -- Hook OnAuraInstanceInfoCleared if it exists (aura-gone signal)
    local baseMixin = _G.CooldownViewerItemMixin
    if baseMixin and baseMixin.OnAuraInstanceInfoCleared then
        hooksecurefunc(baseMixin, "OnAuraInstanceInfoCleared", function()
            C_Timer.After(0, function() RescanForCDMBorrow() end)
        end)
    end

    cdmBorrow.hookInstalled = true
end

local function RestoreHiddenCDMFrames(auraId)
    for frame, id in pairs(hiddenItemFrames) do
        if id == auraId then
            frame:SetAlpha(1)
            hiddenItemFrames[frame] = nil
        end
    end
end

RescanForCDMBorrow = function()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        if aura.cdmBorrow then
            local state = CA._activeAuras[aura.id]
            if state then
                local db = GetDB(aura)
                if not db or not db.enabled then
                    state.container:Hide()
                    RestoreHiddenCDMFrames(aura.id)
                elseif not UnitExists(aura.unit) then
                    if not editModeActive then state.container:Hide() end
                else
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    local itemFrame = FindCDMItemForSpell(cdmId)
                    if itemFrame then
                        BindCDMBorrowTarget(itemFrame, aura)
                        local showOk, isShown = pcall(itemFrame.IsShown, itemFrame)
                        if showOk and isShown then
                            LayoutElements(aura, state)
                            state.container:Show()
                        elseif not editModeActive then
                            state.container:Hide()
                        end
                    elseif not editModeActive then
                        state.container:Hide()
                        RestoreHiddenCDMFrames(aura.id)
                    end
                end
            end
        end
    end
end

-- Expose for debug
CA._rescanForCDMBorrow = function() RescanForCDMBorrow() end

--------------------------------------------------------------------------------
-- Frame Creation
--------------------------------------------------------------------------------

local containersInitialized = false

local function CreateAuraContainer(aura)
    local frameName = "ScooterModClassAura_" .. aura.id
    local container = CreateFrame("Frame", frameName, UIParent)
    container:SetSize(64, 32) -- initial size, auto-resized by layout
    container:SetMovable(true)
    container:SetClampedToScreen(true)

    -- Default position
    local dp = aura.defaultPosition or { point = "CENTER", x = 0, y = -200 }
    container:SetPoint(dp.point, dp.x or 0, dp.y or 0)
    container:Hide()

    -- Create elements from definition
    local elements = {}
    for _, elemDef in ipairs(aura.elements or {}) do
        local creator = elementCreators[elemDef.type]
        if creator then
            table.insert(elements, creator(container, elemDef))
        end
    end

    CA._activeAuras[aura.id] = {
        container = container,
        elements = elements,
    }

    return container
end

local function InitializeContainers()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        if not CA._activeAuras[aura.id] then
            CreateAuraContainer(aura)
        end
    end
end

--------------------------------------------------------------------------------
-- LibEditMode Integration
--------------------------------------------------------------------------------

local function SaveAuraPosition(auraId, layoutName, point, x, y)
    if not addon.db or not addon.db.profile then return end
    addon.db.profile.classAuraPositions = addon.db.profile.classAuraPositions or {}
    addon.db.profile.classAuraPositions[auraId] = addon.db.profile.classAuraPositions[auraId] or {}
    addon.db.profile.classAuraPositions[auraId][layoutName] = {
        point = point,
        x = x,
        y = y,
    }
end

local function RestoreAuraPosition(auraId, layoutName)
    local state = CA._activeAuras[auraId]
    if not state or not state.container then return end

    local positions = addon.db and addon.db.profile and addon.db.profile.classAuraPositions
    local auraPositions = positions and positions[auraId]
    local pos = auraPositions and auraPositions[layoutName]

    if pos and pos.point then
        state.container:ClearAllPoints()
        state.container:SetPoint(pos.point, pos.x or 0, pos.y or 0)
    end
end

local function InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        local state = CA._activeAuras[aura.id]
        if state and state.container then
            state.container.editModeName = aura.editModeName or aura.label

            local auraId = aura.id
            local dp = aura.defaultPosition or { point = "CENTER", x = 0, y = -200 }

            lib:AddFrame(state.container, function(frame, layoutName, point, x, y)
                if point and x and y then
                    frame:ClearAllPoints()
                    frame:SetPoint(point, x, y)
                end
                if layoutName then
                    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
                    if savedPoint then
                        SaveAuraPosition(auraId, layoutName, savedPoint, savedX, savedY)
                    else
                        SaveAuraPosition(auraId, layoutName, point, x, y)
                    end
                end
            end, {
                point = dp.point,
                x = dp.x or 0,
                y = dp.y or 0,
            }, nil)
        end
    end

    lib:RegisterCallback("layout", function(layoutName, layoutIndex)
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            RestoreAuraPosition(aura.id, layoutName)
        end
    end)

    lib:RegisterCallback("enter", function()
        editModeActive = true
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            local st = CA._activeAuras[aura.id]
            if st and st.container then
                local db = GetDB(aura)
                if db and db.enabled then
                    ApplyIconMode(aura, st)
                    ApplyTextStyling(aura, st)
                    LayoutElements(aura, st)
                    st.container:Show()
                    -- Set preview text for applications text elements
                    for _, elem in ipairs(st.elements) do
                        if elem.type == "text" and elem.def.source == "applications" then
                            pcall(elem.widget.SetText, elem.widget, "#")
                            pcall(elem.widget.Show, elem.widget)
                        end
                    end
                end
            end
        end
    end)

    lib:RegisterCallback("exit", function()
        editModeActive = false
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            -- Clear preview text before rescan
            local st = CA._activeAuras[aura.id]
            if st then
                for _, elem in ipairs(st.elements) do
                    if elem.type == "text" and elem.def.source == "applications" then
                        pcall(elem.widget.SetText, elem.widget, "")
                    end
                end
            end
            if CA._activeAuras[aura.id] then
                CA.ScanAura(aura)
            end
        end
        RescanForCDMBorrow()
    end)
end

--------------------------------------------------------------------------------
-- Rebuild
--------------------------------------------------------------------------------

local function RebuildAll()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        ApplyStyling(aura)
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local rebuildPending = false

local caEventFrame = CreateFrame("Frame")
caEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
caEventFrame:RegisterEvent("UNIT_AURA")
caEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
caEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
caEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

caEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not containersInitialized then
            InitializeContainers()
            containersInitialized = true

            C_Timer.After(0.5, function()
                RebuildAll()
                InitializeEditMode()
            end)

            -- CDM Borrow: install mixin hooks and do initial scan after CDM loads
            C_Timer.After(1.0, function()
                InstallMixinHooks()
                RescanForCDMBorrow()
            end)
        else
            RebuildAll()
            C_Timer.After(0.5, function() RescanForCDMBorrow() end)
        end

    elseif event == "UNIT_AURA" then
        -- CDM refreshes its icons on UNIT_AURA; our RefreshData mixin hook
        -- catches that. This rescan is a safety net.
        -- Filter to "target" only — Class Auras only tracks target unit,
        -- and unfiltered UNIT_AURA fires dozens of times per second in raids.
        local unit = ...
        if unit == "target" then
            RescanForCDMBorrow()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target change causes CDM to show/hide different debuffs.
        -- Staggered rescans: PLAYER_TARGET_CHANGED fires before CDM processes
        -- UNIT_TARGET, so the immediate scan may see stale CDM state.
        -- The SetShown hook (above) should handle most cases instantly, but
        -- these deferred rescans are a cheap safety net.
        RescanForCDMBorrow()
        C_Timer.After(0, function() RescanForCDMBorrow() end)
        C_Timer.After(0.1, function() RescanForCDMBorrow() end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: rescan in case CDM state changed while restricted
        RescanForCDMBorrow()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if not rebuildPending then
            rebuildPending = true
            C_Timer.After(0.2, function()
                rebuildPending = false
                RebuildAll()
            end)
        end
    end
end)

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        local auraCopy = aura -- upvalue for closure
        local comp = Component:New({
            id = GetComponentId(aura),
            name = "Class Aura: " .. aura.label,
            settings = aura.settings,
            ApplyStyling = function(component)
                ApplyStyling(auraCopy)
            end,
        })
        self:RegisterComponent(comp)
    end
end)
