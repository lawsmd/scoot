--------------------------------------------------------------------------------
-- ui/v2/settings/FeaturesModel.lua
-- Scoot's model for the Features page (StartHereRenderer.lua).
--
-- The renderer draws whatever addon.UI.SettingsPanel.FeaturesModel holds. This
-- file fills it from core/modules.lua; Camelot fills it in forever/features.lua.
--------------------------------------------------------------------------------

local _, addon = ...

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepCopy(v) end
    return copy
end

-- Listed before ui/v2/settingspanel/core.lua on Scoot.toc, so the table is
-- created here when this file is first to it.
addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}

addon.UI.SettingsPanel.FeaturesModel = {
    pageKey = "startHere",
    title = "Modules",
    intro = "Enable or disable Scoot modules. Disabled modules do not load, freeing them for other addons.",
    legend = addon.FEATURE_GUIDE,
    columns = 3,
    order = addon.MODULE_CATEGORY_ORDER,
    categories = addon.MODULE_CATEGORIES,

    isEnabled = function(catId, subId)
        return addon:IsModuleEnabled(catId, subId)
    end,
    setEnabled = function(catId, subId, value)
        addon:SetModuleEnabled(catId, subId, value)
    end,

    snapshot = function()
        local me = addon.db and addon.db.profile and addon.db.profile.moduleEnabled
        return me and deepCopy(me) or nil
    end,
    restore = function(snap)
        local profile = addon.db and addon.db.profile
        if profile and snap then
            profile.moduleEnabled = deepCopy(snap)
        end
    end,
}
