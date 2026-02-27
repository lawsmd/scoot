-- RaidRenderer.lua - Raid Frames TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.GroupFrames = addon.UI.GroupFrames or {}
local GF = addon.UI.GroupFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "gfRaid"

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function ensureDB()
    return GF.ensureRaidDB()
end

local function ensureTextDB(key)
    return GF.ensureRaidTextDB(key)
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

local function applyStyles()
    GF.applyRaidStyles()
end

local function applyText()
    GF.applyRaidText()
end

--------------------------------------------------------------------------------
-- Edit Mode Helpers
--------------------------------------------------------------------------------

local function getRaidFrame()
    return GF.getRaidFrame()
end

local function getEditModeSetting(settingId)
    local frame = getRaidFrame()
    return GF.getEditModeSetting(frame, settingId)
end

local function setEditModeSetting(settingId, value, options)
    local frame = getRaidFrame()
    GF.setEditModeSetting(frame, settingId, value, options)
end

--------------------------------------------------------------------------------
-- Shared Tab Builders
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn)
    inner:AddDualBarStyleRow({
        label = "Foreground",
        getTexture = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "Texture"] or "default"
        end,
        setTexture = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "Texture"] = v or "default"
            applyFn()
        end,
        colorValues = GF.healthColorValues,
        colorOrder = GF.healthColorOrder,
        colorInfoIcons = GF.healthColorInfoIcons,
        getColorMode = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "ColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "ColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureDB() or {}
            local c = t[barPrefix .. "Tint"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "Tint"] = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
        end,
        customColorValue = "custom",
        hasAlpha = true,
    })

    inner:AddSpacer(8)

    inner:AddDualBarStyleRow({
        label = "Background",
        getTexture = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "BackgroundTexture"] or "default"
        end,
        setTexture = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundTexture"] = v or "default"
            applyFn()
        end,
        colorValues = GF.bgColorValues,
        colorOrder = GF.bgColorOrder,
        getColorMode = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "BackgroundColorMode"] or "default"
        end,
        setColorMode = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureDB() or {}
            local c = t[barPrefix .. "BackgroundTint"] or {0, 0, 0, 1}
            return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundTint"] = {r or 0, g or 0, b or 0, a or 1}
            applyFn()
        end,
        customColorValue = "custom",
        hasAlpha = true,
    })

    -- Background Opacity
    inner:AddSlider({
        label = "Background Opacity",
        min = 0,
        max = 100,
        step = 1,
        get = function()
            local t = ensureDB() or {}
            return tonumber(t[barPrefix .. "BackgroundOpacity"]) or 50
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundOpacity"] = tonumber(v) or 50
            applyFn()
        end,
    })

    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn)
    -- Hide Realm Name toggle (only for Player Name)
    if textKey == "textPlayerName" then
        inner:AddToggle({
            label = "Hide Realm Name",
            description = "Shows only the player name without server (e.g., 'Player' instead of 'Player-Realm')",
            get = function()
                local s = ensureTextDB(textKey) or {}
                return not not s.hideRealm
            end,
            set = function(v)
                local t = ensureDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].hideRealm = v and true or false
                applyFn()
            end,
        })
    end

    -- Show Groups as Numbers Only toggle (only for Group Numbers)
    if textKey == "textGroupNumbers" then
        inner:AddToggle({
            label = "Show as Numbers Only",
            description = "Display '1', '2' instead of 'Group 1', 'Group 2'. Auto-centers based on orientation.",
            get = function()
                local t = ensureDB() or {}
                return t.groupTitleNumbersOnly == true
            end,
            set = function(v)
                local t = ensureDB()
                if not t then return end
                t.groupTitleNumbersOnly = v or nil  -- nil when false (Zero-Touch)
                applyFn()
            end,
            infoIcon = GF.TOOLTIPS.groupTitleNumbersOnly,
        })
    end

    -- Font
    inner:AddFontSelector({
        label = "Font",
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.fontFace or "FRIZQT__"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].fontFace = v
            applyFn()
        end,
    })

    -- Style
    inner:AddSelector({
        label = "Style",
        values = GF.fontStyleValues,
        order = GF.fontStyleOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.style or "OUTLINE"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].style = v
            applyFn()
        end,
    })

    -- Size
    inner:AddSlider({
        label = "Size",
        min = 6,
        max = 32,
        step = 1,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return tonumber(s.size) or 12
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].size = tonumber(v) or 12
            applyFn()
        end,
    })

    -- Color
    inner:AddSelectorColorPicker({
        label = "Color",
        values = GF.fontColorValues,
        order = GF.fontColorOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.colorMode or "default"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].colorMode = v or "default"
            applyFn()
        end,
        getColor = function()
            local s = ensureTextDB(textKey) or {}
            local c = s.color or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].color = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    -- Alignment (9-way anchor)
    inner:AddSelector({
        label = "Alignment",
        values = GF.anchorValues,
        order = GF.anchorOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.anchor or "TOPLEFT"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].anchor = v or "TOPLEFT"
            applyFn()
        end,
    })

    -- Offset X/Y
    inner:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X",
            min = -50,
            max = 50,
            step = 1,
            get = function()
                local s = ensureTextDB(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.x) or 0
            end,
            set = function(v)
                local t = ensureDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.x = tonumber(v) or 0
                applyFn()
            end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -50,
            max = 50,
            step = 1,
            get = function()
                local s = ensureTextDB(textKey) or {}
                local o = s.offset or {}
                return tonumber(o.y) or 0
            end,
            set = function(v)
                local t = ensureDB()
                if not t then return end
                t[textKey] = t[textKey] or {}
                t[textKey].offset = t[textKey].offset or {}
                t[textKey].offset.y = tonumber(v) or 0
                applyFn()
            end,
        },
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function GF.RenderRaid(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        GF.RenderRaid(panel, scrollContent)
    end)

    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType

    local isSeparateGroups = GF.isRaidSeparateGroups()
    local isCombineGroups = not isSeparateGroups

    ----------------------------------------------------------------------------
    -- Collapsible Section: Positioning & Sorting
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Positioning & Sorting",
        componentId = COMPONENT_ID,
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if EM and EM.RaidGroupDisplayType and RGD and #GF.raidGroupsOrder > 0 then
                inner:AddSelector({
                    label = "Groups",
                    values = GF.raidGroupsValues,
                    order = GF.raidGroupsOrder,
                    get = function()
                        return getEditModeSetting(EM.RaidGroupDisplayType) or RGD.SeparateGroupsVertical
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            setEditModeSetting(EM.RaidGroupDisplayType, v, {
                                suspendDuration = 0.25,
                            })
                            -- Re-render to show/hide conditional controls
                            C_Timer.After(0.3, function()
                                GF.RenderRaid(panel, scrollContent)
                            end)
                        end)
                    end,
                })
            end

            if isCombineGroups then
                if EM and EM.SortPlayersBy then
                    inner:AddSelector({
                        label = "Sort By",
                        values = GF.raidSortByValues,
                        order = GF.raidSortByOrder,
                        get = function()
                            return getEditModeSetting(EM.SortPlayersBy) or 0
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                setEditModeSetting(EM.SortPlayersBy, v, {
                                    suspendDuration = 0.25,
                                })
                            end)
                        end,
                        infoIcon = GF.TOOLTIPS.sortBy,
                    })
                end

                if EM and EM.RowSize then
                    inner:AddSlider({
                        label = "Column Size",
                        description = "Number of frames per row/column.",
                        min = 2,
                        max = 10,
                        step = 1,
                        get = function()
                            return getEditModeSetting(EM.RowSize) or 5
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                setEditModeSetting(EM.RowSize, v, {
                                    suspendDuration = 0.25,
                                })
                            end)
                        end,
                        infoIcon = GF.TOOLTIPS.columnSize,
                    })
                end
            else
                inner:AddDescription("Sort By and Column Size options are only available when Groups is set to 'Combine Groups'.")
            end

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Sizing
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = COMPONENT_ID,
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if EM and EM.FrameWidth then
                inner:AddSlider({
                    label = "Frame Width",
                    min = 72,
                    max = 144,
                    step = 2,
                    get = function()
                        return getEditModeSetting(EM.FrameWidth) or 72
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            setEditModeSetting(EM.FrameWidth, v, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })
            end

            if EM and EM.FrameHeight then
                inner:AddSlider({
                    label = "Frame Height",
                    min = 36,
                    max = 72,
                    step = 2,
                    get = function()
                        return getEditModeSetting(EM.FrameHeight) or 36
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            setEditModeSetting(EM.FrameHeight, v, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })
            end

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Style
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Style",
        componentId = COMPONENT_ID,
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            buildStyleTab(inner, "healthBar", applyStyles)
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Border (Separate Groups only)
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Border",
        componentId = COMPONENT_ID,
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if isSeparateGroups then
                if EM and EM.DisplayBorder then
                    inner:AddToggle({
                        label = "Display Border",
                        description = "Shows Blizzard's default border around each raid GROUP.",
                        get = function()
                            local v = getEditModeSetting(EM.DisplayBorder)
                            return v and v ~= 0
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                setEditModeSetting(EM.DisplayBorder, v and 1 or 0, {
                                    suspendDuration = 0.25,
                                })
                            end)
                        end,
                        infoIcon = GF.TOOLTIPS.displayBorderRaid,
                    })
                end
            else
                inner:AddDescription("Display Border is only available when Groups is set to 'Separate Groups'.")
            end

            inner:AddSpacer(12)
            inner:AddLabel("Health Bar Borders")

            inner:AddBarBorderSelector({
                label = "Border Style",
                includeNone = true,
                get = function()
                    local cfg = ensureDB() or {}
                    return cfg.healthBarBorderStyle or "none"
                end,
                set = function(v)
                    local cfg = ensureDB()
                    if not cfg then return end
                    cfg.healthBarBorderStyle = v or "none"
                    GF.applyRaidHealthBarBorders()
                end,
            })

            inner:AddToggleColorPicker({
                label = "Border Tint",
                get = function()
                    local cfg = ensureDB() or {}
                    return not not cfg.healthBarBorderTintEnable
                end,
                set = function(v)
                    local cfg = ensureDB()
                    if not cfg then return end
                    cfg.healthBarBorderTintEnable = not not v
                    GF.applyRaidHealthBarBorders()
                end,
                getColor = function()
                    local cfg = ensureDB() or {}
                    local c = cfg.healthBarBorderTintColor or {1, 1, 1, 1}
                    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end,
                setColor = function(r, g, b, a)
                    local cfg = ensureDB()
                    if not cfg then return end
                    cfg.healthBarBorderTintColor = {r or 1, g or 1, b or 1, a or 1}
                    GF.applyRaidHealthBarBorders()
                end,
                hasAlpha = true,
            })

            inner:AddSlider({
                label = "Border Thickness",
                min = 1,
                max = 8,
                step = 0.5,
                precision = 1,
                get = function()
                    local cfg = ensureDB() or {}
                    return tonumber(cfg.healthBarBorderThickness) or 1
                end,
                set = function(v)
                    local cfg = ensureDB()
                    if not cfg then return end
                    cfg.healthBarBorderThickness = tonumber(v) or 1
                    GF.applyRaidHealthBarBorders()
                end,
            })

            inner:AddDualSlider({
                label = "Border Inset",
                sliderA = {
                    axisLabel = "H", min = -4, max = 4, step = 1,
                    get = function()
                        local cfg = ensureDB() or {}
                        return tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                    end,
                    set = function(v)
                        local cfg = ensureDB()
                        if not cfg then return end
                        cfg.healthBarBorderInsetH = tonumber(v) or 0
                        GF.applyRaidHealthBarBorders()
                    end,
                    minLabel = "-4", maxLabel = "+4",
                },
                sliderB = {
                    axisLabel = "V", min = -4, max = 4, step = 1,
                    get = function()
                        local cfg = ensureDB() or {}
                        return tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
                    end,
                    set = function(v)
                        local cfg = ensureDB()
                        if not cfg then return end
                        cfg.healthBarBorderInsetV = tonumber(v) or 0
                        GF.applyRaidHealthBarBorders()
                    end,
                    minLabel = "-4", maxLabel = "+4",
                },
            })

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Text
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Text",
        componentId = COMPONENT_ID,
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "playerName", label = "Player Name" },
                    { key = "statusText", label = "Health/Status" },
                    { key = "groupNumbers", label = "Group Numbers" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "text_tabs",
                buildContent = {
                    playerName = function(cf, tabInner)
                        buildTextTab(tabInner, "textPlayerName", applyText)
                    end,
                    statusText = function(cf, tabInner)
                        buildTextTab(tabInner, "textStatusText", applyText)
                    end,
                    groupNumbers = function(cf, tabInner)
                        buildTextTab(tabInner, "textGroupNumbers", applyText)
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Icons
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Icons",
        componentId = COMPONENT_ID,
        sectionKey = "icons",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "roleIcons", label = "Role Icons" },
                    { key = "groupLead", label = "Group Lead" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "icons_tabs",
                buildContent = {
                    roleIcons = function(cf, tabInner)
                        tabInner:AddSelector({
                            label = "Icon Set",
                            values = GF.roleIconSetValues,
                            order = GF.roleIconSetOrder,
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.roleIconSet or "default"
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.roleIconSet = v
                                    GF.applyRaidRoleIcons()
                                end
                            end,
                        })
                        -- Visibility filter
                        tabInner:AddSelector({
                            label = "Visibility",
                            values = {
                                showAll = "Show All",
                                hideDPS = "Hide DPS Icons",
                                hideAll = "Hide All",
                            },
                            order = { "showAll", "hideDPS", "hideAll" },
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.roleIconVisibility or "showAll"
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.roleIconVisibility = v
                                    GF.applyRaidRoleIcons()
                                end
                            end,
                        })

                        -- Scale slider
                        tabInner:AddSlider({
                            label = "Scale",
                            min = 25,
                            max = 200,
                            step = 5,
                            displaySuffix = "%",
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.roleIconScale or 100
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.roleIconScale = v
                                    GF.applyRaidRoleIcons()
                                end
                            end,
                        })

                        -- Position selector (9-point + Default)
                        local roleAnchorValues = {
                            default = "Default",
                            TOPLEFT = "Top-Left", TOP = "Top-Center", TOPRIGHT = "Top-Right",
                            LEFT = "Left", CENTER = "Center", RIGHT = "Right",
                            BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom-Center", BOTTOMRIGHT = "Bottom-Right",
                        }
                        local roleAnchorOrder = { "default", "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

                        tabInner:AddSelector({
                            label = "Position",
                            values = roleAnchorValues,
                            order = roleAnchorOrder,
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.roleIconAnchor or "default"
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.roleIconAnchor = v
                                    GF.applyRaidRoleIcons()
                                end
                            end,
                        })

                        -- Offset dual slider (X and Y)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local db = GF.ensureRaidDB()
                                    return db and db.roleIconOffsetX or 0
                                end,
                                set = function(v)
                                    local db = GF.ensureRaidDB()
                                    if db then
                                        db.roleIconOffsetX = v
                                        GF.applyRaidRoleIcons()
                                    end
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local db = GF.ensureRaidDB()
                                    return db and db.roleIconOffsetY or 0
                                end,
                                set = function(v)
                                    local db = GF.ensureRaidDB()
                                    if db then
                                        db.roleIconOffsetY = v
                                        GF.applyRaidRoleIcons()
                                    end
                                end,
                            },
                        })

                        tabInner:Finalize()
                    end,
                    groupLead = function(cf, tabInner)
                        -- Icon Set selector
                        tabInner:AddSelector({
                            label = "Icon Set",
                            values = {
                                default = "Blizzard Default",
                                desaturated = "Blizzard Default (White)",
                            },
                            order = { "default", "desaturated" },
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.groupLeadIconSet or "default"
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.groupLeadIconSet = v
                                    GF.applyRaidGroupLeadIcons()
                                end
                            end,
                        })

                        -- Show toggle
                        tabInner:AddToggle({
                            label = "Show Group Lead Icon",
                            description = "Displays a crown icon on the group/raid leader's frame.",
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.groupLeadIconShow or false
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.groupLeadIconShow = v
                                    GF.applyRaidGroupLeadIcons()
                                end
                            end,
                        })

                        -- Scale slider
                        tabInner:AddSlider({
                            label = "Scale",
                            min = 25,
                            max = 200,
                            step = 5,
                            displaySuffix = "%",
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.groupLeadIconScale or 100
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.groupLeadIconScale = v
                                    GF.applyRaidGroupLeadIcons()
                                end
                            end,
                        })

                        -- Position selector (9-point)
                        local leadAnchorValues = {
                            TOPLEFT = "Top-Left", TOP = "Top-Center", TOPRIGHT = "Top-Right",
                            LEFT = "Left", CENTER = "Center", RIGHT = "Right",
                            BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom-Center", BOTTOMRIGHT = "Bottom-Right",
                        }
                        local leadAnchorOrder = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

                        tabInner:AddSelector({
                            label = "Position",
                            values = leadAnchorValues,
                            order = leadAnchorOrder,
                            get = function()
                                local db = GF.ensureRaidDB()
                                return db and db.groupLeadIconAnchor or "TOPLEFT"
                            end,
                            set = function(v)
                                local db = GF.ensureRaidDB()
                                if db then
                                    db.groupLeadIconAnchor = v
                                    GF.applyRaidGroupLeadIcons()
                                end
                            end,
                        })

                        -- Offset dual slider (X and Y)
                        tabInner:AddDualSlider({
                            label = "Offset",
                            sliderA = {
                                axisLabel = "X",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local db = GF.ensureRaidDB()
                                    return db and db.groupLeadIconOffsetX or 0
                                end,
                                set = function(v)
                                    local db = GF.ensureRaidDB()
                                    if db then
                                        db.groupLeadIconOffsetX = v
                                        GF.applyRaidGroupLeadIcons()
                                    end
                                end,
                            },
                            sliderB = {
                                axisLabel = "Y",
                                min = -50, max = 50, step = 1,
                                get = function()
                                    local db = GF.ensureRaidDB()
                                    return db and db.groupLeadIconOffsetY or 0
                                end,
                                set = function(v)
                                    local db = GF.ensureRaidDB()
                                    if db then
                                        db.groupLeadIconOffsetY = v
                                        GF.applyRaidGroupLeadIcons()
                                    end
                                end,
                            },
                        })

                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Visibility
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = COMPONENT_ID,
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddToggle({
                label = "Hide Heal Prediction",
                description = "Hides incoming heal prediction bars (both your heals and others' heals).",
                get = function()
                    local db = GF.ensureRaidDB()
                    return db and db.hideHealPrediction or false
                end,
                set = function(v)
                    local db = GF.ensureRaidDB()
                    if db then
                        db.hideHealPrediction = v
                    end
                    GF.applyRaidStyles()
                end,
            })
            inner:AddToggle({
                label = "Hide Absorb Bars",
                description = "Hides absorb shield overlays and related glow effects on health bars.",
                get = function()
                    local db = GF.ensureRaidDB()
                    return db and db.hideAbsorbBars or false
                end,
                set = function(v)
                    local db = GF.ensureRaidDB()
                    if db then
                        db.hideAbsorbBars = v
                    end
                    GF.applyRaidStyles()
                end,
            })
            inner:AddToggle({
                label = "Hide Over Absorb Glow",
                description = "Hides the glow effect when absorb shields exceed health bar width.",
                get = function()
                    local db = GF.ensureRaidDB()
                    return db and db.hideOverAbsorbGlow or false
                end,
                set = function(v)
                    local db = GF.ensureRaidDB()
                    if db then
                        db.hideOverAbsorbGlow = v
                    end
                    GF.applyRaidStyles()
                end,
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Finalize
    ----------------------------------------------------------------------------

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("gfRaid", function(panel, scrollContent)
    GF.RenderRaid(panel, scrollContent)
end)
