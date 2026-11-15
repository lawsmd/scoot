-- NotesRenderer.lua - Notes settings renderer: the look every note shares.
-- Notes are made, written and deleted on screen (core/components/notes/).
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.Notes = {}

local Notes = addon.UI.Settings.Notes
local SettingsBuilder = addon.UI.SettingsBuilder

--------------------------------------------------------------------------------
-- Render Function
--------------------------------------------------------------------------------

function Notes.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        Notes.Render(panel, scrollContent)
    end)

    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers("notes")

    builder:AddDescription(
        "Right-click the minimap button and choose Create Note. " ..
        "The pencil on a note edits it and the X deletes it. Drag a note to move it, " ..
        "click its title to collapse it and right-click the title to rename it. " ..
        "Fonts come from your Tooltip settings."
    )
    builder:AddDescription(
        "While editing: # Heading, ## Smaller heading, - bullet, 1. numbered, " ..
        "[ ] checkbox, --- line, > quote, **emphasis**. " ..
        "A first line that starts with # is the note's title. " ..
        "Clicking a checkbox removes its line."
    )

    builder:AddSection("Text")

    builder:AddSlider({
        label = "Scale",
        min = 0.25,
        max = 2.0,
        step = 0.05,
        precision = 2,
        minLabel = "25%",
        maxLabel = "200%",
        get = function() return h.get("scale") or 1.0 end,
        set = function(val) h.setAndApply("scale", val) end,
    })

    builder:AddColorPicker({
        label = "Header Color",
        get = function() return h.get("headerColor") or { 0.1, 1.0, 0.1, 1 } end,
        set = function(r, g, b, a) h.setAndApply("headerColor", { r, g, b, a }) end,
        hasAlpha = true,
    })

    builder:AddColorPicker({
        label = "Text Color",
        get = function() return h.get("bodyColor") or { 1, 1, 1, 1 } end,
        set = function(r, g, b, a) h.setAndApply("bodyColor", { r, g, b, a }) end,
        hasAlpha = true,
    })

    builder:AddSection("Window")

    -- Art rows and art border entries appear only where the client offers
    -- them (core/panelart.lua).
    local borderOrder = { "tooltip", "none" }
    local borderValues = { tooltip = "Tooltip", none = "None" }
    local artBorders = {}
    if addon.PanelArt then
        local order, values = addon.PanelArt.Entries("border")
        for _, key in ipairs(order) do
            borderOrder[#borderOrder + 1] = key
            borderValues[key] = values[key]
            artBorders[key] = true
        end
    end
    local function borderStyle()
        local key = h.get("windowBorderStyle") or "tooltip"
        return borderValues[key] and key or "tooltip"
    end

    builder:AddPanelArtSelector({ slot = "window",
        get = function() return h.get("windowBackdropTexture") end,
        set = function(v) h.setAndApply("windowBackdropTexture", v) end })
    builder:AddSlider({ label = "Backdrop Opacity", min = 0, max = 100, step = 1,
        get = function() return h.get("windowBackdropOpacity") or 100 end,
        set = function(v) h.setAndApply("windowBackdropOpacity", v) end })
    builder:AddSelector({ label = "Border Style", values = borderValues, order = borderOrder,
        get = borderStyle,
        set = function(v)
            h.setAndApply("windowBorderStyle", v)
            builder:DeferredRefreshAll()
        end })
    local titleArt = builder:AddPanelArtSelector({ slot = "title", label = "Title Backdrop",
        plain = "none", plainLabel = "None",
        get = function() return h.get("titleBarBackdropTexture") end,
        set = function(v)
            h.setAndApply("titleBarBackdropTexture", v)
            builder:DeferredRefreshAll()
        end })
    -- The title's art and an art border both draw at this opacity.
    builder:AddSlider({ label = "Title Opacity", min = 0, max = 100, step = 1,
        get = function() return h.get("titleBarBackdropOpacity") or 100 end,
        set = function(v) h.setAndApply("titleBarBackdropOpacity", v) end,
        isDisabled = function() return titleArt() == "none" and not artBorders[borderStyle()] end })

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("notes", function(panel, scrollContent)
    Notes.Render(panel, scrollContent)
end)

--------------------------------------------------------------------------------
-- Return module
--------------------------------------------------------------------------------

return Notes
