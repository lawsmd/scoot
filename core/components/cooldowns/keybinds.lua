-- keybinds.lua - Keybind resolution for CDM icon overlays
local addonName, addon = ...

addon.SpellBindings = addon.SpellBindings or {}
local SpellBindings = addon.SpellBindings

-- Cached mappings
local spellKeys = {}  -- spellID -> formatted keybind string
local itemKeys = {}   -- itemID -> formatted keybind string
local iconSpellCache = setmetatable({}, { __mode = "k" })  -- cdmIcon -> spellID

-- Throttle state
local ScheduleRebuild  -- defined below; forward-declared for the combat deferral
local REBUILD_THROTTLE = 0.2

-- Reference to overlay system
local activeOverlays  -- set during Initialize

--------------------------------------------------------------------------------
-- Slot-to-Binding Command Mapping
--------------------------------------------------------------------------------

local slotBindingCommands = {}

-- Slots 1-12: Main action bar (ACTIONBUTTON1-12)
for i = 1, 12 do
    slotBindingCommands[i] = "ACTIONBUTTON" .. i
end

-- Slots 25-36: MultiActionBar3 (Right bar)
for i = 1, 12 do
    slotBindingCommands[24 + i] = "MULTIACTIONBAR3BUTTON" .. i
end

-- Slots 37-48: MultiActionBar4 (Left bar)
for i = 1, 12 do
    slotBindingCommands[36 + i] = "MULTIACTIONBAR4BUTTON" .. i
end

-- Slots 49-60: MultiActionBar1 (Bottom Right)
for i = 1, 12 do
    slotBindingCommands[48 + i] = "MULTIACTIONBAR1BUTTON" .. i
end

-- Slots 61-72: MultiActionBar2 (Bottom Left)
for i = 1, 12 do
    slotBindingCommands[60 + i] = "MULTIACTIONBAR2BUTTON" .. i
end

-- Slots 133-144: MultiActionBar5 (Bar 5)
for i = 1, 12 do
    slotBindingCommands[132 + i] = "MULTIACTIONBAR5BUTTON" .. i
end

-- Slots 145-156: MultiActionBar6 (Bar 6)
for i = 1, 12 do
    slotBindingCommands[144 + i] = "MULTIACTIONBAR6BUTTON" .. i
end

-- Slots 157-168: MultiActionBar7 (Bar 7)
for i = 1, 12 do
    slotBindingCommands[156 + i] = "MULTIACTIONBAR7BUTTON" .. i
end

-- Slots 169-180: MultiActionBar8 (Bar 8)
for i = 1, 12 do
    slotBindingCommands[168 + i] = "MULTIACTIONBAR8BUTTON" .. i
end

--------------------------------------------------------------------------------
-- FormatBinding — Compress raw keybind strings into short display text
--------------------------------------------------------------------------------

local function FormatBinding(rawKey)
    if not rawKey or rawKey == "" then return nil end

    local key = rawKey

    -- Replace modifier prefixes
    key = key:gsub("SHIFT%-", "S")
    key = key:gsub("CTRL%-", "C")
    key = key:gsub("ALT%-", "A")

    -- Replace special numpad keys before generic NUMPAD
    key = key:gsub("NUMPADDECIMAL", "N.")
    key = key:gsub("NUMPADPLUS", "N+")
    key = key:gsub("NUMPADMINUS", "N-")
    key = key:gsub("NUMPAD", "N")

    -- Replace other special keys
    key = key:gsub("MOUSEBUTTON", "M")
    key = key:gsub("BUTTON", "B")
    key = key:gsub("ESCAPE", "Esc")
    key = key:gsub("BACKSPACE", "BkSp")
    key = key:gsub("SPACEBAR", "Sp")
    key = key:gsub("SPACE", "Sp")
    key = key:gsub("DELETE", "Del")
    key = key:gsub("INSERT", "Ins")
    key = key:gsub("HOME", "Hm")
    key = key:gsub("PAGEUP", "PgU")
    key = key:gsub("PAGEDOWN", "PgD")

    return key
end

--------------------------------------------------------------------------------
-- StoreSpellKey — Store a binding for a spellID, preferring shortest
--------------------------------------------------------------------------------

local function StoreSpellKey(spellID, formatted)
    if not spellID or spellID == 0 or not formatted then return end

    local existing = spellKeys[spellID]
    if not existing or #formatted < #existing then
        spellKeys[spellID] = formatted
    end

    -- Also store for override and base variants
    pcall(function()
        if C_Spell and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID and overrideID ~= 0 then
                local ex = spellKeys[overrideID]
                if not ex or #formatted < #ex then
                    spellKeys[overrideID] = formatted
                end
            end
        end
    end)

    pcall(function()
        if FindBaseSpellByID then
            local baseID = FindBaseSpellByID(spellID)
            if baseID and baseID ~= spellID and baseID ~= 0 then
                local ex = spellKeys[baseID]
                if not ex or #formatted < #ex then
                    spellKeys[baseID] = formatted
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- RebuildSpellKeyMap — Full scan of action bar slots (out of combat only)
--------------------------------------------------------------------------------

local function RebuildSpellKeyMap()
    if InCombatLockdown and InCombatLockdown() then
        -- Rebuild after combat; repeat queues coalesce onto one entry.
        addon.Events.RunOutOfCombat(ScheduleRebuild, "Cooldowns:Keybinds:rebuild")
        return
    end

    wipe(spellKeys)
    wipe(itemKeys)

    for slot, command in pairs(slotBindingCommands) do
        local key1, key2 = GetBindingKey(command)
        if not key1 and not key2 then
            -- No binding for this slot
        else
            local formatted1 = key1 and FormatBinding(key1)
            local formatted2 = key2 and FormatBinding(key2)
            -- Pick the shorter of the two bindings
            local formatted = formatted1
            if formatted2 and (not formatted or #formatted2 < #formatted) then
                formatted = formatted2
            end

            if formatted then
                -- Get what's in this slot
                local ok, actionType, id, subType = pcall(GetActionInfo, slot)
                if ok and actionType then
                    if actionType == "spell" and id and id ~= 0 then
                        StoreSpellKey(id, formatted)
                    elseif actionType == "macro" and id then
                        -- Resolve macro to underlying spell
                        pcall(function()
                            local macroSpellID
                            if GetMacroSpell then
                                macroSpellID = select(1, GetMacroSpell(id))
                            end
                            if macroSpellID and macroSpellID ~= 0 then
                                StoreSpellKey(macroSpellID, formatted)
                            end
                        end)
                    elseif actionType == "item" and id and id ~= 0 then
                        local existing = itemKeys[id]
                        if not existing or #formatted < #existing then
                            itemKeys[id] = formatted
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- ResolveIconSpell — Get spellID from a CDM icon frame
--------------------------------------------------------------------------------

local function ResolveIconSpell(cdmIcon)
    if not cdmIcon then return nil end

    -- Check cache first (combat-safe)
    local cached = iconSpellCache[cdmIcon]
    if cached then return cached end

    -- Out of combat: resolve from CDM data
    if InCombatLockdown and InCombatLockdown() then return nil end

    local spellID

    -- Try C_CooldownViewer API
    pcall(function()
        local cooldownID = cdmIcon.cooldownID
        if cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
            if info and info.spellID and info.spellID ~= 0 then
                spellID = info.spellID
            end
        end
    end)

    -- Fallback: try GetSpellID method
    if not spellID then
        pcall(function()
            if cdmIcon.GetSpellID then
                local sid = cdmIcon:GetSpellID()
                if sid and type(sid) == "number" and sid ~= 0 then
                    spellID = sid
                end
            end
        end)
    end

    if spellID then
        iconSpellCache[cdmIcon] = spellID
    end

    return spellID
end

--------------------------------------------------------------------------------
-- GetBindingForIcon — Main lookup: spellID → formatted keybind string
--------------------------------------------------------------------------------

local function GetBindingForIcon(cdmIcon)
    local spellID = ResolveIconSpell(cdmIcon)
    if not spellID then return nil end

    -- Direct match
    local binding = spellKeys[spellID]
    if binding then return binding end

    -- Override match
    pcall(function()
        if not binding and C_Spell and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= 0 then
                binding = spellKeys[overrideID]
            end
        end
    end)
    if binding then return binding end

    -- Base match
    pcall(function()
        if not binding and FindBaseSpellByID then
            local baseID = FindBaseSpellByID(spellID)
            if baseID and baseID ~= 0 then
                binding = spellKeys[baseID]
            end
        end
    end)

    return binding
end

--------------------------------------------------------------------------------
-- GetBindingForSpellID — Direct spell ID lookup (for Custom Groups)
--------------------------------------------------------------------------------

function SpellBindings.GetBindingForSpellID(spellID)
    if not spellID then return nil end

    -- Direct match
    local binding = spellKeys[spellID]
    if binding then return binding end

    -- Override match
    pcall(function()
        if not binding and C_Spell and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= 0 then
                binding = spellKeys[overrideID]
            end
        end
    end)
    if binding then return binding end

    -- Base match
    pcall(function()
        if not binding and FindBaseSpellByID then
            local baseID = FindBaseSpellByID(spellID)
            if baseID and baseID ~= 0 then
                binding = spellKeys[baseID]
            end
        end
    end)

    return binding
end

--------------------------------------------------------------------------------
-- GetBindingForItemID — Direct item ID lookup (for Custom Groups)
--------------------------------------------------------------------------------

function SpellBindings.GetBindingForItemID(itemID)
    if not itemID then return nil end
    return itemKeys[itemID]
end

--------------------------------------------------------------------------------
-- Refresh Callbacks — Notify external consumers when bindings change
--------------------------------------------------------------------------------

local refreshCallbacks = {}

function SpellBindings.RegisterRefreshCallback(fn)
    table.insert(refreshCallbacks, fn)
end

--------------------------------------------------------------------------------
-- ApplyToIcon — Render keybind text on a CDM icon's overlay
--------------------------------------------------------------------------------

function SpellBindings.ApplyToIcon(cdmIcon, cfg)
    if not cdmIcon or not activeOverlays then return end

    local overlay = activeOverlays[cdmIcon]
    if not overlay then return end

    -- Ensure keybindText FontString exists on this overlay
    if not overlay.keybindText then return end

    if not cfg or not cfg.enabled then
        overlay.keybindText:Hide()
        return
    end

    local binding = GetBindingForIcon(cdmIcon)
    if not binding then
        overlay.keybindText:SetText("")
        overlay.keybindText:Hide()
        return
    end

    overlay.keybindText:SetText(binding)

    -- Apply font styling using the shared function
    if addon.ApplyFontStyleDirect then
        addon.ApplyFontStyleDirect(overlay.keybindText, cfg, false, overlay)
    end

    overlay.keybindText:Show()
end

--------------------------------------------------------------------------------
-- RefreshAllIcons — Called after cache rebuild or settings change
--------------------------------------------------------------------------------

function SpellBindings.RefreshAllIcons(componentId)
    if not activeOverlays then return end

    local CDM_VIEWERS = addon.CDM_VIEWERS
    if not CDM_VIEWERS then return end

    -- Find the viewer for this component
    local viewerName
    if componentId then
        for vn, cid in pairs(CDM_VIEWERS) do
            if cid == componentId then
                viewerName = vn
                break
            end
        end
    end

    -- Only Essential and Utility support keybinds
    if componentId and componentId ~= "essentialCooldowns" and componentId ~= "utilityCooldowns" then
        return
    end

    local function refreshViewer(vName, cId)
        -- Only Essential and Utility
        if cId ~= "essentialCooldowns" and cId ~= "utilityCooldowns" then return end

        local viewer = _G[vName]
        if not viewer then return end

        local component = addon.Components and addon.Components[cId]
        if not component or not component.db then return end

        local cfg = component.db.textBindings
        if not cfg or not cfg.enabled then
            -- Hide all keybind text on this viewer's overlays
            local children = { viewer:GetChildren() }
            for _, child in ipairs(children) do
                local overlay = activeOverlays[child]
                if overlay and overlay.keybindText then
                    overlay.keybindText:Hide()
                end
            end
            return
        end

        local children = { viewer:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.Icon then
                SpellBindings.ApplyToIcon(child, cfg)
            end
        end
    end

    if viewerName then
        refreshViewer(viewerName, componentId)
    else
        -- Refresh all applicable viewers
        for vn, cid in pairs(CDM_VIEWERS) do
            refreshViewer(vn, cid)
        end
    end
end

--------------------------------------------------------------------------------
-- ClearIconCache — Clear spell cache for a released icon
--------------------------------------------------------------------------------

function SpellBindings.ClearIconCache(cdmIcon)
    if cdmIcon then
        iconSpellCache[cdmIcon] = nil
    end
end

--------------------------------------------------------------------------------
-- RebuildCache — Public force-rebuild
--------------------------------------------------------------------------------

function SpellBindings.RebuildCache()
    RebuildSpellKeyMap()
end

--------------------------------------------------------------------------------
-- Throttled Rebuild — Max once per REBUILD_THROTTLE seconds
--------------------------------------------------------------------------------

local rebuildScheduled = false

function ScheduleRebuild()
    if rebuildScheduled then return end
    rebuildScheduled = true
    C_Timer.After(REBUILD_THROTTLE, function()
        rebuildScheduled = false
        RebuildSpellKeyMap()
        SpellBindings.RefreshAllIcons()
        for _, fn in ipairs(refreshCallbacks) do
            pcall(fn)
        end
    end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- Every registered event schedules a rebuild; a rebuild landing in combat
-- queues itself on the shared regen drain.
local function OnEvent()
    ScheduleRebuild()
end

local eventsArmed = false

--------------------------------------------------------------------------------
-- Initialize — Build initial cache, register events
--------------------------------------------------------------------------------

function SpellBindings.Initialize()
    -- Latched: Initialize re-runs with component re-initialization, and the
    -- old frame's repeat RegisterEvent calls were no-ops.
    if not eventsArmed then
        eventsArmed = true
        for _, event in ipairs({
            "UPDATE_BINDINGS",
            "ACTIONBAR_SLOT_CHANGED",
            "ACTIONBAR_PAGE_CHANGED",
            "UPDATE_BONUS_ACTIONBAR",
            "PLAYER_TALENT_UPDATE",
            "SPELLS_CHANGED",
        }) do
            addon.Events.On("Cooldowns:Keybinds", event, OnEvent)
        end
    end

    -- Build initial cache (deferred to ensure action bars are loaded)
    C_Timer.After(1.0, function()
        RebuildSpellKeyMap()
        SpellBindings.RefreshAllIcons()
    end)
end

-- SetActiveOverlays — Called by core.lua to provide access to the overlay table
function SpellBindings.SetActiveOverlays(tbl)
    activeOverlays = tbl
end
