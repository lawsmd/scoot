-- deeplink.lua - Open the settings panel directly to a page, section, and tab
--
-- Generalises the recipe search.lua proved. The one invariant that matters:
-- collapsible and tab state must be seeded BEFORE SelectItem, because renderers
-- read addon.UI._sectionStates / _tabStates at construction time. Writing after
-- the render is a no-op.
local addonName, addon = ...

local UIPanel = addon.UI.SettingsPanel
local Navigation = addon.UI.Navigation

--------------------------------------------------------------------------------
-- NavModel lookups
--------------------------------------------------------------------------------

local parentKeys      -- childKey -> parentKey
local navChildren     -- childKey -> nav child entry

local function BuildMaps()
    if parentKeys then return end
    parentKeys, navChildren = {}, {}

    for _, parent in ipairs(Navigation.NavModel or {}) do
        if parent.children then
            for _, child in ipairs(parent.children) do
                parentKeys[child.key] = parent.key
                navChildren[child.key] = child
            end
        end
    end
end

--- True when the page's module (or sub-module) is switched off for this session.
--- Uses Navigation:IsNavModuleActive rather than a bare addon._activeModules read,
--- because the latter ignores moduleSubId - which matters for damageMeterV2 under
--- the mutually-exclusive damageMeter category.
function addon.UI:IsNavKeyDisabled(navKey)
    BuildMaps()
    local child = navChildren[navKey]
    if not child or not child.module then return false end
    return not Navigation:IsNavModuleActive(child.module, child.moduleSubId)
end

--------------------------------------------------------------------------------
-- OpenToPage
--------------------------------------------------------------------------------

--- Open the settings panel at navKey, optionally expanding a collapsible section
--- and selecting a tab within it.
---
--- opts = {
---   componentId   = "notes",        -- state namespace
---   sectionKey    = "note3",        -- collapsible to expand
---   tab           = "content",      -- tab to select
---   tabSectionKey = "note3Tabs",    -- tab strip's own key; defaults to sectionKey
---   pageState     = { key = "_damageMeterYSelectedWindow", value = 3 },
--- }
---
--- Returns true if navigation was tried.
function addon.UI:OpenToPage(navKey, opts)
    if not navKey then return false end
    opts = opts or {}

    -- Matches UIPanel:Show()'s silent combat bail.
    if InCombatLockdown and InCombatLockdown() then return false end

    BuildMaps()

    -- A disabled module can't be configured, so send the user where they can
    -- enable it and drop the state seed.
    local targetKey = navKey
    if addon.UI:IsNavKeyDisabled(navKey) then
        targetKey = "startHere"
        opts = {}
    end

    -- Navigation._frame only exists after Initialize().
    if not UIPanel._initialized then UIPanel:Initialize() end
    if not UIPanel.frame then return false end

    -- Step 1: seed state before anything renders.
    if opts.componentId and opts.sectionKey then
        addon.UI._sectionStates = addon.UI._sectionStates or {}
        addon.UI._sectionStates[opts.componentId] = addon.UI._sectionStates[opts.componentId] or {}
        addon.UI._sectionStates[opts.componentId][opts.sectionKey] = true
    end

    if opts.componentId and opts.tab then
        -- A collapsible and its inner tab strip use different section keys under
        -- the same componentId (NotesRenderer: "note3" vs "note3Tabs").
        local tabSection = opts.tabSectionKey or opts.sectionKey
        if tabSection then
            addon.UI._tabStates = addon.UI._tabStates or {}
            addon.UI._tabStates[opts.componentId] = addon.UI._tabStates[opts.componentId] or {}
            addon.UI._tabStates[opts.componentId][tabSection] = opts.tab
        end
    end

    if opts.pageState and opts.pageState.key then
        UIPanel[opts.pageState.key] = opts.pageState.value
    end

    -- Step 2: expand the parent nav section.
    local parentKey = parentKeys[targetKey]
    local expandChanged = false
    if parentKey and not Navigation._expandedSections[parentKey] then
        Navigation._expandedSections[parentKey] = true
        expandChanged = true
    end

    -- Step 3: show. Show() rebuilds the nav itself.
    if not UIPanel:IsShown() then
        UIPanel:Show()
    elseif expandChanged then
        Navigation:Rebuild()
    end

    -- Step 4: render. Must follow Show(); the guard in UIPanel:Show's deferred
    -- re-render is what stops it repainting the previous page over this one.
    Navigation:SelectItem(targetKey)
    return true
end
