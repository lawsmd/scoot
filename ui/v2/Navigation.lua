-- Navigation.lua - Terminal-style navigation sidebar with custom scrollbar
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Navigation = {}
local Navigation = addon.UI.Navigation
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local NAV_WIDTH = 220  -- Width of the navigation sidebar
local ROW_HEIGHT = 24  -- Height of each navigation row
local PARENT_ROW_HEIGHT = 28  -- Slightly taller for section headers
local CHILD_INDENT = 20  -- Indentation for child items
local PADDING_LEFT = 8
local PADDING_TOP = 8
local PADDING_RIGHT = 8

-- Scrollbar dimensions
local SCROLLBAR_WIDTH = 8
local SCROLLBAR_THUMB_MIN_HEIGHT = 30
local SCROLLBAR_TRACK_PADDING = 2
local SCROLLBAR_RIGHT_MARGIN = 8  -- Gap between scrollbar and right edge/separator

-- Tree line dimensions (texture-based, not text)
local TREE_LINE_WIDTH = 1
local TREE_LINE_HORIZONTAL_LENGTH = 10
local TREE_LINE_COLOR_ALPHA = 0.4

--------------------------------------------------------------------------------
-- Navigation Model (matching existing navModel structure)
--------------------------------------------------------------------------------

Navigation.NavModel = {
    -- "Features" and "Search" are now top-bar header buttons (settingspanel/core.lua),
    -- not NavModel entries. Their renderer keys ("startHere", "search") remain unchanged.
    {
        key = "profiles",
        label = "Profiles",
        collapsible = true,
        children = {
            { key = "profilesManage", label = "Manage Profiles" },
            { key = "profilesPresets", label = "Presets" },
            { key = "profilesRules", label = "Rules" },
            { key = "profilesImportExport", label = "Import/Export" },
        },
    },
    {
        key = "applyAll",
        label = "Apply All",
        collapsible = true,
        children = {
            { key = "applyAllFonts", label = "Fonts" },
            { key = "applyAllTextures", label = "Bar Textures" },
        },
    },
    {
        key = "interface",
        label = "Interface",
        collapsible = true,
        children = {
            { key = "damageMeter", label = "Damage Meters", module = "damageMeter", moduleSubId = "damageMeter",
                variant = "X",
                versionBadge = { label = "X", title = "Damage Meters X", text = "Reskins Blizzard's built-in damage meter frames while keeping the native functionality intact." } },
            { key = "damageMeterV2", label = "Damage Meters", module = "damageMeter", moduleSubId = "damageMeterV2",
                variant = "Y",
                versionBadge = { label = "Y", title = "Damage Meters Y", text = "Custom frames that replace Blizzard's meter entirely. Multi-column and multi-window support." } },
            { key = "tooltip", label = "Tooltip", module = "tooltip" },
            { key = "objectiveTracker", label = "Objective Tracker", module = "objectiveTracker" },
            { key = "minimap", label = "Minimap", module = "minimap" },
            { key = "chat", label = "Chat" },
            { key = "notes", label = "Notes", module = "notes" },
            { key = "misc", label = "Misc." },
        },
    },
    {
        key = "bossWarnings",
        label = "Boss Warnings",
        collapsible = true,
        children = {
            { key = "bwWarnings", label = "Boss Warnings", module = "bossWarnings" },
            { key = "bwTimeline", label = "Boss Timeline", module = "bossWarnings" },
            { key = "bwBars", label = "Boss Bars", module = "bossWarnings" },
        },
    },
    {
        key = "qol",
        label = "Quality of Life",
        collapsible = true,
        children = {
            { key = "qolEditMode", label = "Edit Mode" },
            { key = "qolLootVendors", label = "Loot & Vendors" },
            { key = "qolQuests", label = "Map & Quests" },
            { key = "qolDungeonJournal", label = "Dungeon Journal" },
        },
    },
    {
        key = "cdm",
        label = "Cooldown Manager",
        collapsible = true,
        children = {
            { key = "cdmQoL", label = "Quality of Life", module = "cooldownManager" },
            { key = "essentialCooldowns", label = "Essential Cooldowns", module = "cooldownManager" },
            { key = "utilityCooldowns", label = "Utility Cooldowns", module = "cooldownManager" },
            { key = "trackedBuffs", label = "Tracked Buffs", module = "cooldownManager" },
            { key = "trackedBars", label = "Tracked Bars", module = "cooldownManager" },
            { key = "customGroup1", label = "Custom Group 1", module = "cooldownManager" },
            { key = "customGroup2", label = "Custom Group 2", module = "cooldownManager" },
            { key = "customGroup3", label = "Custom Group 3", module = "cooldownManager" },
            { key = "customGroup4", label = "Custom Group 4", module = "cooldownManager" },
            { key = "customGroup5", label = "Custom Group 5", module = "cooldownManager" },
        },
    },
    {
        key = "classAuras",
        label = "Class Auras",
        collapsible = true,
        children = {
            { key = "classAurasDeathKnight", label = "Death Knight", module = "classAuras" },
            { key = "classAurasDemonHunter", label = "Demon Hunter", module = "classAuras" },
            { key = "classAurasDruid",       label = "Druid", module = "classAuras" },
            { key = "classAurasEvoker",      label = "Evoker", module = "classAuras" },
            { key = "classAurasHunter",      label = "Hunter", module = "classAuras" },
            { key = "classAurasMage",        label = "Mage", module = "classAuras" },
            { key = "classAurasMonk",        label = "Monk", module = "classAuras" },
            { key = "classAurasPaladin",     label = "Paladin", module = "classAuras" },
            { key = "classAurasPriest",      label = "Priest", module = "classAuras" },
            { key = "classAurasRogue",       label = "Rogue", module = "classAuras" },
            { key = "classAurasShaman",      label = "Shaman", module = "classAuras" },
            { key = "classAurasWarlock",     label = "Warlock", module = "classAuras" },
            { key = "classAurasWarrior",     label = "Warrior", module = "classAuras" },
        },
    },
    {
        key = "prd",
        label = "Personal Resource",
        collapsible = true,
        children = {
            { key = "prdGeneral", label = "General", module = "prd" },
            { key = "prdHealthBar", label = "Health Bar", module = "prd" },
            { key = "prdPowerBar", label = "Power Bar", module = "prd" },
            { key = "prdClassResource", label = "Class Resource", module = "prd" },
        },
    },
    {
        key = "unitFrames",
        label = "Unit Frames",
        collapsible = true,
        children = {
            -- Player and Target are three-state units (OFF / X / Z, cycled on
            -- the Features page), so each is a PAIR of children sharing a
            -- variantGroup: the group's active member is the only one shown.
            -- When the whole group is off, only the groupFallback member
            -- renders -- grayed, and with hideBadgesWhenDisabled its badge is
            -- suppressed so an OFF unit reads as plain "Player", not "Player
            -- [X]". The disabled hover tooltip already points at the Features
            -- page.
            { key = "ufPlayer", label = "Player", module = "unitFrames", moduleSubId = "Player",
                variant = "X",
                versionBadge = { label = "X", title = "Player Frame X", text = "Blizzard's own Player frame, restyled in place by Scoot." },
                variantGroup = "ufPlayer", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzPlayer", label = "Player", module = "unitFramesZ", moduleSubId = "Player",
                variant = "Z",
                versionBadge = { label = "Z", title = "Player Frame Z", text = "Scoot's own text-first Player frame, replacing Blizzard's while enabled. Positioned in Edit Mode and configured here." },
                betaBadge = true,
                variantGroup = "ufPlayer" },
            { key = "ufTarget", label = "Target", module = "unitFrames", moduleSubId = "Target",
                variant = "X",
                versionBadge = { label = "X", title = "Target Frame X", text = "Blizzard's own Target frame, restyled in place by Scoot." },
                variantGroup = "ufTarget", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzTarget", label = "Target", module = "unitFramesZ", moduleSubId = "Target",
                variant = "Z",
                versionBadge = { label = "Z", title = "Target Frame Z", text = "Scoot's own text-first Target frame, replacing Blizzard's while enabled. Positioned in Edit Mode and configured here." },
                betaBadge = true,
                variantGroup = "ufTarget" },
            { key = "ufFocus", label = "Focus", module = "unitFrames", moduleSubId = "Focus" },
            { key = "ufPet", label = "Pet", module = "unitFrames", moduleSubId = "Pet" },
            { key = "ufToT", label = "Target of Target", module = "unitFrames", moduleSubId = "TargetOfTarget" },
            { key = "ufFocusTarget", label = "Target of Focus", module = "unitFrames", moduleSubId = "FocusTarget" },
            { key = "ufBoss", label = "Boss", module = "unitFrames", moduleSubId = "Boss",
                variant = "X",
                versionBadge = { label = "X", title = "Boss Frames X", text = "Blizzard's own Boss frames, restyled in place by Scoot. All five share one configuration." },
                variantGroup = "ufBoss", groupFallback = true, hideBadgesWhenDisabled = true },
            { key = "ufzBoss", label = "Boss", module = "unitFramesZ", moduleSubId = "Boss",
                variant = "Z",
                versionBadge = { label = "Z", title = "Boss Frames Z", text = "Scoot's own text-first Boss frames, replacing Blizzard's while enabled. The five frames stack as one block you position in Edit Mode and share the configuration on this page." },
                betaBadge = true,
                variantGroup = "ufBoss" },
            -- Last row of Unit Frames, and Z-only: the X variant is configured
            -- per frame, on each frame's own page above. alwaysShow keeps the row
            -- visible while X is selected so the Z badge can still explain what
            -- this is — grayed out is exactly when someone needs to ask.
            { key = "castBarZ", label = "Cast Bars", module = "castBars", moduleSubId = "castBarZ",
                variant = "Z",
                versionBadge = { label = "Z", title = "Cast Bar Z", text = "Scoot's own cast bars, drawn as filling text instead of a bar. Positioned freely in Edit Mode and configured here." },
                betaBadge = true,
                alwaysShow = true },
        },
    },
    {
        key = "groupFrames",
        label = "Group Frames",
        collapsible = true,
        children = {
            { key = "gfParty", label = "Party Frames", module = "groupFrames", moduleSubId = "party" },
            { key = "gfRaid", label = "Raid Frames", module = "groupFrames", moduleSubId = "raid" },
            { key = "gfAuraTracking", label = "Aura Tracking", module = "groupFrames", moduleSubId = "auraTracking", betaBadge = true },
        },
    },
    {
        key = "actionBars",
        label = "Action Bars",
        collapsible = true,
        children = {
            { key = "actionBars18", label = "Action Bars 1-8", module = "actionBars" },
            { key = "petBar", label = "Pet Bar", module = "actionBars" },
            { key = "stanceBar", label = "Stance Bar", module = "actionBars" },
            { key = "microBar", label = "Micro Bar", module = "actionBars" },
            { key = "extraAbilities", label = "Extra Abilities", module = "extraAbilities" },
        },
    },
    {
        key = "buffsDebuffs",
        label = "Buffs/Debuffs",
        collapsible = true,
        children = {
            { key = "buffs", label = "Buffs", module = "buffsDebuffs", moduleSubId = "buffs" },
            { key = "debuffs", label = "Debuffs", module = "buffsDebuffs", moduleSubId = "debuffs" },
        },
    },
    {
        key = "sct",
        label = "Scrolling Combat Text",
        collapsible = true,
        children = {
            { key = "sctDamage", label = "Damage Numbers", module = "sct" },
        },
    },
    -- Reports sits last among real sections; Debug is hidden by default and
    -- only appears below it via /scoot debugmenu.
    {
        key = "reports",
        label = "Reports",
        collapsible = true,
        children = {
            { key = "reportsWidget", label = "Widget", module = "widget" },
            { key = "reportsList", label = "Config", module = "widget" },
        },
    },
    {
        key = "debug",
        label = "Debug",
        collapsible = true,
        hidden = true,  -- Hidden by default, shown via /scoot debugmenu
        children = {
            { key = "debugMenu", label = "Debug Menu" },
        },
    },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

Navigation._expandedSections = {}  -- Track which parent sections are expanded
Navigation._selectedKey = nil      -- Currently selected navigation item (nil = Home via logo)
Navigation._rows = {}              -- References to created row frames

--- Check if a module category (and optionally sub-toggle) was active at session start.
function Navigation:IsNavModuleActive(moduleCategory, moduleSubId)
    if not addon._activeModules then return true end
    if not addon._activeModules[moduleCategory] then return false end
    -- Sub-toggle check (e.g., damageMeter + damageMeterV2)
    if moduleSubId and addon._activeModuleSubs and addon._activeModuleSubs[moduleCategory] then
        local sub = addon._activeModuleSubs[moduleCategory][moduleSubId]
        if sub == false then return false end
    end
    return true
end

--- Check if every child of a collapsible parent has a module field and all are disabled.
function Navigation:AreAllChildrenModuleDisabled(navItem)
    if not navItem.collapsible or not navItem.children then return false end
    for _, child in ipairs(navItem.children) do
        if not child.module then
            return false  -- Non-module child is always active
        end
        if self:IsNavModuleActive(child.module, child.moduleSubId) then
            return false  -- At least one module-child is active
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Custom Scrollbar
--------------------------------------------------------------------------------

local function CreateScrollbar(parent, scrollFrame)
    local ar, ag, ab = Theme:GetAccentColor()

    -- Scrollbar container (with margin from right edge)
    local scrollbar = CreateFrame("Frame", nil, parent)
    scrollbar:SetWidth(SCROLLBAR_WIDTH)
    scrollbar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SCROLLBAR_RIGHT_MARGIN, -PADDING_TOP)
    scrollbar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_RIGHT_MARGIN, PADDING_TOP)

    -- Track background (subtle)
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(ar, ag, ab, 0.1)
    scrollbar._track = track

    -- Thumb (draggable part)
    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(SCROLLBAR_THUMB_MIN_HEIGHT)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(ar, ag, ab, 0.5)
    thumb._tex = thumbTex

    -- Hover effect for thumb
    thumb:SetScript("OnEnter", function(self)
        local r, g, b = Theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 0.8)
    end)

    thumb:SetScript("OnLeave", function(self)
        if not self._isDragging then
            local r, g, b = Theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    scrollbar._thumb = thumb
    scrollbar._scrollFrame = scrollFrame

    -- Calculate and update thumb size/position based on content
    local function UpdateScrollbar()
        if not scrollFrame then return end

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local trackHeight = scrollbar:GetHeight() or 1

        -- Hide scrollbar if content fits
        if contentHeight <= visibleHeight then
            scrollbar:Hide()
            return
        end

        scrollbar:Show()

        -- Calculate thumb height proportionally
        local thumbHeight = math.max(
            SCROLLBAR_THUMB_MIN_HEIGHT,
            (visibleHeight / contentHeight) * trackHeight
        )
        thumb:SetHeight(thumbHeight)

        -- Calculate thumb position based on scroll offset
        local maxScroll = contentHeight - visibleHeight
        local currentScroll = scrollFrame:GetVerticalScroll() or 0
        local scrollPercent = maxScroll > 0 and (currentScroll / maxScroll) or 0

        local maxThumbOffset = trackHeight - thumbHeight
        local thumbOffset = scrollPercent * maxThumbOffset

        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -thumbOffset)
    end

    scrollbar.Update = UpdateScrollbar

    -- Dragging the thumb
    local dragStartY, dragStartScroll

    thumb:SetScript("OnDragStart", function(self)
        self._isDragging = true
        local r, g, b = Theme:GetAccentColor()
        self._tex:SetColorTexture(r, g, b, 1)

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        dragStartY = cursorY / scale
        dragStartScroll = scrollFrame:GetVerticalScroll() or 0
    end)

    thumb:SetScript("OnDragStop", function(self)
        self._isDragging = false
        if not self:IsMouseOver() then
            local r, g, b = Theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.5)
        else
            local r, g, b = Theme:GetAccentColor()
            self._tex:SetColorTexture(r, g, b, 0.8)
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cursorY = cursorY / scale

        local deltaY = dragStartY - cursorY  -- Inverted because Y increases downward in scroll

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local trackHeight = scrollbar:GetHeight() or 1
        local thumbHeight = thumb:GetHeight()

        local maxScroll = contentHeight - visibleHeight
        local maxThumbOffset = trackHeight - thumbHeight

        if maxThumbOffset > 0 and maxScroll > 0 then
            local scrollDelta = (deltaY / maxThumbOffset) * maxScroll
            local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + scrollDelta))
            scrollFrame:SetVerticalScroll(newScroll)
        end
    end)

    -- Click on track to jump
    scrollbar:EnableMouse(true)
    scrollbar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cursorY = cursorY / scale

        local selfBottom = self:GetBottom() or 0
        local clickY = cursorY - selfBottom
        local trackHeight = self:GetHeight() or 1

        local clickPercent = 1 - (clickY / trackHeight)  -- Inverted

        local contentHeight = 0
        local scrollChild = scrollFrame:GetScrollChild()
        if scrollChild then
            contentHeight = scrollChild:GetHeight() or 0
        end

        local visibleHeight = scrollFrame:GetHeight() or 1
        local maxScroll = contentHeight - visibleHeight

        if maxScroll > 0 then
            local newScroll = clickPercent * maxScroll
            scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, newScroll)))
        end
    end)

    -- Subscribe to theme updates
    Theme:Subscribe("Scrollbar_" .. tostring(scrollbar), function(r, g, b)
        if scrollbar._track then
            scrollbar._track:SetColorTexture(r, g, b, 0.1)
        end
        if thumb._tex and not thumb._isDragging then
            thumb._tex:SetColorTexture(r, g, b, 0.5)
        end
    end)

    return scrollbar
end

--------------------------------------------------------------------------------
-- Navigation Frame Creation
--------------------------------------------------------------------------------

function Navigation:Create(parent)
    if not parent then return nil end

    -- Create main navigation frame (no background - inherits from parent)
    local navFrame = CreateFrame("Frame", "ScootNavFrame", parent)
    navFrame:SetWidth(NAV_WIDTH)
    navFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", Theme.BORDER_WIDTH, -(80 + Theme.BORDER_WIDTH))
    navFrame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", Theme.BORDER_WIDTH, Theme.BORDER_WIDTH)

    -- Right border separator
    local separator = navFrame:CreateTexture(nil, "BORDER")
    separator:SetWidth(1)
    separator:SetPoint("TOPRIGHT", navFrame, "TOPRIGHT", 0, 0)
    separator:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", 0, 0)
    local ar, ag, ab = Theme:GetAccentColor()
    separator:SetColorTexture(ar, ag, ab, 0.4)
    navFrame._separator = separator

    -- Custom scroll frame (no template - built from scratch)
    local scrollFrame = CreateFrame("ScrollFrame", "ScootNavScrollFrame", navFrame)
    scrollFrame:SetPoint("TOPLEFT", navFrame, "TOPLEFT", PADDING_LEFT, -PADDING_TOP)
    scrollFrame:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", -(SCROLLBAR_RIGHT_MARGIN + SCROLLBAR_WIDTH + 4), PADDING_TOP)
    scrollFrame:EnableMouseWheel(true)

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local scrollChild = self:GetScrollChild()
        local contentHeight = scrollChild and scrollChild:GetHeight() or 0
        local visibleHeight = self:GetHeight() or 1
        local maxScroll = math.max(0, contentHeight - visibleHeight)

        local step = ROW_HEIGHT * 3  -- Scroll 3 rows at a time
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))

        self:SetVerticalScroll(newScroll)

        -- Update custom scrollbar
        if navFrame._scrollbar and navFrame._scrollbar.Update then
            navFrame._scrollbar:Update()
        end
    end)

    -- Content frame that will hold all nav items
    local contentFrame = CreateFrame("Frame", "ScootNavContent", scrollFrame)
    contentFrame:SetWidth(scrollFrame:GetWidth() or (NAV_WIDTH - PADDING_LEFT - SCROLLBAR_RIGHT_MARGIN - SCROLLBAR_WIDTH - 4))
    scrollFrame:SetScrollChild(contentFrame)
    navFrame._content = contentFrame
    navFrame._scrollFrame = scrollFrame

    -- Create custom scrollbar
    local scrollbar = CreateScrollbar(navFrame, scrollFrame)
    navFrame._scrollbar = scrollbar

    -- Update scrollbar when scroll changes
    scrollFrame:SetScript("OnScrollRangeChanged", function()
        if scrollbar and scrollbar.Update then
            scrollbar:Update()
        end
    end)

    -- Initialize expanded state (start collapsed)
    self:InitializeExpandedState()

    -- Build navigation rows
    self:BuildRows(contentFrame)

    -- Initial scrollbar update
    C_Timer.After(0.1, function()
        if scrollbar and scrollbar.Update then
            scrollbar:Update()
        end
    end)

    -- Store reference
    self._frame = navFrame

    -- Subscribe to theme updates
    Theme:Subscribe("Navigation_Frame", function(r, g, b)
        if navFrame._separator then
            navFrame._separator:SetColorTexture(r, g, b, 0.4)
        end
        self:UpdateRowColors()
    end)

    return navFrame
end

--------------------------------------------------------------------------------
-- Initialize Expanded State
--------------------------------------------------------------------------------

function Navigation:InitializeExpandedState()
    for _, parent in ipairs(self.NavModel) do
        if parent.collapsible then
            self._expandedSections[parent.key] = false
        end
    end
end

--------------------------------------------------------------------------------
-- Build Navigation Rows
--------------------------------------------------------------------------------

function Navigation:BuildRows(contentFrame)
    if not contentFrame then return end

    -- Clear existing rows
    for _, row in ipairs(self._rows) do
        if row and row.Hide then
            row:Hide()
            row:SetParent(nil)
        end
    end
    self._rows = {}

    local yOffset = 0
    local rowIndex = 0

    -- Build sorted iteration order: disabled parent groups sink to bottom
    local debugEnabled = addon.db and addon.db.profile and addon.db.profile.debugMenuEnabled
    local enabledIndices = {}
    local disabledIndices = {}
    for i, parent in ipairs(self.NavModel) do
        local skip = parent.hidden and not debugEnabled
        if not skip and parent.collapsible and self:AreAllChildrenModuleDisabled(parent) then
            disabledIndices[#disabledIndices + 1] = i
        elseif not skip then
            enabledIndices[#enabledIndices + 1] = i
        end
    end
    for _, idx in ipairs(disabledIndices) do
        enabledIndices[#enabledIndices + 1] = idx
    end

    for _, parentIdx in ipairs(enabledIndices) do
        local parent = self.NavModel[parentIdx]
        rowIndex = rowIndex + 1

        -- Check if all children's modules are disabled (grays out the parent)
        local isParentModuleDisabled = self:AreAllChildrenModuleDisabled(parent)
        if isParentModuleDisabled then
            self._expandedSections[parent.key] = false
        end

        -- Create parent row
        local parentRow = self:CreateParentRow(contentFrame, parent, yOffset, isParentModuleDisabled)
        self._rows[rowIndex] = parentRow
        yOffset = yOffset - PARENT_ROW_HEIGHT

        -- Create child rows if parent is collapsible and has children
        if parent.collapsible and parent.children then
            local isExpanded = self._expandedSections[parent.key]

            -- variantGroup pass: children sharing a variantGroup are alternative
            -- pages for one three-state unit (OFF/X/Z), spanning two categories
            -- -- which is why the mutuallyExclusive filter below cannot serve
            -- them. Among members, only the active one shows; when the whole
            -- group is off, only the groupFallback member shows (grayed, via
            -- the normal disabled path).
            local groupActive = nil
            for _, child in ipairs(parent.children) do
                if child.variantGroup and self:IsNavModuleActive(child.module, child.moduleSubId) then
                    groupActive = groupActive or {}
                    groupActive[child.variantGroup] = true
                end
            end

            -- Pre-filter: skip inactive variants for mutuallyExclusive categories
            local visibleChildren = {}
            for _, child in ipairs(parent.children) do
                local catDef = child.module and addon.MODULE_CATEGORIES and addon.MODULE_CATEGORIES[child.module]
                local isMutuallyExclusive = catDef and catDef.mutuallyExclusive
                if child.variantGroup then
                    if groupActive and groupActive[child.variantGroup] then
                        if self:IsNavModuleActive(child.module, child.moduleSubId) then
                            visibleChildren[#visibleChildren + 1] = child
                        end
                    elseif child.groupFallback then
                        visibleChildren[#visibleChildren + 1] = child
                    end
                elseif isMutuallyExclusive and not child.alwaysShow then
                    -- Only show the active variant: the variants of a mutually
                    -- exclusive category are alternative pages for one feature,
                    -- so showing both would read as duplicates. alwaysShow opts
                    -- out for a section that has no other variant page to fall
                    -- back on, keeping the row visible but grayed.
                    if self:IsNavModuleActive(child.module, child.moduleSubId) then
                        visibleChildren[#visibleChildren + 1] = child
                    end
                else
                    visibleChildren[#visibleChildren + 1] = child
                end
            end

            for childIdx, child in ipairs(visibleChildren) do
                rowIndex = rowIndex + 1
                local isLastChild = (childIdx == #visibleChildren)
                local isModuleDisabled = child.module and not self:IsNavModuleActive(child.module, child.moduleSubId)
                local childRow = self:CreateChildRow(
                    contentFrame,
                    child,
                    yOffset,
                    isLastChild,
                    isExpanded,
                    #visibleChildren,
                    childIdx,
                    isModuleDisabled
                )
                self._rows[rowIndex] = childRow

                if isExpanded then
                    yOffset = yOffset - ROW_HEIGHT
                end
            end
        end
    end

    -- Set content frame height
    local totalHeight = math.abs(yOffset) + PADDING_TOP
    contentFrame:SetHeight(math.max(totalHeight, 100))

    -- Update scrollbar
    if self._frame and self._frame._scrollbar and self._frame._scrollbar.Update then
        self._frame._scrollbar:Update()
    end
end

--------------------------------------------------------------------------------
-- Create Parent Row (Section header - no tree lines)
--------------------------------------------------------------------------------

function Navigation:CreateParentRow(parent, navItem, yOffset, isModuleDisabled)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PARENT_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Store metadata
    row._key = navItem.key
    row._isParent = true
    row._isCollapsible = navItem.collapsible
    row._isModuleDisabled = isModuleDisabled
    row._navItem = navItem

    local ar, ag, ab = Theme:GetAccentColor()

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.15)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Selection background
    local selectBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    selectBg:SetAllPoints()
    selectBg:SetColorTexture(ar, ag, ab, 0.25)
    selectBg:Hide()
    row._selectBg = selectBg

    -- Expand/collapse indicator (▶/▼) - only for collapsible
    local indicator = row:CreateFontString(nil, "OVERLAY")
    local fontPath = Theme:GetFont("BUTTON")
    indicator:SetFont(fontPath, 10, "")
    indicator:SetPoint("LEFT", row, "LEFT", 4, 0)

    if navItem.collapsible then
        local isExpanded = self._expandedSections[navItem.key]
        indicator:SetText(isExpanded and "▼" or "▶")
        indicator:SetTextColor(ar, ag, ab, 0.7)
    else
        indicator:SetText("")
    end
    row._indicator = indicator

    -- Label text
    local label = row:CreateFontString(nil, "OVERLAY")
    local labelSize = navItem.fontSize or 12
    Theme:ApplyLabelFont(label, labelSize)
    if navItem.collapsible then
        label:SetPoint("LEFT", indicator, "RIGHT", 6, 0)
    else
        label:SetPoint("LEFT", row, "LEFT", 8, 0)
    end
    label:SetText(navItem.label)
    row._label = label

    if isModuleDisabled then
        -- Disabled: gray out label + indicator, show tooltip on hover
        local dimR, dimG, dimB = Theme:GetDimTextColor()
        label:SetTextColor(dimR, dimG, dimB, 0.35)
        if navItem.collapsible then
            indicator:SetTextColor(dimR, dimG, dimB, 0.35)
        end

        row:SetScript("OnEnter", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                local tip = C:GetOrCreateTooltip()
                tip:SetContent("Module Disabled", "Enable this module on the Features page to access its settings.")
                tip:ShowAtAnchor(self, "TOPLEFT", "TOPRIGHT", 8, 0)
            end
        end)
        row:SetScript("OnLeave", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                C:GetOrCreateTooltip():Hide()
            end
        end)
        row:SetScript("OnClick", nil)
    else
        -- Hover effect
        row:SetScript("OnEnter", function(self)
            local r, g, b = Theme:GetAccentColor()
            self._hoverBg:SetColorTexture(r, g, b, 0.15)
            self._hoverBg:Show()
            self._label:SetTextColor(1, 1, 1, 1)
        end)

        row:SetScript("OnLeave", function(self)
            self._hoverBg:Hide()
            local r, g, b = Theme:GetAccentColor()
            if Navigation._selectedKey == self._key then
                self._label:SetTextColor(1, 1, 1, 1)
            else
                self._label:SetTextColor(r, g, b, 1)
            end
        end)

        -- Click handler
        row:SetScript("OnClick", function(self, button)
            if self._isCollapsible then
                Navigation:ToggleSection(self._key)
            else
                Navigation:SelectItem(self._key)
            end
        end)
    end

    self:UpdateRowSelectionState(row)
    return row
end

--------------------------------------------------------------------------------
-- Create Child Row (with texture-based tree lines)
--------------------------------------------------------------------------------

function Navigation:CreateChildRow(parent, navItem, yOffset, isLastChild, isVisible, totalChildren, childIndex, isModuleDisabled)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Store metadata
    row._key = navItem.key
    row._isParent = false
    row._navItem = navItem
    row._isLastChild = isLastChild
    row._isModuleDisabled = isModuleDisabled

    local ar, ag, ab = Theme:GetAccentColor()

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.15)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Selection background
    local selectBg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    selectBg:SetAllPoints()
    selectBg:SetColorTexture(ar, ag, ab, 0.25)
    selectBg:Hide()
    row._selectBg = selectBg

    -- Tree lines using textures (not text characters)
    local treeLines = {}

    -- Vertical line (from parent down to this item)
    local vertLine = row:CreateTexture(nil, "ARTWORK")
    vertLine:SetWidth(TREE_LINE_WIDTH)
    vertLine:SetColorTexture(ar, ag, ab, TREE_LINE_COLOR_ALPHA)
    vertLine:SetPoint("TOPLEFT", row, "TOPLEFT", 10, 0)

    if isLastChild then
        -- For last child, vertical line goes from top to center (where horizontal line is)
        vertLine:SetPoint("BOTTOM", row, "LEFT", 10, 0)
    else
        -- For other children, vertical line goes full height
        vertLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
    end
    treeLines.vertical = vertLine

    -- Horizontal line (branch to label)
    local horizLine = row:CreateTexture(nil, "ARTWORK")
    horizLine:SetHeight(TREE_LINE_WIDTH)
    horizLine:SetColorTexture(ar, ag, ab, TREE_LINE_COLOR_ALPHA)
    horizLine:SetPoint("LEFT", row, "LEFT", 10 + TREE_LINE_WIDTH, 0)
    horizLine:SetWidth(TREE_LINE_HORIZONTAL_LENGTH - TREE_LINE_WIDTH)
    treeLines.horizontal = horizLine

    row._treeLines = treeLines

    -- Label text
    local label = row:CreateFontString(nil, "OVERLAY")
    Theme:ApplyValueFont(label, 11)
    label:SetPoint("LEFT", row, "LEFT", CHILD_INDENT + 6, 0)
    label:SetText(navItem.label)
    row._label = label

    -- Version badge info icon (e.g., "X" / "Y" with variant color).
    -- hideBadgesWhenDisabled: a variantGroup's OFF fallback row must read as
    -- plain "Player", not "Player [X]" -- no mode is in effect, so no letter.
    local suppressBadges = isModuleDisabled and navItem.hideBadgesWhenDisabled
    if navItem.versionBadge and not suppressBadges
        and addon.UI and addon.UI.Controls and addon.UI.Controls.CreateInfoIcon then
        -- Use variant color if available (X=green, Y=yellow, Z=blue)
        local badgeColor = nil
        if navItem.variant and addon.VARIANT_COLORS and addon.VARIANT_COLORS[navItem.variant] then
            badgeColor = addon.VARIANT_COLORS[navItem.variant]
        end

        -- For mutually exclusive and mode-cycled entries, append switch
        -- instructions to the tooltip
        local catDef = navItem.module and addon.MODULE_CATEGORIES and addon.MODULE_CATEGORIES[navItem.module]
        local tooltipSuffix = ""
        if catDef and catDef.mutuallyExclusive then
            tooltipSuffix = "\n\nSwitch variants on the Features page."
        elseif navItem.variantGroup then
            tooltipSuffix = "\n\nSwitch modes on the Features page."
        end

        row._versionBadge = addon.UI.Controls:CreateInfoIcon({
            parent = row,
            tooltipTitle = navItem.versionBadge.title or "",
            tooltipText = (navItem.versionBadge.text or "") .. tooltipSuffix,
            size = 18,
            iconType = "info",
            customText = navItem.versionBadge.label or "",
            colorOverride = badgeColor,
        })
        -- Adjust font size for badge label
        if row._versionBadge._iconText then
            local fontPath = row._versionBadge._iconText:GetFont()
            if fontPath then
                pcall(row._versionBadge._iconText.SetFont, row._versionBadge._iconText, fontPath, 8, "OUTLINE")
            end
        end
        row._versionBadge:SetPoint("LEFT", label, "RIGHT", 4, 0)
    end

    -- Beta badge (red "beta" label)
    if navItem.betaBadge and not suppressBadges
        and addon.UI and addon.UI.Controls and addon.UI.Controls.CreateInfoIcon then
        local BETA_COLOR = { 0.9, 0.2, 0.2 }
        local betaBadge = addon.UI.Controls:CreateInfoIcon({
            parent = row,
            tooltipTitle = "Beta Feature",
            tooltipText = "This feature is new and may need additional testing. Please report any issues you encounter.",
            size = 18,
            width = 32,
            iconType = "info",
            customText = "beta",
            colorOverride = BETA_COLOR,
        })
        if betaBadge._iconText then
            local fontPath = betaBadge._iconText:GetFont()
            if fontPath then
                pcall(betaBadge._iconText.SetFont, betaBadge._iconText, fontPath, 8, "OUTLINE")
            end
        end
        local anchorFrame = row._versionBadge or label
        betaBadge:SetPoint("LEFT", anchorFrame, "RIGHT", 4, 0)
        row._betaBadge = betaBadge
    end

    if isModuleDisabled then
        -- Disabled module: gray out label and tree lines, no interaction
        local dimR, dimG, dimB = Theme:GetDimTextColor()
        label:SetTextColor(dimR, dimG, dimB, 0.35)
        for _, line in pairs(treeLines) do
            line:SetColorTexture(ar, ag, ab, TREE_LINE_COLOR_ALPHA * 0.3)
        end
        if row._versionBadge and row._versionBadge._iconText then
            row._versionBadge._iconText:SetTextColor(dimR, dimG, dimB, 0.35)
            for _, tex in pairs(row._versionBadge._border) do tex:SetColorTexture(dimR, dimG, dimB, 0.15) end
        end
        if row._betaBadge and row._betaBadge._iconText then
            row._betaBadge._iconText:SetTextColor(dimR, dimG, dimB, 0.35)
            for _, tex in pairs(row._betaBadge._border) do tex:SetColorTexture(dimR, dimG, dimB, 0.15) end
        end
        row:SetScript("OnEnter", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                local tip = C:GetOrCreateTooltip()
                if navItem.variantGroup then
                    -- A three-state unit sitting on OFF: "module disabled" would
                    -- be the wrong mental model -- nothing is broken, the unit
                    -- just has no mode selected.
                    tip:SetContent("Frame Off",
                        "Scoot is leaving this frame alone. Choose the X or Z mode on the Features page to configure it.")
                else
                    tip:SetContent("Module Disabled", "Enable this module on the Features page to access its settings.")
                end
                tip:ShowAtAnchor(self, "TOPLEFT", "TOPRIGHT", 8, 0)
            end
        end)
        row:SetScript("OnLeave", function(self)
            local C = addon.UI and addon.UI.Controls
            if C and C.GetOrCreateTooltip then
                C:GetOrCreateTooltip():Hide()
            end
        end)
        row:SetScript("OnClick", nil)
    else
        -- Hover effect
        row:SetScript("OnEnter", function(self)
            local r, g, b = Theme:GetAccentColor()
            self._hoverBg:SetColorTexture(r, g, b, 0.15)
            self._hoverBg:Show()
            self._label:SetTextColor(r, g, b, 1)
        end)

        row:SetScript("OnLeave", function(self)
            self._hoverBg:Hide()
            if Navigation._selectedKey == self._key then
                local r, g, b = Theme:GetAccentColor()
                self._label:SetTextColor(r, g, b, 1)
            else
                self._label:SetTextColor(1, 1, 1, 1)
            end
        end)

        -- Click handler
        row:SetScript("OnClick", function(self, button)
            Navigation:SelectItem(self._key)
        end)
    end

    -- Set visibility
    if isVisible then
        row:Show()
    else
        row:Hide()
    end

    self:UpdateRowSelectionState(row)
    return row
end

--------------------------------------------------------------------------------
-- Toggle Section Expand/Collapse
--------------------------------------------------------------------------------

function Navigation:ToggleSection(parentKey)
    if not parentKey then return end

    self._expandedSections[parentKey] = not self._expandedSections[parentKey]

    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

--------------------------------------------------------------------------------
-- Select Navigation Item
--------------------------------------------------------------------------------

function Navigation:SelectItem(key)
    if not key then return end

    local previousKey = self._selectedKey
    self._selectedKey = key

    for _, row in ipairs(self._rows) do
        if row and row._key then
            self:UpdateRowSelectionState(row)
        end
    end

    if self._onSelectCallback then
        self._onSelectCallback(key, previousKey)
    end
end

--------------------------------------------------------------------------------
-- Update Row Selection State
--------------------------------------------------------------------------------

function Navigation:UpdateRowSelectionState(row)
    if not row or not row._key then return end
    if row._isModuleDisabled then return end

    local isSelected = (self._selectedKey == row._key)
    local ar, ag, ab = Theme:GetAccentColor()

    if isSelected then
        row._selectBg:SetColorTexture(ar, ag, ab, 0.25)
        row._selectBg:Show()
        if row._isParent then
            row._label:SetTextColor(1, 1, 1, 1)
        else
            row._label:SetTextColor(ar, ag, ab, 1)
        end
    else
        row._selectBg:Hide()
        if row._isParent then
            row._label:SetTextColor(ar, ag, ab, 1)
        else
            row._label:SetTextColor(1, 1, 1, 1)
        end
    end

    if self.UpdateJumpingLettersColor then
        self:UpdateJumpingLettersColor(row)
    end
end

--------------------------------------------------------------------------------
-- Update All Row Colors (theme change)
--------------------------------------------------------------------------------

function Navigation:UpdateRowColors()
    local ar, ag, ab = Theme:GetAccentColor()

    for _, row in ipairs(self._rows) do
        if row then
            if row._indicator then
                row._indicator:SetTextColor(ar, ag, ab, 0.7)
            end

            if row._hoverBg then
                row._hoverBg:SetColorTexture(ar, ag, ab, 0.15)
            end
            if row._selectBg then
                row._selectBg:SetColorTexture(ar, ag, ab, 0.25)
            end

            -- Update tree line colors for child rows
            if row._treeLines then
                local alpha = row._isModuleDisabled and (TREE_LINE_COLOR_ALPHA * 0.3) or TREE_LINE_COLOR_ALPHA
                for _, line in pairs(row._treeLines) do
                    line:SetColorTexture(ar, ag, ab, alpha)
                end
            end

            -- Re-apply dim colors for disabled rows (parent or child)
            if row._isModuleDisabled then
                local dimR, dimG, dimB = Theme:GetDimTextColor()
                if row._label then
                    row._label:SetTextColor(dimR, dimG, dimB, 0.35)
                end
                if row._indicator then
                    row._indicator:SetTextColor(dimR, dimG, dimB, 0.35)
                end
            end

            self:UpdateRowSelectionState(row)
        end
    end
end

--------------------------------------------------------------------------------
-- Expand All / Collapse All
--------------------------------------------------------------------------------

function Navigation:ExpandAll()
    for _, parent in ipairs(self.NavModel) do
        if parent.collapsible then
            self._expandedSections[parent.key] = true
        end
    end

    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

function Navigation:CollapseAll()
    for _, parent in ipairs(self.NavModel) do
        if parent.collapsible then
            self._expandedSections[parent.key] = false
        end
    end

    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

--------------------------------------------------------------------------------
-- Set Selection Callback
--------------------------------------------------------------------------------

function Navigation:SetOnSelectCallback(callback)
    if type(callback) == "function" then
        self._onSelectCallback = callback
    end
end

--------------------------------------------------------------------------------
-- Get Current Selection
--------------------------------------------------------------------------------

function Navigation:GetSelectedKey()
    return self._selectedKey
end

--------------------------------------------------------------------------------
-- Get Navigation Frame
--------------------------------------------------------------------------------

function Navigation:GetFrame()
    return self._frame
end

--------------------------------------------------------------------------------
-- Rebuild Navigation (e.g., when debug menu visibility changes)
--------------------------------------------------------------------------------

function Navigation:Rebuild()
    if self._frame and self._frame._content then
        self:BuildRows(self._frame._content)
    end
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function Navigation:Cleanup()
    if self.CleanupJumpingLetters then
        self:CleanupJumpingLetters()
    end

    Theme:Unsubscribe("Navigation_Frame")

    for _, row in ipairs(self._rows) do
        if row then
            row:Hide()
            row:SetParent(nil)
        end
    end

    self._rows = {}
    self._frame = nil
end
