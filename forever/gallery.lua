--------------------------------------------------------------------------------
-- forever/gallery.lua
-- /camelot gallery: one of each Blizzard chrome part in a lab window, with a
-- readout of what the running client resolves.
--
-- The settings framework takes a skin's word for how each surface is drawn,
-- and on Forever a retail template or atlas name draws that client's own art.
-- This window is where a part is looked at before a skin names it: every
-- candidate template, nine-slice layout and atlas from the borrow list, built
-- once each and labelled, blank where the client lacks it.
--
-- Everything is built under pcall. A template or frame type one client lacks
-- reports as missing in its cell and in the report; nothing aborts. The
-- report goes to the copyable window, never to chat. It also reads every
-- atlas Blizzard's own Legacy pane draws, when that pane has been opened, so
-- a part copied from it is named from the client rather than from a sheet.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CELL_W, CELL_H = 220, 110
local COLUMNS = 4
local GROUP_GAP = 28
local WINDOW_W, WINDOW_H = 960, 640

--------------------------------------------------------------------------------
-- Candidates
--------------------------------------------------------------------------------

-- Templates the settings panel could build its chrome from. `setup` runs
-- under pcall after construction, so a method one build lacks costs nothing.
local TEMPLATES = {
    { label = "UIPanelButtonTemplate", frameType = "Button", template = "UIPanelButtonTemplate",
      setup = function(f)
          f:SetText("Edit Mode")
          if f.FitToText then f:FitToText() else f:SetSize(110, 22) end
      end },
    { label = "UIPanelCloseButton", frameType = "Button", template = "UIPanelCloseButton" },
    { label = "MinimalCheckboxTemplate", frameType = "CheckButton", template = "MinimalCheckboxTemplate",
      setup = function(f) f:SetChecked(true) end },
    { label = "UICheckButtonTemplate", frameType = "CheckButton", template = "UICheckButtonTemplate",
      setup = function(f) f:SetChecked(true) end },
    { label = "MinimalSliderWithSteppersTemplate", frameType = "Frame", template = "MinimalSliderWithSteppersTemplate",
      size = { 200, 40 }, setup = function(f) f:Init(50, 0, 100, 100) end },
    { label = "WowStyle1DropdownTemplate", frameType = "DropdownButton", template = "WowStyle1DropdownTemplate",
      size = { 140, 25 },
      setup = function(f)
          f:SetupMenu(function(_, root)
              root:CreateRadio("Bronze", function() return true end, function() end)
              root:CreateRadio("Gray", function() return false end, function() end)
          end)
          if f.SetDefaultText then f:SetDefaultText("Bronze") end
      end },
    { label = "MinimalScrollBar", frameType = "EventFrame", template = "MinimalScrollBar", size = { 8, 90 },
      setup = function(f)
          if f.Init then f:Init(0.4, 0.1) else f:SetVisibleExtentPercentage(0.4) end
      end },
    { label = "MinimalTabTemplate", frameType = "Button", template = "MinimalTabTemplate", size = { 100, 37 },
      setup = function(f)
          f:SetText("General")
          if f.SetSelected then f:SetSelected(true) end
      end },
    { label = "PanelTabButtonTemplate", frameType = "Button", template = "PanelTabButtonTemplate", size = { 100, 32 },
      setup = function(f) f:SetText("Player") end },
    { label = "ListHeaderThreeSliceTemplate", frameType = "Button", template = "ListHeaderThreeSliceTemplate",
      size = { 190, 30 }, setup = function(f) if f.Text then f.Text:SetText("Section") end end },
    { label = "SettingsFrameTemplate", frameType = "Frame", template = "SettingsFrameTemplate", size = { 200, 96 } },
    { label = "InsetFrameTemplate", frameType = "Frame", template = "InsetFrameTemplate", size = { 200, 80 } },
    -- The Legacy pane's window: the portrait panel with its title plate,
    -- close button and ring
    { label = "PortraitFrameTemplate", frameType = "Frame", template = "PortraitFrameTemplate", size = { 190, 84 },
      setup = function(f)
          f:SetTitle("Portrait")
          f:SetPortraitToAsset(addon.MinimapIcon or "Interface\\ICONS\\INV_Misc_QuestionMark")
      end },
    -- The Legacy pane's cell button. Its OnLoad reads XML key values a bare
    -- construct does not supply, so the construct is expected to fail and
    -- the template's presence is the answer that matters.
    { label = "RingedMaskedButtonTemplate", frameType = "CheckButton", template = "RingedMaskedButtonTemplate",
      size = { 67, 67 }, note = "OnLoad wants XML key values; a bare construct is expected to fail" },
    { label = "LargeSideTabButtonTemplate", frameType = "Frame", template = "LargeSideTabButtonTemplate", size = { 43, 55 } },
}

-- Nine-slice layouts applied to a bare frame. A kit formats the piece names,
-- which is how the options border becomes optionsframe-nineslice-*.
local NINE_SLICES = {
    { label = "UniqueCornersLayout / OptionsFrame", layout = "UniqueCornersLayout", kit = "OptionsFrame" },
    { label = "UniqueCornersLayout / SliderBar", layout = "UniqueCornersLayout", kit = "SliderBar" },
    { label = "ButtonFrameTemplateNoPortrait", layout = "ButtonFrameTemplateNoPortrait" },
    { label = "SimplePanelTemplate", layout = "SimplePanelTemplate" },
    { label = "Dialog", layout = "Dialog" },
    { label = "InsetFrameTemplate", layout = "InsetFrameTemplate" },
    { label = "GenericMetal", layout = "GenericMetal" },
    { label = "PortraitFrameTemplate", layout = "PortraitFrameTemplate" },
}

-- Atlases drawn at native size. The last one is the art-set probe: its file
-- id says which set the client is serving.
local ATLASES = {
    "optionsframe-nineslice-cornertopleft",
    "ui-frame-metal-cornertopleft",
    "heavybronze-frame-basic",
    "heavybronze-frame-background",
    "common-internaltab",
    "common-internaltab-hover",
    "common-internaltab-selected",
    "common-button-list-mid",
    "common-button-list-large",
    "common-button-list-large-hover",
    "common-button-list-large-selected",
    "minimal-scrollbar-arrow-top",
    "minimal_sliderbar_button",
    "checkbox-minimal",
    "checkmark-minimal",
    "common-dropdown-a-button",
    "common-search-border-middle",
    "RedButton-Exit",
    "Options_Tab_Middle",
    "uiframe-activetab-left",
    "common-sidetab",
    "common-sidetab-selected",
    -- The Legacy pane's own parts, drawn by Blizzard without the Forever suffix
    "Legacy-Tree-Frame-background",
    "Legacy-Tree-Frame-divider-Vertical",
    "Legacy-Tree-Frame-Card",
    "Legacy-Tree-Frame-Card-Glow",
    "UI-Legacy-Tree-Professions",
    "ui-hud-unitframe-player-portraiton",
}

local ART_SET_PROBE = "ui-hud-unitframe-player-portraiton"
local ART_SET_FILES = { [8036209] = "set 1 (Forever)", [4642466] = "set 0 (retail)" }
local FOREVER_SUFFIX = "-c60"

--------------------------------------------------------------------------------
-- Readout helpers
--------------------------------------------------------------------------------

local function atlasInfo(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if ok and type(info) == "table" then return info end
    return nil
end

local function atlasLine(name)
    local info = atlasInfo(name)
    if not info then return string.format("%-44s nil", name) end
    local tiles = (info.tilesHorizontally and "H" or "") .. (info.tilesVertically and "V" or "")
    -- The texcoords are what a sliced card's slice widths are read from
    return string.format("%-44s file %s  %dx%d%s  tc %.4f %.4f %.4f %.4f", name, tostring(info.file),
        info.width or 0, info.height or 0, tiles ~= "" and ("  tiles " .. tiles) or "",
        info.leftTexCoord or 0, info.rightTexCoord or 0, info.topTexCoord or 0, info.bottomTexCoord or 0)
end

local function templateInfo(name)
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return nil, "no C_XMLUtil" end
    local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
    if not ok then return nil, "error" end
    return info, info and "present" or "missing"
end

-- The kit-formatted atlas name a nine-slice piece resolves to.
local function pieceAtlas(pieceLayout, kit)
    local atlas = pieceLayout and pieceLayout.atlas
    if type(atlas) ~= "string" then return nil end
    if kit and atlas:find("%%s") then return string.format(atlas, kit) end
    return atlas
end

local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                 "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

--------------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------------

-- Constructions the report reads back after the lab is built.
local built = {}

local function labelCell(cell, text, missing)
    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 4, 4)
    label:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -4, 4)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(missing and ("|cffff5555[missing]|r " .. text) or text)
end

local function newCell(parent, x, y)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(CELL_W, CELL_H)
    cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local bg = cell:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.25)
    return cell
end

local function buildTemplateCell(cell, entry)
    local ok, frame = pcall(CreateFrame, entry.frameType, nil, cell, entry.template)
    if not ok or not frame then
        built[entry.label] = { missing = true, err = tostring(frame) }
        labelCell(cell, entry.label, true)
        return
    end
    if entry.size then frame:SetSize(entry.size[1], entry.size[2]) end
    frame:SetPoint("CENTER", cell, "CENTER", 0, 8)
    local setupOk, err = true, nil
    if entry.setup then setupOk, err = pcall(entry.setup, frame) end
    built[entry.label] = { frame = frame, setupOk = setupOk, err = err }
    labelCell(cell, entry.label, false)
end

local function buildNineSliceCell(cell, entry)
    local layout = NineSliceLayouts and NineSliceLayouts[entry.layout]
    if not (layout and NineSliceUtil and NineSliceUtil.ApplyLayout) then
        built[entry.label] = { missing = true }
        labelCell(cell, entry.label, true)
        return
    end
    local frame = CreateFrame("Frame", nil, cell)
    frame:SetSize(200, 84)
    frame:SetPoint("CENTER", cell, "CENTER", 0, 8)
    local ok, err = pcall(NineSliceUtil.ApplyLayout, frame, layout, entry.kit)
    built[entry.label] = { frame = frame, setupOk = ok, err = err, missing = not ok }
    labelCell(cell, entry.label, not ok)
end

local function buildAtlasCell(cell, name)
    local info = atlasInfo(name)
    if not info then
        labelCell(cell, name, true)
        return
    end
    local tex = cell:CreateTexture(nil, "ARTWORK")
    local w, h = info.width or 32, info.height or 32
    local maxW, maxH = CELL_W - 20, CELL_H - 40
    local scale = math.min(1, maxW / math.max(w, 1), maxH / math.max(h, 1))
    tex:SetSize(math.max(1, w * scale), math.max(1, h * scale))
    tex:SetPoint("CENTER", cell, "CENTER", 0, 8)
    pcall(tex.SetAtlas, tex, name)
    labelCell(cell, name, false)
end

--------------------------------------------------------------------------------
-- The lab window
--------------------------------------------------------------------------------

local lab

local function groupHeading(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    fs:SetText(text)
    return y - GROUP_GAP
end

-- Lays one group of cells out in rows of COLUMNS and returns the next y.
local function layGroup(parent, count, y, buildOne)
    for i = 1, count do
        local col = (i - 1) % COLUMNS
        local row = math.floor((i - 1) / COLUMNS)
        local cell = newCell(parent, 4 + col * (CELL_W + 8), y - row * (CELL_H + 8))
        buildOne(cell, i)
    end
    local rows = math.ceil(count / COLUMNS)
    return y - rows * (CELL_H + 8) - 12
end

local function buildLab()
    local f = CreateFrame("Frame", (addon.Brand or "Scoot") .. "ChromeGallery", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", f.TitleBg, "LEFT", 6, 0)
    title:SetText((addon.Brand or "Scoot") .. " chrome gallery")

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(COLUMNS * (CELL_W + 8) + 4)
    scroll:SetScrollChild(child)

    local y = -4
    y = groupHeading(child, "Templates", y)
    y = layGroup(child, #TEMPLATES, y, function(cell, i) buildTemplateCell(cell, TEMPLATES[i]) end)
    y = groupHeading(child, "Nine-slice layouts", y)
    y = layGroup(child, #NINE_SLICES, y, function(cell, i) buildNineSliceCell(cell, NINE_SLICES[i]) end)
    y = groupHeading(child, "Atlases at native size", y)
    y = layGroup(child, #ATLASES, y, function(cell, i) buildAtlasCell(cell, ATLASES[i]) end)
    child:SetHeight(-y + 8)

    return f
end

local function showLab()
    if not lab then lab = buildLab() end
    lab:Show()
end

--------------------------------------------------------------------------------
-- The report
--------------------------------------------------------------------------------

-- Every atlas name drawn anywhere under a frame, for the report's read of
-- Blizzard's Legacy pane. Reads only; the frame is Blizzard's.
local function collectAtlases(frame, seen, depth)
    if not frame or depth > 8 then return end
    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetAtlas then
                local ok, atlas = pcall(region.GetAtlas, region)
                if ok and type(atlas) == "string" and atlas ~= "" then seen[atlas] = true end
            end
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            collectAtlases(child, seen, depth + 1)
        end
    end
end

local function fontLine(name)
    local obj = _G[name]
    if not obj or not obj.GetFont then return string.format("%-20s nil", name) end
    local ok, path, height, flags = pcall(obj.GetFont, obj)
    if not ok then return string.format("%-20s error", name) end
    return string.format("%-20s %s  %s  %s", name, tostring(path), tostring(height), tostring(flags))
end

local function report()
    if not lab then lab = buildLab() end
    local lines, push = addon.DebugLines("=== Chrome gallery ===", "")

    local ok, version, build, date, toc = pcall(GetBuildInfo)
    if ok then
        push("client:   %s (%s) %s  interface %s", tostring(version), tostring(build), tostring(date), tostring(toc))
    end
    local probe = atlasInfo(ART_SET_PROBE)
    local setName = probe and (ART_SET_FILES[probe.file] or ("unknown, file " .. tostring(probe.file))) or "unresolved"
    push("art set:  %s  (%s)", setName, ART_SET_PROBE)
    push("C_XMLUtil.GetTemplateInfo: %s", (C_XMLUtil and C_XMLUtil.GetTemplateInfo) and "present" or "absent")

    push("")
    push("Templates")
    for _, entry in ipairs(TEMPLATES) do
        local _, state = templateInfo(entry.template)
        local b = built[entry.label] or {}
        local status = b.missing and "construct failed" or "constructed"
        if b.setupOk == false then status = status .. ", setup error: " .. tostring(b.err) end
        if entry.note then status = status .. "  (" .. entry.note .. ")" end
        push("  %-36s %-10s %s", entry.template, tostring(state), status)
    end
    local btn = built["UIPanelButtonTemplate"] and built["UIPanelButtonTemplate"].frame
    if btn and btn.Left and btn.Left.GetTexture then
        local okT, tex = pcall(btn.Left.GetTexture, btn.Left)
        push("  UIPanelButtonTemplate Left texture: %s", okT and tostring(tex) or "error")
    end
    local _, bugsackTab = templateInfo("CharacterFrameTabTemplate")
    push("  %-36s %s  (the template a display addon's tabs asked for)", "CharacterFrameTabTemplate", tostring(bugsackTab))

    push("")
    push("Nine-slice layouts (piece atlas, size)")
    for _, entry in ipairs(NINE_SLICES) do
        local layout = NineSliceLayouts and NineSliceLayouts[entry.layout]
        push("  %s%s", entry.layout, entry.kit and (" / " .. entry.kit) or "")
        if not layout then
            push("    nil")
        else
            for _, piece in ipairs(PIECES) do
                local name = pieceAtlas(layout[piece], entry.kit)
                if name then
                    local info = atlasInfo(name)
                    push("    %-18s %-44s %s", piece, name,
                        info and string.format("%dx%d", info.width or 0, info.height or 0) or "nil")
                end
            end
        end
    end

    push("")
    push("Atlases, each with its Forever-suffixed twin")
    for _, name in ipairs(ATLASES) do
        push("  " .. atlasLine(name))
        push("  " .. atlasLine(name .. FOREVER_SUFFIX))
    end

    push("")
    push("Fonts")
    push("  " .. fontLine("GameFontNormal"))
    push("  " .. fontLine("GameFontHighlight"))

    push("")
    push("Blizzard's Legacy pane")
    local legacy = rawget(_G, "LegacySystemFrame")
    if not legacy then
        push("  LegacySystemFrame absent (a load-on-demand addon; open the pane once, then report again)")
    else
        local okL, layoutType = pcall(function() return legacy.NineSlice and legacy.NineSlice.layoutType end)
        push("  LegacySystemFrame present  NineSlice.layoutType %s", okL and tostring(layoutType) or "error")
        local seen = {}
        pcall(collectAtlases, legacy, seen, 0)
        local names = {}
        for name in pairs(seen) do names[#names + 1] = name end
        table.sort(names)
        push("  atlases drawn under it: %d", #names)
        for _, name in ipairs(names) do
            push("    " .. atlasLine(name))
        end
    end

    push("")
    push("Blizzard's own options panel")
    local okP, layoutType, kit = pcall(function()
        local ns = SettingsPanel and SettingsPanel.NineSlice
        return ns and ns.layoutType, ns and ns.layoutTextureKit
    end)
    push("  SettingsPanel.NineSlice: layoutType %s  textureKit %s",
        okP and tostring(layoutType) or "error", okP and tostring(kit) or "error")

    addon.DebugShowWindow("Chrome gallery", lines)
end

local function probeOne(name)
    if type(name) ~= "string" or name == "" then return addon.Commands.USAGE end
    local lines, push = addon.DebugLines("=== Atlas ===", "")
    push(atlasLine(name))
    push(atlasLine(name .. FOREVER_SUFFIX))
    local info, state = templateInfo(name)
    push("")
    push("as a template: %s", tostring(state))
    if info then
        push("  type %s  size %sx%s  inherits %s", tostring(info.type), tostring(info.width),
            tostring(info.height), tostring(info.inherits))
    end
    addon.DebugShowWindow("Atlas " .. name, lines)
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

addon:RegisterSlashCommand({
    name = "gallery",
    help = "one of each Blizzard chrome part, with an atlas and template readout",
    default = "show",
    verbs = {
        { word = "show", help = "open the lab window", fn = showLab },
        { word = "report", help = "what this client resolves, in the copy window", fn = report },
        { word = "atlas", usage = "atlas <name>", help = "one atlas or template name, with its Forever twin", fn = probeOne },
    },
})
