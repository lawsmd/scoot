-- reports/core.lua - Report registry and per-report enabled state
--
-- A report is an on-demand summary the user runs from the widget's click
-- menu. This file is pure data and accessors: no frames, no events. Report
-- definitions register at file load; everything visual is created lazily by
-- the menu and the report's own Run implementation, which can only be
-- reached if the widget module built its frame — so no module gating is
-- needed here.
local addonName, addon = ...

addon.Reports = addon.Reports or {}
local Reports = addon.Reports

Reports._ordered = Reports._ordered or {}
Reports._byId = Reports._byId or {}

-- Single source for the plain-language widget explanation. Shown at the top
-- of the Reports > Widget settings page, and by the widget's click menu when
-- no report is enabled (the lone diamond would otherwise confuse users).
Reports.WIDGET_EXPLANATION = "The widget is the small green diamond on your screen. It is the launch point for Scoot's reports: left-click the diamond to open a menu of the reports you have enabled, then pick one to open it in a panel attached to the diamond. The diamond does nothing else on its own — if you only see a lone diamond, visit the Reports page to enable the reports you want it to launch."

--------------------------------------------------------------------------------
-- Enabled state
--------------------------------------------------------------------------------
-- Zero-Touch: stored as true / nil, never false. Absent table = all disabled.
-- profile.reports = { enabled = { [reportId] = true } }
--------------------------------------------------------------------------------

local function getReportsDB()
    local profile = addon and addon.db and addon.db.profile
    return profile and rawget(profile, "reports") or nil
end

function Reports:IsEnabled(id)
    local db = getReportsDB()
    local enabled = db and rawget(db, "enabled") or nil
    return (enabled and enabled[id]) == true
end

function Reports:SetEnabled(id, on)
    if not id or not self._byId[id] then return end
    local profile = addon and addon.db and addon.db.profile
    if not profile then return end

    if on then
        if rawget(profile, "reports") == nil then profile.reports = {} end
        local db = profile.reports
        if rawget(db, "enabled") == nil then db.enabled = {} end
        db.enabled[id] = true
        -- Start warming spec/ilvl data right away so the report opens with
        -- cells already filled instead of a cold cache.
        if addon.Inspect then
            addon.Inspect:EnsureStarted()
        end
    else
        local db = getReportsDB()
        local enabled = db and rawget(db, "enabled") or nil
        if enabled then
            enabled[id] = nil
        end
    end
end

function Reports:HasAnyEnabled()
    for _, def in ipairs(self._ordered) do
        if self:IsEnabled(def.id) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

-- def = { id, label, description, order?, Run(def, ctx) }
function Reports:Register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then return end
    if type(def.label) ~= "string" or type(def.Run) ~= "function" then return end
    if self._byId[def.id] then return end

    self._byId[def.id] = def
    table.insert(self._ordered, def)
    table.sort(self._ordered, function(a, b)
        local ao, bo = a.order or 100, b.order or 100
        if ao ~= bo then return ao < bo end
        return a.label < b.label
    end)
end

function Reports:Get(id)
    return id and self._byId[id] or nil
end

function Reports:GetAll()
    return self._ordered
end

function Reports:GetEnabled()
    local out = {}
    for _, def in ipairs(self._ordered) do
        if self:IsEnabled(def.id) then
            table.insert(out, def)
        end
    end
    return out
end

function Reports:Run(id, ctx)
    local def = self._byId[id]
    if not def then return end
    pcall(def.Run, def, ctx or {})
end
