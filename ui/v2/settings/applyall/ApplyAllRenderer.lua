-- ApplyAllRenderer.lua - Global Font and Bar Texture settings pages
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.ApplyAll = addon.UI.Settings.ApplyAll or {}

local function FontDisplayName(key)
    return addon.FontDisplayNames and addon.FontDisplayNames[key] or key
end

local function TextureDisplayName(key)
    return addon.Media and addon.Media.GetBarTextureDisplayName
        and addon.Media.GetBarTextureDisplayName(key) or key
end

local MODES = {
    {
        key = "applyAllFonts",
        controlsField = "_applyAllFontsControls",
        containerHeight = 340,
        scrollHeight = 460,
        infoText = "Any Scoot font field can hold the Global Header Font or Global Body Font token, picked from its font picker, and follow the values set here. Apply commits both values and reloads the UI.\n\nScrolling Combat Text is excluded: its font changes need a full game restart.",
        selectors = {
            { method = "CreateFontSelector", label = "Header Font", offsetY = -130,
              getName = "GetPendingHeaderFont", setName = "SetPendingHeaderFont" },
            { method = "CreateFontSelector", label = "Body Font", offsetY = -186,
              getName = "GetPendingBodyFont", setName = "SetPendingBodyFont" },
        },
        buttonOffsetY = -262,
        applyName = "ApplyFonts",
        dialogId = "SCOOT_APPLYALL_FONTS",
        noun = "font",
        abortLabel = "Fonts",
        displayName = FontDisplayName,
        alreadySetText = "The Global Fonts already hold those values; no reload needed.",
    },
    {
        key = "applyAllTextures",
        controlsField = "_applyAllTexturesControls",
        containerHeight = 260,
        scrollHeight = 400,
        infoText = "Any Scoot bar texture field can hold the Global Bar Texture token, picked from its texture picker, and follow the value set here. Apply commits the value and reloads the UI.",
        selectors = {
            { method = "CreateBarTextureSelector", label = "Bar Texture", offsetY = -100,
              getName = "GetPendingBarTexture", setName = "SetPendingBarTexture" },
        },
        buttonOffsetY = -180,
        applyName = "ApplyBarTextures",
        dialogId = "SCOOT_APPLYALL_TEXTURES",
        noun = "texture",
        abortLabel = "Bar Textures",
        displayName = TextureDisplayName,
        alreadySetText = "The Global Bar Texture is already set to that texture; no reload needed.",
    },
}

-- Note: Controls are stored on panel[mode.controlsField] for ClearContent() compatibility;
-- navigation.lua ClearContent() looks for the two literal field names.

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

        -- Selector rows (larger, minimal labels); pickers opened here must not
        -- offer the token buttons -- a global holding a token would be circular
        for _, sel in ipairs(mode.selectors) do
            local selector = Controls[sel.method](Controls, {
                parent = container,
                label = sel.label,
                get = function()
                    local aa = addon.ApplyAll
                    return aa and aa[sel.getName](aa)
                end,
                set = function(valueKey)
                    local aa = addon.ApplyAll
                    if aa and aa[sel.setName] then
                        aa[sel.setName](aa, valueKey)
                    end
                end,
                width = 320,
                labelFontSize = 16,
                selectorHeight = 35,
                rowHeight = 52,
                suppressTokens = true,
            })
            if selector then
                selector:SetPoint("TOPLEFT", container, "TOPLEFT", 20, sel.offsetY)
                selector:SetPoint("TOPRIGHT", container, "TOPRIGHT", -20, sel.offsetY)
                table.insert(controls, selector)
            end
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
                if not aa then return end

                local values = {}
                for i, sel in ipairs(mode.selectors) do
                    local value = aa[sel.getName](aa)
                    if not value or value == "" then
                        if addon.Print then addon:Print(selectPrompt) end
                        return
                    end
                    values[i] = value
                end

                local formatArgs = {}
                for i, value in ipairs(values) do
                    formatArgs[i] = mode.displayName(value)
                end

                if addon.Dialogs and addon.Dialogs.Show then
                    addon.Dialogs:Show(mode.dialogId, {
                        formatArgs = formatArgs,
                        data = { values = values },
                        onAccept = function(data)
                            local vals = data and data.values
                            if not vals then return end
                            if not addon.ApplyAll or not addon.ApplyAll[mode.applyName] then return end

                            local result = addon.ApplyAll[mode.applyName](addon.ApplyAll, unpack(vals))
                            if result and result.ok then
                                ReloadUI()
                            elseif result and result.reason == "noChanges" then
                                if addon.Print then addon:Print(mode.alreadySetText) end
                            else
                                local reason = result and result.reason or "Unknown"
                                local friendly = {
                                    noDatabase = "Settings database unavailable.",
                                    noSelection = selectPrompt,
                                    tokenValue = "A Global value cannot be a Global token.",
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
        scrollContent:SetHeight(mode.scrollHeight)
    end

    return render
end

for _, mode in ipairs(MODES) do
    addon.UI.SettingsPanel:RegisterRenderer(mode.key, CreateRenderer(mode))
end
