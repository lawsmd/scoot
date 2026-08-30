-- AuraTrackingRenderer.lua - Settings page for aura tracking on group frames
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.AuraTracking = {}

local AuraTrackingUI = addon.UI.Settings.AuraTracking
local SettingsBuilder = addon.UI.SettingsBuilder
local GF = addon.UI.GroupFrames

--------------------------------------------------------------------------------
-- Runtime State
--------------------------------------------------------------------------------

AuraTrackingUI._selectedClass = nil
AuraTrackingUI._selectedSpellId = nil

--------------------------------------------------------------------------------
-- Anchor Option Tables
--------------------------------------------------------------------------------

local ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
local ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function ensureDB()
    if not GF or not GF.ensureAuraTrackingDB then
        local db = addon.db and addon.db.profile
        if not db then return nil end
        db.groupFrames = db.groupFrames or {}
        db.groupFrames.auraTracking = db.groupFrames.auraTracking or {}
        db.groupFrames.auraTracking.spells = db.groupFrames.auraTracking.spells or {}
        return db.groupFrames.auraTracking
    end
    return GF.ensureAuraTrackingDB()
end

local SPELL_DEFAULTS = addon.AuraTracking and addon.AuraTracking.SPELL_DEFAULTS or {
    enabled = false,
    trackAllSources = false,
    iconStyle = "spell",
    iconColor = "original",
    iconCustomColor = { 1, 1, 1, 1 },
    iconScale = 100,
    showDuration = true,
    anchor = "BOTTOMRIGHT",
    rank = 1,
    offsetX = 0,
    offsetY = 0,
}

local function ensureSpellConfig(spellId)
    local ha = ensureDB()
    if not ha then return SPELL_DEFAULTS end
    if not ha.spells[spellId] then
        ha.spells[spellId] = {}
    end
    return setmetatable(ha.spells[spellId], { __index = SPELL_DEFAULTS })
end

local function getSetting(spellId, key)
    local config = ensureSpellConfig(spellId)
    return config[key]
end

local function setSetting(spellId, key, value)
    local config = ensureSpellConfig(spellId)
    config[key] = value
    -- Notify core to refresh
    if addon.AuraTracking and addon.AuraTracking.OnConfigChanged then
        addon.AuraTracking.OnConfigChanged()
    end
end

--------------------------------------------------------------------------------
-- Icon Style Row (Custom Control)
--------------------------------------------------------------------------------
-- A row that shows the current icon preview and opens the IconPicker.
--------------------------------------------------------------------------------

local function CreateIconStyleRow(parent, spellId, builder)
    local theme = addon.UI.Theme
    local accentR, accentG, accentB = 0.20, 0.90, 0.30
    if theme and theme.GetAccentColor then
        accentR, accentG, accentB = theme:GetAccentColor()
    end
    local labelFont = (theme and theme.GetFont and theme:GetFont("LABEL")) or "Fonts\\FRIZQT__.TTF"
    local valueFont = (theme and theme.GetFont and theme:GetFont("VALUE")) or "Fonts\\FRIZQT__.TTF"

    local ROW_HEIGHT = 36
    local ICON_SIZE = 28
    local BUTTON_WIDTH = 200

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(accentR, accentG, accentB, 0)
    row._hoverBg = hoverBg

    -- Bottom border
    local rowBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    rowBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rowBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    rowBorder:SetHeight(1)
    rowBorder:SetColorTexture(accentR, accentG, accentB, 0.2)
    row._rowBorder = rowBorder

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(labelFont, 13, "")
    label:SetPoint("LEFT", row, "LEFT", 12, 0)
    label:SetText("Icon Style")
    label:SetTextColor(accentR, accentG, accentB, 1)
    row._label = label

    -- Selector button (right side)
    local selectorBtn = CreateFrame("Button", nil, row)
    selectorBtn:SetSize(BUTTON_WIDTH, ICON_SIZE + 4)
    selectorBtn:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    selectorBtn:EnableMouse(true)
    selectorBtn:RegisterForClicks("AnyUp")

    -- Border
    local borderAlpha = 0.5
    local bTop = selectorBtn:CreateTexture(nil, "BORDER")
    bTop:SetPoint("TOPLEFT") bTop:SetPoint("TOPRIGHT") bTop:SetHeight(1)
    bTop:SetColorTexture(accentR, accentG, accentB, borderAlpha)
    local bBot = selectorBtn:CreateTexture(nil, "BORDER")
    bBot:SetPoint("BOTTOMLEFT") bBot:SetPoint("BOTTOMRIGHT") bBot:SetHeight(1)
    bBot:SetColorTexture(accentR, accentG, accentB, borderAlpha)
    local bLeft = selectorBtn:CreateTexture(nil, "BORDER")
    bLeft:SetPoint("TOPLEFT", 0, -1) bLeft:SetPoint("BOTTOMLEFT", 0, 1) bLeft:SetWidth(1)
    bLeft:SetColorTexture(accentR, accentG, accentB, borderAlpha)
    local bRight = selectorBtn:CreateTexture(nil, "BORDER")
    bRight:SetPoint("TOPRIGHT", 0, -1) bRight:SetPoint("BOTTOMRIGHT", 0, 1) bRight:SetWidth(1)
    bRight:SetColorTexture(accentR, accentG, accentB, borderAlpha)

    -- Background
    local selBg = selectorBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    selBg:SetAllPoints()
    selBg:SetColorTexture(0.06, 0.06, 0.08, 1)
    selectorBtn._bg = selBg

    -- Icon preview
    local iconPreview = selectorBtn:CreateTexture(nil, "ARTWORK")
    iconPreview:SetSize(ICON_SIZE, ICON_SIZE)
    iconPreview:SetPoint("LEFT", selectorBtn, "LEFT", 6, 0)
    selectorBtn._iconPreview = iconPreview

    -- Label text
    local selText = selectorBtn:CreateFontString(nil, "OVERLAY")
    selText:SetFont(valueFont, 11, "")
    selText:SetPoint("LEFT", iconPreview, "RIGHT", 8, 0)
    selText:SetPoint("RIGHT", selectorBtn, "RIGHT", -24, 0)
    selText:SetJustifyH("LEFT")
    selText:SetWordWrap(false)
    selectorBtn._text = selText

    -- Drop indicator
    local dropArrow = selectorBtn:CreateFontString(nil, "OVERLAY")
    dropArrow:SetFont(valueFont, 10, "")
    dropArrow:SetPoint("RIGHT", selectorBtn, "RIGHT", -8, 0)
    dropArrow:SetText("\226\150\188") -- ▼
    dropArrow:SetTextColor(accentR, accentG, accentB, 0.8)

    -- Update display
    local function UpdateDisplay()
        local style = getSetting(spellId, "iconStyle") or "spell"

        -- Reset preview size and border backing
        iconPreview:SetSize(ICON_SIZE, ICON_SIZE)
        if selectorBtn._borderTex then selectorBtn._borderTex:Hide() end

        -- Parse prefix variants
        local isBordered = style:sub(1, 7) == "border:"
        local isWide = style:sub(1, 5) == "wide:"
        local baseStyle = style
        if isBordered then
            baseStyle = style:sub(8)
        elseif isWide then
            baseStyle = style:sub(6)
        end

        if isBordered then
            -- Same-shape black backing for 1px border effect
            if not selectorBtn._borderTex then
                local bt = selectorBtn:CreateTexture(nil, "ARTWORK", nil, -1)
                bt:SetPoint("CENTER", iconPreview, "CENTER")
                selectorBtn._borderTex = bt
            end
            -- Use the same atlas colored black for matching silhouette
            local borderOk = pcall(selectorBtn._borderTex.SetAtlas, selectorBtn._borderTex, baseStyle)
            if not borderOk then
                selectorBtn._borderTex:SetColorTexture(0, 0, 0, 1)
            end
            selectorBtn._borderTex:SetDesaturated(true)
            selectorBtn._borderTex:SetVertexColor(0, 0, 0, 1)
            selectorBtn._borderTex:SetSize(ICON_SIZE, ICON_SIZE)
            selectorBtn._borderTex:Show()
            iconPreview:SetSize(ICON_SIZE - 2, ICON_SIZE - 2)
            local ok = pcall(iconPreview.SetAtlas, iconPreview, baseStyle)
            if not ok then
                iconPreview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            iconPreview:SetDesaturated(true)
            iconPreview:SetVertexColor(0.8, 0.8, 0.8, 1)
            selText:SetText("Bordered " .. baseStyle)
        elseif isWide then
            -- 3:1 aspect ratio preview
            local wideH = math.ceil(ICON_SIZE / 3)
            iconPreview:SetSize(ICON_SIZE, wideH)
            local ok = pcall(iconPreview.SetAtlas, iconPreview, baseStyle)
            if not ok then
                iconPreview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            iconPreview:SetDesaturated(true)
            iconPreview:SetVertexColor(0.8, 0.8, 0.8, 1)
            selText:SetText("Wide " .. baseStyle)
        elseif style == "spell" then
            -- Show the spell's own icon
            local tex
            pcall(function()
                tex = C_Spell.GetSpellTexture(spellId)
            end)
            iconPreview:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            iconPreview:SetDesaturated(false)
            iconPreview:SetVertexColor(1, 1, 1, 1)
            selText:SetText("Spell Icon")
        elseif style:sub(1, 5) == "anim:" then
            -- Animated icon: show placeholder + label
            local animId = style:sub(6)
            local AE = addon.AuraTracking and addon.AuraTracking.AnimEngine
            local def = AE and AE.GetDef(animId)
            iconPreview:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            iconPreview:SetDesaturated(false)
            iconPreview:SetVertexColor(0.8, 0.8, 0.8, 1)
            selText:SetText(def and def.label or animId)
        elseif style:sub(1, 5) == "file:" then
            -- File-based custom texture
            local path = style:sub(6)
            iconPreview:SetTexture(path)
            iconPreview:SetDesaturated(true)
            iconPreview:SetVertexColor(0.8, 0.8, 0.8, 1)
            -- Extract short name from path for display
            local shortName = path:match("([^\\]+)$") or style
            selText:SetText(shortName)
        else
            -- Atlas-based icon
            local ok = pcall(iconPreview.SetAtlas, iconPreview, style)
            if not ok then
                iconPreview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            iconPreview:SetDesaturated(true)
            iconPreview:SetVertexColor(0.8, 0.8, 0.8, 1)
            selText:SetText(style)
        end
    end

    UpdateDisplay()

    -- Hover
    selectorBtn:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
        row._hoverBg:SetColorTexture(accentR, accentG, accentB, 0.08)
    end)
    selectorBtn:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
        row._hoverBg:SetColorTexture(0, 0, 0, 0)
    end)

    -- Click opens picker
    selectorBtn:SetScript("OnClick", function(self)
        local currentStyle = getSetting(spellId, "iconStyle") or "spell"
        addon.ShowIconPicker(self, currentStyle, function(selectedKey)
            setSetting(spellId, "iconStyle", selectedKey)
            UpdateDisplay()
        end)
    end)

    row._selectorBtn = selectorBtn
    row._updateDisplay = UpdateDisplay

    return row
end

--------------------------------------------------------------------------------
-- Spell Icon Grid
--------------------------------------------------------------------------------
-- Creates centered rows of spell icons for the selected class.
--------------------------------------------------------------------------------

local GRID_ICON_SIZE = 36
local GRID_ICON_SPACING = 6
local GRID_MAX_PER_ROW = 8
local GRID_BORDER_WIDTH = 2

local function CreateSpellGrid(parent, classToken, scrollContent, panel, builder)
    local HA = addon.AuraTracking
    if not HA or not HA.SPELL_REGISTRY then return nil, 0 end

    local spells = HA.SPELL_REGISTRY[classToken]
    if not spells or #spells == 0 then return nil, 0 end

    local theme = addon.UI.Theme
    local accentR, accentG, accentB = 0.20, 0.90, 0.30
    if theme and theme.GetAccentColor then
        accentR, accentG, accentB = theme:GetAccentColor()
    end

    local container = CreateFrame("Frame", nil, parent)
    local parentWidth = scrollContent:GetWidth() or 500
    local totalCols = math.min(#spells, GRID_MAX_PER_ROW)
    local gridWidth = totalCols * GRID_ICON_SIZE + (totalCols - 1) * GRID_ICON_SPACING
    local numRows = math.ceil(#spells / GRID_MAX_PER_ROW)
    local gridHeight = numRows * GRID_ICON_SIZE + (numRows - 1) * GRID_ICON_SPACING
    container:SetHeight(gridHeight + 16)

    local iconButtons = {}

    for i, entry in ipairs(spells) do
        local col = (i - 1) % GRID_MAX_PER_ROW
        local row = math.floor((i - 1) / GRID_MAX_PER_ROW)

        -- Calculate row width for centering
        local itemsInRow = math.min(#spells - row * GRID_MAX_PER_ROW, GRID_MAX_PER_ROW)
        local rowWidth = itemsInRow * GRID_ICON_SIZE + (itemsInRow - 1) * GRID_ICON_SPACING

        local btn = CreateFrame("Button", nil, container)
        btn:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")

        -- Center each row
        local xOff = col * (GRID_ICON_SIZE + GRID_ICON_SPACING)
        local yOff = -(row * (GRID_ICON_SIZE + GRID_ICON_SPACING)) - 8

        btn:SetPoint("TOPLEFT", container, "TOP", -rowWidth / 2 + xOff, yOff)

        -- Icon texture
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", GRID_BORDER_WIDTH, -GRID_BORDER_WIDTH)
        icon:SetPoint("BOTTOMRIGHT", -GRID_BORDER_WIDTH, GRID_BORDER_WIDTH)
        btn._icon = icon

        -- Set spell icon
        local spellTex
        pcall(function()
            spellTex = C_Spell.GetSpellTexture(entry.id)
        end)
        icon:SetTexture(spellTex or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Border frame (accent highlight)
        local borderBg = btn:CreateTexture(nil, "BACKGROUND", nil, -5)
        borderBg:SetAllPoints()
        borderBg:SetColorTexture(0, 0, 0, 0)
        btn._borderBg = borderBg

        -- Check if enabled (small dot indicator)
        local config = ensureSpellConfig(entry.id)
        if config.enabled then
            -- Small accent dot in corner
            local dot = btn:CreateTexture(nil, "OVERLAY")
            dot:SetSize(6, 6)
            dot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
            dot:SetColorTexture(accentR, accentG, accentB, 1)
            btn._enabledDot = dot
        end

        -- Highlight if selected
        local isSelected = (AuraTrackingUI._selectedSpellId == entry.id)
        if isSelected then
            borderBg:SetColorTexture(accentR, accentG, accentB, 0.6)
        end

        btn._spellId = entry.id
        btn._spellName = entry.name

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            if AuraTrackingUI._selectedSpellId ~= self._spellId then
                self._borderBg:SetColorTexture(accentR, accentG, accentB, 0.3)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self._spellId)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            if AuraTrackingUI._selectedSpellId ~= self._spellId then
                self._borderBg:SetColorTexture(0, 0, 0, 0)
            end
            GameTooltip:Hide()
        end)

        -- Click to select
        btn:SetScript("OnClick", function(self)
            AuraTrackingUI._selectedSpellId = self._spellId
            AuraTrackingUI.Render(panel, scrollContent)
        end)

        iconButtons[i] = btn
    end

    container._iconButtons = iconButtons
    return container, gridHeight + 16
end

--------------------------------------------------------------------------------
-- Main Render Function
--------------------------------------------------------------------------------

function AuraTrackingUI.Render(panel, scrollContent)
    panel:ClearContent()

    local HA = addon.AuraTracking
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        AuraTrackingUI.Render(panel, scrollContent)
    end)

    -- Default to player's class on fresh session
    if not AuraTrackingUI._selectedClass then
        local _, classToken = UnitClass("player")
        -- Only use player class if it is in the registry
        if HA and HA.SPELL_REGISTRY and HA.SPELL_REGISTRY[classToken] then
            AuraTrackingUI._selectedClass = classToken
        else
            AuraTrackingUI._selectedClass = HA.CLASS_ORDER and HA.CLASS_ORDER[1] or "DRUID"
        end
    end

    --------------------------------------------------------------------------
    -- Blizzard icon note (single yellow paragraph, no header)
    --------------------------------------------------------------------------

    builder:AddDescription(
        "Blizzard draws party and raid buff icons in a protected internal system, so addons cannot restyle, shrink, or reposition them individually. "
        .. "Patch 12.1 added a Blizzard setting that can turn those buff icons off entirely; the toggle below controls it. "
        .. "Scoot's custom tracked icons are drawn separately and work whether Blizzard's icons are shown or hidden. "
        .. "Each tracked aura keeps its own position, so an aura that is not currently on a group member leaves its spot empty rather than shifting the others.",
        { color = {1, 0.82, 0}, topPadding = 4, bottomPadding = -16 }
    )

    --------------------------------------------------------------------------
    -- Hide Blizzard Buff Icons (toggle driving the raidFramesDisplayBuffs CVar)
    --------------------------------------------------------------------------

    local buffCVarOk, buffCVarValue = pcall(function()
        return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("raidFramesDisplayBuffs")
    end)
    local buffCVarPresent = buffCVarOk and buffCVarValue ~= nil

    if buffCVarPresent then
        -- Adopt a pre-existing CVar override into the profile so the preference
        -- survives to other characters. Only when the profile has no opinion yet
        -- and the live CVar differs from the client's REGISTERED default (queried,
        -- not assumed), i.e. the user already changed it deliberately, so this is
        -- not a Zero-Touch violation. ensureDB() runs the replacementStyle
        -- conversion first, so an overlay-era profile has already been migrated by
        -- the time this check runs.
        local cvarDefault = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault("raidFramesDisplayBuffs")
        do
            local at = ensureDB()
            if at and at.hideBlizzardBuffIcons == nil then
                local cur = C_CVar.GetCVar("raidFramesDisplayBuffs")
                if cur ~= nil and cvarDefault ~= nil and cur ~= cvarDefault then
                    at.hideBlizzardBuffIcons = (cur == "0")
                end
            end
        end

        local defaultNote = ""
        if cvarDefault == "1" then
            defaultNote = " (Blizzard default: shown)"
        elseif cvarDefault == "0" then
            defaultNote = " (Blizzard default: hidden)"
        end

        builder:AddToggle({
            key = "hideBlizzardBuffIcons",
            label = "Hide Blizzard Buff Icons",
            description = "Turns off Blizzard's own buff icons on raid frames and raid-style party frames" .. defaultNote .. ". "
                .. "Debuffs are not affected. Scoot's custom tracked icons render either way.",
            get = function()
                local at = ensureDB() or {}
                if at.hideBlizzardBuffIcons ~= nil then return at.hideBlizzardBuffIcons end
                -- Unset: reflect the live CVar so the checkbox matches reality.
                local cur = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("raidFramesDisplayBuffs")
                return cur == "0"
            end,
            set = function(v)
                local at = ensureDB()
                if not at then return end
                at.hideBlizzardBuffIcons = v and true or false
                if addon.ApplyGroupBuffIconsHidden then
                    addon.ApplyGroupBuffIconsHidden("toggle")
                end
            end,
        })
    else
        builder:AddDescription(
            "Hiding Blizzard's buff icons requires a game setting that is not available on this client.",
            { color = {1, 0.4, 0.4} }
        )
    end

    --------------------------------------------------------------------------
    -- Class Selector (centered, emphasized, 400px wide)
    --------------------------------------------------------------------------

    local selectorValues = {}
    local selectorOrder = {}
    if HA and HA.CLASS_ORDER and HA.CLASS_LABELS then
        for _, classToken in ipairs(HA.CLASS_ORDER) do
            selectorValues[classToken] = HA.CLASS_LABELS[classToken] or classToken
            table.insert(selectorOrder, classToken)
        end
    end

    builder:AddSelector({
        key = "classSelector",
        label = "",
        emphasized = true,
        values = selectorValues,
        order = selectorOrder,
        width = 400,
        get = function() return AuraTrackingUI._selectedClass end,
        set = function(v)
            AuraTrackingUI._selectedClass = v
            AuraTrackingUI._selectedSpellId = nil
            AuraTrackingUI.Render(panel, scrollContent)
        end,
    })

    -- Center the selector widget (same pattern as ActionBarRenderer)
    local selectorRow = builder._controls[#builder._controls]
    if selectorRow then
        local children = { selectorRow:GetChildren() }
        for _, child in ipairs(children) do
            if child._border then
                child:ClearAllPoints()
                child:SetPoint("CENTER", selectorRow, "CENTER", 0, 0)
                break
            end
        end
        if selectorRow._label then
            selectorRow._label:Hide()
        end
        if selectorRow._rowBorder then
            if selectorRow._rowBorder.LEFT then
                selectorRow._rowBorder.LEFT:Hide()
            end
            if selectorRow._rowBorder.BOTTOM then
                selectorRow._rowBorder.BOTTOM:Hide()
            end
        end
        if selectorRow._emphBg then
            selectorRow._emphBg:Hide()
        end
    end

    --------------------------------------------------------------------------
    -- Other-class note
    --------------------------------------------------------------------------
    -- Tracked icons hold fixed positions, so an enabled spell this character
    -- cannot cast is filtered out of the layout rather than left holding an
    -- empty slot. Say so on the tab where it can be enabled by accident.
    --------------------------------------------------------------------------

    local _, playerClassToken = UnitClass("player")
    if playerClassToken and AuraTrackingUI._selectedClass ~= playerClassToken then
        builder:AddDescription(
            "This is another class's list. On this character, a spell here is only tracked if you turn on Track All Sources for it, since you cannot cast it yourself.",
            { color = {1, 0.82, 0}, topPadding = 2, bottomPadding = 2 }
        )
    end

    --------------------------------------------------------------------------
    -- Spell Icon Grid (directly below class selector, no divider)
    --------------------------------------------------------------------------

    local gridContainer, gridHeight = CreateSpellGrid(
        scrollContent, AuraTrackingUI._selectedClass, scrollContent, panel, builder
    )
    if gridContainer then
        -- Position the grid manually in the builder flow
        gridContainer:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, builder._currentY)
        gridContainer:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, builder._currentY)
        table.insert(builder._controls, gridContainer)
        builder._currentY = builder._currentY - gridHeight
    end

    --------------------------------------------------------------------------
    -- Per-Spell Config (shown when a spell is selected)
    --------------------------------------------------------------------------

    local selectedId = AuraTrackingUI._selectedSpellId
    if selectedId then
        local spellName = (HA and HA.SPELL_NAMES and HA.SPELL_NAMES[selectedId]) or ("Spell " .. selectedId)

        builder:AddSpacer(12)

        -- Enable toggle (always visible)
        builder:AddToggle({
            key = "enableToggle",
            label = "Custom Aura Display for " .. spellName,
            description = "Hide the default buff icon and replace it with a custom styled icon on group frames.",
            emphasized = true,
            get = function() return getSetting(selectedId, "enabled") end,
            set = function(v)
                local cfg = ensureSpellConfig(selectedId)
                if v then
                    -- Enabling: land at end of current anchor's list (BOTTOMRIGHT default
                    -- when the aura has never been configured before). AutoSlotAtEnd
                    -- writes anchor + rank, so enabled is set last.
                    local targetAnchor = (cfg and cfg.anchor) or "BOTTOMRIGHT"
                    if HA and HA.AutoSlotAtEnd then
                        HA.AutoSlotAtEnd(selectedId, targetAnchor)
                    end
                    if cfg then cfg.enabled = true end
                else
                    -- Disabling: clear enabled, then re-sequence the anchor so the
                    -- remaining enabled auras keep contiguous 1..N ranks.
                    local oldAnchor = (cfg and cfg.anchor) or "BOTTOMRIGHT"
                    if cfg then cfg.enabled = false end
                    if HA and HA.ReindexAnchor then
                        HA.ReindexAnchor(oldAnchor)
                    end
                end
                if HA and HA.OnConfigChanged then HA.OnConfigChanged() end
                AuraTrackingUI.Render(panel, scrollContent)
            end,
        })

        local isEnabled = getSetting(selectedId, "enabled")

        ------------------------------------------------------------------
        -- Tabbed per-spell section
        ------------------------------------------------------------------
        local stackable = HA and HA.STACKABLE_SPELLS and HA.STACKABLE_SPELLS[selectedId] or false

        local tabs = {
            { key = "settings",    label = "Settings" },
            { key = "style",       label = "Style" },
            { key = "sizing",      label = "Sizing" },
            { key = "positioning", label = "Positioning" },
        }
        if stackable then
            table.insert(tabs, { key = "stacksText", label = "Stacks Text" })
        end

        builder:AddTabbedSection({
            tabs = tabs,
            componentId = "gfAuraTracking",
            sectionKey = "perSpell_" .. selectedId,
            defaultTab = "settings",
            buildContent = {
                --------------------------------------------------------
                -- Settings
                --------------------------------------------------------
                settings = function(tabContent, tabBuilder)
                    tabBuilder:AddToggle({
                        key = "trackAllSources",
                        label = "Track from All Players",
                        description = "Show this icon when the aura is applied by any player, not just you.",
                        get = function() return getSetting(selectedId, "trackAllSources") end,
                        set = function(v) setSetting(selectedId, "trackAllSources", v) end,
                        disabled = function() return not getSetting(selectedId, "enabled") end,
                    })
                    tabBuilder:AddToggle({
                        key = "showDuration",
                        label = "Show Duration",
                        description = "Display a drain effect on the icon that reveals a dark backdrop as the aura's remaining duration decreases.",
                        get = function()
                            local v = getSetting(selectedId, "showDuration")
                            if v == nil then return true end
                            return v
                        end,
                        set = function(v) setSetting(selectedId, "showDuration", v) end,
                        disabled = function() return not isEnabled end,
                    })
                end,

                --------------------------------------------------------
                -- Style (icon style picker + icon color)
                --------------------------------------------------------
                style = function(tabContent, tabBuilder)
                    -- Icon Style custom row, parented to tabContent
                    local iconStyleRow = CreateIconStyleRow(tabContent, selectedId, tabBuilder)
                    if iconStyleRow then
                        if #tabBuilder._controls > 0 then
                            tabBuilder._currentY = tabBuilder._currentY - 12
                        end
                        iconStyleRow:SetPoint("TOPLEFT", tabContent, "TOPLEFT", 0, tabBuilder._currentY)
                        iconStyleRow:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", 0, tabBuilder._currentY)
                        table.insert(tabBuilder._controls, iconStyleRow)
                        tabBuilder._currentY = tabBuilder._currentY - iconStyleRow:GetHeight()

                        if not isEnabled then
                            local theme = addon.UI.Theme
                            local dimR, dimG, dimB = 0.5, 0.5, 0.5
                            if theme and theme.GetDimTextColor then
                                dimR, dimG, dimB = theme:GetDimTextColor()
                            end
                            iconStyleRow._label:SetTextColor(dimR, dimG, dimB, 0.35)
                            iconStyleRow._selectorBtn:SetAlpha(0.35)
                            iconStyleRow._selectorBtn:EnableMouse(false)
                            iconStyleRow._rowBorder:SetColorTexture(dimR, dimG, dimB, 0.1)
                        end
                    end

                    tabBuilder:AddSelectorColorPicker({
                        key = "iconColor",
                        label = "Icon Color",
                        values = { original = "Texture Original", custom = "Custom", rainbow = "Rainbow" },
                        order = { "original", "custom", "rainbow" },
                        customValue = "custom",
                        hasAlpha = true,
                        get = function() return getSetting(selectedId, "iconColor") or "original" end,
                        set = function(v) setSetting(selectedId, "iconColor", v) end,
                        getColor = function()
                            local c = getSetting(selectedId, "iconCustomColor") or { 1, 1, 1, 1 }
                            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                        end,
                        setColor = function(r, g, b, a)
                            setSetting(selectedId, "iconCustomColor", { r, g, b, a })
                        end,
                        disabled = function() return not isEnabled end,
                    })
                end,

                --------------------------------------------------------
                -- Sizing
                --------------------------------------------------------
                sizing = function(tabContent, tabBuilder)
                    tabBuilder:AddSlider({
                        key = "iconScale",
                        label = "Icon Scale",
                        min = 25,
                        max = 300,
                        step = 5,
                        get = function() return getSetting(selectedId, "iconScale") or 100 end,
                        set = function(v) setSetting(selectedId, "iconScale", v) end,
                        displaySuffix = "%",
                        disabled = function() return not isEnabled end,
                    })
                end,

                --------------------------------------------------------
                -- Positioning (anchor+priority, group spacing, offset)
                --------------------------------------------------------
                positioning = function(tabContent, tabBuilder)
                    local Controls = addon.UI and addon.UI.Controls
                    local theme = addon.UI and addon.UI.Theme

                    local rowHeight = 54
                    local topLabelY = -6
                    local controlY = -24

                    local row = CreateFrame("Frame", nil, tabContent)
                    row:SetHeight(rowHeight)

                    local accR, accG, accB = 0.2, 0.9, 0.3
                    if theme and theme.GetAccentColor then accR, accG, accB = theme:GetAccentColor() end
                    local dimR, dimG, dimB = 0.5, 0.5, 0.5
                    if theme and theme.GetDimTextColor then dimR, dimG, dimB = theme:GetDimTextColor() end

                    local function headerColor()
                        if isEnabled then return { accR, accG, accB } end
                        return { dimR, dimG, dimB }
                    end

                    local anchorLabel = row:CreateFontString(nil, "OVERLAY")
                    if theme and theme.ApplyLabelFont then
                        theme:ApplyLabelFont(anchorLabel, 12)
                    else
                        anchorLabel:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                    end
                    anchorLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 0, topLabelY)
                    anchorLabel:SetText("Anchor")
                    local hc = headerColor()
                    anchorLabel:SetTextColor(hc[1], hc[2], hc[3], 1)

                    local anchorSel
                    if Controls and Controls._CreateMiniSelector then
                        anchorSel = Controls._CreateMiniSelector({
                            values = ANCHOR_VALUES,
                            order  = ANCHOR_ORDER,
                            get = function() return getSetting(selectedId, "anchor") or "BOTTOMRIGHT" end,
                            set = function(v)
                                local cfg = ensureSpellConfig(selectedId)
                                if not cfg then return end
                                local oldAnchor = rawget(cfg, "anchor") or cfg.anchor or "BOTTOMRIGHT"
                                if oldAnchor == v then return end
                                if cfg.enabled and HA and HA.ReindexAnchor and HA.AutoSlotAtEnd then
                                    HA.ReindexAnchor(oldAnchor)
                                    HA.AutoSlotAtEnd(selectedId, v)
                                else
                                    cfg.anchor = v
                                end
                                if HA and HA.OnConfigChanged then HA.OnConfigChanged() end
                                AuraTrackingUI.Render(panel, scrollContent)
                            end,
                        }, row, theme, false)
                        anchorSel:SetWidth(190)
                        anchorSel:SetPoint("TOPLEFT", row, "TOPLEFT", 0, controlY)
                    end

                    local rankSel
                    if Controls and Controls.CreateRankSelector then
                        rankSel = Controls:CreateRankSelector({
                            parent = row,
                            count = 6,
                            labelText = "Priority",
                            get = function()
                                local r = tonumber(getSetting(selectedId, "rank"))
                                if not r or r < 1 then r = 1 end
                                return r
                            end,
                            currentSpellId = function() return selectedId end,
                            isInGroup = function()
                                if not isEnabled then return false end
                                local cfg = ensureSpellConfig(selectedId)
                                return cfg and cfg.enabled and true or false
                            end,
                            spellIdAt = function(rank)
                                if not HA or not HA.EnabledInAnchor then return nil end
                                local cfg = ensureSpellConfig(selectedId)
                                local anchor = (cfg and cfg.anchor) or "BOTTOMRIGHT"
                                local cls = HA.SPELL_TO_CLASS and HA.SPELL_TO_CLASS[selectedId] or nil
                                local list = HA.EnabledInAnchor(anchor, nil, cls)
                                local entry = list[rank]
                                return entry and entry.spellId or nil
                            end,
                            set = function(newRank)
                                if not isEnabled then return end
                                local cfg = ensureSpellConfig(selectedId)
                                local anchor = (cfg and cfg.anchor) or "BOTTOMRIGHT"
                                if HA and HA.ReorderRank then
                                    HA.ReorderRank(anchor, selectedId, newRank)
                                end
                                if HA and HA.OnConfigChanged then HA.OnConfigChanged() end
                                AuraTrackingUI.Render(panel, scrollContent)
                            end,
                        })
                        rankSel:SetPoint("TOPLEFT", row, "TOPLEFT", 220, controlY + 4)
                    end

                    if #tabBuilder._controls > 0 then
                        tabBuilder._currentY = tabBuilder._currentY - 12
                    end
                    row:SetPoint("TOPLEFT", tabContent, "TOPLEFT", 0, tabBuilder._currentY)
                    row:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", 0, tabBuilder._currentY)
                    table.insert(tabBuilder._controls, row)
                    tabBuilder._currentY = tabBuilder._currentY - rowHeight

                    -- Position Group Spacing (per-anchor)
                    local cfg = ensureSpellConfig(selectedId)
                    local curAnchor = (cfg and cfg.anchor) or "BOTTOMRIGHT"
                    local anchorLabelStr = ANCHOR_VALUES[curAnchor] or curAnchor
                    tabBuilder:AddSlider({
                        key = "positionGroupSpacing_" .. selectedId,
                        label = "Position Group Spacing (" .. anchorLabelStr .. ")",
                        description = "Extra pixels between consecutive icons sharing this anchor. "
                            .. "Shared across every aura assigned to this anchor group.",
                        min = -5,
                        max = 15,
                        step = 1,
                        displaySuffix = " px",
                        get = function()
                            local at = ensureDB()
                            local map = at and at.positionGroupSpacing
                            if type(map) == "table" and type(map[curAnchor]) == "number" then
                                return map[curAnchor]
                            end
                            return 2
                        end,
                        set = function(v)
                            local at = ensureDB()
                            if not at then return end
                            if type(at.positionGroupSpacing) ~= "table" then
                                at.positionGroupSpacing = {}
                            end
                            at.positionGroupSpacing[curAnchor] = v
                            if HA and HA.OnConfigChanged then HA.OnConfigChanged() end
                        end,
                        disabled = function() return not isEnabled end,
                    })

                    -- Extra breathing room between Position Group Spacing's divider
                    -- and the Offset DualSlider. The default ITEM_SPACING is tight
                    -- against the slider's bottom rule; a small spacer separates them.
                    tabBuilder:AddSpacer(8)

                    -- setSetting applies on its own, so no apply is passed
                    tabBuilder:AddOffsetPair({
                        range = 50,
                        disabled = function() return not isEnabled end,
                        get = function(axis) return getSetting(selectedId, axis == "x" and "offsetX" or "offsetY") end,
                        set = function(axis, v) setSetting(selectedId, axis == "x" and "offsetX" or "offsetY", v) end,
                    })
                end,

                --------------------------------------------------------
                -- Stacks Text (only inserted when stackable == true)
                --------------------------------------------------------
                stacksText = function(tabContent, tabBuilder)
                    local Helpers = addon.UI.Settings and addon.UI.Settings.Helpers or GF
                    local DEFAULTS = (HA and HA.STACKS_TEXT_DEFAULTS) or {
                        fontFace = "FRIZQT__", size = 12, style = "OUTLINE",
                        colorMode = "default", customColor = { 1, 1, 1, 1 },
                        anchor = "BOTTOMRIGHT", offsetX = 0, offsetY = 0,
                    }

                    local function getST(key)
                        local cfg = ensureSpellConfig(selectedId)
                        local st = cfg and rawget(cfg, "stacksText")
                        if st and st[key] ~= nil then return st[key] end
                        return DEFAULTS[key]
                    end

                    local function setST(key, value)
                        local cfg = ensureSpellConfig(selectedId)
                        if not cfg then return end
                        if not rawget(cfg, "stacksText") then
                            cfg.stacksText = {}
                        end
                        cfg.stacksText[key] = value
                    end

                    local function applyST()
                        if HA and HA.OnConfigChanged then HA.OnConfigChanged() end
                    end

                    -- Composite fields map straight onto the stacksText keys;
                    -- only the custom color is stored under customColor
                    local FIELD_KEYS = { color = "customColor" }
                    tabBuilder:AddTextStyleBlock({
                        get = function(field) return getST(FIELD_KEYS[field] or field) end,
                        set = function(field, value) setST(FIELD_KEYS[field] or field, value) end,
                        apply = applyST,
                        disabled = function() return not isEnabled end,
                        defaults = { size = 12 },
                        font = { description = "Font used for the stack count text." },
                        -- Plain order: the stack count string is bound to the
                        -- aura container (SetApplicationCount), so the engine
                        -- writes the text natively and a Deep Shadow copy,
                        -- which is fed by hooks on Lua SetText, would stay
                        -- empty. True since the container port.
                        style = { order = Helpers.fontStyleOrder or GF.fontStyleOrder },
                        size = { min = 6, max = 32 },
                        color = {
                            key = "stacksTextColor",
                            values = { ["default"] = "Default (White)", ["custom"] = "Custom" },
                            order = { "default", "custom" },
                        },
                        alignment = {
                            kind = "anchor9",
                            label = "Position",
                            description = "Where the stacks text sits within the icon's bounding box.",
                            values = ANCHOR_VALUES,
                            order = ANCHOR_ORDER,
                        },
                        offset = { range = 50 },
                    })
                end,
            },
        })
    end

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("gfAuraTracking", function(panel, scrollContent)
    -- Reset to player's class each time the page is navigated to
    AuraTrackingUI._selectedClass = nil
    AuraTrackingUI._selectedSpellId = nil
    AuraTrackingUI.Render(panel, scrollContent)
end)

return AuraTrackingUI
