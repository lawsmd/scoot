-- SpellbookOverlay.lua - TUIButton on Blizzard Spellbook to open CDM Custom Groups tab
local _, addon = ...

local Controls = addon.UI and addon.UI.Controls
local CG = addon.CustomGroups

local spellbookButton = nil
local initialized = false

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

local function ShouldShowButton()
    if not (CG and CG.IsAnyGroupEnabled and CG.IsAnyGroupEnabled()) then
        return false
    end
    local ok, sbFrame = pcall(function()
        return PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
    end)
    if not ok or not sbFrame then return false end
    local success, isVis = pcall(sbFrame.IsVisible, sbFrame)
    return success and isVis
end

local function UpdateButtonVisibility()
    if not spellbookButton then return end
    if ShouldShowButton() then
        spellbookButton:Show()
    else
        spellbookButton:Hide()
    end
end

--------------------------------------------------------------------------------
-- Click handler
--------------------------------------------------------------------------------

local function OnButtonClick()
    local frame = _G.CooldownViewerSettings
    local alreadyOpen = false
    if frame then
        local ok, shown = pcall(frame.IsShown, frame)
        alreadyOpen = ok and shown
    end

    if not alreadyOpen then
        addon._pendingCDMCustomGroupsTabActivation = true
        addon:OpenCooldownManagerSettings()
    end

    if addon.ActivateCDMCustomGroupsTab then
        addon._pendingCDMCustomGroupsTabActivation = nil
        addon.ActivateCDMCustomGroupsTab()
    end
end

--------------------------------------------------------------------------------
-- Button creation (one-time)
--------------------------------------------------------------------------------

local function CreateSpellbookButton()
    if spellbookButton then return end

    if not Controls then
        Controls = addon.UI and addon.UI.Controls
    end
    if not Controls then return end

    local ok, tabSystem = pcall(function()
        return PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem
    end)
    if not ok or not tabSystem then return end

    local ok2, sbFrame = pcall(function()
        return PlayerSpellsFrame.SpellBookFrame
    end)
    if not ok2 or not sbFrame then return end

    spellbookButton = Controls:CreateButton({
        parent = sbFrame,
        text = "Open Custom CDM Groups",
        height = 29,
        fontSize = 13,
        borderAlpha = 0.8,
        name = "ScootSpellbookCDMButton",
        onClick = OnButtonClick,
    })

    spellbookButton:SetAlpha(0.8)

    spellbookButton:ClearAllPoints()
    spellbookButton:SetPoint("TOP", tabSystem, "BOTTOM", 0, -10)

    local ok3, parentLevel = pcall(sbFrame.GetFrameLevel, sbFrame)
    if ok3 and parentLevel then
        spellbookButton:SetFrameLevel(parentLevel + 10)
    end

    UpdateButtonVisibility()
end

--------------------------------------------------------------------------------
-- Initialization: wait for Blizzard_PlayerSpells to load
--------------------------------------------------------------------------------

local function SetupSpellbookHooks()
    if initialized then return end
    initialized = true

    local ER = _G.EventRegistry
    if not ER or type(ER.RegisterCallback) ~= "function" then return end

    ER:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.Show", function()
        if not spellbookButton then
            CreateSpellbookButton()
        end
        UpdateButtonVisibility()
    end, "ScootSpellbookOverlay")

    ER:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.Hide", function()
        UpdateButtonVisibility()
    end, "ScootSpellbookOverlay")

    ER:RegisterCallback("PlayerSpellsFrame.CloseFrame", function()
        UpdateButtonVisibility()
    end, "ScootSpellbookOverlay")

    -- Catch the case where spellbook is already open at registration time
    -- (e.g. Blizzard_PlayerSpells loaded and opened in the same frame)
    if not spellbookButton then
        CreateSpellbookButton()
    end
    UpdateButtonVisibility()
end

-- OnAddonLoaded runs the callback immediately when Blizzard_PlayerSpells is
-- already in (the old PlayerSpellsFrame immediate check).
addon.Events.OnAddonLoaded("Blizzard_PlayerSpells", function()
    C_Timer.After(0, SetupSpellbookHooks)
end)

--------------------------------------------------------------------------------
-- Refresh hook: re-check visibility when group enable toggles change
--------------------------------------------------------------------------------

if addon.RefreshCustomGroupsTabVisibility then
    hooksecurefunc(addon, "RefreshCustomGroupsTabVisibility", UpdateButtonVisibility)
end
