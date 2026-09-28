# Main Window Design Alignment — CentralGUI vs. the Floating Windows

**Status: Implemented and live-verified, all 6 phases (2026-09-28).** Approved by the user
("all phases, sequential agents"), implemented by a chain of implementer agents (one dispatch per
phase, Phase 3 further split into 3 sub-dispatches — 3a `UIFactory.lua`/`CentralGUI.lua`, 3b
`CentralGUIBrowser.lua`, 3c `CentralGUIPopups.lua` + 5 panels — for reviewability given ~150+ real
call sites addon-wide), each phase syntax-checked (`luaparse`), headless-tested
(`raidgroups_spec.lua`/`tankcast_spec.lua`, 301/387 passing throughout, never regressed), diff-reviewed
by the orchestrating session before deploy, then deployed via `Sync-Addon`+`/reload` and live-verified
on the running client before the next phase started. Phase 5's font-size half (§4 Phase 5's "decide
whether any main-window text should adopt fontize-style custom sizing") was deliberately declined —
the spec itself framed it as an open decision, not a required change, and after 6 phases across 12
files the responsible call was to stop at the well-defined elastic-sizing fix and not scope-creep
further. Live-verified per phase: Phase 0 (zero visual change, confirmed via a live function-existence
query), Phase 1 (flat 1px hairline border replacing the ornate 32px dialog border, all 8 tabs +
minimize/maximize/resize), Phase 2 (the alpha-bleed fix confirmed both numerically — before/after
`GetWidth()`/height readings — and visually on the Composition tab's deliberately-translucent panels,
plus `AddGroupPopup` re-verified in both collapsed and expanded mode per the spec's own flag), Phase 3
(title-bar chrome buttons, Composition tab buttons, `AddGroupPopup` buttons, LFM Browser's 6 action
buttons, and all 6 remaining panels' buttons/close-buttons — close-button click-through function
confirmed, not just visual), Phase 4 (Raid Mgmt/Character/Blacklist panels re-checked, including a
scroll to the bottom of Raid Mgmt to confirm the two off-limits scroll-height lines were genuinely
untouched), Phase 5 (all 8 tab labels re-measured with even padding, no clipping, no overlap,
selection recolor re-confirmed on the new elastic tab sizes). One reload-staleness false negative
was caught and corrected mid-project (see `wow-test-harness-reliability-gotchas` memory /
`raid-tools-requirements-traceability.md` row XC-007) - not specific to this project, a general
harness discipline lesson.

No `.lua` files were touched to produce the original design document below — it was read-only
research plus a written spec and a mockup artifact; all `.lua` changes described above happened in
the separate implementation pass this status line summarizes.

**Scope:** `AutoInvitePlus/ui/CentralGUI.lua`, `AutoInvitePlus/ui/CentralGUIBrowser.lua`,
`AutoInvitePlus/ui/CentralGUIPopups.lua`, and `AutoInvitePlus/ui/panels/*.lua` (the main `/aip`
window and its own tabs — `CharacterPanel.lua` included, even though it has no direct
`UIPanelButtonTemplate` call sites of its own; see §2.1). Explicitly **out of scope**:
`modules/Queue.lua`, `modules/Waitlist.lua`, `modules/RosterManager.lua`, `modules/Blacklist.lua`,
`modules/RaidToolsUI.lua`, `modules/Promote.lua` — these also use `UIPanelButtonTemplate`/raw
backdrops and will look slightly more out-of-family once this lands, but the user's ask was the main
window + its tabs, not every window in the addon. Flagged at the end as a plausible future follow-on,
not part of this plan. (`ui/CompositionUI.lua` is a separate, genuinely out-of-scope file that still
gets touched as an unavoidable side effect of one specific shared-factory change — flagged precisely
where that happens, in Phase 3, not treated as in-scope.)

**Governing constraint (said twice by the user): DO NOT BREAK ANYTHING.** Every phase below is
scoped to be independently shippable and independently testable via `/aip testdata` + `/reload`,
and the "Do Not Touch" section names the specific things past live-testing rounds already found
fragile.

---

## 0. Ground truth: the floating-window visual vocabulary

Read directly from `AutoInvitePlus/ui/RaidGroupsWindow.lua` and `AutoInvitePlus/ui/TankCastWindow.lua`
(TankCast owns the canonical skin helpers; RaidGroups calls into them when present and falls back to
an inline copy of the same values otherwise — `RaidGroupsWindow.lua:64-76`).

**Panel body** (`TK.SkinPanel`, `TankCastWindow.lua:76-87`):
```lua
f:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1,
                 insets = {left=1,right=1,top=1,bottom=1} })
f:SetBackdropColor(0.04, 0.045, 0.065, bgAlpha or 0.96)       -- #0A0B11
f:SetBackdropBorderColor(0.30, 0.33, 0.42, 1)                  -- #4D546B
-- + a subtle top-to-bottom body gradient texture (0.03,0.035,0.05 -> 0.075,0.08,0.115)
```
A flat 1px hairline border on a plain white 8×8 texture, not a Blizzard tiled/ornate dialog
texture. `RaidGroupsWindow.lua:64-69`'s fallback copy is pixel-for-pixel identical.

**Header strip** (`TK.SkinHeader`, `TankCastWindow.lua:90-103`): a vertical gradient bar
(`0.09,0.10,0.15` → `0.17,0.18,0.26`), a 1px gold hairline divider (`1, 0.82, 0, 0.55`), and a 4px
gold glow gradient fading to 0 alpha beneath it. `RaidGroupsWindow.lua:71-76`'s fallback is a flatter
single-color version of the same idea (no gradient/glow) — the two files are not byte-identical, but
close enough to read as one language.

**Buttons** (`TK.FlatButton`, `TankCastWindow.lua:107-136`): flat dark fill (`0.10,0.11,0.16,0.95`),
1px slate border (`0.24,0.26,0.34,1`); on hover, border and fill both shift to gold-tinted
(`0.95,0.76,0.12` border / `0.16,0.15,0.10` fill). No Blizzard button texture at all.

**Close button** (`TK.CloseButton`, `TankCastWindow.lua:139-152`): a 14px frame with a plain "x"
glyph (`GameFontHighlight`'s own face at a custom size, via `fontize`), grey by default
(`0.7,0.72,0.8`), red on hover (`1,0.35,0.3`). No round Blizzard `UIPanelCloseButton` texture.

**Popups** (`TankCastConfig.lua:178-188`, `RaidGroupsWindow.lua:303-393`): built from `TK.SkinPanel`
directly (same flat hairline body), gold title text (`1,0.82,0`), and — where the popup is genuinely
a Blizzard `StaticPopupDialogs` entry reused from the pooled `StaticPopup1-4` frames (`RaidGroupsWindow.lua`
`ensureCappedEditBox`, `~303-393`) — an explicit, hard-won routine that hides every Blizzard `Texture`
region on the popup *before* re-applying `skinPanel`, because `skinPanel`'s own fill is implemented as
regular `Texture` children on this client and hiding chrome *after* skinning wipes the fresh skin
along with Blizzard's (documented in the routine's own comments and in traceability doc row RG-022,
which records 6 live-found bugs getting this exact interaction right). This is not a pattern to
casually re-derive from scratch elsewhere — see §3 Do Not Touch.

**Toast/alert chrome** (`RG.ShowBubble`, `RaidGroupsWindow.lua:1225-1280`): same flat `skinPanel` body,
but with the border explicitly brightened to full gold (`1,0.82,0,1`) to read as an alert rather than
"just another dark panel," 12pt outlined text, explicit `SetWidth` for reliable word-wrap, and a
per-frame (`OnUpdate`) height re-assertion because a one-shot `SetHeight` right after `SetText` can
race Blizzard's own layout pass and undershoot (same fix pattern used in the Note/Assignment popup).

**Spacing conventions:** `RaidGroupsWindow.lua` uses `PAD=4, HDR_H=16`; `TankCastWindow.lua` uses
`PAD=3, HDR_H=16`. The two floating windows are not perfectly identical twins — `HDR_H=16` is the
one constant genuinely shared between them. This spec does not require the main window to adopt
either window's tiny `PAD`/`HDR_H` values (it is a full application window, not a compact utility
window); it only requires the main window's own colors/border-style/button-chrome to converge on
the shared flat/gold vocabulary above.

---

## 1. What the main window already gets right (do not re-litigate)

This is not a from-scratch redesign — `CentralGUI.lua` has already had real theming work done on it
this session and in prior rounds. Confirmed by reading the code, not assumed:

- `GUI.ApplyBackdrop` (`CentralGUI.lua:301-307`) already fills dark-navy (`0.045,0.05,0.072` / `#0B0D12`)
  with a slate border (`0.34,0.37,0.46` / `#575E75`) — a **near-miss**, not a clash, against TK's
  `0.04,0.045,0.065` / `0.30,0.33,0.42`. Same idea, slightly different numbers.
- `GUI.StylePopup` (`CentralGUI.lua:311-340`) already adds a gold-hairline title strip
  (`1,0.82,0,0.5`) and a solid navy backing layer — structurally the same idea as `TK.SkinHeader`'s
  divider, just built from Blizzard's tiled `UI-DialogBox-Background-Dark` art underneath instead of
  a flat fill.
- The main frame's title bar (`CentralGUI.lua:898-903`) already has a navy strip + gold divider.
- The tab bar (`CentralGUI.lua:1093-1150`) already uses flat navy/gold-tint fills for
  unselected/selected tabs, not a Blizzard tab texture.
- The status bar (`CentralGUI.lua:1206-1211`) already has the same navy-fill + gold-divider pattern.
- `AIP.UI.Colors` (`UIFactory.lua:21-39`) already centralizes a semantic token palette including
  `goldRGB = {1,0.82,0}` and `borderRGB = {0.34,0.37,0.46}` — a real design-token system already
  exists; it just hasn't fully converged with TK/RG's numbers or been applied everywhere.
- `RaidManagementPanel.lua` (14 `SetBackdrop` call sites) already reuses `0.045,0.05,0.072` /
  `0.34,0.37,0.46` and gold (`1,0.82,0`) headers with `WHITE8X8` divider rules — this panel is
  **already close to the target language**, just via Blizzard's tiled `ChatFrameBackground` +
  `UI-Tooltip-Border` textures instead of a flat 1px hairline.
- `GUI.QueueVisibleRows`/`GUI.ApplyColumnLayout` (`CentralGUI.lua:79-240`) are genuinely elastic:
  row count and column widths are both derived from a real measured content-frame width/height, no
  hardcoded guess. Cite as the model to match elsewhere, not a bug to fix.
- `AddGroupPopup`'s `COLLAPSED_HEIGHT`-family constants were already fixed to derive from real
  widget geometry (traceability doc row XC-006, first bullet) — already elastic-correct.

**Conclusion:** the real gap is not "the main window ignores the theme." It is that the main window
independently reinvented a *close cousin* of the same dark-navy/gold theme using Blizzard's stock
tiled dialog/tooltip/button art as the underlying chrome, while the floating windows use a flat,
custom, hairline-bordered chrome with no Blizzard texture in the panel/button/popup layer at all.
That texture-family difference — not the color palette — is what reads as "drifted" next to the
floating windows.

---

## 2. Concrete divergence inventory

Ranked by **visual impact** (how much of the window's on-screen footprint it touches) first, then
by **implementation risk** within similar-impact items.

### 2.1 — HIGH impact / MEDIUM risk: Button chrome (`UIPanelButtonTemplate`)

**Finding:** `UIPanelButtonTemplate` (Blizzard's stock button art, `Interface\Buttons\UI-Panel-Button-Up/Down`
— see the color correction below) is used addon-wide 141 times across 14 files. Within this spec's
actual scope (`CentralGUI.lua`, `CentralGUIBrowser.lua`, `CentralGUIPopups.lua`, `UIFactory.lua`'s
shared factory, and the five in-scope panels), the real count — recounted per-file, not estimated —
is **~100 call sites (102 grep hits**, a plain-text line-count that can include a comment mentioning
the string, e.g. `CentralGUI.lua:918` itself, so treat it as an upper bound, not an exact tally**)**:
`CentralGUI.lua` ×11, `CentralGUIBrowser.lua` ×32, `CentralGUIPopups.lua` ×4, `UIFactory.lua` ×3
(`UI.CreateButton`/`UI.CreateIconButton`-adjacent code), and the panels ×52
(`RaidManagementPanel.lua` 18, `BlacklistPanel.lua` 11, `SettingsPanel.lua` 10,
`LootHistoryPanel.lua` 7, `FavoritesPanel.lua` 6 — `CharacterPanel.lua` has **zero direct**
`UIPanelButtonTemplate` call sites, but it *is* in scope: its buttons all go through
`AIP.UI.CreateButton`, so it inherits whatever that shared factory renders — see the Phase 3 note
below). The remaining 39 addon-wide occurrences are in `modules/*.lua` (Queue, Waitlist,
RosterManager, Blacklist, RaidToolsUI, Promote), explicitly out of scope per this spec's header.
`AIP.UI.CreateButton` (`UIFactory.lua:335-356`), the addon's own shared button factory, also builds on
`UIPanelButtonTemplate`, so code that already "does the right thing" by calling the shared helper
still inherits stock Blizzard chrome.

One correction to a comment found while auditing, revised after checking real evidence:
`CentralGUI.lua:917-921`'s comment claims the window-chrome buttons (close/maximize/minimize/simplify)
"reuse the addon's own maroon/gold `UIPanelButtonTemplate` skin." A repo screenshot
(`Screenshots/LFM.png`, read directly) confirms the *color* description is accurate, and rules out an
earlier draft's alternative theory: the dropdowns, checkboxes, and scrollbar visible in the same
screenshot all render in plain stock-Blizzard style, not a uniformly reskinned one — if a global
third-party UI skin addon (e.g. ElvUI) were reskinning this client, it would restyle those too, and it
hasn't. So this maroon/red-brown-gradient-with-gold-text look is simply what the stock 3.3.5a
`UIPanelButtonTemplate` renders as on this client — not the grey/tan look this spec's first draft
assumed from memory, and not a third-party skin either. What's still wrong in the comment is only the
*mechanism* claim ("reuse the addon's own skin"): grepping addon-wide for `hooksecurefunc`,
`SetNormalTexture`, `GetNormalTexture`, `SetPushedTexture`, and `GetNormalTexture():SetVertexColor`
turns up zero reskinning of `UIPanelButtonTemplate`'s base textures anywhere (the `SetNormalTexture`
hits that do exist are unrelated icon buttons — the resize grip, `TreeBrowser.lua`'s expand/collapse
arrows, a delete-row "x" icon, ready-check star icons — none of them touch a `UIPanelButtonTemplate`
button's own art). **No addon-side skin/hook/vertex-tint exists anywhere in this codebase — the
"maroon/gold skin" is entirely stock template art, not something AIP set.** There is no single hook to
flip; a real fix touches every call site (or every call site is migrated to go through one new shared
helper, below). (Also worth noting for context, not as a correction: `LFM.png` predates this session's
title-bar consolidation — its separate "Ready"/"Bar"/"RDF"/"Pull"/"Break"/"Tools" buttons are now the
single "..." menu at `CentralGUI.lua:1026-1069` — so it is evidence for what `UIPanelButtonTemplate`
looks like, not for the window's current exact layout.)

**Target treatment:** add `UI.FlatButton(parent, text, w, h, onClick, tooltip)` to `UIFactory.lua`
(loads before `CentralGUI.lua`/panels per the `.toc` order — `core → data → modules → ui\UIFactory.lua`
first in the `ui\` block) that reproduces `TK.FlatButton` exactly (dark fill, slate border, gold-hover
via the same combined `OnEnter`/`OnLeave` handler that recolors the button *and* shows the optional
tooltip in one place — `TankCastWindow.lua:121-134`) without depending on `AIP.TankCast` (UIFactory
must not depend on a feature module that may not be present). `TK.FlatButton`'s pattern of
`SetNormalFontObject`+`SetText` (not a template) already proves `GetFontString()` keeps working on a
plain-`Button`-widget flat button (`TankCastConfig.lua:118,121` calls it successfully on exactly this
kind of button) — and a grep for `GetNormalTexture()` addon-wide found zero call sites, so there is no
"a converted button's texture getter now returns nil" risk to guard against in this codebase today.
**Real risk to flag for Phase 3 implementers:** because `TK.FlatButton`'s hover recolor lives in
`SetScript("OnEnter"/"OnLeave", ...)` (a *replace*, not a *stack*), any call site that currently does
its own separate `:SetScript("OnEnter", ...)` *after* constructing the button (a custom multi-line or
dynamic tooltip, say) will silently clobber the hover recolor if migrated to `UI.FlatButton` without
also moving that logic into the factory's own `tooltip` parameter (or extending `UI.FlatButton` to
accept an additional `onEnter`/`onLeave` callback it chains internally, rather than leaving the call
site to `SetScript` over it). Grep each file's converted buttons for a second `SetScript("OnEnter"|"OnLeave"`
after the `UI.FlatButton(...)` call before considering that file's conversion done. Convert call sites
from `CreateFrame(..., "UIPanelButtonTemplate")` + `:SetText(...)` to `AIP.UI.FlatButton(...)` file by
file (§4, Phase 3). The window-chrome glyph buttons (`CentralGUI.lua:947-952`'s `chromeButton`) get
the same base swap; their gold glyph overlays are unaffected (drawn on top regardless of base texture).

### 2.2 — HIGH impact / LOW risk: Close buttons (`UIPanelCloseButton`)

**Finding:** `UIPanelCloseButton` is used addon-wide in 12 files, but — same scope correction as
§2.1 — only **6 are in this spec's scope**: `CentralGUI.lua`, `CentralGUIPopups.lua`,
`UIFactory.lua` (`UI.CreateCloseButton`, `:392-405`), `RaidManagementPanel.lua`,
`LootHistoryPanel.lua`, and `BlacklistPanel.lua`. The other 6 —
`modules/Queue.lua`, `modules/Waitlist.lua`, `modules/RosterManager.lua`, `modules/Blacklist.lua`,
`modules/RaidToolsUI.lua`, `modules/Promote.lua` — are out of scope per this spec's header. It is a
visually loud, distinctly "default WoW" red button with a gold "×" (`Screenshots/LFM.png`'s top-right
corner shows the actual shape — closer to a red rounded square than a plain circle; the exact geometry
doesn't change the finding) next to the flat "x" glyph the floating windows use (`TK.CloseButton`,
`TankCastWindow.lua:139-152`). Every occurrence is a
standalone popup/window close control, never load-bearing layout (a fixed small square in a corner),
which is why this is lower risk than the general button item despite being visually louder
per-instance.

**Target treatment:** add `UI.CloseButton(parent, onClick, size)` to `UIFactory.lua`, a direct port
of `TK.CloseButton` (flat "x", grey default, red on hover). Swap the 6 in-scope files' call sites one
at a time; each is a single `CreateFrame` line plus (at most) one `:SetPoint` — mechanically simple,
independently verifiable per popup. Note `UI.CreateCloseButton` (`UIFactory.lua:392-405`) is itself an
existing thin wrapper around `UIPanelCloseButton` with no callers found in-repo via grep today — redefining
its body is a zero-blast-radius change; the risk is entirely in the 6 files' direct
`CreateFrame(..., "UIPanelCloseButton")` call sites, not in the wrapper.

### 2.3 — HIGH impact / MEDIUM-HIGH risk: Panel/popup backdrop textures

**Finding:** `GUI.Backdrops` (`CentralGUI.lua:269-298`, four variants: `Panel`/`SubPanel`/`Inset`/`Input`)
and `GUI.StylePopup` (`CentralGUI.lua:311-340`) all build on Blizzard's tiled art —
`Interface\ChatFrame\ChatFrameBackground` + `Interface\Tooltips\UI-Tooltip-Border`, or
`Interface\DialogFrame\UI-DialogBox-Background-Dark` + the same tooltip border for popups — colorized
to the near-miss navy/slate tokens from §1. The floating windows use no tiled Blizzard art anywhere:
a flat `WHITE8X8` 1px hairline (`TK.SkinPanel`) plus, for the popup case, a hand-built gold title
strip and glow. Recounted precisely from the actual call sites (not estimated): `GUI.ApplyBackdrop`
is called **17** times total — `CentralGUI.lua` ×13 (`:1998,2065,2172,2318,2382,2639,2662,2744,5650,
6324,6471,7448,7886`) + `CentralGUIBrowser.lua` ×4 (`:28,294,379,861`) — and `GUI.StylePopup` is
called **7** times total — `CentralGUI.lua` ×3 (`:5567,7415,8229`) + `CentralGUIPopups.lua` ×2
(`:38,136`) + `RaidManagementPanel.lua:2262` + `RaidToolsUI.lua:380` (the Roll window; out of this
spec's scope, but it already piggybacks on `GUI.StylePopup`, so redefining the function restyles that
window too — **add it to Phase 2's live-test list even though it's out of scope**, since it will
visibly change). One dead branch found in passing: `RaidManagementPanel.lua:2264` has an
`elseif AIP.UI and AIP.UI.ApplyBackdrop then AIP.UI.ApplyBackdrop(f, "Window", 1) end` fallback —
`AIP.UI.ApplyBackdrop` does not exist anywhere in `UIFactory.lua` (confirmed against its full
`function UI\.` listing), so this branch can never fire; harmless (the `if AIP.CentralGUI.StylePopup`
branch above it always wins in practice) but worth a one-line cleanup note for whoever touches that
function next. Not in scope to fix here.

Every one of the 24 real calls happens from a one-time `Create*`/`Show*` function, not from a
per-frame `Update`/`OnUpdate` path (confirmed by reading each call site's enclosing function name) —
so a **backdrop-shape** swap is safe without an idempotency guard, the same way `TK.SkinPanel` gets
away with not guarding its own one-time-per-frame calls. **The body gradient specifically is a
different story — see the alpha-bleed risk below.**

**Target treatment:** redefine the four `GUI.Backdrops` entries and `GUI.StylePopup`'s backdrop table
to the flat `WHITE8X8` hairline (mirroring `TK.SkinPanel`'s shape), reusing the *converged* token
values from §2.5 below. Every call site keeps its existing signature
(`GUI.ApplyBackdrop(frame, backdropType, bgAlpha, borderAlpha)`, `GUI.StylePopup(popup, titleHeight)`)
— this is a body-only swap, zero call-site changes required beyond what naturally falls out of §2.4
(border-adjacent anchor insets), and `GUI.StylePopup`'s existing `_aipBg`/`_aipStrip` idempotency
guards and their `5px`/`6px` offsets stay exactly as they are (only the backdrop table's own
`bgFile`/`edgeFile`/`edgeSize`/`insets` values change) — this resolves the apparent tension with §2.4:
the *popup* inset is not touched at all, only the *outer main-frame window* border is (§2.4's own,
separately-scoped, low-risk version).

**Alpha-bleed risk (must fix before porting `TK.SkinPanel`'s gradient body):** `TK.SkinPanel`'s
gradient body texture (`TankCastWindow.lua:83-86`) is drawn with alpha `1` at both gradient stops
regardless of the panel's own `bgAlpha` parameter — because every floating-window caller always
passes a near-opaque alpha (`0.96`/`0.97`) in practice. `GUI.ApplyBackdrop`'s callers are not
uniformly near-opaque: several are **deliberately translucent** — `summaryFrame` at `0.3`
(`CentralGUI.lua:2744`), `buffFrame` at `0.4` (`:2172`), `benefitsFrame` at `0.4` (`:2662`),
`groupsFrame` at `0.5` (`:2382`), `buffSection` at `0.6` (`:2065`), `msgBg` at `0.7`
(`CentralGUIBrowser.lua:379`). Porting the gradient body verbatim would silently make all of these
opaque, a real visual regression this spec must not cause.

**Fix — corrected after catching a compounding error in an earlier draft of this spec:** the gradient
body sits as a *separate texture layer on top of* the backdrop's own fill, so naively scaling *both*
layers by the same `bgAlpha` does not reproduce `bgAlpha` — two stacked layers each at alpha `a`
composite to `1-(1-a)²` (e.g. `0.3` → `0.51`, `0.4` → `0.64`, `0.6` → `0.84`), still a visible
regression for every one of the six translucent callers above (this also rules out the "skip it only
for `Inset`" idea from an earlier draft of this spec — `buffSection` is `SubPanel`, not `Inset`, so a
variant-based skip would have missed it). **Simplest correct fix:** only draw the gradient body when
`bgAlpha >= 0.9` (i.e., treat it as reserved for near-opaque panels, matching every floating-window
caller's own `0.96`/`0.97` in practice); for anything below that threshold, apply `bgAlpha` to the
backdrop's flat fill exactly as today and skip the gradient layer entirely — no compounding, no math
to get subtly wrong twice. Also add an `_aipBody`-style created-once guard on whichever
function ends up creating the gradient texture (mirroring `GUI.StylePopup`'s existing
`_aipBg`/`_aipStrip` guard pattern one function above it) — `GUI.ApplyBackdrop` is called repeatedly
against different frames, so an unguarded `CreateTexture` inside it is fine (each call targets a new
frame), but if any future refactor makes a frame re-enter `ApplyBackdrop` a second time, an unguarded
gradient texture would stack. Cheap insurance, matches the pattern already established one function
above.

### 2.4 — MEDIUM impact / HIGH risk: Main frame's outer border + anchor coupling

**Finding:** the outer window frame itself (`CentralGUI.lua:877-889`) uses the ornate 32px
`Interface\DialogFrame\UI-DialogBox-Border` edge art, and **every other chrome element's anchor
offset is coupled to that border's thickness**: `titleBar` at `10,-10` (`:894-895`), `tabBar` at
`10,-40` (`:1088-1089`), `content` at `10,-75`/`-10,40` (`:1179-1180`), `statusBar` at `10,5`/`-10,5`
(`:1201-1202`), and `solidBg` (the guaranteed-opacity backing layer) inset `11,-11`/`-11,11`
(`:887-888`) to sit just inside the ornate edge. This is the one item in this inventory that is
genuinely layout-adjacent, not purely cosmetic.

**Target treatment (low-risk version — recommended):** swap the backdrop *definition*
(`bgFile`/`edgeFile`/`edgeSize`/`insets`) to the flat `WHITE8X8` 1px-hairline shape and re-tune
`solidBg`'s inset from `11px` down to `1px` to match the new edge thickness — but leave every other
frame's anchor offsets (`10,-10` / `10,-40` / etc.) untouched. **Must also fix two color calls that depended on the old texture supplying its own look, not an
explicit color** — the current code (`CentralGUI.lua:877-883`) calls `SetBackdropColor(0,0,0,1)` (a
literal black fill) and never calls `SetBackdropBorderColor` at all, because the ornate
`UI-DialogBox-Background-Dark`/`UI-DialogBox-Border` art carries its own baked-in look and the black
fill only shows through the art's own translucent regions. Swap the `bgFile` to `WHITE8X8` without
also fixing these and two things go wrong at once: (1) an unset border color on a solid white edge
texture defaults to white (`1,1,1,1`) — a stark bright-white 1px outline around the whole window; (2)
a solid-white *fill* texture at `SetBackdropColor(0,0,0,1)` renders literal opaque black, not navy —
and per the comment already on `solidBg` (`CentralGUI.lua:885-886`, "solid backing layer for
guaranteed opacity… the dark dialog texture alone is semi-transparent"), that black backdrop fill
likely draws *on top of* `solidBg`'s navy `BACKGROUND,-8` layer, which would cover it entirely rather
than let the intended navy show through. **Fix both explicitly:** add
`frame:SetBackdropBorderColor(<slate token>)`, and change `SetBackdropColor(0,0,0,1)` to the
converged navy fill token from §2.5 (matching `solidBg`'s own color, so the two layers agree instead
of one masking the other). (`GUI.ApplyBackdrop` and `GUI.StylePopup` already set both colors
explicitly today, so this gap is specific to the main frame's own hand-written `SetBackdrop` call.)
A 1px border inside what was a 32px-inset layout leaves a ~9-10px flat navy margin around the
window's edge instead of ornate stone — visually a bigger, cleaner navy field, not a broken one.
This is a one-function, no-cascading-anchor-change fix, plus the one added border-color line.

**Explicitly not recommended for this pass:** re-deriving every 10/11px anchor constant to hug a
now-thinner border tightly. That is a genuine layout restructure across the title bar, tab bar,
content area, and status bar simultaneously — exactly the kind of change the user's "don't break
anything" constraint should veto for a design-alignment pass. Ship the backdrop swap, leave the
10-11px margins as "generous padding" rather than "coupled to border thickness," and revisit tighter
insets only as a separate, deliberately-scoped follow-up if the extra margin reads as excessive once
it's live.

### 2.4a — LOW-MEDIUM impact / LOW risk: Tab bar colors are duplicated at two call sites

**Finding:** the tab bar's selected/unselected colors are hardcoded **twice**, and both copies must
change together or tabs will visibly flip appearance the first time a user clicks one. Tab *creation*
(`CentralGUI.lua:1126-1130,1145-1150`) sets the initial colors; `GUI.SelectTab`
(`CentralGUI.lua:8354-8393`, specifically `:8371` and `:8382` for the background, `:8374` and `:8385`
for the text) independently re-asserts the **same literal** `0.30,0.26,0.12`/`0.11,0.12,0.17,0.9`
background pair and gold/grey text pair on every tab switch. Also worth noting precisely:
`GUI.SelectTab` only ever touches `tabBtn.bg` and `tabBtn.text` — it never touches `tabBtn.border`
(the flat grey `0.4,0.4,0.4,1` set once at creation, `:1137`), so the tab border color today is
**static regardless of selection state**, not a per-state color. (The mockup in this spec's Artifact,
§7, matches this: both tabs render with the same slate-token border, selection shown via fill/text
only — no new selection-aware border behavior is proposed here.)

**Target treatment:** update the border color literal (`:1137`) to the converged slate token (§2.5)
at creation time only, since it never changes again. Update both the creation-time and `GUI.SelectTab`
background/text literals to the same converged tokens, citing both line ranges in the same commit/PR
so they can't drift apart again.

### 2.5 — LOW impact / LOW risk: Token unification

**Finding:** three near-identical but not-identical navy/border token pairs currently coexist:
- `TK`/`RG` (canonical, shipped, live-verified): fill `0.04,0.045,0.065` / border `0.30,0.33,0.42`.
- `GUI.ApplyBackdrop`/`GUI.StylePopup` (`CentralGUI.lua:305-306,319-320`): fill `0.045,0.05,0.072` /
  border `0.34,0.37,0.46` (popup fill is `0.05,0.055,0.085`, a third variant again).
- `AIP.UI.Colors.borderRGB` (`UIFactory.lua:32`): `0.34,0.37,0.46` (matches `GUI.ApplyBackdrop`, not TK).

**Target treatment:** pick the floating-window values as the single source of truth (they are what
the user is asking the main window to align *to*), and update `AIP.UI.Colors` (add `bgRGB`, correct
`borderRGB`) plus every literal in `GUI.Backdrops`/`GUI.StylePopup`/per-panel inline backdrops to
match. This is a find-and-replace-shaped change with no layout implications — bundle it into
whichever phase touches each literal anyway (Phase 1/2/4 below) rather than giving it its own pass.

### 2.6 — LOW impact / MEDIUM risk (elastic-sizing flags — audit only, per this session's standing principle)

Per `docs/superpowers/specs/raid-tools-requirements-traceability.md`'s elastic-container-sizing
principle (rows RG-022, XC-006) — flagged here for the implementer to weigh, **not fixed by this
spec**:

- `CentralGUI.lua:1102-1111` (`tabWidths`): a hand-tuned pixel width per tab label instead of a
  measured `tabText:GetStringWidth() + padding`. A real elastic-sizing violation, but low-risk to
  fix only if bundled with a font-size decision (§4 Phase 5) — changing font size changes string
  width, so fixing the measurement and changing the font in the same pass avoids doing the
  measurement twice.
- `RaidManagementPanel.lua:864` (`content:SetHeight(1450)`) and `SettingsPanel.lua:279`
  (`content:SetHeight(1822)`) look like violations on first read. They are not new findings — see
  §3 Do Not Touch; a runtime-measured version of exactly these two was already tried this session
  and reverted after a **live, user-reported regression** (rows overlapping). Do not re-attempt
  without new evidence the earlier root cause is understood.
- A quick pass over popup/frame `SetSize` calls beyond `AddGroupPopup` (§3 item 2, already fixed)
  turned up several more hardcoded popup dimensions worth the same "audit, don't fix" treatment:
  `CentralGUIPopups.lua:33,131` (`280x140`, `300x170`), `CentralGUI.lua:5562`
  (`popup:SetSize(500, COLLAPSED_HEIGHT)` — the `500` width itself is still a guess even though
  `COLLAPSED_HEIGHT` is derived), `CentralGUI.lua:7410,8225` (`400x480`, `430x330`),
  `RaidManagementPanel.lua:920,2256,2822` (`listBg` `150x130`, the Loot Browser popup `400x400`,
  a confirmation popup `280x195`), `BlacklistPanel.lua:730,877` (`450x380`, `450x420`), and
  `LootHistoryPanel.lua:1457,1549` (`280x130`, `400x300`). None of these were inspected further —
  they may be perfectly fine fixed sizes for genuinely fixed-content popups (not every dialog needs
  to be elastic), but each is a candidate worth a quick look before assuming it's fine, given how
  much rigor the AddGroupPopup / Note-Assignment-popup elastic fixes took to get right elsewhere in
  this codebase.

Also explicitly **out of scope for this spec** (not audited, not part of the divergence inventory):
dropdowns (`UIDropDownMenuTemplate` usage throughout), checkboxes (`UI.CreateCheckbox`), sliders
(`UI.CreateSlider`), and scrollbars (`UIPanelScrollFrameTemplate`/`FauxScrollFrameTemplate` usage).
These are all still-stock-Blizzard-chrome widgets that would also read as "not the floating-window
language" once the higher-impact items above ship, but the floating windows themselves don't have
dropdowns/checkboxes/sliders/scrollbars to compare against — `TK`/`RG` have no reference
implementation for any of these widget types, so there is no established target vocabulary to align
*to* yet. A future spec should design one before touching these, rather than improvising a look here.

One more inconsistency worth naming even though it's not ranked above (no clean single target to
converge on yet, same reason as the previous paragraph): **edit-box chrome currently has three
different treatments** in this addon — `GUI.CreateStyledEditBox` (`CentralGUI.lua:343-384`, grey
`0.5,0.5,0.5,1` border, yellow-grey `0.6,0.6,0.3,1` on focus), `AIP.UI.StyleEditBox`
(`UIFactory.lua:235-256`, `0.45,0.45,0.5` border, full gold `1,0.82,0` on focus), and
`SettingsPanel.lua:137-172`'s own inline `SetBackdrop` (`0.05,0.05,0.05,0.95` fill /
`0.5,0.5,0.5,1` border, `0.8,0.8,0.3,1` on focus — a third, independently-written copy of the same
idea). Flagged for awareness; not part of this spec's phased plan.

---

## 3. Do Not Touch

Things a future implementer should leave alone or handle with extra live-verification rigor, with
the history that justifies each one:

1. **`RaidManagementPanel.lua:864` and `SettingsPanel.lua:279`'s fixed scroll-child heights
   (`1450`, `1822`).** Traceability doc row **XC-006**: these were already given a "measure the
   deepest shown child every layout pass" elastic treatment once this session. The user reported,
   live, on their own screen, that it made rows visibly overlap in both panels. Root cause was not
   fully isolated (likely a pooled/template child reporting `IsShown()==true` with a stale
   `GetBottom()`). Both were reverted to the static heights and re-verified clean. **Leave these
   two exactly as they are** unless someone is prepared to actually debug the original root cause,
   not just retry the same fix.
2. **`AddGroupPopup`'s `COLLAPSED_HEIGHT`/`COLLAPSED_NEEDS_Y`/`COLLAPSED_H`/`CUSTOMIZE_BTN_HEIGHT`
   family (`CentralGUI.lua`, `GUI.CreateAddGroupPopup`).** Already fixed to derive from real widget
   geometry (XC-006). §2.3's `GUI.StylePopup` change does **not** move `_aipBg`'s `5px`/`_aipStrip`'s
   `6px` offsets — those stay exactly as they are. What *does* change is the backdrop's own visible
   edge thickness (from the 16px tiled `UI-Tooltip-Border` down to a 1px hairline), which shrinks how
   much of the popup's outer frame the border art itself visually occupies. If `AddGroupPopup`'s own
   internal content is anchored with any assumption about that old 16px edge (not just to
   `_aipBg`/`_aipStrip`), it must be re-opened in both collapsed and expanded/Customize mode and
   live-screenshotted again before calling Phase 2 done, exactly as XC-006's original
   live-verification did.
3. **`GUI.QueueVisibleRows` / `GUI.ApplyColumnLayout` (`CentralGUI.lua:79-240`).** Already
   elastic-correct — cited in this spec as the *model* to match, not a divergence. Do not restructure
   while touching adjacent styling.
4. **`GUI.Config` default/min width/height (`CentralGUI.lua:27-37`), the resize grip
   (`CentralGUI.lua:1275`), and minimize/maximize (`GUI.ToggleMinimize`/`GUI.ToggleMaximize`).**
   These are *not* elastic-sizing violations despite being hardcoded constants — the main window is
   a user-resizable application window with its own resize affordance, a fundamentally different
   pattern from the floating windows' fully content-derived sizing. Do not "fix" these to be elastic;
   that would remove a feature (user resizing) the floating windows don't even have.
5. **`StaticPopupDialogs["AIP_SAVE_COMP_TEMPLATE"]` (`CentralGUI.lua:1877`) and any other genuine
   Blizzard `StaticPopupDialogs` entry.** `RaidGroupsWindow.lua`'s `ensureCappedEditBox` already
   solved "reskin a pooled `StaticPopup1-4` frame to the dark-navy/gold theme" — and it took **6
   live-found bugs** to get right (traceability doc row RG-022: box-over-buttons, invisible-box,
   wiped-backdrop-from-wrong-hide-order, a losing race against Blizzard's own layout pass, and two
   design reversals). That routine's fix is specific to *that* popup's needs (auto-wrap, hard cap,
   no scrollbar) and is not a generic "reskin any StaticPopup" utility to copy elsewhere casually.
   If `AIP_SAVE_COMP_TEMPLATE` or any other StaticPopup needs the same treatment, budget for the same
   live-iteration rigor RG-022 required — don't assume a one-line port of `ensureCappedEditBox` will
   just work.
6. **`AIP.TankCast.*` / `AIP.RaidGroups`'s own skin helpers (`TK.SkinPanel`, `TK.SkinHeader`,
   `TK.FlatButton`, `TK.CloseButton`, `RaidGroupsWindow.lua`'s local `skinPanel`/`skinHeader`
   fallbacks).** Do not move, refactor, or redirect these to call into the new `UIFactory.lua`
   helpers this spec proposes. They are shipped, live-verified, and this session's CLAUDE.md
   explicitly says to keep current module boundaries intact. The new `UI.FlatButton`/`UI.CloseButton`/
   panel-backdrop helpers should be **new, independent code in `UIFactory.lua` that reproduces the
   same values**, not a refactor that makes the floating windows depend on `UIFactory` differently
   than they do today, and not a refactor that makes `UIFactory` depend on `AIP.TankCast` (which may
   load later or be absent in principle, even though in practice both ship together).

---

## 4. Phased breakdown

Each phase is independently shippable and independently testable (`/reload`, `/aip testdata`,
visually compare against the floating windows via `/aip groups` / `/aip tanks` open alongside).

**Phase 0 — Additive tokens + helpers (zero visual change, zero risk).**
Add to `UIFactory.lua` (loads first in the `ui\` block, before `CentralGUI.lua` and all panels):
`UI.FlatButton`, `UI.CloseButton`, `UI.FlatPanelBackdrop`(the flat hairline shape as data, for
`GUI.Backdrops` to consume), and correct `UI.Colors.borderRGB`/add `UI.Colors.bgRGB` to the TK/RG
canonical values (§2.5). Nothing calls these yet — this phase should produce a *no-diff* screenshot
of the live addon. Test: `/reload`, confirm no Lua errors, confirm the window looks pixel-identical
to before.

**Phase 1 — Main frame chrome.** Swap the outer frame's `SetBackdrop` (§2.4, low-risk version only)
and `solidBg` inset; reconcile the title bar strip, tab bar background/border, and status bar to the
Phase 0 tokens. Test: open the main window, all 8 tabs, minimize/maximize/resize, confirm nothing
clips at the new margin.

**Phase 2 — `GUI.ApplyBackdrop` / `GUI.StylePopup` bodies.** Redefine the four `GUI.Backdrops`
variants and `GUI.StylePopup`'s backdrop table to the flat hairline shape, with the alpha-bleed fix
for the gradient body (§2.3). All 24 real call sites (17 `ApplyBackdrop` + 7 `StylePopup`, exact
line numbers listed in §2.3) inherit the change for free — re-open each one live rather than trusting
the count, **including `RaidToolsUI.lua:380`'s Roll window even though it's out of this spec's
scope**, since it will visibly change too. Re-verify `AddGroupPopup` collapsed + expanded per §3
item 2. Pay particular attention to the six deliberately-translucent callers named in §2.3
(`summaryFrame`, `buffFrame`, `benefitsFrame`, `groupsFrame`, `buffSection`, `msgBg`) — confirm they
are still translucent, not accidentally opaque, after the change. Test: open every popup this
touches (`AddGroupPopup`, `EnrollPopup`, the composition save-template flow, the recommendations
popup, the loot browser, the Roll window) at least once.

**Phase 3 — Buttons + close buttons.** Roll out `UI.FlatButton`/`UI.CloseButton` file by file:
suggested order `UIFactory.lua`'s own `UI.CreateButton` (fixes every caller that already uses the
shared factory) → `CentralGUI.lua` → `CentralGUIBrowser.lua` (the LFM tab, the default/most-seen tab —
prioritize this file within the phase) → `CentralGUIPopups.lua` → each in-scope `ui/panels/*.lua` file
in turn (§2.1's 52-site breakdown). **Changing `UI.CreateButton`'s own body is itself a blast-radius
change, not a zero-risk one** — a grep for its actual callers found two files: `ui/panels/CharacterPanel.lua`
(genuinely in scope per this spec's header, even though it has no *direct* `UIPanelButtonTemplate`
call sites of its own — see §2.1) and `ui/CompositionUI.lua` (genuinely out of scope, but still gets
restyled as an unavoidable side effect of changing the shared factory both files call). Add both to
this phase's test list regardless of scope status — a shared-factory change reaches every caller
regardless of which file "owns" the call site, the same lesson §2.3 already applied to
`RaidToolsUI.lua:380` for `GUI.StylePopup`. Each file is independently testable (open just that
tab/popup, confirm buttons still fire their `onClick`, confirm no text clipping from the new chrome's
slightly different padding, and re-check any custom `OnEnter`/`OnLeave` tooltip per the hover-clobber
risk noted in §2.1).

**Phase 4 — Per-panel inline backdrops.** `RaidManagementPanel.lua` (14 sites, already using
near-matching tokens — mostly a literal-value touch-up once Phase 0's tokens exist), plus
`BlacklistPanel.lua`, `LootHistoryPanel.lua`, `CharacterPanel.lua`, `SettingsPanel.lua`'s inline
`SetBackdrop` calls. Convert hand-written backdrop tables to reference the Phase 0 helpers/tokens
instead of re-declaring Blizzard tiled art per call site.

**Phase 5 — Elastic tab widths + font pass (optional, lowest priority).** Fix `tabWidths` (§2.6) to
measure `GetStringWidth()` instead of guessing, and decide whether any main-window text should adopt
`fontize`-style custom sizing. This phase is fenced off on its own because changing font size changes
string widths, which rechecks `ApplyColumnLayout`'s flex-column math (`GUI.QUEUE_HEADER_INSET` etc.)
— do this last, after the visual chrome work is settled and stable, so it isn't entangled with
unrelated regressions if something needs to be bisected.

**Beyond this spec (not a phase, just a note):** once the main window and its own panels match the
floating-window language, `modules/Queue.lua`, `modules/Waitlist.lua`, `modules/RosterManager.lua`,
`modules/Blacklist.lua`, and `modules/RaidToolsUI.lua` (all also `UIPanelButtonTemplate`-based) will
be the next most visible outliers. Worth a follow-up ask, not assumed as part of this one.

---

## 5. Summary table

| # | Divergence | Impact | Risk | File:line (representative) |
|---|---|---|---|---|
| 2.1 | `UIPanelButtonTemplate` buttons (~100 sites in-scope / 141 addon-wide) | High | Medium | `CentralGUI.lua:948`, `UIFactory.lua:336` |
| 2.2 | `UIPanelCloseButton` (6 files in scope, 12 addon-wide) | High | Low | `CentralGUI.lua:5576,7422`, `CentralGUIPopups.lua:45,143` |
| 2.3 | Tiled Blizzard backdrop textures in `GUI.Backdrops`/`StylePopup` (+ gradient-body alpha-bleed risk) | High | Medium-High | `CentralGUI.lua:269-340` |
| 2.4 | Outer frame's ornate 32px border + anchor coupling | Medium | High | `CentralGUI.lua:877-889` |
| 2.4a | Tab bar colors duplicated at 2 call sites (creation + `SelectTab`) | Low-Medium | Low | `CentralGUI.lua:1126-1150,8354-8393` |
| 2.5 | Token drift (3 near-identical navy/border pairs) | Low | Low | `CentralGUI.lua:305-306,319-320`; `UIFactory.lua:32` |
| 2.6 | `tabWidths` hardcoded + several popup `SetSize` calls (elastic flags, audit only) | Low | Medium | `CentralGUI.lua:1102-1111` |

---

## 6. Sources

- `AutoInvitePlus/ui/RaidGroupsWindow.lua` (read in full, lines 1-1280)
- `AutoInvitePlus/ui/TankCastWindow.lua` (read in full, lines 1-1042)
- `AutoInvitePlus/ui/TankCastConfig.lua` (grepped for skin-relevant patterns: `SkinPanel`,
  `SetBackdrop`, `fontize`, gold color literals)
- `AutoInvitePlus/ui/CentralGUI.lua` (targeted reads: 1-280, 280-700, 825-1225; `GUI.SelectTab`
  read in full at 8354-8393; greps for `SetBackdrop`, `CreateFrame`, `StaticPopup`,
  `ApplyBackdrop`/`StylePopup` call sites, `tabWidths`, `hooksecurefunc`/`SetNormalTexture`/
  `GetNormalTexture`/`SetPushedTexture`, `popup:SetSize`; the 5259-5570/5546-onward `AddGroupPopup`
  region and 7408-onward `EnrollPopup` region were located via grep line hits, not read in full)
- `AutoInvitePlus/ui/CentralGUIBrowser.lua`, `AutoInvitePlus/ui/CentralGUIPopups.lua` (grepped for
  `SetBackdrop`/`UIPanelButtonTemplate`/`UIPanelCloseButton`/`popup:SetSize`)
- `AutoInvitePlus/ui/UIFactory.lua` (read: 1-50, 335-395; greps for `function UI\.`,
  `hooksecurefunc`/`SetNormalTexture`/`GetNormalTexture`)
- `AutoInvitePlus/ui/panels/RaidManagementPanel.lua`, `SettingsPanel.lua` (grepped for
  `SetBackdrop`/fonts/heights/`popup:SetSize`; `RaidManagementPanel.lua:2245-2274` read in full)
- `AutoInvitePlus/ui/panels/BlacklistPanel.lua`, `LootHistoryPanel.lua`, `FavoritesPanel.lua`,
  `CharacterPanel.lua` (grepped for `UIPanelButtonTemplate` per-file counts and `popup:SetSize`;
  not read in full — flagged in §3 as a limitation where relevant)
- `AutoInvitePlus/AutoInvitePlus.toc` (load order, confirms `UIFactory.lua` loads before `CentralGUI.lua`
  and all `ui/panels/*.lua`)
- `Screenshots/LFM.png` (read directly as an image — the only rendered-in-game evidence used in this
  spec; predates this session's title-bar consolidation, so treated as evidence for
  `UIPanelButtonTemplate`'s stock color/shape only, not for the window's current exact layout)
- `docs/superpowers/specs/raid-tools-requirements-traceability.md` (read in full — rows RG-022,
  XC-006 specifically inform §3's Do Not Touch list)
