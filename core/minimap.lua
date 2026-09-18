--------------------------------------------------------------------------------
-- minimap.lua - the minimap button, one file for both addons.
--
-- LibDataBroker holds the launcher object, LibDBIcon draws it on the minimap
-- ring, drags it, and remembers where the player left it. Clicking opens the
-- settings panel, which is what the slash word with no command does.
--
-- Two things differ between the addons, and both are host seams read at
-- login rather than at file scope, so the host file can load in any order:
--
--   addon.MinimapIcon         the texture; Scoot's logo when nothing names one
--   addon.MinimapButtonStore  a function returning the live table LibDBIcon
--                             writes minimapPos, hide and lock into
--
-- Scoot names neither and takes the fallbacks below: its own icon, and
-- db.profile.minimap, the shape core/init.lua and both presets already
-- carry. Camelot names both in forever/minimap.lua, because CamelotDB keeps
-- a library's table in `documents` and its icon is not this one.
--
-- The button follows the profile. LibDBIcon holds the table it was handed,
-- and AceDB swaps the profile out from under it, so the callbacks below hand
-- it the new profile's table and it moves to where that profile left it.
--------------------------------------------------------------------------------

local addonName, addon = ...

local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)

if not LDB or not LDBIcon then
    return
end

-- LibDataBroker keys every object by one string across all addons in the
-- session, so the two buttons are told apart by the brand and nothing else.
local OBJECT = addon.Brand or "Scoot"

local DEFAULT_POSITION = 220

--------------------------------------------------------------------------------
-- The host seams
--------------------------------------------------------------------------------

local function icon()
    return addon.MinimapIcon or ((addon.MediaPath or "Interface\\AddOns\\Scoot\\") .. "ScootIcon")
end

-- The live table out of the active profile, returned by reference: LibDBIcon
-- writes the drag position straight into it.
local function store()
    if type(addon.MinimapButtonStore) == "function" then
        local t = addon.MinimapButtonStore()
        if type(t) == "table" then return t end
    end

    local profile = addon.db and addon.db.profile
    if profile then
        profile.minimap = profile.minimap or { hide = false, minimapPos = DEFAULT_POSITION }
        return profile.minimap
    end

    -- No database yet. The button still draws and drags; the position is lost
    -- at logout, which is better than no button.
    return { hide = false, minimapPos = DEFAULT_POSITION }
end

--------------------------------------------------------------------------------
-- The launcher
--------------------------------------------------------------------------------

local function openSettings()
    if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
        addon.UI.SettingsPanel:Toggle()
    end
end

local function createLauncher()
    return LDB:NewDataObject(OBJECT, {
        type = "launcher",
        text = OBJECT,
        icon = icon(),
        OnClick = function(_, _)
            -- Either button opens the panel. A right-click menu waits for a
            -- second thing worth putting on it.
            openSettings()
        end,
        OnTooltipShow = function(tooltip)
            -- The addon name is a brand mark and follows the accent, read on
            -- every show because the player can change it. The white words
            -- below are labels.
            local hex = addon.GetAccentHex and addon.GetAccentHex()
            tooltip:AddLine(hex and ("|cff" .. hex .. OBJECT .. "|r") or OBJECT)
            tooltip:AddLine(" ")
            tooltip:AddLine("|cffffffffClick|r to open settings")
            tooltip:AddLine("|cffffffffDrag|r to move this button")
        end,
    })
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

-- PLAYER_LOGIN, not ADDON_LOADED: LibDBIcon positions a button against the
-- minimap shape and waits for login itself before it places anything. The
-- database is read at ADDON_LOADED, which is earlier, so the profile is there.
addon.Events.Once("MinimapButton", "PLAYER_LOGIN", function()
    LDBIcon:Register(OBJECT, createLauncher(), store())

    if not addon.db then return end

    -- AceDB's own callbacks rather than a single-slot host hook, which the
    -- next module would want.
    local watcher = {}
    local function repoint()
        LDBIcon:Refresh(OBJECT, store())
    end
    addon.db.RegisterCallback(watcher, "OnProfileChanged", repoint)
    addon.db.RegisterCallback(watcher, "OnProfileCopied", repoint)
    addon.db.RegisterCallback(watcher, "OnProfileReset", repoint)
    addon._minimapWatcher = watcher
end)

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local MinimapButton = {}
addon.MinimapButton = MinimapButton

function MinimapButton:Show()
    store().hide = false
    LDBIcon:Show(OBJECT)
end

function MinimapButton:Hide()
    store().hide = true
    LDBIcon:Hide(OBJECT)
end

function MinimapButton:IsShown()
    local button = LDBIcon:GetMinimapButton(OBJECT)
    return (button and button:IsShown()) and true or false
end

function MinimapButton:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

addon:RegisterSlashCommand({
    name = "minimap",
    help = "show, hide, or toggle the minimap button",
    default = "toggle",
    verbs = {
        { word = "show", help = "put the button back on the ring",
          fn = function() MinimapButton:Show() end },
        { word = "hide", help = "take the button off the ring",
          fn = function() MinimapButton:Hide() end },
        { word = "toggle", help = "swap between the two",
          fn = function() MinimapButton:Toggle() end },
    },
})
