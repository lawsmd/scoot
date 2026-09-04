-- PartyRenderer.lua - Party Frames TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.GroupFrames = addon.UI.GroupFrames or {}
local GF = addon.UI.GroupFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "gfParty"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = GF.BindFrame("party")

--------------------------------------------------------------------------------
-- Shared Tab Builders
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn)
    local get, set = B.barAccessors(barPrefix)
    inner:AddBarStyleBlock({ get = get, set = set, apply = applyFn })
    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn, includeHideToggle, hideLabel, defaultAnchor)
    local get, set = B.textAccessors(textKey)
    inner:AddTextStyleBlock({
        get = get, set = set, apply = applyFn,
        defaults = { size = 12 },
        hideToggle = includeHideToggle and { label = hideLabel or "Hide" } or nil,
        hideRealmToggle = textKey == "textPlayerName" and {
            description = "Shows only the player name without server (e.g., 'Player' instead of 'Player-Realm')",
        } or nil,
        size = { min = 6, max = 32 },
        alignment = {
            kind = "anchor9",
            label = "Alignment",
            default = defaultAnchor or "TOPLEFT",
            values = GF.anchorValues,
            order = GF.anchorOrder,
        },
        offset = { range = 50 },
    })
    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function GF.RenderParty(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        GF.RenderParty(panel, scrollContent)
    end)

    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting

    ----------------------------------------------------------------------------
    -- Parent-Level Edit Mode Settings
    ----------------------------------------------------------------------------

    builder:AddToggle({
        label = "Use Raid-Style Party Frames",
        description = "Uses compact raid-style frames for party. Enables additional customization options.",
        emphasized = true,
        get = function()
            if not EM or not EM.UseRaidStylePartyFrames then return false end
            local v = B.getEditModeSetting(EM.UseRaidStylePartyFrames)
            return v and v ~= 0
        end,
        set = function(v)
            if not EM or not EM.UseRaidStylePartyFrames then return end
            C_Timer.After(0, function()
                B.setEditModeSetting(EM.UseRaidStylePartyFrames, v and 1 or 0, {
                    skipApply = true,
                    suspendDuration = 0.25,
                })
                -- Re-render to show/hide conditional controls
                C_Timer.After(0.3, function()
                    GF.RenderParty(panel, scrollContent)
                end)
            end)
        end,
        infoIcon = GF.TOOLTIPS.raidStyleParty,
    })

    local isRaidStyle = GF.isRaidStyleParty()
    if not isRaidStyle then
        builder:AddToggle({
            label = "Show Party Frame Background",
            get = function()
                if not EM or not EM.ShowPartyFrameBackground then return true end
                local v = B.getEditModeSetting(EM.ShowPartyFrameBackground)
                return v and v ~= 0
            end,
            set = function(v)
                if not EM or not EM.ShowPartyFrameBackground then return end
                C_Timer.After(0, function()
                    B.setEditModeSetting(EM.ShowPartyFrameBackground, v and 1 or 0, {
                        suspendDuration = 0.25,
                    })
                end)
            end,
        })
    end

    ----------------------------------------------------------------------------
    -- Collapsible Section: Positioning & Sorting
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Positioning & Sorting",
        componentId = COMPONENT_ID,
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if isRaidStyle then
                inner:AddToggle({
                    label = "Use Horizontal Layout",
                    get = function()
                        if not EM or not EM.UseHorizontalGroups then return false end
                        local v = B.getEditModeSetting(EM.UseHorizontalGroups)
                        return v and v ~= 0
                    end,
                    set = function(v)
                        if not EM or not EM.UseHorizontalGroups then return end
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.UseHorizontalGroups, v and 1 or 0, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })

                inner:AddSelector({
                    label = "Sort By",
                    values = GF.partySortByValues,
                    order = GF.partySortByOrder,
                    get = function()
                        if not EM or not EM.SortPlayersBy then return 0 end
                        return B.getEditModeSetting(EM.SortPlayersBy) or 0
                    end,
                    set = function(v)
                        if not EM or not EM.SortPlayersBy then return end
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.SortPlayersBy, v, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })
            else
                inner:AddDescription("Additional positioning options are available when 'Use Raid-Style Party Frames' is enabled.")
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
            if isRaidStyle then
                inner:AddSlider({
                    label = "Frame Width",
                    min = 72,
                    max = 144,
                    step = 2,
                    get = function()
                        if not EM or not EM.FrameWidth then return 72 end
                        return B.getEditModeSetting(EM.FrameWidth) or 72
                    end,
                    set = function(v)
                        if not EM or not EM.FrameWidth then return end
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.FrameWidth, v, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })

                inner:AddSlider({
                    label = "Frame Height",
                    min = 36,
                    max = 72,
                    step = 2,
                    get = function()
                        if not EM or not EM.FrameHeight then return 36 end
                        return B.getEditModeSetting(EM.FrameHeight) or 36
                    end,
                    set = function(v)
                        if not EM or not EM.FrameHeight then return end
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.FrameHeight, v, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })
            else
                inner:AddSlider({
                    label = "Frame Size (Scale)",
                    min = 100,
                    max = 200,
                    step = 5,
                    get = function()
                        if not EM or not EM.FrameSize then return 100 end
                        local v = B.getEditModeSetting(EM.FrameSize)
                        -- Edit Mode may return index 0..20; normalize to 100..200
                        if v and v <= 20 then return 100 + (v * 5) end
                        return math.max(100, math.min(200, v or 100))
                    end,
                    set = function(v)
                        if not EM or not EM.FrameSize then return end
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.FrameSize, v, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                    minLabel = "100%",
                    maxLabel = "200%",
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
            buildStyleTab(inner, "healthBar", B.applyStyles)
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Border (Raid-Style only)
    ----------------------------------------------------------------------------

    if isRaidStyle then
        builder:AddCollapsibleSection({
            title = "Border",
            componentId = COMPONENT_ID,
            sectionKey = "border",
            defaultExpanded = false,
            buildContent = function(contentFrame, inner)
                inner:AddToggle({
                    label = "Display Border",
                    description = "Shows Blizzard's default border around the party group.",
                    get = function()
                        if not EM or not EM.DisplayBorder then return false end
                        local v = B.getEditModeSetting(EM.DisplayBorder)
                        return v and v ~= 0
                    end,
                    set = function(v)
                        if not EM or not EM.DisplayBorder then return end
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.DisplayBorder, v and 1 or 0, {
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                    infoIcon = GF.TOOLTIPS.displayBorder,
                })

                inner:AddSpacer(12)
                inner:AddLabel("Health Bar Borders")

                do
                    local get, set = B.barAccessors("healthBar")
                    inner:AddBarBorderBlock({
                        get = get, set = set, apply = B.applyHealthBarBorders,
                        style = { default = "none" },
                        thickness = { clamp = false },
                    })
                end

                inner:Finalize()
            end,
        })
    end

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
                    { key = "partyTitle", label = "Party Title" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "text_tabs",
                buildContent = {
                    playerName = function(cf, tabInner)
                        buildTextTab(tabInner, "textPlayerName", B.applyText, false)
                    end,
                    statusText = function(cf, tabInner)
                        buildTextTab(tabInner, "textStatusText", B.applyText, false, nil, "CENTER")
                    end,
                    partyTitle = function(cf, tabInner)
                        buildTextTab(tabInner, "textPartyTitle", B.applyText, true, "Hide Party Title")
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
                        tabInner:AddSelectorToggleRow({
                            label = "Icon Set",
                            selector = {
                                values = GF.roleIconSetValues,
                                order = GF.roleIconSetOrder,
                                get = function()
                                    local db = B.ensureDB()
                                    return db and db.roleIconSet or "default"
                                end,
                                set = function(v)
                                    local db = B.ensureDB()
                                    if db then
                                        db.roleIconSet = v
                                        B.applyRoleIcons()
                                    end
                                end,
                            },
                            toggle = {
                                label = "Desaturate",
                                get = function()
                                    local db = B.ensureDB()
                                    return db and db.roleIconDesaturate or false
                                end,
                                set = function(v)
                                    local db = B.ensureDB()
                                    if db then
                                        db.roleIconDesaturate = v
                                        B.applyRoleIcons()
                                    end
                                end,
                            },
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
                                local db = B.ensureDB()
                                return db and db.roleIconVisibility or "showAll"
                            end,
                            set = function(v)
                                local db = B.ensureDB()
                                if db then
                                    db.roleIconVisibility = v
                                    B.applyRoleIcons()
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
                                local db = B.ensureDB()
                                return db and db.roleIconScale or 100
                            end,
                            set = function(v)
                                local db = B.ensureDB()
                                if db then
                                    db.roleIconScale = v
                                    B.applyRoleIcons()
                                end
                            end,
                        })

                        -- Position selector (9-point + Default)
                        tabInner:AddSelector({
                            label = "Position",
                            values = GF.roleAnchorValues,
                            order = GF.roleAnchorOrder,
                            get = function()
                                local db = B.ensureDB()
                                return db and db.roleIconAnchor or "default"
                            end,
                            set = function(v)
                                local db = B.ensureDB()
                                if db then
                                    db.roleIconAnchor = v
                                    B.applyRoleIcons()
                                end
                            end,
                        })

                        -- Offset dual slider (X and Y)
                        tabInner:AddOffsetPair({
                            range = 50,
                            get = function(axis) local db = B.getDB(); return db and db[axis == "x" and "roleIconOffsetX" or "roleIconOffsetY"] end,
                            set = function(axis, v) local db = B.ensureDB(); if db then db[axis == "x" and "roleIconOffsetX" or "roleIconOffsetY"] = v end end,
                            apply = B.applyRoleIcons,
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
                                local db = B.ensureDB()
                                return db and db.groupLeadIconSet or "default"
                            end,
                            set = function(v)
                                local db = B.ensureDB()
                                if db then
                                    db.groupLeadIconSet = v
                                    B.applyGroupLeadIcons()
                                end
                            end,
                        })

                        -- Show toggle
                        tabInner:AddToggle({
                            label = "Show Group Lead Icon",
                            description = "Displays a crown icon on the group/raid leader's frame.",
                            get = function()
                                local db = B.ensureDB()
                                return db and db.groupLeadIconShow or false
                            end,
                            set = function(v)
                                local db = B.ensureDB()
                                if db then
                                    db.groupLeadIconShow = v
                                    B.applyGroupLeadIcons()
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
                                local db = B.ensureDB()
                                return db and db.groupLeadIconScale or 100
                            end,
                            set = function(v)
                                local db = B.ensureDB()
                                if db then
                                    db.groupLeadIconScale = v
                                    B.applyGroupLeadIcons()
                                end
                            end,
                        })

                        -- Position selector (9-point)
                        tabInner:AddSelector({
                            label = "Position",
                            values = GF.anchorValues,
                            order = GF.anchorOrder,
                            get = function()
                                local db = B.ensureDB()
                                return db and db.groupLeadIconAnchor or "TOPLEFT"
                            end,
                            set = function(v)
                                local db = B.ensureDB()
                                if db then
                                    db.groupLeadIconAnchor = v
                                    B.applyGroupLeadIcons()
                                end
                            end,
                        })

                        -- Offset dual slider (X and Y)
                        tabInner:AddOffsetPair({
                            range = 50,
                            get = function(axis) local db = B.getDB(); return db and db[axis == "x" and "groupLeadIconOffsetX" or "groupLeadIconOffsetY"] end,
                            set = function(axis, v) local db = B.ensureDB(); if db then db[axis == "x" and "groupLeadIconOffsetX" or "groupLeadIconOffsetY"] = v end end,
                            apply = B.applyGroupLeadIcons,
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
                    local db = B.ensureDB()
                    return db and db.hideHealPrediction or false
                end,
                set = function(v)
                    local db = B.ensureDB()
                    if db then
                        db.hideHealPrediction = v
                    end
                    B.applyStyles()
                end,
            })
            inner:AddToggle({
                label = "Hide Absorb Bars",
                description = "Hides absorb shield overlays and related glow effects on health bars.",
                get = function()
                    local db = B.ensureDB()
                    return db and db.hideAbsorbBars or false
                end,
                set = function(v)
                    local db = B.ensureDB()
                    if db then
                        db.hideAbsorbBars = v
                    end
                    B.applyStyles()
                end,
            })
            inner:AddToggle({
                label = "Hide Over Absorb Glow",
                description = "Hides the glow effect when absorb shields exceed health bar width.",
                get = function()
                    local db = B.ensureDB()
                    return db and db.hideOverAbsorbGlow or false
                end,
                set = function(v)
                    local db = B.ensureDB()
                    if db then
                        db.hideOverAbsorbGlow = v
                    end
                    B.applyStyles()
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

addon.UI.SettingsPanel:RegisterRenderer("gfParty", function(panel, scrollContent)
    GF.RenderParty(panel, scrollContent)
end)
