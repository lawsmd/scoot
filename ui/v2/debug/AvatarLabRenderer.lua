-- AvatarLabRenderer.lua - DEV-ONLY. Surfaces the pixel-art avatar prototype under
-- the hidden Debug section (Debug > Avatar Lab) instead of the player menu, so it
-- can be iterated in-game without exposing it in the shipped product.
--
-- This file injects its own nav entry at load (Navigation.lua is not touched), so
-- when the file is stripped from a release build the Debug entry disappears with
-- it. This file and the avatar infrastructure are removed from CurseForge releases
-- by export-curseforge.ps1.
local addonName, addon = ...

local Nav = addon.UI and addon.UI.Navigation
local UIPanel = addon.UI and addon.UI.SettingsPanel

-- Inject an "Avatar Lab" child under the hidden Debug node.
if Nav and Nav.NavModel then
    for _, node in ipairs(Nav.NavModel) do
        if node.key == "debug" then
            node.children = node.children or {}
            local exists = false
            for _, child in ipairs(node.children) do
                if child.key == "avatarLab" then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(node.children, { key = "avatarLab", label = "Avatar Lab" })
            end
            break
        end
    end
end

local function renderAvatarLab(panel, scrollContent)
    panel:ClearContent()

    local SettingsBuilder = addon.UI.SettingsBuilder
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        renderAvatarLab(panel, scrollContent)
    end)

    builder:AddDescription(
        "Development prototype. Procedurally generated pixel-art head shown beside " ..
        "the player portrait. This lives under Debug and is excluded from release " ..
        "builds. Auto-matches your race and sex; every feature can be overridden below."
    )

    local UF = addon.UI.UnitFrames
    if UF and UF.buildAvatarSection then
        UF.buildAvatarSection(builder, "avatarLab", "Player")
    end

    builder:Finalize()
end

if UIPanel and UIPanel.RegisterRenderer then
    UIPanel:RegisterRenderer("avatarLab", renderAvatarLab)
end
