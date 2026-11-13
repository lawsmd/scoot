-- KeybindsRenderer.lua - Quality of Life: Keybinds profiles, export and import page
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

-- The selector's entry while the binding set has no profile selected.
local NONE = "none"

local KEY_SELECTOR = "profile"
local KEY_ACTIONS = "profileActions"
local CHECK_ICON = { texture = "Interface\\Buttons\\UI-CheckBox-Check" }

-- The panel showing this page, and the repaint of the Apply and Save state
-- while the profiles section is built.
local currentPanel, paintState

local function promptSave(id, paint)
    local KB = addon.Keybinds
    Controls:ShowDialog(nil, {
        text = "Overwrite " .. (KB.Profiles.Name(id) or "this keybind profile") .. " with the keys bound now?",
        acceptText = "Save",
        acceptWidth = 120,
        onAccept = function()
            local ok, err = KB.Profiles.Save(id)
            if not ok then info(err or "The profile was not saved.") end
            paint()
        end,
    })
end

local function applyProfile(id, paint)
    local KB = addon.Keybinds
    local result, err = KB.Profiles.Apply(id)
    if not result then
        info(err or "The profile was not applied.")
    elseif #result.failed > 0 then
        info("Applied " .. (KB.Profiles.Name(id) or "the keybind profile") .. "." .. KB.FailedText(result))
    end
    paint()
end

local function promptNew(inner)
    local KB = addon.Keybinds
    Controls:ShowDialog(nil, {
        text = "Save the keys bound now as a new keybind profile:",
        hasEditBox = true,
        editBoxText = "",
        acceptText = "Create",
        acceptWidth = 120,
        onAccept = function(_, name)
            local id, err = KB.Profiles.Create(name)
            if not id then
                info(err or "The profile was not created.")
                return
            end
            inner:DeferredRefreshAll()
        end,
    })
end

local function promptRename(inner)
    local KB = addon.Keybinds
    local id = KB.Profiles.SelectedId()
    if not id then return end
    Controls:ShowDialog(nil, {
        text = "Rename this keybind profile:",
        hasEditBox = true,
        editBoxText = KB.Profiles.Name(id) or "",
        acceptText = "Rename",
        acceptWidth = 120,
        onAccept = function(_, name)
            local ok, err = KB.Profiles.Rename(id, name)
            if not ok then
                info(err or "The profile was not renamed.")
                return
            end
            inner:DeferredRefreshAll()
        end,
    })
end

local function promptDelete(inner)
    local KB = addon.Keybinds
    local options = {}
    for _, entry in ipairs(KB.Profiles.List()) do
        options[#options + 1] = { value = entry.id, label = entry.name }
    end
    if #options == 0 then return end
    Controls:ShowDialog(nil, {
        text = "Choose a keybind profile to delete. The keys bound now stay as they are.",
        listOptions = options,
        selectedValue = KB.Profiles.SelectedId(),
        acceptText = "Delete",
        acceptWidth = 120,
        onAccept = function(_, _, id)
            if id ~= nil then KB.Profiles.Delete(id) end
            inner:DeferredRefreshAll()
        end,
    })
end

-- The selector only selects; "None" is listed only while it is true. Apply
-- and Save read one comparison per paint, since it walks every command.
local function buildProfiles(_, inner)
    local KB = addon.Keybinds
    local values, order = {}, {}
    if not KB.Profiles.SelectedId() then
        values[NONE] = "None"
        order[1] = NONE
    end
    for _, entry in ipairs(KB.Profiles.List()) do
        values[entry.id] = entry.name
        order[#order + 1] = entry.id
    end

    local function isApplied()
        local id = KB.Profiles.SelectedId()
        return id ~= nil and KB.Profiles.Matches(id)
    end
    local applied = isApplied()

    local function paint()
        local row, actions = inner:GetControl(KEY_SELECTOR), inner:GetControl(KEY_ACTIONS)
        if not (row and actions) then return end
        applied = isApplied()
        local apply = row:GetButton()
        apply:SetEnabled(KB.Profiles.SelectedId() ~= nil)
        apply:SetText(applied and "Applied" or "Apply")
        apply:SetIcon(applied and CHECK_ICON or nil)
        apply:SetTone(applied and "success" or nil)
        actions:Refresh()
    end

    inner:AddSelector({
        key = KEY_SELECTOR,
        label = "Profile",
        values = values,
        order = order,
        sizeScale = 1.25,
        get = function() return KB.Profiles.SelectedId() or NONE end,
        set = function(id)
            if id == NONE then return end
            KB.Profiles.Select(id)
            inner:DeferredRefreshAll()
        end,
        button = {
            text = "Apply",
            width = 150,
            tooltip = function()
                if not KB.Profiles.SelectedId() then return "Choose or create a keybind profile first." end
            end,
            onClick = function()
                local id = KB.Profiles.SelectedId()
                if id and not applied then applyProfile(id, paint) end
            end,
        },
    })
    inner:AddButtonRow({
        key = KEY_ACTIONS,
        noBottomBorder = true,
        buttons = {
            { text = "New", onClick = function() promptNew(inner) end },
            {
                text = "Rename",
                onClick = function() promptRename(inner) end,
                isDisabled = function() return not KB.Profiles.SelectedId() end,
            },
            {
                text = "Delete",
                onClick = function() promptDelete(inner) end,
                isDisabled = function() return #KB.Profiles.List() == 0 end,
            },
            {
                text = "Save",
                onClick = function()
                    local id = KB.Profiles.SelectedId()
                    if id then promptSave(id, paint) end
                end,
                isHidden = function() return applied or not KB.Profiles.SelectedId() end,
            },
        },
    })
    inner:Finalize()

    -- The search scan builds this section with no controls behind it.
    if inner:GetControl(KEY_SELECTOR) then
        paint()
        paintState = paint
    end
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

-- Only a product whose action bars provide the hover mode sets KB.Mode.
local function addModeRow(builder)
    local mode = addon.Keybinds.Mode
    if not mode then return end
    builder:AddButtonRow({
        emphasized = true,
        justify = "CENTER",
        noBottomBorder = true,
        buttons = {
            {
                text = "Enter Keybind Mode",
                width = 240,
                tooltip = function() return mode.DisabledReason() end,
                isDisabled = function() return mode.DisabledReason() ~= nil end,
                onClick = function()
                    local ok, err = mode.Enter()
                    if not ok then info(err or "Keybind Mode could not start.") end
                end,
            },
        },
    })
end

function Page.Render(panel, scrollContent)
    panel:ClearContent()
    currentPanel, paintState = panel, nil

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    -- A dialog can outlive a page change, and its refresh must not draw this
    -- page over the one the player moved to.
    builder:SetOnRefresh(function()
        if panel._currentCategoryKey == NAV_KEY then Page.Render(panel, scrollContent) end
    end)

    addModeRow(builder)

    builder:AddCollapsibleSection({
        title = "Keybind Profiles",
        componentId = NAV_KEY,
        sectionKey = "profiles",
        buildContent = buildProfiles,
    })

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

-- Any change to the live keys, from any surface, repaints Apply and Save. One
-- apply fires the event many times, so the repaints fold into one.
local repaintQueued = false
addon.Events.On("UI:QoLKeybinds", "UPDATE_BINDINGS", function()
    if repaintQueued then return end
    repaintQueued = true
    C_Timer.After(0, function()
        repaintQueued = false
        if paintState and currentPanel and currentPanel._currentCategoryKey == NAV_KEY then
            paintState()
        end
    end)
end)

return Page
