-- FontsRenderer.lua - Apply All Fonts settings renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ApplyAll = addon.UI.Settings.ApplyAll or {}
addon.UI.Settings.ApplyAll.Fonts = {}

local Fonts = addon.UI.Settings.ApplyAll.Fonts
local SettingsBuilder = addon.UI.SettingsBuilder

-- Note: Controls are now stored on panel._applyAllFontsControls for ClearContent() compatibility

function Fonts.Render(panel, scrollContent)
    panel:ClearContent()

    local Controls = addon.UI.Controls
    local Theme = addon.UI.Theme

    -- Track controls for cleanup on the PANEL (not module) so ClearContent() can find them
    -- ClearContent() looks for panel._applyAllFontsControls
    panel._applyAllFontsControls = panel._applyAllFontsControls or {}
    for _, ctrl in ipairs(panel._applyAllFontsControls) do
        if ctrl.Cleanup then ctrl:Cleanup() end
        if ctrl.Hide then ctrl:Hide() end
        if ctrl.SetParent then ctrl:SetParent(nil) end
    end
    panel._applyAllFontsControls = {}

    local ar, ag, ab = Theme:GetAccentColor()

    -- Container frame for layout
    local container = CreateFrame("Frame", nil, scrollContent)
    container:SetSize(500, 280)
    container:SetPoint("TOP", scrollContent, "TOP", 0, -60)
    container:SetPoint("LEFT", scrollContent, "LEFT", 40, 0)
    container:SetPoint("RIGHT", scrollContent, "RIGHT", -40, 0)
    table.insert(panel._applyAllFontsControls, container)

    -- Info text (centered, dimmed)
    local info = container:CreateFontString(nil, "OVERLAY")
    info:SetFont(Theme:GetFont("LABEL"), 12, "")
    info:SetPoint("TOP", container, "TOP", 0, 0)
    info:SetWidth(420)
    info:SetJustifyH("CENTER")
    info:SetText("Select a font below, then click Apply. This will overwrite every Scoot font face and force a UI reload. Sizes, colors, offsets, and outlines remain unchanged.\n\nScrolling Combat Text fonts are excluded (require game restart).")
    info:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Font selector row (larger, minimal label)
    local fontSelector = Controls:CreateFontSelector({
        parent = container,
        label = "Font",
        get = function()
            return addon.ApplyAll and addon.ApplyAll:GetPendingFont() or "FRIZQT__"
        end,
        set = function(fontKey)
            if addon.ApplyAll and addon.ApplyAll.SetPendingFont then
                addon.ApplyAll:SetPendingFont(fontKey)
            end
        end,
        width = 320,
        labelFontSize = 16,
        selectorHeight = 35,
        rowHeight = 52,
    })
    if fontSelector then
        fontSelector:SetPoint("TOPLEFT", container, "TOPLEFT", 20, -120)
        fontSelector:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, -120)
        table.insert(panel._applyAllFontsControls, fontSelector)
    end

    -- Apply button
    local applyBtn = Controls:CreateButton({
        parent = container,
        text = "Apply",
        width = 160,
        height = 38,
        fontSize = 14,
        onClick = function()
            local pending = addon.ApplyAll and addon.ApplyAll:GetPendingFont()
            if not pending or pending == "" then
                if addon.Print then addon:Print("Select a font before applying.") end
                return
            end

            local displayName = addon.FontDisplayNames and addon.FontDisplayNames[pending] or pending

            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_APPLYALL_FONTS", {
                    formatArgs = { displayName },
                    data = { fontKey = pending },
                    onAccept = function(data)
                        if not data or not data.fontKey then return end
                        if not addon.ApplyAll or not addon.ApplyAll.ApplyFonts then return end

                        local result = addon.ApplyAll:ApplyFonts(data.fontKey, { updatePending = true })
                        if result and result.ok and result.changed and result.changed > 0 then
                            ReloadUI()
                        else
                            local reason = result and result.reason or "Unknown"
                            local friendly = {
                                noProfile = "Profile database unavailable.",
                                noSelection = "Select a font before applying.",
                                noChanges = "All entries already use that font.",
                            }
                            local detail = friendly[reason] or tostring(reason or "Unknown error.")
                            if addon.Print then
                                addon:Print("Apply All (Fonts) aborted: " .. detail)
                            end
                        end
                    end,
                })
            else
                if addon.Print then addon:Print("Dialog system unavailable.") end
            end
        end,
    })
    applyBtn:SetPoint("TOP", container, "TOP", 0, -200)
    table.insert(panel._applyAllFontsControls, applyBtn)

    -- Set scroll content height
    scrollContent:SetHeight(400)
end

addon.UI.SettingsPanel:RegisterRenderer("applyAllFonts", function(panel, scrollContent)
    Fonts.Render(panel, scrollContent)
end)

return Fonts
