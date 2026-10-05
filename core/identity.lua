--------------------------------------------------------------------------------
-- core/identity.lua
-- Scoot's identity, set before any other file loads.
--
-- Scoot and Camelot are two addons cut from one working tree, and a file both
-- TOCs list names neither of them. It reads its display name, its media root,
-- its slash word and its minimap icon off the four names below, set here for
-- Scoot and in forever/camelot.lua for Camelot. A file-scope read of any of
-- them has to find it already set, so this file is first on Scoot.toc after
-- the libraries, and nothing it needs loads before it.
--
-- WoW hands each addon its own `addon` table through the vararg, so a file
-- listed on both TOCs runs twice, once per addon, each instance reading its
-- own identity. That property is the whole sharing mechanism.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Brand = "Scoot"
addon.MediaPath = "Interface\\AddOns\\" .. addonName .. "\\"
addon.SlashToken = "scoot"
-- A PNG is named with its extension: an extension-less texture path resolves
-- to .blp, then .tga, and never to .png.
addon.MinimapIcon = addon.MediaPath .. "ScootIcon.png"
