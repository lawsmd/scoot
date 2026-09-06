-- CDMPicker.lua - Cooldown Manager catalog grid for the ScootAura editor
--
-- The Cooldown Manager is a data source here: its category sets supply a
-- browsable spell catalog so most users never type an ID. One flat grid,
-- alphabetical. Off-catalog IDs stay welcome through the editor's ID box.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.ScootAuraCDMPicker = {}
local Picker = addon.UI.ScootAuraCDMPicker

local CELL_W, CELL_H = 90, 60
local ICON_SIZE = 30

local UnitClass = _G.UnitClass
local GetNumShapeshiftForms = _G.GetNumShapeshiftForms
local GetShapeshiftFormInfo = _G.GetShapeshiftFormInfo

--------------------------------------------------------------------------------
-- Minimal scroll region (wheel + thin thumb), shared with the editor window
--------------------------------------------------------------------------------

function Picker.CreateScrollRegion(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetClipsChildren(true)

    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    child:SetSize(1, 1)
    scrollFrame:SetScrollChild(child)

    local track = scrollFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -1, 0)
    track:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -1, 0)
    track:SetColorTexture(1, 1, 1, 0.06)

    -- All three callers keep their scroll region for the session, so the thumb
    -- goes on the shared accent subscription rather than freezing at the color
    -- the accent happened to be when the region was built.
    local thumb = scrollFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    thumb:SetWidth(4)
    addon.UI.Controls.RegisterThemedFill(thumb, 0.5)

    local function UpdateThumb()
        local viewH = scrollFrame:GetHeight() or 0
        local contentH = child:GetHeight() or 0
        if contentH <= viewH or viewH <= 0 then
            track:Hide()
            thumb:Hide()
            return
        end
        track:Show()
        thumb:Show()
        local thumbH = math.max(20, viewH * (viewH / contentH))
        local maxScroll = contentH - viewH
        local frac = math.min(1, (scrollFrame:GetVerticalScroll() or 0) / maxScroll)
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -1, -frac * (viewH - thumbH))
    end

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then child:SetWidth(w) end
        UpdateThumb()
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
        local target = math.min(maxScroll, math.max(0, (self:GetVerticalScroll() or 0) - delta * 44))
        self:SetVerticalScroll(target)
        UpdateThumb()
    end)

    scrollFrame.ResetScroll = function()
        scrollFrame:SetVerticalScroll(0)
        UpdateThumb()
    end
    scrollFrame.UpdateThumb = UpdateThumb

    return scrollFrame, child
end

--------------------------------------------------------------------------------
-- Catalog data (plain-guarded; the CDM APIs go secret under restrictions)
--------------------------------------------------------------------------------

-- One flat list, deduped across every category, alphabetical by shown name.
-- A cell's identity is what Blizzard's CDM settings treat as the item's
-- spell: `overrideTooltipSpellID` when the entry carries one (several tracked
-- entries can share one base and differ only there: Balance's Eclipse base
-- fronts a Solar bar and a Lunar bar, Prot Paladin's spec passive fronts four
-- tracked buffs), else the base `spellID` (stable across talent swaps; the
-- engine expansion keys on it and unions every entry sharing it). The cell
-- shows the entry as Blizzard tooltips it: by the current talent override
-- when there is one (Flame Shock's base 470411 reads "Voltaic Blaze" with
-- that icon while the talent is taken). Name and icon come from
-- SAU.DescribeSpell, the same describer the editor chip and the Aura List
-- use, so a click never changes what the player saw.
local function BuildCatalog()
    local entries = {}
    local SAU = addon.ScootAuras
    local enum = Enum and Enum.CooldownViewerCategory
    if not SAU or not enum or not C_CooldownViewer
        or not C_CooldownViewer.GetCooldownViewerCategorySet
        or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return entries
    end
    -- Fresh override state for this open (talents may have changed).
    SAU.InvalidateSpellDescriptions()

    local cats = {}
    for _, value in pairs(enum) do
        if type(value) == "number" then
            table.insert(cats, value)
        end
    end
    table.sort(cats)

    local seen = {}
    for _, catValue in ipairs(cats) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, catValue, true)
        if ok and type(ids) == "table" and not issecretvalue(ids) then
            for _, cooldownID in ipairs(ids) do
                if not issecretvalue(cooldownID) then
                    local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if iok and type(info) == "table" and not issecretvalue(info) then
                        local sid = not issecretvalue(info.spellID) and info.spellID or nil
                        local tid = not issecretvalue(info.overrideTooltipSpellID)
                            and info.overrideTooltipSpellID or nil
                        local identity = (type(tid) == "number" and tid > 0) and tid or sid
                        if type(identity) == "number" and not seen[identity] then
                            seen[identity] = true
                            local name, icon, shownId = SAU.DescribeSpell(identity)
                            table.insert(entries, {
                                spellId = identity,
                                baseSpellId = sid,
                                shownSpellId = shownId,
                                name = name,
                                icon = icon,
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return entries
end

-- Exposed for the debug dump (/scoot debug sa catalog).
Picker.BuildCatalog = BuildCatalog

--------------------------------------------------------------------------------
-- Extra cells per tracker kind
--------------------------------------------------------------------------------

-- Missing-buff trackers watch buffs the Cooldown Manager mostly does not
-- list: group buffs and the player's forms/stances. C_CooldownViewer's group
-- buff list is Blizzard's own roster, the same one the Cooldown Manager
-- settings show under Group Buffs, so it stays right as classes gain and lose
-- buffs; the fixed table below covers a client that does not have the API.
-- Forms come from the shapeshift bar, a plain API that hands back each form's
-- spell ID.
local CLASS_RAID_BUFF = {
    DRUID   = 1126,    -- Mark of the Wild
    MAGE    = 1459,    -- Arcane Intellect
    WARRIOR = 6673,    -- Battle Shout
    PRIEST  = 21562,   -- Power Word: Fortitude
    EVOKER  = 369459,  -- Source of Magic
    SHAMAN  = 462854,  -- Skyfury
}

local function MissingKindEntries(seen)
    local SAU = addon.ScootAuras
    if not SAU then return {} end
    local entries = {}
    local function addSpell(spellId)
        if type(spellId) ~= "number" or spellId <= 0 or seen[spellId] then return end
        seen[spellId] = true
        local name, icon, shownId = SAU.DescribeSpell(spellId)
        table.insert(entries, {
            spellId = spellId,
            baseSpellId = spellId,
            shownSpellId = shownId,
            name = name,
            icon = icon,
        })
    end

    -- isKnown filters the list to buffs this character can actually cast, so
    -- a Shaman sees Skyfury and not Arcane Intellect.
    local listed = false
    if C_CooldownViewer and C_CooldownViewer.GetGroupBuffItems then
        local ok, items = pcall(C_CooldownViewer.GetGroupBuffItems)
        if ok and type(items) == "table" and not issecretvalue(items) then
            for _, item in ipairs(items) do
                if type(item) == "table" and item.isKnown == true then
                    addSpell(item.spellID)
                    listed = true
                end
            end
        end
    end
    if not listed then
        local _, classToken = UnitClass("player")
        addSpell(CLASS_RAID_BUFF[classToken])
    end

    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        local okN, count = pcall(GetNumShapeshiftForms)
        if okN and type(count) == "number" and not issecretvalue(count) then
            for i = 1, count do
                local ok, _, _, _, formSpellId = pcall(GetShapeshiftFormInfo, i)
                if ok and type(formSpellId) == "number" and not issecretvalue(formSpellId) then
                    addSpell(formSpellId)
                end
            end
        end
    end
    return entries
end

--- Cells prepended for a kind, deduped against the CDM catalog identities.
local function ExtraEntriesForKind(kind, catalog)
    if kind ~= "missingbuff" then return {} end
    local seen = {}
    for _, entry in ipairs(catalog) do
        seen[entry.spellId] = true
        if entry.baseSpellId then seen[entry.baseSpellId] = true end
        if entry.shownSpellId then seen[entry.shownSpellId] = true end
    end
    return MissingKindEntries(seen)
end

--------------------------------------------------------------------------------
-- Grid construction
--------------------------------------------------------------------------------

-- The cell the pointer is on. Cells are destroyed rather than pooled, so a
-- rebuild or an editor close can take a cell out from under the pointer
-- without OnLeave firing, and the tooltip would be left on screen.
local hoveredCell = nil

--- Drops a tooltip left on a cell the caller is about to destroy or hide.
function Picker.HideTooltip()
    if not hoveredCell then return end
    hoveredCell = nil
    GameTooltip:Hide()
end

-- Blizzard's own spell tooltip, described by the ID the cell is named and
-- iconed from rather than the one it stores, so the tooltip always agrees with
-- the art under the pointer (base 470411 reads "Voltaic Blaze" while the talent
-- is taken). The ID line repeats what the Tooltip component's Show Tooltip IDs
-- option adds through the data processor, whose per-pass dedup cannot see a
-- line added after SetSpellByID returns, so it is skipped when that option is
-- on and copies its AddDoubleLine format when it is off.
local function ShowCellTooltip(cell, entry)
    local id = entry.shownSpellId or entry.spellId
    if type(id) ~= "number" then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(id)
    local comp = addon.Components and addon.Components.tooltip
    if not (comp and comp.db and comp.db.showTooltipIDs) then
        GameTooltip:AddDoubleLine("Spell ID:", tostring(id), 0.5, 0.5, 1.0, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function CreateCell(parent, entry, onPick)
    local theme = addon.UI and addon.UI.Theme
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(CELL_W, CELL_H)

    local hover = cell:CreateTexture(nil, "BACKGROUND", nil, -7)
    hover:SetAllPoints()
    if theme then
        local ar, ag, ab = theme:GetAccentColor()
        hover:SetColorTexture(ar, ag, ab, 0.12)
    else
        hover:SetColorTexture(1, 1, 1, 0.08)
    end
    hover:Hide()

    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOP", cell, "TOP", 0, -3)
    icon:SetTexture(entry.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local name = cell:CreateFontString(nil, "OVERLAY")
    local fontPath = theme and theme:GetFont("LABEL") or "Fonts\\FRIZQT__.TTF"
    name:SetFont(fontPath, 9, "")
    name:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    name:SetPoint("LEFT", cell, "LEFT", 2, 0)
    name:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
    name:SetJustifyH("CENTER")
    name:SetMaxLines(2)
    name:SetText(entry.name)
    name:SetTextColor(0.85, 0.85, 0.85, 1)

    cell:SetScript("OnEnter", function()
        hover:Show()
        hoveredCell = cell
        ShowCellTooltip(cell, entry)
    end)
    cell:SetScript("OnLeave", function()
        hover:Hide()
        if hoveredCell == cell then hoveredCell = nil end
        GameTooltip:Hide()
    end)
    cell:SetScript("OnClick", function() onPick(entry.spellId) end)
    return cell
end

--------------------------------------------------------------------------------
-- Public: attach the picker to a region
--------------------------------------------------------------------------------

--- Builds the catalog UI inside `parent`. opts.onPick(spellId) fires on cell
-- click. Returns { Refresh = fn(kind) } for rebuilds on show (catalogs shift
-- with spec changes) and on kind change (some kinds prepend their own cells).
function Picker.Attach(parent, opts)
    local theme = addon.UI and addon.UI.Theme
    local onPick = opts and opts.onPick or function() end
    local labelFont = theme and theme:GetFont("LABEL") or "Fonts\\FRIZQT__.TTF"

    local scrollFrame, child = Picker.CreateScrollRegion(parent)
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    local widgets = {}
    local picker = {}

    local function AddHeader(text, y)
        local fs = child:CreateFontString(nil, "OVERLAY")
        fs:SetFont(labelFont, 11, "")
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -y)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        if theme then
            local dr, dg, db = theme:GetDimTextColor()
            fs:SetTextColor(dr, dg, db, 1)
        else
            fs:SetTextColor(0.6, 0.6, 0.6, 1)
        end
        table.insert(widgets, fs)
        return y + 18
    end

    local function LayoutGrid(entries, columns, y)
        for i, entry in ipairs(entries) do
            local col = (i - 1) % columns
            local rowIdx = math.floor((i - 1) / columns)
            local cell = CreateCell(child, entry, onPick)
            cell:SetPoint("TOPLEFT", child, "TOPLEFT", 4 + col * CELL_W, -y - rowIdx * CELL_H)
            table.insert(widgets, cell)
        end
        return y + math.ceil(#entries / columns) * CELL_H + 4
    end

    function picker.Refresh(kind)
        Picker.HideTooltip()
        for _, w in ipairs(widgets) do
            w:Hide()
            w:SetParent(nil)
        end
        widgets = {}

        local catalog = BuildCatalog()
        local extra = ExtraEntriesForKind(kind, catalog)
        local width = child:GetWidth()
        if not width or width < CELL_W then width = parent:GetWidth() or 400 end
        local columns = math.max(3, math.floor(width / CELL_W))
        local y = 4

        if #extra > 0 then
            y = AddHeader("Class buff and forms", y)
            y = LayoutGrid(extra, columns, y)
            y = AddHeader("Cooldown Manager", y + 2)
        end

        if #catalog == 0 then
            local empty = child:CreateFontString(nil, "OVERLAY")
            empty:SetFont(labelFont, 11, "")
            empty:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -y - 4)
            empty:SetPoint("TOPRIGHT", child, "TOPRIGHT", -8, -y - 4)
            empty:SetJustifyH("LEFT")
            empty:SetText("Cooldown Manager data is not available right now. You can still enter a spell ID above.")
            empty:SetTextColor(0.6, 0.6, 0.6, 1)
            table.insert(widgets, empty)
            y = y + 36
        end

        y = LayoutGrid(catalog, columns, y)

        child:SetHeight(math.max(y, 1))
        scrollFrame.ResetScroll()
    end

    picker.Refresh()
    return picker
end

return Picker
