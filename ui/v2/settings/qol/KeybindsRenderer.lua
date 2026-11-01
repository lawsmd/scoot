-- KeybindsRenderer.lua - Quality of Life: Keybinds export and import page
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.Keybinds = {}

local Page = addon.UI.Settings.QoL.Keybinds
local SettingsBuilder = addon.UI.SettingsBuilder
local Controls = addon.UI.Controls

local NAV_KEY = "qolKeybinds"

local function info(message)
    Controls:InfoDialog(message)
end

-- Export: the box, read-only, then Generate, which fills it, focuses it and
-- selects the text for Ctrl+C. The text lives in addon.Keybinds.state, so a
-- collapse or a page change rebuilds the box with it.
local function buildExport(_, inner)
    local KB = addon.Keybinds
    inner:AddMultiLineEditBox({
        key = "exportBox",
        readOnly = true,
        fontSize = 11,
        height = 110,
        placeholder = "Press Generate, then Ctrl+C.",
        get = function() return KB.state.exportText end,
    })
    inner:AddButtonRow({
        noBottomBorder = true,
        buttons = {
            {
                text = "Generate Keybind String",
                onClick = function()
                    local str, err = KB.Export()
                    if not str then
                        info(err or "Export failed.")
                        return
                    end
                    KB.state.exportText = str
                    local box = inner:GetControl("exportBox")
                    if box then
                        box:SetText(str)
                        C_Timer.After(0.05, function()
                            box:SetFocus()
                            box:SelectAll()
                        end)
                    end
                end,
            },
        },
    })
    inner:Finalize()
end

-- Import: the box, then Import, which decodes, previews, confirms and
-- applies. Combat is checked at the click and again at the accept, since the
-- dialog can outlive a pull.
local function buildImport(_, inner)
    local KB = addon.Keybinds
    local IE = addon.ImportExport
    inner:AddMultiLineEditBox({
        key = "importBox",
        fontSize = 11,
        height = 110,
        placeholder = "Paste a " .. ((IE and IE.PREFIX_KEYBINDS) or "keybind") .. " string here.",
        get = function() return KB.state.importText end,
        set = function(text) KB.state.importText = text or "" end,
    })
    inner:AddButtonRow({
        noBottomBorder = true,
        buttons = {
            {
                text = "Import Keybinds",
                onClick = function()
                    if InCombatLockdown() then
                        info(KB.COMBAT_MESSAGE)
                        return
                    end
                    local box = inner:GetControl("importBox")
                    local text = (box and box:GetText()) or KB.state.importText
                    KB.state.importText = text or ""
                    local envelope, err = KB.Decode(text)
                    if not envelope then
                        info(err or "Import failed.")
                        return
                    end
                    local preview, previewErr = KB.Preview(envelope)
                    if not preview then
                        info(previewErr or "Import failed.")
                        return
                    end
                    Controls:ShowDialog(nil, {
                        text = KB.ConfirmText(envelope, preview),
                        acceptText = "Import",
                        acceptWidth = 120,
                        onAccept = function()
                            if InCombatLockdown() then
                                info(KB.COMBAT_MESSAGE)
                                return
                            end
                            local result, applyErr = KB.Apply(envelope)
                            if result then
                                info(KB.ResultText(envelope, result))
                            else
                                info(applyErr or "Import failed.")
                            end
                        end,
                    })
                end,
            },
        },
    })
    inner:Finalize()
end

function Page.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    builder:SetOnRefresh(function() Page.Render(panel, scrollContent) end)

    builder:AddCollapsibleSection({
        title = "Export",
        componentId = NAV_KEY,
        sectionKey = "export",
        buildContent = buildExport,
    })

    builder:AddCollapsibleSection({
        title = "Import",
        componentId = NAV_KEY,
        sectionKey = "import",
        buildContent = buildImport,
    })

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Page.Render(panel, scrollContent)
end)

return Page
