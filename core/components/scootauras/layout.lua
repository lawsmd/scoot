-- scootauras/layout.lua - Element positioning inside the visual frame
--
-- Ported from the class-aura layout engine, generalized over the tracker's
-- shape. All dimensions come from settings, never from widget reads (aura
-- widgets can carry secret geometry); the host size flows through the engine's
-- SetHostSize so the Edit Mode drag unit (the shell) matches the visual.
local addonName, addon = ...

local SAU = addon.ScootAuras

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

local GAP = 2

-- Flush-corner outside anchors: the text's opposing point pins to the host's
-- same-named point, one GAP outward. { textPoint, offsetX, offsetY }
local OUTSIDE_ANCHORS = {
    TOPLEFT     = { "BOTTOMLEFT",     0,  GAP },
    TOP         = { "BOTTOM",         0,  GAP },
    TOPRIGHT    = { "BOTTOMRIGHT",    0,  GAP },
    LEFT        = { "RIGHT",       -GAP,    0 },
    RIGHT       = { "LEFT",         GAP,    0 },
    BOTTOMLEFT  = { "TOPLEFT",        0, -GAP },
    BOTTOM      = { "TOP",            0, -GAP },
    BOTTOMRIGHT = { "TOPRIGHT",       0, -GAP },
}

--- Shape-driven element visibility, shared with the binding layer.
function SAU.ResolveVisibility(tracker, db)
    local shape = tracker.shape or "icon"
    local showIcon
    if shape == "bar" then
        showIcon = db and db.barShowIcon or false
    else
        -- "icon" shows the spell icon; "shape" shows the atlas art in the same
        -- texture element.
        showIcon = not (db and db.iconMode == "hidden")
    end
    return {
        shape = shape,
        showIcon = showIcon,
        showBar = (shape == "bar"),
        showText = not (db and db.hideText),
        showStacks = not (db and db.hideStackText),
        showName = (shape == "bar") and not (db and db.hideNameText),
    }
end

local function LayoutElements(trackerId, tracker, state)
    if not state or not state.elements then return end

    local db = SAU.GetDB(trackerId)
    local vis = SAU.ResolveVisibility(tracker, db)

    local textElem, texElem, barElem, nameElem, stacksElem
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" then
            local source = elem.def.source
            if source == "name" then
                nameElem = elem
            elseif source == "applications" then
                stacksElem = elem
            else
                textElem = elem
            end
        end
        if elem.type == "texture" then texElem = elem end
        if elem.type == "bar" then barElem = elem end
    end

    local function SetHostSize(w, h)
        SAU.Engine.SetHostSize(state, math.max(w, 1), math.max(h, 1))
    end

    -- Icon dimensions from settings only.
    local iconW, iconH = 32, 32
    if texElem then
        if not vis.showIcon then
            iconW, iconH = 0, 0
            texElem.widget:Hide()
        else
            local base = tonumber(db and db.iconSize) or 32
            if vis.shape == "icon" then
                local ratio = tonumber(db and db.iconShape) or 0
                if ratio ~= 0 and addon.IconRatio and addon.IconRatio.CalculateDimensions then
                    iconW, iconH = addon.IconRatio.CalculateDimensions(base, ratio)
                else
                    iconW, iconH = base, base
                end
            else
                -- Shape art and the bar's side icon stay square.
                iconW, iconH = base, base
            end
        end
    end

    local barW = tonumber(db and db.barWidth) or 120
    local barH = tonumber(db and db.barHeight) or 12

    if barElem then
        if vis.showBar then
            barElem.widget:SetSize(barW, barH)
        else
            barElem.widget:Hide()
        end
    end

    if not vis.showText and textElem then
        textElem.widget:Hide()
    end

    local textPosition = (db and db.textPosition) or "inside"

    if vis.shape == "bar" then
        -- Bar shape: the bar is the anchor and the icon is an optional
        -- addition beside it. Both sit INSIDE the host, so the shell (the
        -- Edit Mode drag box) wraps the whole tracker. Duration text rides
        -- the bar and is positioned after the bar block below.
        local iconSide = (db and db.barIconSide) or "LEFT"
        local iconGap = tonumber(db and db.barIconGap) or 2

        -- The cadence lock bar (state.lockBar, outside the button tree) mirrors
        -- the bar region's host-relative rect so its fill texture can serve
        -- as the clip anchor. Absent on the Edit Mode preview shim.
        local function PlaceLockBar(point)
            local lockBar = state.lockBar
            if not lockBar then return end
            lockBar:ClearAllPoints()
            lockBar:SetSize(barW, barH)
            lockBar:SetPoint(point, state.container, point, 0, 0)
        end

        if barElem and vis.showBar then
            barElem.widget:ClearAllPoints()
        end
        if texElem and vis.showIcon and iconW > 0 then
            texElem.widget:ClearAllPoints()
            texElem.widget:SetSize(iconW, iconH)
            texElem.widget:Show()
            if barElem and vis.showBar then
                if iconSide == "RIGHT" then
                    barElem.widget:SetPoint("LEFT", state.container, "LEFT", 0, 0)
                    texElem.widget:SetPoint("LEFT", barElem.widget, "RIGHT", iconGap, 0)
                    PlaceLockBar("LEFT")
                else
                    barElem.widget:SetPoint("RIGHT", state.container, "RIGHT", 0, 0)
                    texElem.widget:SetPoint("RIGHT", barElem.widget, "LEFT", -iconGap, 0)
                    PlaceLockBar("RIGHT")
                end
            else
                texElem.widget:SetPoint("CENTER", state.container, "CENTER", 0, 0)
            end
            SetHostSize(iconW + iconGap + barW, math.max(iconH, barH))
        else
            if barElem and vis.showBar then
                barElem.widget:SetPoint("CENTER", state.container, "CENTER", 0, 0)
                PlaceLockBar("CENTER")
            end
            SetHostSize(barW, barH)
        end
        if barElem and vis.showBar then
            barElem.widget:Show()
        end

    elseif textPosition == "outside" then
        local anchor = (db and db.textOuterAnchor) or "RIGHT"
        local txOff = tonumber(db and db.textOffsetX) or 0
        local tyOff = tonumber(db and db.textOffsetY) or 0

        if texElem and vis.showIcon then
            texElem.widget:ClearAllPoints()
            texElem.widget:SetSize(iconW, iconH)
            texElem.widget:Show()
        end
        if textElem and vis.showText then
            textElem.widget:ClearAllPoints()
            textElem.widget:Show()
        end

        local textW, textH = 0, 0
        if textElem and vis.showText then
            local ok, w = pcall(textElem.widget.GetStringWidth, textElem.widget)
            if ok and type(w) == "number" and not issecretvalue(w) then textW = w end
            local ok2, h = pcall(textElem.widget.GetHeight, textElem.widget)
            if ok2 and type(h) == "number" and not issecretvalue(h) then textH = h end
        end

        if anchor == "RIGHT" then
            if texElem and vis.showIcon then texElem.widget:SetPoint("LEFT", state.container, "LEFT", 0, 0) end
            if textElem and vis.showText then
                textElem.widget:SetJustifyH("LEFT")
                if texElem and vis.showIcon then
                    textElem.widget:SetPoint("LEFT", texElem.widget, "RIGHT", GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("LEFT", state.container, "LEFT", txOff, tyOff)
                end
            end
            SetHostSize(iconW + GAP + textW, iconH)

        elseif anchor == "LEFT" then
            if texElem and vis.showIcon then texElem.widget:SetPoint("RIGHT", state.container, "RIGHT", 0, 0) end
            if textElem and vis.showText then
                textElem.widget:SetJustifyH("RIGHT")
                if texElem and vis.showIcon then
                    textElem.widget:SetPoint("RIGHT", texElem.widget, "LEFT", -GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("RIGHT", state.container, "RIGHT", txOff, tyOff)
                end
            end
            SetHostSize(textW + GAP + iconW, iconH)

        elseif anchor == "ABOVE" then
            if texElem and vis.showIcon then texElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", 0, 0) end
            if textElem and vis.showText then
                textElem.widget:SetJustifyH("CENTER")
                if texElem and vis.showIcon then
                    textElem.widget:SetPoint("BOTTOM", texElem.widget, "TOP", txOff, GAP + tyOff)
                else
                    textElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", txOff, tyOff)
                end
            end
            SetHostSize(iconW, iconH + GAP + textH)

        else -- "BELOW"
            if texElem and vis.showIcon then texElem.widget:SetPoint("TOP", state.container, "TOP", 0, 0) end
            if textElem and vis.showText then
                textElem.widget:SetJustifyH("CENTER")
                if texElem and vis.showIcon then
                    textElem.widget:SetPoint("TOP", texElem.widget, "BOTTOM", txOff, -GAP + tyOff)
                else
                    textElem.widget:SetPoint("TOP", state.container, "TOP", txOff, tyOff)
                end
            end
            SetHostSize(iconW, iconH + GAP + textH)
        end

    else -- "inside"
        local innerAnchor = (db and db.textInnerAnchor) or "CENTER"

        if texElem and vis.showIcon then
            texElem.widget:ClearAllPoints()
            texElem.widget:SetAllPoints(state.container)
            texElem.widget:Show()
        end

        if textElem and vis.showText then
            textElem.widget:ClearAllPoints()
            local offsets = INSIDE_OFFSETS[innerAnchor] or { 0, 0 }
            local txOff = tonumber(db and db.textOffsetX) or 0
            local tyOff = tonumber(db and db.textOffsetY) or 0
            textElem.widget:SetPoint(innerAnchor, state.container, innerAnchor, offsets[1] + txOff, offsets[2] + tyOff)
            textElem.widget:SetJustifyH("CENTER")
            textElem.widget:Show()
        end

        SetHostSize(iconW, iconH)
    end

    -- Bar shape: duration text anchors to the bar, inside or outside.
    if vis.shape == "bar" and textElem and vis.showText and barElem and vis.showBar then
        textElem.widget:ClearAllPoints()
        local txOff = tonumber(db and db.textOffsetX) or 0
        local tyOff = tonumber(db and db.textOffsetY) or 0
        if textPosition == "outside" then
            local anchor = (db and db.textOuterAnchor) or "RIGHT"
            if anchor == "RIGHT" then
                textElem.widget:SetJustifyH("LEFT")
                textElem.widget:SetPoint("LEFT", barElem.widget, "RIGHT", GAP + txOff, tyOff)
            elseif anchor == "LEFT" then
                textElem.widget:SetJustifyH("RIGHT")
                textElem.widget:SetPoint("RIGHT", barElem.widget, "LEFT", -GAP + txOff, tyOff)
            elseif anchor == "ABOVE" then
                textElem.widget:SetJustifyH("CENTER")
                textElem.widget:SetPoint("BOTTOM", barElem.widget, "TOP", txOff, GAP + tyOff)
            else -- "BELOW"
                textElem.widget:SetJustifyH("CENTER")
                textElem.widget:SetPoint("TOP", barElem.widget, "BOTTOM", txOff, -GAP + tyOff)
            end
        else
            local innerAnchor = (db and db.textInnerAnchor) or "CENTER"
            local offsets = INSIDE_OFFSETS[innerAnchor] or { 0, 0 }
            textElem.widget:SetJustifyH("CENTER")
            textElem.widget:SetPoint(innerAnchor, barElem.widget, innerAnchor, offsets[1] + txOff, offsets[2] + tyOff)
        end
        textElem.widget:Show()
    end

    -- Stack count: inside 9-way or outside flush-corner 8-way. The bar hosts
    -- it for bar shape, the icon/host rect otherwise.
    if stacksElem then
        local w = stacksElem.widget
        w:ClearAllPoints()  -- required: the wire-time corner anchor is otherwise permanent
        local host = (vis.shape == "bar" and barElem and vis.showBar) and barElem.widget or state.container
        local sxOff = tonumber(db and db.stackTextOffsetX) or 0
        local syOff = tonumber(db and db.stackTextOffsetY) or 0
        if ((db and db.stackTextPosition) or "inside") == "outside" then
            local anchor = (db and db.stackTextOuterAnchor) or "TOPRIGHT"
            local m = OUTSIDE_ANCHORS[anchor] or OUTSIDE_ANCHORS.TOPRIGHT
            w:SetPoint(m[1], host, anchor, m[2] + sxOff, m[3] + syOff)
        else
            local anchor = (db and db.stackTextInnerAnchor) or "BOTTOMRIGHT"
            local offsets = INSIDE_OFFSETS[anchor] or { 0, 0 }
            w:SetPoint(anchor, host, anchor, offsets[1] + sxOff, offsets[2] + syOff)
        end
    end

    -- Aura name text, anchored to the bar.
    if nameElem then
        if not (vis.showName and barElem and vis.showBar) then
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

SAU._LayoutElements = LayoutElements
