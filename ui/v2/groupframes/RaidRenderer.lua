-- RaidRenderer.lua - Raid Frames TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.GroupFrames = addon.UI.GroupFrames or {}
local GF = addon.UI.GroupFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "gfRaid"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = GF.BindFrame("raid")

--------------------------------------------------------------------------------
-- Shared Tab Builders
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn)
    local get, set = B.barAccessors(barPrefix)
    inner:AddBarStyleBlock({ get = get, set = set, apply = applyFn })
    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn)
    -- Show Groups as Numbers Only toggle (only for Group Numbers); flat raid
    -- db key with nil-when-false (Zero-Touch) semantics, so it stays outside
    -- the composite
    if textKey == "textGroupNumbers" then
        inner:AddToggle({
            label = "Show as Numbers Only",
            description = "Display '1', '2' instead of 'Group 1', 'Group 2'. Auto-centers based on orientation.",
            get = function()
                local t = B.getDB() or {}
                return t.groupTitleNumbersOnly == true
            end,
            set = function(v)
                local t = B.ensureDB()
                if not t then return end
                t.groupTitleNumbersOnly = v or nil  -- nil when false (Zero-Touch)
                applyFn()
            end,
            infoIcon = GF.TOOLTIPS.groupTitleNumbersOnly,
        })
    end

    local get, set = B.textAccessors(textKey)
    inner:AddTextStyleBlock({
        get = get, set = set, apply = applyFn,
        defaults = { size = 12 },
        hideRealmToggle = textKey == "textPlayerName" and {
            description = "Shows only the player name without server (e.g., 'Player' instead of 'Player-Realm')",
        } or nil,
        size = { min = 6, max = 32 },
        alignment = {
            kind = "anchor9",
            label = "Alignment",
            default = "TOPLEFT",
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
    -- Master Toggle: Hide Raid Frames
    ----------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Raid Frames",
        description = "Hides the raid frames and stops them taking clicks, for small screens like ScooterDeck. Party frames are unaffected, and the styling below stays saved.",
        emphasized = true,
        get = function()
            local t = B.ensureDB() or {}
            return t.hideRaidFrames == true
        end,
        set = function(v)
            local t = B.ensureDB()
            if not t then return end
            t.hideRaidFrames = v or nil  -- nil when false (Zero-Touch)
            if addon.ApplyRaidContainerVisibility then
                addon.ApplyRaidContainerVisibility("toggle")
            end
        end,
    })

    ----------------------------------------------------------------------------
    -- Roster Overlay
    ----------------------------------------------------------------------------

    builder:AddToggleSliderRow({
        label = "Roster Overlay",
        description = "A compact two-column list of your raid. Drag with the left mouse button to move it. Font and name colours come from Player Name below."
            .. (isCombineGroups and " Raid frames are set to combine groups, so the overlay lists names in roster order with no group headings." or ""),
        toggle = {
            label = "Enable",
            get = function()
                local t = B.ensureDB() or {}
                return t.rosterOverlay == true
            end,
            set = function(v)
                local t = B.ensureDB()
                if not t then return end
                t.rosterOverlay = v or nil  -- nil when false (Zero-Touch)
                if addon.ApplyRaidRosterOverlay then
                    addon.ApplyRaidRosterOverlay("toggle")
                end
            end,
        },
        slider = {
            label = "Transparency",
            min = 0,
            max = 100,
            step = 1,
            suffix = "%",
            get = function()
                local t = B.ensureDB() or {}
                return tonumber(t.rosterOverlayAlpha) or 100
            end,
            set = function(v)
                local t = B.ensureDB()
                if not t then return end
                t.rosterOverlayAlpha = tonumber(v) or 100
                if addon.ApplyRaidRosterOverlay then
                    addon.ApplyRaidRosterOverlay("alpha")
                end
            end,
        },
    })

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
                        return B.getEditModeSetting(EM.RaidGroupDisplayType) or RGD.SeparateGroupsVertical
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.RaidGroupDisplayType, v, {
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
                            return B.getEditModeSetting(EM.SortPlayersBy) or 0
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                B.setEditModeSetting(EM.SortPlayersBy, v, {
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
                            return B.getEditModeSetting(EM.RowSize) or 5
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                B.setEditModeSetting(EM.RowSize, v, {
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
                        return B.getEditModeSetting(EM.FrameWidth) or 72
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.FrameWidth, v, {
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
                        return B.getEditModeSetting(EM.FrameHeight) or 36
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            B.setEditModeSetting(EM.FrameHeight, v, {
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
            buildStyleTab(inner, "healthBar", B.applyStyles)
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
                            local v = B.getEditModeSetting(EM.DisplayBorder)
                            return v and v ~= 0
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                B.setEditModeSetting(EM.DisplayBorder, v and 1 or 0, {
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

    ----------------------------------------------------------------------------
    -- Collapsible Section: Debuffs
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Debuffs",
        componentId = COMPONENT_ID,
        sectionKey = "debuffs",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Adopt a pre-existing CVar override into the profile so the preference
            -- survives to other characters. Only when the profile has no opinion yet
            -- and the live CVar differs from Blizzard's default ("1") — i.e. the user
            -- already changed it deliberately, so this is not a Zero-Touch violation.
            do
                local t = B.ensureDB()
                if t and t.enlargeRoleDebuffs == nil then
                    local cur = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("raidFramesDisplayLargerRoleSpecificDebuffs")
                    if cur == "0" then
                        t.enlargeRoleDebuffs = false
                    end
                end
            end

            inner:AddToggle({
                label = "Enlarge Dispellable / Boss Debuffs",
                description = "Blizzard renders dispellable and boss/role-specific debuffs at 1.5x size on raid frames (Blizzard default: on). Turn this off to render those debuffs at the same size as other debuffs. Also applies to raid-style party frames. This scales the icon and its border together — it does not fix oversized borders (see below).",
                get = function()
                    local t = B.ensureDB() or {}
                    if t.enlargeRoleDebuffs ~= nil then return t.enlargeRoleDebuffs end
                    -- Unset: reflect the live CVar so the checkbox matches reality (Blizzard default "1").
                    local cur = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("raidFramesDisplayLargerRoleSpecificDebuffs")
                    return cur ~= "0"
                end,
                set = function(v)
                    local t = B.ensureDB()
                    if not t then return end
                    t.enlargeRoleDebuffs = v and true or false
                    if addon.ApplyRaidLargerRoleDebuffs then
                        addon.ApplyRaidLargerRoleDebuffs("toggle")
                    end
                end,
            })

            inner:AddDescription("Known Blizzard 12.0 bug: raid-frame debuff borders are drawn at a fixed 40px size regardless of icon size, so debuffs with colored (dispellable-type) borders can show a large square outline around a small icon. The debuff renderer runs in Blizzard's secure environment — no addon can resize or hide these borders; this needs a fix from Blizzard. To confirm it isn't Scoot: raise Icon Size in Edit Mode > Raid Frames — the icons grow while the border box stays the same size.")

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
                        buildTextTab(tabInner, "textPlayerName", B.applyText)
                    end,
                    statusText = function(cf, tabInner)
                        buildTextTab(tabInner, "textStatusText", B.applyText)
                    end,
                    groupNumbers = function(cf, tabInner)
                        buildTextTab(tabInner, "textGroupNumbers", B.applyText)
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

addon.UI.SettingsPanel:RegisterRenderer("gfRaid", function(panel, scrollContent)
    GF.RenderRaid(panel, scrollContent)
end)
