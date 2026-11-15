-- damagemetersY/art.lua - The meter's names for the shared panel art (core/panelart.lua)
local _, addon = ...
local DMY = addon.DamageMetersY
local PanelArt = addon.PanelArt

-- The title bar's flat color, for a bar with no art (styling.lua, the preview).
DMY.TITLE_BAR_COLOR = { 0.08, 0.08, 0.10 }

-- The catalog and its painter moved to core/panelart.lua when the Notes
-- windows became their second reader. The meter's files keep these names.
DMY.PanelArt = PanelArt.Catalog
DMY._PanelArtOrder = PanelArt.Order
DMY._PanelArtSource = PanelArt.Source
DMY.PanelArtEntries = PanelArt.Entries
DMY.PanelArtKeys = PanelArt.Keys
DMY.HidePanelArt = PanelArt.Hide
DMY.PanelArtShown = PanelArt.Shown
DMY.ApplyPanelArt = PanelArt.Apply
