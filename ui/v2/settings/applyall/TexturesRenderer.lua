-- TexturesRenderer.lua - Apply All Bar Textures settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ApplyAll = addon.UI.Settings.ApplyAll or {}
addon.UI.Settings.ApplyAll.Textures = {}

local Textures = addon.UI.Settings.ApplyAll.Textures
local SettingsBuilder = addon.UI.SettingsBuilder

-- Note: Controls are now stored on panel._applyAllTexturesControls for ClearContent() compatibility

function Textures.Render(panel, scrollContent)
    panel:ClearContent()

    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme

    -- Track controls for cleanup on the PANEL (not module) so ClearContent() can find them
    -- ClearContent() looks for panel._applyAllTexturesControls
    panel._applyAllTexturesControls = panel._applyAllTexturesControls or {}
    for _, ctrl in ipairs(panel._applyAllTexturesControls) do
        if ctrl.Cleanup then ctrl:Cleanup() end
        if ctrl.Hide then ctrl:Hide() end
        if ctrl.SetParent then ctrl:SetParent(nil) end
    end
    panel._applyAllTexturesControls = {}

    local ar, ag, ab = Theme:GetAccentColor()

    -- Container frame for layout
    local container = CreateFrame("Frame", nil, scrollContent)
    container:SetSize(500, 260)
    container:SetPoint("TOP", scrollContent, "TOP", 0, -60)
    container:SetPoint("LEFT", scrollContent, "LEFT", 40, 0)
    container:SetPoint("RIGHT", scrollContent, "RIGHT", -40, 0)
    table.insert(panel._applyAllTexturesControls, container)

    -- Info text (centered, dimmed)
    local info = container:CreateFontString(nil, "OVERLAY")
    info:SetFont(Theme:GetFont("LABEL"), 12, "")
    info:SetPoint("TOP", container, "TOP", 0, 0)
    info:SetWidth(420)
    info:SetJustifyH("CENTER")
    info:SetText("Select a texture below, then click Apply. This will overwrite every Scoot bar texture (foreground and background) and force a UI reload. Tint, opacity, and color settings remain unchanged.")
    info:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Bar texture selector row (larger, minimal label)
    local textureSelector = Controls:CreateBarTextureSelector({
        parent = container,
        label = "Texture",
        get = function()
            return addon.ApplyAll and addon.ApplyAll:GetPendingBarTexture() or "default"
        end,
        set = function(textureKey)
            if addon.ApplyAll and addon.ApplyAll.SetPendingBarTexture then
                addon.ApplyAll:SetPendingBarTexture(textureKey)
            end
        end,
        width = 320,
        labelFontSize = 16,
        selectorHeight = 35,
        rowHeight = 52,
    })
    if textureSelector then
        textureSelector:SetPoint("TOPLEFT", container, "TOPLEFT", 20, -100)
        textureSelector:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -100)
        table.insert(panel._applyAllTexturesControls, textureSelector)
    end

    -- Apply button
    local applyBtn = Controls:CreateButton({
        parent = container,
        text = "Apply",
        width = 160,
        height = 38,
        fontSize = 14,
        onClick = function()
            local pending = addon.ApplyAll and addon.ApplyAll:GetPendingBarTexture()
            if not pending or pending == "" then
                if addon.Print then addon:Print("Select a texture before applying.") end
                return
            end

            local displayName = addon.Media and addon.Media.GetBarTextureDisplayName
                and addon.Media.GetBarTextureDisplayName(pending) or pending

            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_APPLYALL_TEXTURES", {
                    formatArgs = { displayName or pending },
                    data = { textureKey = pending },
                    onAccept = function(data)
                        if not data or not data.textureKey then return end
                        if not addon.ApplyAll or not addon.ApplyAll.ApplyBarTextures then return end

                        local result = addon.ApplyAll:ApplyBarTextures(data.textureKey, { updatePending = true })
                        if result and result.ok and result.changed and result.changed > 0 then
                            ReloadUI()
                        else
                            local reason = result and result.reason or "Unknown"
                            local friendly = {
                                noProfile = "Profile database unavailable.",
                                noSelection = "Select a texture before applying.",
                                noChanges = "All entries already use that texture.",
                            }
                            local detail = friendly[reason] or tostring(reason or "Unknown error.")
                            if addon.Print then
                                addon:Print("Apply All (Bar Textures) aborted: " .. detail)
                            end
                        end
                    end,
                })
            else
                if addon.Print then addon:Print("Dialog system unavailable.") end
            end
        end,
    })
    applyBtn:SetPoint("TOP", container, "TOP", 0, -180)
    table.insert(panel._applyAllTexturesControls, applyBtn)

    -- Set scroll content height
    scrollContent:SetHeight(400)
end

addon.UI.SettingsPanel:RegisterRenderer("applyAllTextures", function(panel, scrollContent)
    Textures.Render(panel, scrollContent)
end)

return Textures
