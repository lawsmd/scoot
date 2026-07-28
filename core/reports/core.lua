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
-- The last sentence doubles as the menu's empty-state guidance, so the menu
-- appends nothing of its own.
Reports.WIDGET_EXPLANATION = "This is the Scoot widget. It is meant for launching Reports or providing simple notifications. Reports must first be enabled in Reports > Config."

--------------------------------------------------------------------------------
-- Enabled state
--------------------------------------------------------------------------------
-- Zero-Touch: stored as true / nil, never false. Absent table = all disabled.
-- profile.reports = { enabled = { [reportId] = true }, settings = ..., fontFace = ... }
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
-- Report font
--------------------------------------------------------------------------------
-- One face for every report panel, stored Zero-Touch at profile.reports
-- .fontFace (a font key, nil = default). Report output is read against the
-- game world rather than a settings panel, so it defaults to the same Roboto
-- Medium the widget menu uses instead of the lighter UI face.
--------------------------------------------------------------------------------

Reports.DEFAULT_FONT_KEY = "ROBOTO_MED"

function Reports:GetFontKey()
    local db = getReportsDB()
    local key = db and rawget(db, "fontFace") or nil
    if type(key) ~= "string" or key == "" then return self.DEFAULT_FONT_KEY end
    return key
end

-- Resolved file path, ready for SetFont. nil lets the caller fall back.
function Reports:GetFontFace()
    if not addon.ResolveFontFace then return nil end
    return addon.ResolveFontFace(self:GetFontKey())
end

function Reports:SetFontKey(key)
    local profile = addon and addon.db and addon.db.profile
    if not profile then return end

    if type(key) ~= "string" or key == "" or key == self.DEFAULT_FONT_KEY then
        -- Zero-Touch: the default is absence, not a stored value.
        local db = getReportsDB()
        if db then db.fontFace = nil end
    else
        if rawget(profile, "reports") == nil then profile.reports = {} end
        profile.reports.fontFace = key
    end

    -- Open panels restyle in place; the settings page promises no reload.
    if addon.SendMessage then
        addon:SendMessage("SCOOT_REPORTS_FONT_CHANGED", self:GetFontKey())
    end
end

--------------------------------------------------------------------------------
-- Panel backdrop opacity
--------------------------------------------------------------------------------
-- One backdrop alpha for every surface the diamond spawns: the widget's click
-- menu and each report panel. Stored Zero-Touch at profile.reports
-- .backdropOpacity (a percent, nil = default).
--
-- The default is the /scoot window's own backdrop alpha, read from the theme
-- rather than restated here, so report surfaces read as part of the same UI
-- and retuning one retunes both. Only the backdrop moves: text, borders and
-- icons stay fully opaque, so a low value reads as "see through the panel"
-- rather than "the panel is fading out".
--------------------------------------------------------------------------------

-- Percent, used only if the theme file hasn't loaded yet.
local FALLBACK_OPACITY = 96

function Reports:GetDefaultOpacity()
    local theme = addon.UI and addon.UI.Theme
    local a = theme and theme.BACKGROUND and theme.BACKGROUND.a
    if type(a) ~= "number" then return FALLBACK_OPACITY end
    return math.floor(a * 100 + 0.5)
end

-- Percent, 1-100. Fully transparent is deliberately out of range: an invisible
-- panel is indistinguishable from a broken one.
function Reports:GetOpacity()
    local db = getReportsDB()
    local pct = tonumber(db and rawget(db, "backdropOpacity") or nil)
    if not pct then return self:GetDefaultOpacity() end
    return math.max(1, math.min(100, pct))
end

-- Ready for SetColorTexture / SetVertexColor.
function Reports:GetBackdropAlpha()
    return self:GetOpacity() / 100
end

function Reports:SetOpacity(pct)
    local profile = addon and addon.db and addon.db.profile
    if not profile then return end

    pct = tonumber(pct)
    if pct then pct = math.max(1, math.min(100, math.floor(pct + 0.5))) end

    if not pct or pct == self:GetDefaultOpacity() then
        -- Zero-Touch: the default is absence, not a stored value.
        local db = getReportsDB()
        if db then db.backdropOpacity = nil end
    else
        if rawget(profile, "reports") == nil then profile.reports = {} end
        profile.reports.backdropOpacity = pct
    end

    -- Open surfaces restyle in place; the settings page promises no reload.
    if addon.SendMessage then
        addon:SendMessage("SCOOT_REPORTS_OPACITY_CHANGED", self:GetOpacity())
    end
end

--------------------------------------------------------------------------------
-- Per-report settings
--------------------------------------------------------------------------------
-- Zero-Touch: profile.reports.settings[reportId][key], written only once the
-- user moves a control off its default. Reports own their key names; this file
-- only stores them. Every write announces itself so an open panel restyles in
-- place, the same contract the font setting holds.
--------------------------------------------------------------------------------

function Reports:GetSetting(id, key, default)
    if not id or not key then return default end
    local db = getReportsDB()
    local settings = db and rawget(db, "settings") or nil
    local reportSettings = settings and rawget(settings, id) or nil
    local value = reportSettings and rawget(reportSettings, key)
    if value == nil then return default end
    return value
end

-- Pass nil to clear. Callers that treat a particular value as the default
-- should pass nil for it rather than storing it, keeping Zero-Touch intact.
function Reports:SetSetting(id, key, value)
    if not id or not key then return end
    local profile = addon and addon.db and addon.db.profile
    if not profile then return end

    if value == nil then
        local db = getReportsDB()
        local settings = db and rawget(db, "settings") or nil
        local reportSettings = settings and rawget(settings, id) or nil
        if reportSettings then reportSettings[key] = nil end
    else
        if rawget(profile, "reports") == nil then profile.reports = {} end
        local db = profile.reports
        if rawget(db, "settings") == nil then db.settings = {} end
        if rawget(db.settings, id) == nil then db.settings[id] = {} end
        db.settings[id][key] = value
    end

    if addon.SendMessage then
        addon:SendMessage("SCOOT_REPORT_SETTING_CHANGED", id, key)
    end
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

    -- pcall keeps one broken report from taking the UI down with it, but a
    -- bare pcall turns any failure into "clicking it does nothing", which is
    -- indistinguishable from the report having no data. Surface it instead:
    -- a copyable window, never chat.
    local ok, err = pcall(def.Run, def, ctx or {})
    if not ok then
        self._lastRunError = err
        if addon.DebugShowWindow then
            addon.DebugShowWindow("Report failed: " .. def.label, tostring(err))
        end
    end
end
