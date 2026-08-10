-- classauras/layout.lua - Element positioning, inside/outside text anchoring
local addonName, addon = ...

local CA = addon.ClassAuras

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

    local db = CA._GetDB(aura)

    -- Find text, texture, and bar elements
    local textElem, texElem, barElem, nameElem
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" then
            if elem.def.source == "name" then
                nameElem = elem
            else
                textElem = elem
            end
        end
        if elem.type == "texture" then texElem = elem end
        if elem.type == "bar" then barElem = elem end
    end

    -- Mode-based visibility
    local displayMode = (db and db.mode) or "icon"
    local showIcon = (displayMode == "icon" or displayMode == "iconbar")
    local showBar  = (displayMode == "bar" or displayMode == "iconbar")
    local showText = not (db and db.hideText)

    -- Backward compat: treat iconMode "hidden" as mode override
    if db and db.iconMode == "hidden" then
        showIcon = false
    end

    -- Compute icon dimensions from settings (avoids secret-value issues from GetWidth/GetHeight)
    local iconW, iconH = 32, 32
    if texElem then
        if not showIcon then
            iconW, iconH = 0, 0
            texElem.widget:Hide()
        else
            local mode = db and db.iconMode or "default"
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

    -- Bar dimensions from settings
    local barW = tonumber(db and db.barWidth) or 120
    local barH = tonumber(db and db.barHeight) or 12

    -- Size and show/hide bar element
    if barElem then
        if showBar then
            barElem.widget:SetSize(barW, barH)
        else
            barElem.widget:Hide()
        end
    end

    -- Hide text if mode is text-only and there's no icon anchor — text still shows
    if not showText and textElem then
        textElem.widget:Hide()
    end

    local textPosition = (db and db.textPosition) or "inside"

    if textPosition == "outside" then
        local anchor = (db and db.textOuterAnchor) or "RIGHT"
        local txOff = tonumber(db and db.textOffsetX) or 0
        local tyOff = tonumber(db and db.textOffsetY) or 0

        if texElem and showIcon then
            texElem.widget:ClearAllPoints()
            texElem.widget:Show()
        end
        if textElem and showText then
            textElem.widget:ClearAllPoints()
            textElem.widget:Show()
        end

        local textW, textH = 0, 0
        if textElem and showText then
            local ok, w = pcall(textElem.widget.GetStringWidth, textElem.widget)
            if ok and type(w) == "number" and not issecretvalue(w) then textW = w end
            local ok2, h = pcall(textElem.widget.GetHeight, textElem.widget)
            if ok2 and type(h) == "number" and not issecretvalue(h) then textH = h end
        end

        if anchor == "RIGHT" then
            if texElem and showIcon then texElem.widget:SetPoint("LEFT", state.container, "LEFT", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("LEFT")
                if texElem and showIcon then
                    textElem.widget:SetPoint("LEFT", texElem.widget, "RIGHT", GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("LEFT", state.container, "LEFT", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW + GAP + textW, 1), math.max(iconH, 1))

        elseif anchor == "LEFT" then
            if texElem and showIcon then texElem.widget:SetPoint("RIGHT", state.container, "RIGHT", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("RIGHT")
                if texElem and showIcon then
                    textElem.widget:SetPoint("RIGHT", texElem.widget, "LEFT", -GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("RIGHT", state.container, "RIGHT", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(textW + GAP + iconW, 1), math.max(iconH, 1))

        elseif anchor == "ABOVE" then
            if texElem and showIcon then texElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("CENTER")
                if texElem and showIcon then
                    textElem.widget:SetPoint("BOTTOM", texElem.widget, "TOP", txOff, GAP + tyOff)
                else
                    textElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW, 1), math.max(iconH + GAP + textH, 1))

        elseif anchor == "BELOW" then
            if texElem and showIcon then texElem.widget:SetPoint("TOP", state.container, "TOP", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("CENTER")
                if texElem and showIcon then
                    textElem.widget:SetPoint("TOP", texElem.widget, "BOTTOM", txOff, -GAP + tyOff)
                else
                    textElem.widget:SetPoint("TOP", state.container, "TOP", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW, 1), math.max(iconH + GAP + textH, 1))
        end

    else -- "inside" mode
        local innerAnchor = (db and db.textInnerAnchor) or "CENTER"

        if texElem and showIcon then
            texElem.widget:ClearAllPoints()
            texElem.widget:SetAllPoints(state.container)
            texElem.widget:Show()
        end

        if textElem and showText then
            textElem.widget:ClearAllPoints()
            local offsets = INSIDE_OFFSETS[innerAnchor] or { 0, 0 }
            local txOff = tonumber(db and db.textOffsetX) or 0
            local tyOff = tonumber(db and db.textOffsetY) or 0
            textElem.widget:SetPoint(innerAnchor, state.container, innerAnchor, offsets[1] + txOff, offsets[2] + tyOff)
            textElem.widget:SetJustifyH("CENTER")
            textElem.widget:Show()
        end

        state.container:SetSize(math.max(iconW, 1), math.max(iconH, 1))
    end

    -- Position bar relative to icon/container
    if barElem and showBar then
        barElem.widget:ClearAllPoints()
        local barPos = (db and db.barPosition) or "LEFT"
        local bxOff = tonumber(db and db.barOffsetX) or 0
        local byOff = tonumber(db and db.barOffsetY) or 0

        if showIcon and iconW > 0 then
            -- Anchor bar relative to icon
            if barPos == "LEFT" then
                barElem.widget:SetPoint("RIGHT", state.container, "LEFT", -GAP + bxOff, byOff)
            else -- "RIGHT"
                barElem.widget:SetPoint("LEFT", state.container, "RIGHT", GAP + bxOff, byOff)
            end
        else
            -- No icon visible: bar at container center
            barElem.widget:SetPoint("CENTER", state.container, "CENTER", bxOff, byOff)
            -- Resize container to fit bar when bar is the primary element
            if displayMode == "bar" then
                state.container:SetSize(math.max(barW, 1), math.max(barH, 1))
            elseif displayMode == "text" then
                -- text mode: container stays icon-sized for text anchor
            end
        end

        barElem.widget:Show()
    end

    -- Aura name text, anchored to the bar (correct in both bar and iconbar modes)
    if nameElem then
        local showName = showBar and barElem and not (db and db.hideNameText)
        if not showName then
            nameElem.widget:Hide()
        else
            nameElem.widget:ClearAllPoints()
            local namePos = (db and db.nameTextPosition) or "inside"
            local nxOff = tonumber(db and db.nameTextOffsetX) or 0
            local nyOff = tonumber(db and db.nameTextOffsetY) or 0
            local anchorW = barElem.widget

            if namePos == "outside" then
                local anchor = (db and db.nameTextOuterAnchor) or "ABOVE"
                if anchor == "RIGHT" then
                    nameElem.widget:SetJustifyH("LEFT")
                    nameElem.widget:SetPoint("LEFT", anchorW, "RIGHT", GAP + nxOff, nyOff)
                elseif anchor == "LEFT" then
                    nameElem.widget:SetJustifyH("RIGHT")
                    nameElem.widget:SetPoint("RIGHT", anchorW, "LEFT", -GAP + nxOff, nyOff)
                elseif anchor == "ABOVE" then
                    nameElem.widget:SetJustifyH("CENTER")
                    nameElem.widget:SetPoint("BOTTOM", anchorW, "TOP", nxOff, GAP + nyOff)
                else -- "BELOW"
                    nameElem.widget:SetJustifyH("CENTER")
                    nameElem.widget:SetPoint("TOP", anchorW, "BOTTOM", nxOff, -GAP + nyOff)
                end
            else -- "inside"
                local anchor = (db and db.nameTextInnerAnchor) or "LEFT"
                local offsets = INSIDE_OFFSETS[anchor] or { 0, 0 }
                nameElem.widget:SetPoint(anchor, anchorW, anchor, offsets[1] + nxOff, offsets[2] + nyOff)
            end
            nameElem.widget:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Namespace Promotion
--------------------------------------------------------------------------------

CA._LayoutElements = LayoutElements
