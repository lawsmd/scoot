-- importexport.lua - Profile Import/Export serialization pipeline
-- AceSerializer → LibDeflate compress → EncodeForPrint → "!SM1!" prefix
local addonName, addon = ...

addon.ImportExport = {}
local IE = addon.ImportExport

local VERSION = 1
local PREFIX = "!SM1!"

--------------------------------------------------------------------------------
-- Library references (resolved lazily)
--------------------------------------------------------------------------------

local AceSerializer, LibDeflate

local function EnsureLibs()
    if AceSerializer and LibDeflate then return true end
    AceSerializer = LibStub and LibStub:GetLibrary("AceSerializer-3.0", true)
    LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    return (AceSerializer ~= nil) and (LibDeflate ~= nil)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function GetAddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, ver = pcall(C_AddOns.GetAddOnMetadata, addonName, "Version")
        if ok and ver then return ver end
    end
    return "unknown"
end

local function StripPresetMarkers(tbl)
    if type(tbl) ~= "table" then return end
    tbl.__preset = nil
    tbl.__presetName = nil
    tbl.__presetVersion = nil
    for _, v in pairs(tbl) do
        if type(v) == "table" then
            StripPresetMarkers(v)
        end
    end
end

--------------------------------------------------------------------------------
-- Export Profile
--------------------------------------------------------------------------------

function IE:ExportProfile(profileKey)
    if not EnsureLibs() then
        return nil, "Required libraries not loaded."
    end

    if not addon.db or not addon.db.profiles then
        return nil, "No profile database available."
    end

    local profileData = addon.db.profiles[profileKey]
    if not profileData then
        return nil, "Profile '" .. tostring(profileKey) .. "' not found."
    end

    -- Deep copy and strip preset markers
    local data = CopyTable(profileData)
    StripPresetMarkers(data)

    -- Build envelope
    local envelope = {
        version = VERSION,
        addonVersion = GetAddonVersion(),
        profileName = profileKey,
        exportedAt = date("%Y-%m-%d %H:%M:%S"),
        data = data,
    }

    -- Serialize → compress → encode
    local serialized = AceSerializer:Serialize(envelope)
    if not serialized then
        return nil, "Serialization failed."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Compression failed."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Encoding failed."
    end

    return PREFIX .. encoded, nil
end

--------------------------------------------------------------------------------
-- Import Profile (decode + validate)
--------------------------------------------------------------------------------

function IE:ImportProfile(importStr)
    if not EnsureLibs() then
        return false, "Required libraries not loaded."
    end

    if not importStr or importStr == "" then
        return false, "No import string provided."
    end

    -- Validate and strip prefix
    if importStr:sub(1, #PREFIX) ~= PREFIX then
        return false, "Invalid import string. Expected Scoot profile string starting with '" .. PREFIX .. "'."
    end

    local encoded = importStr:sub(#PREFIX + 1)
    if encoded == "" then
        return false, "Import string is empty after prefix."
    end

    -- Decode → decompress → deserialize
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return false, "Failed to decode import string. It may be truncated or corrupted."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Failed to decompress import string. It may be corrupted."
    end

    local success, envelope = AceSerializer:Deserialize(serialized)
    if not success then
        return false, "Failed to deserialize import data: " .. tostring(envelope)
    end

    -- Validate envelope structure
    if type(envelope) ~= "table" then
        return false, "Invalid import data structure."
    end

    if not envelope.version then
        return false, "Import data is missing version information."
    end

    if envelope.version > VERSION then
        return false, "This profile was created with a newer version of Scoot. Please update your addon."
    end

    if type(envelope.data) ~= "table" then
        return false, "Import data is missing profile data."
    end

    return true, envelope
end

--------------------------------------------------------------------------------
-- Validate Import String (no side effects)
--------------------------------------------------------------------------------

function IE:ValidateImportString(importStr)
    if not importStr or importStr == "" then
        return false, "No import string provided."
    end

    if importStr:sub(1, #PREFIX) ~= PREFIX then
        return false, "Invalid format. Expected string starting with '" .. PREFIX .. "'."
    end

    -- Full decode to verify integrity
    return self:ImportProfile(importStr)
end

--------------------------------------------------------------------------------
-- Export Edit Mode String
--------------------------------------------------------------------------------

function IE:ExportEditModeString(layoutName)
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.ConvertLayoutInfoToString then
        return nil, "Edit Mode API not available."
    end

    local layoutInfo = C_EditMode.GetLayouts()
    if not layoutInfo or not layoutInfo.layouts then
        return nil, "Unable to read Edit Mode layouts."
    end

    -- Find the layout by name
    local targetLayout
    for _, layout in ipairs(layoutInfo.layouts) do
        if layout and layout.layoutName == layoutName then
            targetLayout = layout
            break
        end
    end

    if not targetLayout then
        return nil, "Edit Mode layout '" .. tostring(layoutName) .. "' not found."
    end

    -- Convert to string using Blizzard API
    local ok, exportStr = pcall(C_EditMode.ConvertLayoutInfoToString, targetLayout)
    if not ok or not exportStr then
        return nil, "Failed to export Edit Mode layout: " .. tostring(exportStr)
    end

    return exportStr, nil
end
