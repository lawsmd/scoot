-- ApplyAllRenderer.lua - Apply All Fonts and Bar Textures settings renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ApplyAll = addon.UI.Settings.ApplyAll or {}

local MODES = {
    {
        key = "applyAllFonts",
        controlsField = "_applyAllFontsControls",
        containerHeight = 280,
        infoText = "Select a font below, then click Apply. This will overwrite every Scoot font face and force a UI reload. Sizes, colors, offsets, and outlines remain unchanged.\n\nScrolling Combat Text fonts are excluded (require game restart).",
        selectorMethod = "CreateFontSelector",
        selectorLabel = "Font",
        selectorOffsetY = -120,
        buttonOffsetY = -200,
        pendingDefault = "FRIZQT__",
        getPendingName = "GetPendingFont",
        setPendingName = "SetPendingFont",
        applyName = "ApplyFonts",
        dialogId = "SCOOT_APPLYALL_FONTS",
        payloadKey = "fontKey",
        noun = "font",
        abortLabel = "Fonts",
        displayName = function(pending)
            return addon.FontDisplayNames and addon.FontDisplayNames[pending] or pending
        end,
    },
    {
        key = "applyAllTextures",
        controlsField = "_applyAllTexturesControls",
        containerHeight = 260,
        infoText = "Select a texture below, then click Apply. This will overwrite every Scoot bar texture (foreground and background) and force a UI reload. Tint, opacity, and color settings remain unchanged.",
        selectorMethod = "CreateBarTextureSelector",
        selectorLabel = "Texture",
        selectorOffsetY = -100,
        buttonOffsetY = -180,
        pendingDefault = "default",
        getPendingName = "GetPendingBarTexture",
        setPendingName = "SetPendingBarTexture",
        applyName = "ApplyBarTextures",
        dialogId = "SCOOT_APPLYALL_TEXTURES",
        payloadKey = "textureKey",
        noun = "texture",
        abortLabel = "Bar Textures",
        displayName = function(pending)
            return addon.Media and addon.Media.GetBarTextureDisplayName
                and addon.Media.GetBarTextureDisplayName(pending) or pending
        end,
    },
}

-- Note: Controls are stored on panel[mode.controlsField] for ClearContent() compatibility;
-- navigation.lua ClearContent() looks for the two literal field names.

-- Kept off Builder:AddTextStyleBlock: the page writes one face to every component and has no builder-backed storage.
local function CreateRenderer(mode)
    local function render(panel, scrollContent)
        panel:ClearContent()

        local Controls = addon.UI.Controls
        local Theme = addon.UI.Theme

        -- Track controls for cleanup on the PANEL (not module) so ClearContent() can find them
        panel[mode.controlsField] = panel[mode.controlsField] or {}
        for _, ctrl in ipairs(panel[mode.controlsField]) do
            if ctrl.Cleanup then ctrl:Cleanup() end
            if ctrl.Hide then ctrl:Hide() end
            if ctrl.SetParent then ctrl:SetParent(nil) end
        end
        panel[mode.controlsField] = {}
        local controls = panel[mode.controlsField]

        -- Container frame for layout
        local container = CreateFrame("Frame", nil, scrollContent)
        container:SetSize(500, mode.containerHeight)
        container:SetPoint("TOP", scrollContent, "TOP", 0, -60)
        container:SetPoint("LEFT", scrollContent, "LEFT", 40, 0)
        container:SetPoint("RIGHT", scrollContent, "RIGHT", -40, 0)
        table.insert(controls, container)

        -- Info text (centered, dimmed)
        local info = container:CreateFontString(nil, "OVERLAY")
        info:SetFont(Theme:GetFont("LABEL"), 12, "")
        info:SetPoint("TOP", container, "TOP", 0, 0)
        info:SetWidth(420)
        info:SetJustifyH("CENTER")
        info:SetText(mode.infoText)
        info:SetTextColor(0.6, 0.6, 0.6, 1)

        -- Selector row (larger, minimal label)
        local selector = Controls[mode.selectorMethod](Controls, {
            parent = container,
            label = mode.selectorLabel,
            get = function()
                local aa = addon.ApplyAll
                return aa and aa[mode.getPendingName](aa) or mode.pendingDefault
            end,
            set = function(valueKey)
                local aa = addon.ApplyAll
                if aa and aa[mode.setPendingName] then
                    aa[mode.setPendingName](aa, valueKey)
                end
            end,
            width = 320,
            labelFontSize = 16,
            selectorHeight = 35,
            rowHeight = 52,
        })
        if selector then
            selector:SetPoint("TOPLEFT", container, "TOPLEFT", 20, mode.selectorOffsetY)
            selector:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, mode.selectorOffsetY)
            table.insert(controls, selector)
        end

        local selectPrompt = "Select a " .. mode.noun .. " before applying."

        -- Apply button
        local applyBtn = Controls:CreateButton({
            parent = container,
            text = "Apply",
            width = 160,
            height = 38,
            fontSize = 14,
            onClick = function()
                local aa = addon.ApplyAll
                local pending = aa and aa[mode.getPendingName](aa)
                if not pending or pending == "" then
                    if addon.Print then addon:Print(selectPrompt) end
                    return
                end

                local displayName = mode.displayName(pending)

                if addon.Dialogs and addon.Dialogs.Show then
                    addon.Dialogs:Show(mode.dialogId, {
                        formatArgs = { displayName },
                        data = { [mode.payloadKey] = pending },
                        onAccept = function(data)
                            local value = data and data[mode.payloadKey]
                            if not value then return end
                            if not addon.ApplyAll or not addon.ApplyAll[mode.applyName] then return end

                            local result = addon.ApplyAll[mode.applyName](addon.ApplyAll, value, { updatePending = true })
                            if result and result.ok and result.changed and result.changed > 0 then
                                ReloadUI()
                            else
                                local reason = result and result.reason or "Unknown"
                                local friendly = {
                                    noProfile = "Profile database unavailable.",
                                    noSelection = selectPrompt,
                                    noChanges = "All entries already use that " .. mode.noun .. ".",
                                }
                                local detail = friendly[reason] or tostring(reason or "Unknown error.")
                                if addon.Print then
                                    addon:Print("Apply All (" .. mode.abortLabel .. ") aborted: " .. detail)
                                end
                            end
                        end,
                    })
                else
                    if addon.Print then addon:Print("Dialog system unavailable.") end
                end
            end,
        })
        applyBtn:SetPoint("TOP", container, "TOP", 0, mode.buttonOffsetY)
        table.insert(controls, applyBtn)

        -- Set scroll content height
        scrollContent:SetHeight(400)
    end

    return render
end

for _, mode in ipairs(MODES) do
    addon.UI.SettingsPanel:RegisterRenderer(mode.key, CreateRenderer(mode))
end
