-- SelectorGear.lua - In-field gear button opening a sub-options fly-out
-- Attaches a small gear to a selector's value area. The gear shows only while
-- the field sits on an option that has sub-options, and clicking it opens a
-- fly-out holding controls that apply to that option's state alone.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local GEAR_ATLAS = "GM-icon-settings"
local GEAR_ATLAS_FALLBACK = "common-icon-undo"

local GEAR_BOX = 18            -- clickable box
local GEAR_GLYPH_SCALE = 1.35  -- the atlas pads its glyph box; grow the art, not the box
local GEAR_TEXT_GAP = 6        -- space between the value text and the glyph
local GEAR_ALPHA_REST = 0.6
local GEAR_ALPHA_HOVER = 1

-- Room kept clear at each end of the field: the dropdown indicator sits in it
local INDICATOR_RESERVE = 18

local PANEL_DEFAULT_WIDTH = 240
local PANEL_DEFAULT_HEIGHT = 150
local PANEL_DEFAULT_DIRECTION = "DOWN"
local PANEL_DEFAULT_GAP = 10
local PANEL_DEFAULT_PADDING = 10

--------------------------------------------------------------------------------
-- Controls.AttachSelectorGear(host, config)
--------------------------------------------------------------------------------
-- host   : a selector row exposing _selector._valueBtn._text (Selector.lua and
--          the controls built from it). Returns nil for anything else.
-- config :
--   pages      : table (required) keyed by option key -> page config. The gear
--                shows for exactly the keys present here. A page:
--                  build     : function(content, panel, key) builds the panel
--                              body once, the first time that page is opened.
--                              May return an array of extra controls to clean up.
--                  tooltip   : string shown on gear hover
--                  width / height / direction / gap : per-page overrides
--   width      : default panel width (240)
--   height     : default panel height (150)
--   direction  : default panel direction ("DOWN")
--   gap        : default trigger-to-panel spacing (10)
--   padding    : panel content inset (10)
--   tooltip    : default gear tooltip
--   textGap    : space between the value text and the glyph (6)
--   size       : gear box size (18)
--   glyphScale : glyph size relative to the box (1.35)
--   sizeScale  : scales the gear with a scaled host control (1)
--------------------------------------------------------------------------------

function Controls.AttachSelectorGear(host, config)
    if not (host and config and type(config.pages) == "table") then
        return nil
    end

    local selector = host._selector
    local valueBtn = selector and selector._valueBtn
    local valueText = valueBtn and valueBtn._text
    if not valueText then
        return nil
    end

    local theme = GetTheme()
    local pages = config.pages

    local S = config.sizeScale or 1
    local function sc(v) return math.floor(v * S + 0.5) end

    local box = sc(config.size or GEAR_BOX)
    local glyph = math.floor(box * (config.glyphScale or GEAR_GLYPH_SCALE) + 0.5)
    local textGap = sc(config.textGap or GEAR_TEXT_GAP)

    -- The glyph overflows its box evenly, so shift the box out by half that
    -- overflow to leave a true textGap between the text and the visible art.
    local anchorX = textGap + math.floor((glyph - box) / 2 + 0.5)
    local trailing = textGap + glyph
    local shift = math.floor(trailing / 2 + 0.5)

    ---------------------------------------------------------------------------
    -- Gear button
    ---------------------------------------------------------------------------

    local ar, ag, ab = theme:GetAccentColor()

    local gear = CreateFrame("Button", nil, valueBtn)
    gear:SetSize(box, box)
    gear:SetPoint("LEFT", valueText, "RIGHT", anchorX, 0)
    gear:SetFrameLevel(valueBtn:GetFrameLevel() + 2)
    gear:EnableMouse(true)
    gear:RegisterForClicks("AnyUp")
    gear:Hide()

    local tex = gear:CreateTexture(nil, "OVERLAY")
    tex:SetSize(glyph, glyph)
    tex:SetPoint("CENTER", 0, 0)
    -- An atlas name that does not resolve leaves the texture blank rather than
    -- erroring, so check rather than trust.
    if not pcall(tex.SetAtlas, tex, GEAR_ATLAS) or not tex:GetAtlas() then
        pcall(tex.SetAtlas, tex, GEAR_ATLAS_FALLBACK)
    end
    tex:SetDesaturated(true)
    tex:SetVertexColor(ar, ag, ab)
    tex:SetAlpha(GEAR_ALPHA_REST)
    gear._tex = tex

    gear._pageFrames = {}
    gear._pageControls = {}
    gear._shownPage = nil

    host._gear = gear

    ---------------------------------------------------------------------------
    -- Value text placement
    ---------------------------------------------------------------------------

    -- Captured rather than assumed, so a host that centers its value text
    -- differently still restores correctly.
    local origPoint, origRel, origRelPoint, origX, origY = valueText:GetPoint(1)
    origPoint = origPoint or "CENTER"
    origRel = origRel or valueBtn
    origRelPoint = origRelPoint or "CENTER"
    origX = origX or 0
    origY = origY or 0

    local pendingMeasure = false

    local function ShiftText()
        valueText:ClearAllPoints()
        valueText:SetPoint(origPoint, origRel, origRelPoint, origX - shift, origY)

        -- Keep the text-plus-gear pair clear of the dropdown indicator. A long
        -- option name is clamped and truncated rather than allowed to collide.
        local fieldWidth = valueBtn:GetWidth() or 0
        if fieldWidth > 0 then
            -- The pair is centered, so the text loses the reserve at both ends
            -- and the gear's trailing width once.
            local room = fieldWidth - trailing - (2 * sc(INDICATOR_RESERVE))
            valueText:SetWidth(0)
            if room > 0 and (valueText:GetStringWidth() or 0) > room then
                valueText:SetWordWrap(false)
                valueText:SetWidth(room)
            end
        elseif not pendingMeasure then
            -- Width is not known until the row has been laid out.
            pendingMeasure = true
            C_Timer.After(0, function()
                pendingMeasure = false
                if gear:IsShown() then ShiftText() end
            end)
        end
    end

    local function RestoreText()
        valueText:ClearAllPoints()
        valueText:SetPoint(origPoint, origRel, origRelPoint, origX, origY)
        valueText:SetWidth(0)
    end

    ---------------------------------------------------------------------------
    -- Fly-out and pages, both built on demand
    ---------------------------------------------------------------------------

    local function PageValue(page, field, default)
        if page[field] ~= nil then return page[field] end
        if config[field] ~= nil then return config[field] end
        return default
    end

    local function EnsurePanel()
        if gear._panel then return gear._panel end
        if not Controls.CreateFlyout then return nil end

        local panel = Controls:CreateFlyout({
            anchor = gear,
            direction = config.direction or PANEL_DEFAULT_DIRECTION,
            width = config.width or PANEL_DEFAULT_WIDTH,
            height = config.height or PANEL_DEFAULT_HEIGHT,
            padding = config.padding or PANEL_DEFAULT_PADDING,
            gap = config.gap or PANEL_DEFAULT_GAP,
        })
        gear._panel = panel
        return panel
    end

    -- Pages are keyed by the page table itself, so one table assigned to
    -- several option keys builds one shared panel body.
    local function EnsurePage(panel, page, key)
        local frame = gear._pageFrames[page]
        if frame then return frame end

        local content = panel:GetContent()
        frame = CreateFrame("Frame", nil, content)
        frame:SetAllPoints(content)
        gear._pageFrames[page] = frame

        local extra = page.build and page.build(frame, panel, key)

        -- Controls built into the page park their own dropdown frames on
        -- UIParent, so collect anything that knows how to clean itself up.
        local cleanables = {}
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.Cleanup then table.insert(cleanables, child) end
        end
        if type(extra) == "table" then
            for _, control in ipairs(extra) do
                if control and control.Cleanup then table.insert(cleanables, control) end
            end
        end
        gear._pageControls[page] = cleanables

        return frame
    end

    ---------------------------------------------------------------------------
    -- Visibility, driven by the host's display hook
    ---------------------------------------------------------------------------

    local function Sync(key)
        if key == nil then key = host._currentKey end
        local page = (key ~= nil) and pages[key] or nil

        if page then
            gear._tooltip = page.tooltip or config.tooltip
            gear:Show()
            ShiftText()
        else
            gear:Hide()
            RestoreText()
        end

        -- An option change while the panel is open leaves it pointing at a page
        -- that no longer describes the field.
        if gear._panel and gear._panel:IsOpen() and gear._shownPage ~= page then
            gear._panel:Close()
        end
    end
    gear._sync = Sync

    local prevHook = host._onDisplayChanged
    host._onDisplayChanged = function(key)
        if prevHook then prevHook(key) end
        Sync(key)
    end

    ---------------------------------------------------------------------------
    -- Interaction
    ---------------------------------------------------------------------------

    gear:SetScript("OnEnter", function(self)
        self._tex:SetAlpha(GEAR_ALPHA_HOVER)

        -- Entering the gear leaves valueBtn and the row, so hold both hover
        -- states rather than letting the field read as unhovered.
        local r, g, b = GetTheme():GetAccentColor()
        if host._hoverBg then host._hoverBg:Show() end
        if valueBtn._bg then valueBtn._bg:SetColorTexture(r, g, b, 0.1) end
        if valueBtn._dropIndicator then valueBtn._dropIndicator:SetTextColor(r, g, b, 1) end

        if self._tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self._tooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)

    gear:SetScript("OnLeave", function(self)
        self._tex:SetAlpha(GEAR_ALPHA_REST)
        GameTooltip:Hide()

        if host._hoverBg and not host:IsMouseOver() then
            host._hoverBg:Hide()
        end
        if not valueBtn:IsMouseOver() then
            if valueBtn._bg then valueBtn._bg:SetColorTexture(0, 0, 0, 0) end
            if valueBtn._dropIndicator then
                local dr, dg, db = GetTheme():GetDimTextColor()
                valueBtn._dropIndicator:SetTextColor(dr, dg, db, 0.7)
            end
        end
    end)

    gear:SetScript("OnClick", function(self)
        if host._isDisabled or host._syncLocked then return end

        local key = host._currentKey
        local page = (key ~= nil) and pages[key] or nil
        if not page then return end

        local panel = EnsurePanel()
        if not panel then return end

        -- Geometry first, so the nub positions against the final panel size.
        panel:SetDirection(PageValue(page, "direction", PANEL_DEFAULT_DIRECTION))
        panel:SetGap(PageValue(page, "gap", PANEL_DEFAULT_GAP))
        panel:SetFlyoutSize(
            PageValue(page, "width", PANEL_DEFAULT_WIDTH),
            PageValue(page, "height", PANEL_DEFAULT_HEIGHT)
        )

        local frame = EnsurePage(panel, page, key)
        for pageKey, pageFrame in pairs(self._pageFrames) do
            pageFrame:SetShown(pageKey == page)
        end
        self._shownPage = page

        panel:Toggle()
    end)

    ---------------------------------------------------------------------------
    -- Theme
    ---------------------------------------------------------------------------

    local subscribeKey = "SelectorGear_" .. tostring(gear)
    gear._subscribeKey = subscribeKey
    theme:Subscribe(subscribeKey, function(r, g, b)
        tex:SetVertexColor(r, g, b)
    end)

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    function gear:Cleanup()
        if self._subscribeKey then
            GetTheme():Unsubscribe(self._subscribeKey)
            self._subscribeKey = nil
        end

        for _, cleanables in pairs(self._pageControls) do
            for _, control in ipairs(cleanables) do
                if control.Cleanup then control:Cleanup() end
            end
        end
        wipe(self._pageControls)
        wipe(self._pageFrames)
        self._shownPage = nil

        if self._panel then
            self._panel:Close()
            self._panel:Cleanup()
            self._panel:Hide()
            self._panel:SetParent(nil)
            self._panel = nil
        end
    end

    -- The builder's Clear pass calls Cleanup on the host, never on the gear.
    local hostCleanup = host.Cleanup
    host.Cleanup = function(self, ...)
        gear:Cleanup()
        if hostCleanup then
            return hostCleanup(self, ...)
        end
    end

    Sync()

    return gear
end
