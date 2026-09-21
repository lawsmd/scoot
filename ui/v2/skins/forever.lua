-- forever.lua - the Forever skin: Blizzard's WoW Forever palette, and
-- Blizzard's own panel parts for the chrome.
--
-- The palette is measured out of the Forever build's art, and the comment
-- on each value names the atlas it came from. The chrome table takes the
-- retail construction and lets the client's art set do the work: the window
-- is Blizzard's portrait panel, the template Forever's own Legacy pane is
-- built on, and its parts exist on retail too, so /camelot draws a gray
-- portrait panel on the retail client and a bronze one on Forever from this
-- one table. The Legacy pane's own atlases exist only on Forever; each is
-- declared with a fallback the retail client takes. None of it has been
-- seen lit, so the numbers that place the toolbar and the panes are
-- proposals.
--
-- The panel text is the client's own face, the one Blizzard draws its
-- buttons and panel titles in. The row metrics are still tui's, and
-- metrics.slots is the number that has to follow the face: its fixed widths
-- were measured on a monospace grid, so an option label longer than its slot
-- clips until the framework's content-fit phase lands. Metrics cannot be
-- omitted, since Controls.Metrics() returns Skin.Metrics() with no fallback.
--
-- Registration only, no SetActive here: forever/menu.lua activates it for
-- Camelot, and /scoot debug skin forever switches Scoot to it for a look.
local addonName, addon = ...

local Skin = addon.UI.Skin

-- The addon that loaded this file, not a literal: the Forever client has no
-- Scoot folder to resolve against, only whichever junction points at this one.
-- core/fonts.lua takes the same fallback.
local ROOT = addon.MediaPath or "Interface\\AddOns\\Scoot\\"
local FONT_BASE = ROOT .. "media\\fonts\\"

-- One face for the whole panel, read off GameFontNormal rather than named:
-- the path behind that font object is Friz Quadrata on an English client and
-- the locale's own file everywhere else, so the panel reads in the face the
-- client draws its own buttons and panel titles in. FRIZQT__ stands in if the
-- object is ever missing. Friz Quadrata ships no bold and the widget API has
-- no weight, so the header role is the same face at a larger size, which is
-- how Blizzard's own headings are built. The one bold in the family is Friz
-- Quad Bold, QualiType's OFL digitization of the same design
-- (addon.Fonts.FRIZQUAD_BOLD, core/fonts.lua); the toggle role carries it.
-- Arial Narrow is one line away: addon.Fonts.ARIALN.
local UI_FACE = (GameFontNormal and select(1, GameFontNormal:GetFont()))
    or addon.Fonts.FRIZQT__
-- Roboto stays the proportional pair: the role is the known-proportional
-- fallback Theme:GetFont reaches for when a role's file will not load.
local PROP_REG  = addon.Fonts.ROBOTO_REG or (FONT_BASE .. "Roboto-Regular.ttf")
local PROP_MED  = addon.Fonts.ROBOTO_MED or (FONT_BASE .. "Roboto-Medium.ttf")

Skin.Register("forever", {
    -- Kept off Theme accent: contrast floor. The near black and the warm
    -- grays are what the accent is read against; they cannot move with it.
    -- Forever's chrome carries its color through lighting rather than tint,
    -- so the dark roles sit lower than tui's greens do and the accent has to
    -- carry the bronze on its own.
    palette = {
        -- #f2e2c2, the lit highlight of CamelotLogoBronze.tga and the
        -- brightest of the emblem's three tones (#745436 shadow, #c8a055
        -- body, this). The accent colors the panel's text as well as its
        -- glyphs and fills, and the bronze it held before, #a78151 off
        -- ui-frame-metal-cornertopleft-2x, drew a page title and a row label
        -- at luminance 135 against a background of 13: brown on brown. The
        -- cream draws at 227 and keeps the emblem's warmth. The bronze the
        -- unit frame art multiplies its metal by is a number of its own and
        -- does not follow this one (forever/unitframes/art.lua).
        accentDefault   = { r = 0.949, g = 0.886, b = 0.761, a = 1 },
        -- #0d0805, heavybronze-frame-background-c60 at body luminance.
        -- Forever is darker behind its panels than retail is.
        background      = { r = 0.051, g = 0.031, b = 0.020, a = 0.96 },
        backgroundSolid = { r = 0.051, g = 0.031, b = 0.020, a = 0.99 },
        textPrimary     = { r = 1, g = 1, b = 1, a = 1 },
        -- #9b8a7b, the common-search-border-middle highlight: a warm gray
        -- that sits with the chrome instead of against it.
        textDim         = { r = 0.608, g = 0.541, b = 0.482, a = 1 },
        -- #cbbeab, the lightest pixel in heavybronze-frame-basic-c60.
        textDimLight    = { r = 0.796, g = 0.745, b = 0.671, a = 1 },
        -- #1d1611, the lit edge of a common-button-list-mid-c60 row.
        collapsibleBg   = { r = 0.114, g = 0.086, b = 0.067, a = 1 },
    },

    fonts = {
        label     = { path = UI_FACE, size = 13 },
        value     = { path = UI_FACE, size = 12 },
        desc      = { path = UI_FACE, size = 11 },
        -- The section headers, the one heading role the framework shares:
        -- a collapsible's title, and the Game Menu panel's. Deep Shadow sits
        -- on the role itself because both stand on the same dark wood.
        header    = { path = UI_FACE, size = 16, style = "DEEPSHADOWTHICKOUTLINE" },
        -- Every button's text: the toolbar, the page header's actions, the
        -- dropdowns and fields, the Edit Mode dialog. The style is the role's
        -- own decision, so buttons need no seam of their own. Deep Shadow was
        -- tried here first and read too heavy at 13pt, where the copy's fixed
        -- two-pixel offset is a sixth of the glyph; the crisp variant keeps
        -- the thick outline and drops the copy, drawing it through the
        -- engine's vector text renderer. A client that rejects the SLUG flag
        -- renders plain THICKOUTLINE instead, silently and by design
        -- (addon.FontStyles.slugSupported, probed at load; 'debug slug'
        -- reports what the client answered).
        button    = { path = UI_FACE, size = 13, style = "THICKOUTLINESLUG" },
        miniLabel = { path = UI_FACE, size = 11 },
        -- The toggle's ON and OFF, on a settings row and on the Features
        -- page's pills alike. Roboto Condensed Bold stood here for its weight
        -- and read as another addon's font beside the client face the rest of
        -- the panel draws in, narrow where everything around it is wide. The
        -- face went back to the client's, with the weight from the crisp
        -- thick outline; now it is Friz Quad Bold, the same design in a real
        -- bold, so the pill's weight is the glyph's own and reads as one face
        -- with the panel. The outline stays for the unlit pill, where the dim
        -- text stands on the pane and the outline is the rim the rest of the
        -- panel's text has. Lit, the text is black on this fill and the
        -- outline is the glyph's own color: 9pt with a thin one closed the
        -- letters up, so the lit pill takes the face and the size alone
        -- (Toggle.lua, StartHereRenderer.lua).
        toggle    = { path = addon.Fonts.FRIZQUAD_BOLD or UI_FACE, size = 12, style = "THICKOUTLINESLUG" },
        -- The names that stand on the wood, in Deep Shadow Thick Outline,
        -- which draws a black copy of the string behind it
        -- (core/fontpair.lua): the nav card's group name, the child row under
        -- it, the page name in the title band, and a hand-drawn block's
        -- heading. Each is a role of its own because the roles they would
        -- otherwise take (label, value) carry the rest of the panel's text.
        -- The surface's metric points at the role -- nav.card.labelFontRole,
        -- nav.card.childLabelFontRole, contentHeader.fontRole,
        -- blockTitleFontRole -- and overrides the size beside it, so what
        -- these roles really decide is the style. 'font <role> <STYLE>' tries
        -- another key on the open panel and 'font styles' lists them.
        navLabel      = { path = UI_FACE, size = 14, style = "DEEPSHADOWTHICKOUTLINE" },
        navChildLabel = { path = UI_FACE, size = 11, style = "DEEPSHADOWTHICKOUTLINE" },
        pageHeader    = { path = UI_FACE, size = 20, style = "DEEPSHADOWTHICKOUTLINE" },
        -- A hand-drawn block's heading, the page's own title for the group of
        -- controls under it (blockTitleFontRole). The Manage Profiles page's
        -- "Active Layout" is the one so far.
        blockTitle    = { path = UI_FACE, size = 18, style = "DEEPSHADOWTHICKOUTLINE" },
        -- A settings row's own name: "Cast Bar Style", "Cast Bar Scale", every
        -- row the builder draws (rowLabelFontRole). It stands on the page's
        -- wood the way the headings above it do, so it takes an outline, but
        -- it takes the crisp one rather than Deep Shadow: the names above it
        -- are one to a card or one to a page, while these repeat down the
        -- page at 13pt, the size where the copy's fixed two-pixel offset read
        -- heavy on the buttons. The size matches the label role it left, so
        -- the row heights, which are font-driven, do not move.
        rowLabel      = { path = UI_FACE, size = 13, style = "THICKOUTLINESLUG" },
        -- The value a field shows, dropdown and selector alike
        -- (dropdown.fontRole, field.fontRole). It reads as a button, so it
        -- takes the button's crisp outline rather than the names' Deep Shadow.
        fieldValue    = { path = UI_FACE, size = 12, style = "THICKOUTLINESLUG" },
        proportional    = { path = PROP_REG, size = 12 },
        proportionalMed = { path = PROP_MED, size = 12 },
    },

    -- The two SCOOT_ICON keys still name the other addon's art because
    -- nothing in Camelot draws them yet. Both resolve through the junction.
    textures = {
        NOISE_OVERLAY = ROOT .. "media\\textures\\frosted-noise",
        SCOOT_ICON    = ROOT .. "ScootIcon",
        SCOOT_ICON_TRANSPARENT = ROOT .. "ScootIconTransparent",
        -- The window's portrait and the Edit Mode dialog's mark: Camelot's
        -- emblem, the file the minimap button draws, named once in
        -- forever/camelot.lua. Scoot can wear this skin through
        -- /scoot debug skin forever and its export prunes forever/, so the
        -- question mark every client has stands in there.
        CAMELOT_EMBLEM = (addon.Logo and addon.Logo.bronze)
            or "Interface\\ICONS\\INV_Misc_QuestionMark",
    },

    -- The chrome: Blizzard's parts where a part exists, the framework's flat
    -- draw where the look is a fill. A name only Forever carries declares
    -- the fallback the retail client takes; a name the running client lacks
    -- with no fallback falls to the flat default through Chrome.Spec.
    chrome = {
        -- Blizzard's portrait panel: the frame is the template, and its
        -- metal border, title plate and close button come with it. The
        -- border is rebuilt from ButtonFrameTemplateNoPortrait, which is
        -- that same metal with a plain top-left corner in place of the
        -- ringed one: the emblem is a disc already, and a second ring
        -- around it drew a circle inside a circle. The emblem hangs on the
        -- corner rather than sitting inside it: a 60 px box centred 12
        -- right and 10 down from the frame's top-left, which puts the mark
        -- over the mitre where the two metal edges meet and lets the edges
        -- run out from under it. The star is opaque to 0.40 of the box in
        -- that direction, 24 px, against 17 px from the centre to the
        -- mitre, so the corner stays covered. Both numbers were read off a
        -- screenshot: 46 px on the old ring's centre drew the mark small
        -- and wholly inside the border, with the corner above it. The round
        -- mask the template puts on a unit portrait comes off: it is 4 px
        -- narrower than the box and sits 2 px high in it, so the star's
        -- bottom point falls outside, and a mark drawn to its own edge has
        -- no use for a crop. The mark draws over the border art (overlay):
        -- the ring's hole let a portrait show through the corner, and a
        -- plain corner would lay its metal over half the mark instead.
        -- The dark page under the title band is the Legacy pane's
        -- own background. Its art bakes in a lighter column on the left,
        -- a streak band across the top and a bordered panel filling the
        -- rest, so it is cut at the panel's edges (column 121; rows 52 and
        -- 60 bracket the top border) and each cell stretched to its own
        -- pane, which puts the baked edges on the nav's right edge and the
        -- title band's bottom whatever the window's size. The wood column
        -- was painted around Blizzard's three fixed cells and goes dark
        -- behind them (rows 160 to 400), so under the border it repeats
        -- its light band, rows 64 to 128, instead of stretching. The
        -- panel's other three borders are cut out too (columns 121 to 124
        -- and 806 to 809, rows 503 to 506, each with the shadow outside
        -- it), the last two splits each way held at the art's own distance
        -- from the far edge, so the border and the fill inside it are
        -- separate cells and names gives each cell its opacity piece.
        -- Retail has no such atlas and fills the rect flat. The options
        -- border stands in if a client ever lacks the template.
        window = {
            kind = "template", template = "PortraitFrameTemplate",
            layout = "ButtonFrameTemplateNoPortrait",
            portrait = { texture = "CAMELOT_EMBLEM", size = 60, x = -18, y = 20,
                         mask = false, overlay = true },
            contentBackground = {
                kind = "atlas", atlas = "Legacy-Tree-Frame-background",
                grid = {
                    cols = { 121, 125, 806, 810 }, rows = { 52, 60, 503, 507 },
                    fromRight = 2, fromBottom = 2,
                    tile = { { col = 1, row = 3, v = { 64, 128 } } },
                    names = {
                        { "pageStreaks", "pageStreaks", "pageStreaks", "pageStreaks", "pageStreaks" },
                        { "pageTopBorder", "pageTopBorder", "pageTopBorder", "pageTopBorder", "pageTopBorder" },
                        { "navColumn", "pageBorder", "pageFill", "pageBorder", "pageBorder" },
                        { "pageBorder", "pageBorder", "pageBorder", "pageBorder", "pageBorder" },
                        { "pageBorder", "pageBorder", "pageBorder", "pageBorder", "pageBorder" },
                    },
                    -- The page and the wood carried on under the border
                    -- strips that edge them, so a faint border never shows
                    -- more of the world than the pane inside it. The shadow
                    -- outside the border (column 5, row 5) gets none.
                    underlay = {
                        { name = "pageFill", from = { 3, 3 },
                          cells = { { 2, 2 }, { 3, 2 }, { 4, 2 }, { 2, 3 }, { 4, 3 }, { 2, 4 }, { 3, 4 }, { 4, 4 } } },
                        { name = "navColumn", from = { 1, 3 }, cells = { { 1, 2 }, { 1, 4 } } },
                    },
                },
                inset = { left = 2, top = 21, right = 2, bottom = 2 }, sublevel = -5,
                fallback = { kind = "flat", fill = "window" },
            },
            fallback = { kind = "nineSlice", layout = "UniqueCornersLayout", textureKit = "OptionsFrame", background = "window" },
        },
        -- The picker dialogs (font, bar texture, bar border, icon) on the
        -- same panel template as the window, at dialog size: the metal
        -- border, the tiled rock, the streak band and the 21px title plate
        -- come with it, and the close button in the corner is the one
        -- closeButton = { kind = "window" } adopts. No emblem: the panel
        -- behind the dialog already carries one, and a second mark on a box
        -- this size would stand over its own title. The plain corner is what
        -- ButtonFrameTemplateNoPortrait draws in the ring's place.
        picker = {
            kind = "template", template = "PortraitFrameTemplate",
            layout = "ButtonFrameTemplateNoPortrait",
            portrait = false,
            -- Pieces of its own rather than the window's. The panel's fill is
            -- translucent against the world; this dialog stands on that panel,
            -- so the same number would show the world through two backdrops
            -- and the font names would read against whatever is behind both.
            -- It draws solid.
            pieces = { border = "pickerBorder", fill = "pickerFill", streaks = "pickerStreaks" },
            fallback = { kind = "nineSlice", layout = "UniqueCornersLayout", textureKit = "OptionsFrame", background = "window" },
        },
        -- The title is the product's banner image. x 60 was where the
        -- portrait ring ended; the emblem that replaced it ends at 35, and
        -- the banner's own art starts about 3 inside its texture, so the
        -- two stood 28 apart. x 46 halves that to 14. The image is taller
        -- than the 21px title plate on purpose: it stands above the window's
        -- top edge and hangs into the band under the plate. The close button
        -- is the window template's own, and so is the title where a product
        -- has no image; those fallbacks still clear the old ring's width.
        titleBar = {
            kind = "texture", point = "TOPLEFT", x = 46, y = 6, height = 51,
            fallback = {
                kind = "window", justify = "LEFT", offsets = { left = 62, right = -24 },
                fallback = { kind = "text", fontObject = "GameFontNormal", point = "TOPLEFT", x = 24, y = -20 },
            },
        },
        closeButton = { kind = "window", fallback = { kind = "template", template = "UIPanelCloseButton" } },
        -- The gray body of Blizzard's Options dropdown: 39x39 with a 7 px
        -- shadow outside a 1 px rim, bronze on Forever and gray on retail
        -- behind one name. Cut into nine so it takes any size; the label and
        -- icon are the framework's, colored by the two token maps.
        button = {
            kind = "sliced",
            normal = "common-dropdown-c-button", hover = "common-dropdown-c-button-hover-1",
            pressed = "common-dropdown-c-button-pressed-1", selected = "common-dropdown-c-button-pressed-1",
            disabled = "common-dropdown-c-button-disabled",
            slice = { left = 11, right = 11, top = 11, bottom = 11 },
            edge = { left = 7, right = 7, top = 7, bottom = 7 },
            pieces = { border = "buttonBorder", fill = "buttonFill" },
            pressedOffset = { 1, -1 },
            labelColors = { normal = "primary", hover = "primary", selected = "accent", disabled = { token = "dim", alpha = 0.6 } },
            glyphColors = { normal = "accent", hover = "primary", selected = "accent", disabled = { token = "dim", alpha = 0.5 } },
            fallback = { kind = "template", template = "UIPanelButtonTemplate", font = "template" },
        },
        -- The grabber vanilla put on every resizable window, and the one
        -- Blizzard still puts on its own: the chat frame's corner, Edit
        -- Mode's resize button and PanelResizeButtonTemplate all draw these
        -- three files. 16x16 native, which is metrics.resizeGrip.size, so the
        -- ridges land on the pixel grid. The Highlight file is Blizzard's own
        -- hover lift and draws over the base rather than replacing it; the
        -- Down file is the pressed state. Referenced by path, not by atlas
        -- name, so the art set does not reach it: the cream accent tint is
        -- what carries it off retail's gray and onto the bronze panel.
        resizeGrip = {
            kind = "texture",
            normal = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
            pressed = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
            glow = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
            tint = "accent",
        },
        scrollBar = { kind = "template", template = "MinimalScrollBar", frameType = "EventFrame" },
        -- The in-panel tab art, 96x30, cut across into two 16 px shoulders
        -- and a middle. Only the middle stretches, so the margin between the
        -- label and the art's curve is the same on every tab whatever the
        -- label's width; stretching the whole member scaled that margin with
        -- the tab, and a strip of two tabs then held its two labels
        -- differently. metrics.tab.height is the member's own 30 for the same
        -- reason down the other axis. The selected member is a gold rim over
        -- a dark face, not the gold face the palette's four samples of its
        -- rim suggested, so its label is the cream accent. Black, which an
        -- all-gold face would want, drew as dark on dark.
        tab = {
            kind = "sliced", normal = "common-internaltab", hover = "common-internaltab-hover",
            selected = "common-internaltab-selected",
            slice = { left = 16, right = 16 },
            labelColors = { normal = "dim", hover = "primary", selected = "accent" },
        },
        -- The body under the strip is the panel's own ground, which is darker
        -- than the section face around it, and its box is the cream accent at
        -- the tab metric's own alpha. The gold the tab art wears, #ffe872 off
        -- common-internaltab-selected, is on the section around it instead:
        -- the outer box is the warmer hue and the inner one the cooler, which
        -- is the way round the eye reads as nesting. The two colors were the
        -- other way first. Drawn in one color the two read as a frame inside
        -- a frame, and drawn not at all the tabbed area had no edge.
        tabBody = { kind = "flat", fill = "background" },
        -- List-row art under section headers and nav rows. The client face
        -- has no triangle characters, so the indicator is the stepper's
        -- arrow, turned a quarter clockwise while the section is open. edge
        -- is the clear margin the row art keeps outside its drawn border at
        -- header size, read off a screenshot: the open body's box moves in
        -- and up by it, so its lines meet the border the art draws.
        sectionHeader = {
            kind = "atlas", normal = "common-button-list-mid", hover = "common-button-list-mid-hover",
            open = "common-button-list-mid-selected",
            -- The open header wears the lit gold, which is brighter than the
            -- hover wash, so the cursor keeps that art and lifts it instead of
            -- swapping down to the wash.
            hoverOverOpen = false, hoverGlow = 0.3,
            edge = { left = 3, right = 3, bottom = 3 },
            glyphs = {
                expanded = { atlas = "common-dropdown-icon-next", size = 16, rotation = -math.pi / 2 },
                collapsed = { atlas = "common-dropdown-icon-next", size = 16 },
            },
        },
        -- The open section's box, in the gold of the header art above it:
        -- #ffe872, the rim of common-internaltab-selected off the palette, at
        -- the alpha that gold was drawn at on the tabbed body. The header is
        -- atlas art here, so the three edges the flat draw adds are the whole
        -- box and the color is set on this role alone.
        sectionBody = {
            kind = "flat", background = "collapsible",
            border = { color = { 1, 0.910, 0.447 }, alpha = 0.5 },
        },
        -- Nav rows: one list-row atlas per state. Hover is the dim wash,
        -- selected the lit gold the open section header wears, so the page
        -- the content pane holds is the bright row and the row under the
        -- cursor is the faint one. Selected outranks hover in Chrome's state
        -- walk, so the current page keeps its gold as the cursor crosses it.
        -- That gold stands beside the card's own glow, which is why it draws
        -- through navRowSelected rather than at full: '/camelot opacity
        -- navRowSelected <n>' tries a value on the open panel. The name goes
        -- warm gray when the row is neither, which leaves white to mean the
        -- cursor is on it or the page is open.
        navRow = {
            kind = "atlas", hover = "common-button-list-mid-hover",
            selected = "common-button-list-mid-selected",
            parent = { labelColors = { normal = "accent", hover = "primary", selected = "primary", disabled = { token = "dim", alpha = 0.35 } } },
            child  = { labelColors = { normal = "dimLight", hover = "primary", selected = "primary", disabled = { token = "dim", alpha = 0.35 } } },
        },
        -- The Legacy pane's group cards: the group's name at the left of
        -- the header band, the child rows indented inside the same card
        -- while it is open, and the gold glow at the right edge while open,
        -- standing inside the card's top and bottom edges the way Blizzard's
        -- ends on the border. The face is
        -- cut into nine slices by texcoords; the slices hold the corner
        -- knots, which reach 10 pixels in, and the edge is the margin the
        -- art keeps outside its border (a clear column or two and the
        -- knots' tips), so the border's outer edge is the row's edge. The
        -- glow's arrow sits in rows 17 to 59 of its atlas and keeps its own
        -- scale on a tall card. Neither atlas exists on retail, where the
        -- group is the text row navRow draws.
        navCard = {
            kind = "card", atlas = "Legacy-Tree-Frame-Card",
            slice = { left = 12, right = 12, top = 12, bottom = 12 },
            edge = { left = 3, right = 3, top = 3, bottom = 2 },
            glow = { kind = "atlas", atlas = "Legacy-Tree-Frame-Card-Glow", fixed = { top = 17, bottom = 59 } },
            labelColors = { normal = "primary", hover = "accent", open = "accent", selected = "accent",
                            disabled = { token = "dim", alpha = 0.35 } },
            fallback = { kind = "flat" },
        },
        -- The Legacy pane's divider between its column and its content, its
        -- caps (4 rows at the top, 5 at the bottom) kept at their own size.
        -- Blizzard starts it on the page border's bronze line and ends it
        -- on the window's edge: reach.top is windowInset up to the border
        -- band's bottom plus 4 into the band, reach.bottom is windowInset.
        navDivider = {
            kind = "atlas", normal = "Legacy-Tree-Frame-divider-Vertical",
            slice = { top = 4, bottom = 5 },
            reach = { top = 10, bottom = 6 },
            fallback = { kind = "flat" },
        },
        -- The same body as the button. Blizzard draws it three ways: the
        -- wide field (the -1 states, with an open state), the square stepper
        -- beside it (the -2 states), and the arrows as art of their own.
        -- The arrows ship gold, so they are desaturated and take glyphColors.
        dropdown = {
            kind = "sliced",
            normal = "common-dropdown-c-button", hover = "common-dropdown-c-button-hover-1",
            pressed = "common-dropdown-c-button-pressed-1", open = "common-dropdown-c-button-open",
            disabled = "common-dropdown-c-button-disabled",
            slice = { left = 11, right = 11, top = 11, bottom = 11 },
            edge = { left = 7, right = 7, top = 7, bottom = 7 },
            pieces = { border = "buttonBorder", fill = "buttonFill" },
            glyphs = { open = { atlas = "common-dropdown-c-button-hover-arrow" } },
            indicator = { point = "BOTTOM", x = 0, y = -5, show = "hover" },
            glyphColors = { normal = "accent", hover = "accent" },
            -- The arrow hangs under the field, so the value has the whole
            -- width and sits in its middle, as a button's text does.
            justify = "CENTER",
            fallback = { kind = "flat" },
        },
        field = {
            kind = "sliced", spans = "value",
            normal = "common-dropdown-c-button", hover = "common-dropdown-c-button-hover-1",
            pressed = "common-dropdown-c-button-pressed-1", open = "common-dropdown-c-button-open",
            disabled = "common-dropdown-c-button-disabled",
            slice = { left = 11, right = 11, top = 11, bottom = 11 },
            edge = { left = 7, right = 7, top = 7, bottom = 7 },
            pieces = { border = "buttonBorder", fill = "buttonFill" },
            glyphs = { open = { atlas = "common-dropdown-c-button-hover-arrow" } },
            indicator = { point = "BOTTOM", x = 0, y = -5, show = "hover" },
            glyphColors = { normal = "accent", hover = "accent" },
            fallback = { kind = "flat" },
        },
        arrowButton = {
            kind = "sliced",
            normal = "common-dropdown-c-button", hover = "common-dropdown-c-button-hover-2",
            pressed = "common-dropdown-c-button-pressed-2", disabled = "common-dropdown-c-button-disabled",
            slice = { left = 11, right = 11, top = 11, bottom = 11 },
            edge = { left = 7, right = 7, top = 7, bottom = 7 },
            pieces = { border = "buttonBorder", fill = "buttonFill" },
            pressedOffset = { 1, -1 },
            glyphs = {
                prev = { atlas = "common-dropdown-icon-back", size = 17 },
                next = { atlas = "common-dropdown-icon-next", size = 17 },
            },
            glyphColors = { normal = "accent", hover = "primary", pressed = "primary", disabled = { token = "dim", alpha = 0.5 } },
            fallback = { kind = "flat" },
        },
        -- The help icon, so far the one beside the page header's Defaults
        -- button. Blizzard hangs the same pair in its own options list, a
        -- DefaultsButton with a help button beside it, and the art under that
        -- button is Interface\common\help-i: the letter alone, which is why
        -- the ringed version anchors a minimap border behind it and the
        -- ringless one draws the file on its own. That is the one here, so
        -- the square box and the typed character go and the letter stands on
        -- the wood. Blizzard's letter is 46 pixels on a 64 pixel button and
        -- 30 on the ringless one, because the ink is a fraction of the
        -- texture, so scale 2 draws the 12 pixels the page header asks for
        -- at 24 and the button grows with it. A site that anchors a neighbour
        -- at a fixed offset from the size it asked for sits that much closer.
        -- The file ships gold; desaturating it and coloring it from the two
        -- tokens is what the stepper arrows do, and it puts the letter in the
        -- panel's cream. Dropping desaturate from the glyph keeps the gold.
        -- The question mark has no art of its own and takes the letter too.
        infoIcon = {
            kind = "glyph", scale = 2,
            glyphs = {
                info = { texture = "Interface\\common\\help-i" },
                help = { texture = "Interface\\common\\help-i" },
            },
            glyphColors = { normal = "accent", hover = "primary" },
            fallback = { kind = "flat" },
        },
        -- The box that icon opens: the nine-slice the client draws its own
        -- tooltips with, so Forever's art set serves its own behind these
        -- names. The layout's center ships as a light gray for the caller to
        -- color, which drew white body text on white until the tint went on;
        -- Blizzard's own tooltips color it the same way, through
        -- SetCenterColor in TooltipBackdropTemplateMixin. It takes the
        -- panel's own background rather than Blizzard's near black, so the
        -- box reads as part of this panel, and the border keeps the art's
        -- gold. padding is the inset the text keeps off the edge, against the
        -- flat box's 12.
        tooltip = {
            kind = "nineSlice", layout = "TooltipDefaultLayout", padding = 14,
            tint = { center = "background" },
            fallback = { kind = "flat" },
        },
        -- The slider Blizzard's own options panel draws: the track, the thumb
        -- and the two steppers, bronze on Forever behind the retail names.
        slider = { kind = "template", template = "MinimalSliderWithSteppersTemplate" },
        -- The typed value box beside it: the three common-search-border
        -- pieces of InputBoxTemplate, the box the options search bar is drawn
        -- in. The fill is baked into the art, so the inputField opacity piece
        -- lightens the rim with it.
        input = { kind = "template", template = "InputBoxTemplate", frameType = "EditBox" },
        -- The search page's query box: the options search bar itself, the
        -- same three border pieces with the magnifying glass at the left and
        -- the clear button at the right, which the value box above leaves
        -- out. Its art draws at searchField, 1, as the options panel draws it.
        searchBox = { kind = "template", template = "SearchBoxTemplate", frameType = "EditBox" },
        -- The Edit Mode selection box on one of the addon's own frames
        -- (ui/v2/editmode/SelectionSkin.lua): the window's border over the
        -- window's tiled rock, both fainter than the window draws them. The
        -- window's corners are 75 units, so a frame shorter than minSize on
        -- either axis takes `small`, the metal border the Edit Mode dialog
        -- itself wears. scale multiplies onto the three opacity pieces per
        -- state. The glow is the border drawn again, additive and a few
        -- units out, pulsing while the frame is selected.
        -- pad.gap is the standoff the box keeps off the element on every side.
        -- A cast bar is around 26 units tall against corner art of 32, so
        -- without it the two corners draw over each other and the border reads
        -- as collapsed; the box grows past the gap until they have the gap
        -- between them.
        editSelection = {
            kind = "nineSlice", layout = "ButtonFrameTemplateNoPortrait",
            minSize = 170,
            pad = { gap = 6 },
            small = { kind = "nineSlice", layout = "Dialog" },
            fill = { texture = "Interface\\FrameGeneral\\UI-Background-Rock", inset = 4 },
            scale = { highlight = 0.55, selected = 0.9 },
            -- Outset 0: the additive copy lies on the border and lights it. Any
            -- outset draws the copy beside it, which reads as a second border.
            glow = { outset = 0, tint = { 1, 0.82, 0.45 },
                     highlight = 0.25, pulse = { from = 0.3, to = 0.7, duration = 1.4 } },
            labelColor = "primary",
            fallback = { kind = "flat" },
        },
        -- The box that opens on a click in Edit Mode (ui/v2/editmode/Dialog.lua).
        -- "blizzard" keeps LibEditMode's own border and close button, which
        -- are the translucent dialog border and black fill the client's Edit
        -- Mode dialog draws, and marks the box as the addon's with the emblem
        -- over its top-left corner. The mark is the minimap button's file, a
        -- star drawn to its own edge: it wears no ring and takes no round
        -- crop, both of which are there to fill a hole this mark does not
        -- have. It hangs a quarter of its box outside the corner, as the
        -- window's emblem does.
        editDialog = {
            kind = "blizzard",
            portrait = { texture = "CAMELOT_EMBLEM", ring = false, mask = false,
                         size = 32, x = -8, y = 8 },
            titleColor = "primary",
            -- Beside the element and locked there. The gap clears the mark's
            -- overhang on the box's left edge; Dialog.lua adds the selection
            -- box's own standoff on top of it.
            attach = { gap = 14 },
        },
    },

    -- How opaque each piece of the art above draws, 0 to 1. A border and the
    -- fill inside it are separate pieces, so the panel can go translucent
    -- behind a border that stays solid. The backdrops start low on purpose,
    -- to be raised by eye, and a border gives up half as much as a
    -- backdrop. The panes lie over the window's fill, so where two backdrops
    -- stack the eye sees less of the world than either number says.
    -- /camelot opacity <piece> <value> tries a number on the open panel
    -- and the bare command prints this table to paste back. The
    -- framework's flat fills keep their alphas in metrics below.
    opacity = {
        -- The window: the metal border, the tiled rock behind everything,
        -- the streaks under the title, and the emblem in the corner
        windowBorder  = 0.75,
        windowFill    = 0.65,
        titleStreaks  = 1,
        portrait      = 1,
        -- The picker dialogs stand on the panel rather than on the world, so
        -- they draw solid: a dialog at the window's 0.65 shows the panel
        -- through it and the world through the panel.
        pickerBorder  = 1,
        pickerFill    = 1,
        pickerStreaks = 1,
        -- The Legacy background's cells: the streak band, the bordered
        -- panel's top edge, its other three edges, the page inside them, and
        -- the wood column behind the nav
        pageStreaks   = 0.65,
        pageTopBorder = 0.75,
        pageBorder    = 0.75,
        pageFill      = 0.65,
        navColumn     = 0.65,
        navDivider    = 1,
        -- A nav card's eight outer slices and its center
        cardBorder    = 0.75,
        cardFill      = 0.65,
        cardGlow      = 1,
        -- The two nav row states. The selected row's gold sits a few pixels
        -- from the card's glow, so it gives up a quarter of its light and the
        -- glow stays the brightest thing in the column.
        navRowHover    = 1,
        navRowSelected = 0.75,
        -- One baked image each, border and fill together
        sectionHeader = 1,
        tab           = 1,
        -- The rim with its shadow and bevel, and the face inside them
        buttonBorder  = 1,
        buttonFill    = 1,
        closeButton   = 1,
        scrollTrack   = 1,
        scrollThumb   = 1,
        -- A slider's value box, rim and fill in one image. The search bar
        -- draws it at 1, which is darker than a value on the page needs.
        inputField    = 0.8,
        -- The search page's query box, the same art, at the options panel's own 1
        searchField   = 1,
        -- The Edit Mode selection box: the window's two values, which the
        -- role's per-state scale then lowers
        editSelectionBorder = 0.75,
        editSelectionFill   = 0.65,
        editSelectionGlow   = 1,
    },

    metrics = {
        -- Row layout
        rowHeight = 36,
        rowHeightField = 42,
        rowHeightEmphasized = 72,
        dualRowHeight = 53,
        -- Room under a captioned cluster. The caption band lifts the controls
        -- toward the row's top, so the row grows by this and the cluster
        -- stays in the band above it; the divider then clears the fields.
        dualRowPadBottom = 6,
        controlHeight = 28,
        rowPadding = 12,
        labelTopPad = 10,
        labelLineHeight = 16,
        descGap = 2,
        descPadBottom = 10,
        maxRowHeight = 200,

        -- Page spine
        itemSpacing = 12,
        contentPadding = 8,
        sectionSpacing = 16,
        sectionHeaderHeight = 32,
        firstItemOffset = 8,

        -- Dividers and borders. windowBorderWidth is the flat border the
        -- window falls back to when the nine-slice below is missing.
        dividerThickness = 1,
        dividerAlpha = 0.2,
        borderWidth = 2,
        windowBorderWidth = 3,

        -- Panel chrome. The portrait panel's metal border draws outside the
        -- frame rect and its own background sits 2px inside it, so the
        -- panes stand a few pixels in. The title band is the template's
        -- 21px title plate, the toolbar on its bottom line (toolbar.y), the page
        -- header's line (contentHeader.top, contentHeaderHeight) and the
        -- page background's top border, 8 pixels ending at the band's
        -- bottom: 50 + 32 + 8. The Legacy pane's own band, title plate to
        -- border, is 47 pixels and holds one line; this one holds two. The
        -- close button keeps the template's corner. The closeButton offsets
        -- are read only if the chain falls past the window kind.
        windowInset = 6,
        panelWidth = 1125,
        panelHeight = 715,
        panelMinWidth = 800,
        panelMinHeight = 550,
        panelMaxWidth = 1600,
        panelMaxHeight = 1000,
        titleBarHeight = 90,
        logoFontSize = 6,
        -- The page header sits in the title band, above the content pane
        -- and level with the Legacy pane's points widget: the page's name
        -- at the left, the action buttons at the right end, the page
        -- background's own border under it, and the copy-from field waiting
        -- on a dropdown in this chrome.
        contentHeaderHeight = 32,
        contentHeader = { placement = "band", top = 50, padLeft = 16, actions = "right",
                          separator = false, copyFrom = false, padRight = 8, gap = 8, iconGap = 6,
                          fontRole = "pageHeader" },
        -- The nav column holds a group name and nothing else, so its width
        -- is that name plus the card's borders. The card's left edge is
        -- windowInset + nav.padLeft + card.padLeft from the window and its
        -- right edge is this number, so a cut here takes the space off the
        -- right of the card and brings the divider, the wood column's edge
        -- and the content pane left with it. /camelot nav width tries a
        -- number on the open panel.
        navWidth = 180,
        closeButton = { size = 24, x = -6, y = -6, fontSize = 16 },
        resizeGrip = { size = 16, x = -8, y = 8, dot = 2, step = 4, alpha = 0.7 },
        -- The toolbar stands on the title plate's bottom line: the
        -- template's TitleContainer runs from y -1 to y -21. overlay puts the
        -- buttons over the metal border, which draws at the NineSlice's level.
        -- The banner logo holds the left of the band, so the row stands right
        -- of the window's center: shift 0.5 is halfway from there to the close
        -- button, which is where the row read too tight against the corner.
        toolbar = { height = 22, spacing = 12, y = -21, fontSize = 11, overlay = true,
                    shift = 0.5 },
        pulse = { period = 1.5, minAlpha = 0.3, tick = 0.016 },

        -- featuresPaneTop is left out on purpose. The Features page raises its
        -- content pane into the band under the title bar where the band is
        -- empty, which is how tui gets three columns of modules on screen
        -- without a scroll. This band is art the whole way down: the title
        -- plate, the toolbar on its bottom line at y -21 to -32, the page
        -- header at 50 to 82, and the page background's own top border, the
        -- eight pixels ending at titleBarHeight. With no key the page keeps
        -- the pane where every other page has it, under that border.

        -- A hand-drawn page's block heading takes the blockTitle role, which
        -- is the only way a style reaches a label a page draws itself.
        blockTitleFontRole = "blockTitle",
        -- Every settings row's name, wherever the row comes from: the row
        -- chrome and the measures that size a cluster against the name read
        -- this one role (Controls.RowLabelFontRole).
        rowLabelFontRole = "rowLabel",

        -- The panel's own numbers, per surface. paneInset is the scroll
        -- frame's inset inside the content pane.
        paneInset = 8,
        nav = {
            rowHeight = 24, parentRowHeight = 28, childIndent = 20,
            padLeft = 8, padTop = 8,
            treeLineWidth = 0, treeLineX = 10, treeLineLength = 10, treeLineAlpha = 0.4,
            -- The divider is 12 wide and centered on the nav's edge; the
            -- content pane starts past its far half
            dividerWidth = 1, dividerAlpha = 0.4, dividerGap = 6,
            indicatorSize = 10,
            hoverAlpha = 0.15, selectedAlpha = 0.25,
            -- The group cards. height is the header band; inner is the
            -- border's depth, which the child rows and the hover fill keep
            -- inside; padBottom closes the card under the last child. The
            -- card's right edge stands reach past the nav's edge, where the
            -- divider's line and the page border's baked edge are, so the
            -- border's bronze band ends over the divider's bright column and
            -- the corner knots sit on the page border, as Blizzard's card
            -- does with its right edge 6 past the divider's center; padRight
            -- is 0 inside that. The glow's bar hugs the border's inner edge
            -- at glowOffset and ends glowInset inside the card's top and
            -- bottom, on the border, the 5 of 93 rows Blizzard's does. The
            -- name starts labelPadLeft in, past the border. A child row is the
            -- click target and the box the hover and selected art fill sits
            -- inside it, ending childBoxPad 10 past the name, so the clear
            -- space each side of the name is the same whatever the name is.
            -- childPadLeft 10 holds the box's left edge, and the art's own
            -- 3-pixel fade, off the border's bronze band, which ends 6 pixels
            -- inside the row, and puts the name 20 from the card against the
            -- group name's 16. childPadRight 30 is the row's right edge and
            -- the box's ceiling, clear of the glow, whose bright band reaches
            -- 23 pixels inside the card at its widest.
            card = { height = 40, spacing = 6, padLeft = 4, padRight = 0, reach = 3, inner = 8, padBottom = 8,
                     childPadLeft = 10, childPadRight = 30, childBoxPad = 10,
                     glowOffset = -7, glowInset = 5, hoverAlpha = 0.08, disabledAlpha = 0.75,
                     labelFontRole = "navLabel", labelSize = 14, labelPadLeft = 16,
                     childLabelFontRole = "navChildLabel" },
        },
        scrollBar = { width = 8, thumbMin = 30, margin = 8, gap = 4,
                      trackAlpha = 0.1, thumbAlpha = 0.5, thumbHoverAlpha = 0.8, thumbDragAlpha = 1 },
        button = { height = 26, padding = 12, borderWidth = 2, fontSize = 12 },
        -- height is common-internaltab's own 30, so the art draws unscaled.
        -- padding clears the 16 px shoulder the cut keeps at native size and
        -- leaves the label 4 px of the flat middle on each side.
        -- labelOffsetY drops the label off the button's center. A FontString's
        -- box runs from the face's ascender to its descender, and a label
        -- whose letters stand on the baseline fills only the upper part of it,
        -- so a box centered on the button draws its letters high in the tab.
        -- 5 is more than that accounts for: the art's face sits in the upper
        -- part of the 30 and the rest is the skirt it meets the body with, so
        -- the number is the eye pass's, not a measurement of the font.
        tab = {
            height = 30, padding = 20, spacing = 2, barPadding = 8, rowSpacing = 2,
            borderWidth = 1, borderAlpha = 0.6, contentPadding = 8, maxPerRow = 5,
            fontSize = 12, infoIconSize = 12, infoIconGap = 4, hoverAlpha = 0.15,
            labelOffsetY = -5,
        },
        collapsible = {
            borderWidth = 1, borderAlpha = 0.6, contentPadding = 12,
            indicatorSize = 14, titleSize = 16,
        },
        dropdown = { width = 150, height = 22, borderAlpha = 0.6, borderHoverAlpha = 0.9, hoverAlpha = 0.15,
                     padding = 8, fontSize = 11, indicatorSize = 9, fontRole = "fieldValue" },
        home = {
            guideInset = 40, guideIconSize = 24, guideRowSpacing = 11, guideTextWidth = 304,
            guideTextSize = 11, guideIconTextGap = 8, accentInset = 6,
            logoFontSize = 26, mascotFontSize = 6, textSize = 13,
        },

        -- Dual-row slots
        slotGap = 12,
        miniLabelHeight = 14,
        miniLabelGap = 3,
        maxClusterWidth = 410,
        slots = { toggle = 70, slider = 130, selector = 140, selectorWide = 240, swatch = 28, input = 36 },
        minDescWidth = 200,
        -- A dual slider row on the template slider. The template insets its
        -- track by a stepper each side and its art is 20 tall; the value box
        -- is wide enough that three digits clear the art's end caps.
        dualSlider = { trackWidth = 100, stepperWidth = 20, height = 20,
                       inputWidth = 40, inputGap = 8, groupGap = 16 },
        -- The search page's query box on SearchBoxTemplate: the art is 20
        -- tall and starts 5 units left of the EditBox, the same three pieces
        -- the slider's value box draws. The typed text reads in the value
        -- role, plain, as typed text does in the options panel.
        searchBox = { height = 20, reach = 5, fontRole = "value" },

        field = {
            -- The value reads in the dropdown's role, so a selector field and
            -- a dropdown carry the same text on the same art
            fontRole = "fieldValue",
            -- The steppers are buttons of their own beside the field
            arrowGap = 4,
            arrowWidth = 28,
            indicatorWidth = 8,
            indicatorGap = 4,
            textInset = 8,
            gearWidth = 22,
            tokenIconWidth = 10,
            widthStep = 20,
            popupMaxWidth = 360,
        },

        sublevels = { bg = -8, fill = -7, hover = -6 },
        alphas = { hover = 0.08, emphasis = 0.03, selected = 0.12, borderNormal = 0.6, borderFocus = 1.0 },
    },
})
