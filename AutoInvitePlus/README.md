# AutoInvite Plus v4.3.10

A comprehensive raid organization suite for World of Warcraft 3.3.5a (WotLK) with LFM/LFG browser, auto-invite system, and inspection engine.

## Features

### LFM Browser
- **Group Tree View**: Browse groups advertised in chat channels organized by raid type
- **Real-time Scanning**: Automatically captures LFM messages from Trade, LFG, and custom channels
- **Group Details Panel**: View detailed information about selected groups including leader, requirements, and composition needs
- **Quick Request**: Send auto-invite keywords to groups with one click
- **Detailed Request**: Send comprehensive whisper with your class, spec, GS, iLvl, and achievements

### Auto-Invite System
- **Keyword Detection**: Automatically invite players who whisper trigger keywords (e.g., "inv", "invite")
- **Queue System**: Optional queue mode for manual approval of invite requests
- **Blacklist Integration**: Flag or auto-reject blacklisted players
- **Response Messages**: Customizable automatic whisper responses

### LFG Enrollment
- **Self-Enrollment**: List yourself as looking for group with detailed stats
- **Auto-Broadcasting**: Automatically broadcast your LFG message at configurable intervals
- **Achievement Linking**: Include your best raid achievements in messages

### Composition Advisor
- **Raid Templates**: Pre-configured templates for WotLK, TBC, Classic raids
- **Role Tracking**: Track tanks, healers, and DPS requirements
- **Class Breakdown**: Visual display of current raid composition
- **Buff/Debuff Tracking**: Comprehensive tracking of 40+ raid buffs and debuffs organized by category
- **Raid Member Table**: Scrollable table showing all raid members with class, role, and GearScore
- **Buff Categories**: Critical buffs, stat buffs, damage buffs, debuffs, and utility abilities
- **Alternate Detection**: Shows when an alternate buff provider is available

### Blacklist Management
- **Search & Filter**: Find blacklisted players by name or source
- **Multiple Sources**: Track where each blacklist entry came from
- **Export/Import**: Share blacklists with guildmates

## Installation

1. Download and extract to `Interface/AddOns/AutoInvitePlus`
2. Ensure all files are in the folder (not in a subfolder)
3. Restart WoW or type `/reload`

## Slash Commands

| Command | Description |
|---------|-------------|
| `/aip` | Open main window |
| `/aip toggle` | Toggle auto-invite on/off |
| `/aip queue` | Show invite queue |
| `/aip bl <name>` | Add player to blacklist |
| `/aip unbl <name>` | Remove from blacklist |
| `/aip clear` | Clear invite queue |
| `/aip spam` | Broadcast invite message once |

## Quick Start Guide

### Setting Up Auto-Invite

1. Open settings with `/aip` and go to **Settings** tab
2. Check **Enable Auto-Invite**
3. Set trigger keywords (default: "inv;invite")
4. Choose listening channels (Whisper recommended)
5. Players who whisper your keywords will be invited automatically

### Creating a Group (LFM)

1. Open the addon with `/aip`
2. Click **Add Group** button
3. Select raid type, size, and requirements
4. Enter minimum GearScore and iLvl
5. Click **Create** to start broadcasting

### Looking for Group (LFG)

1. Open the addon with `/aip`
2. Click **Enroll Me** button
3. Select the raid you're looking for
4. Your stats are auto-detected (GS, iLvl, spec)
5. Click **Enroll** to start broadcasting

### Finding Groups

1. Open the addon with `/aip`
2. Browse the tree view showing available groups
3. Click a group to see details
4. Use **Quick Req** to send the invite keyword
5. Or use **Request Invite** for a detailed application

### Using the Queue

1. Enable "Use Queue" in settings
2. Players requesting invites are added to queue
3. Review requests in the Queue tab
4. Click **Inv** to invite, **Rej** to reject, **W** for waitlist

## Settings Overview

### [1] Auto-Invite System
- **Enable Auto-Invite**: Master toggle for automatic inviting
- **Trigger Keywords**: Words that trigger auto-invite (separated by ;)
- **Max Group Size**: Maximum players to invite
- **Auto-convert to Raid**: Automatically create raid when group is full
- **Guild Only**: Only accept requests from guild members
- **Use Queue**: Require manual approval for invites

### [2] Listen Channels
Select which channels to monitor for invite requests:
- Whisper (recommended)
- Say, Yell, Guild
- Custom channels

### [3] Broadcast Settings
Configure LFM/LFG message broadcasting:
- Select target channels
- Set message template
- Configure cooldown between broadcasts
- Auto-broadcast interval

### [4] LFM/LFG Scanner
- Enable chat scanning for other players' messages
- Select channels to scan
- Set cache duration

### [5] Response Messages
Customize automatic whisper responses:
- Invite accepted message
- Invite rejected message
- Waitlist message

### [6] GUI Appearance
- **Window Opacity**: Adjust transparency (30-100%)
- **Unfocused Opacity**: Reduce opacity when not hovering

### [7] Debug & Data
- Enable debug messages
- Clear all data
- Reset to defaults

## Tips & Best Practices

### Avoid Chat Bans
- Use auto-tuned broadcast intervals
- Don't spam multiple channels simultaneously
- Default settings are optimized for safety

### Efficient Group Building
- Set clear GearScore/iLvl requirements
- Use the queue system for quality control
- Blacklist problematic players promptly

### Finding Groups
- Check multiple raid categories
- Use the search filter
- Send detailed requests for better chances

## Troubleshooting

### Groups not appearing in browser
- Ensure LFM/LFG scanner is enabled in settings
- Check that the correct channels are selected for scanning
- Groups expire after 15 minutes of inactivity

### Auto-invite not working
- Verify "Enable Auto-Invite" is checked
- Check that keywords match what players are whispering
- Ensure listening channels include Whisper

### Dropdowns closing immediately
- This was fixed in v4.2.1
- If still occurring, try `/reload`

## Changelog

### v4.3.10
- **Improved Achievement Lookup for Request Invite:**
  - Added `NormalizeRaidKey` function to handle different raid key formats
  - Achievement lookup now tries multiple variations (e.g., "ICC" finds ICC25H achievements)
  - Strips spaces and normalizes case for consistent matching
  - Falls back to checking all size/mode combinations for the base raid
  - Request Invite whisper now reliably includes best achievement at the end

### v4.3.9
- **Fixed Add Group Popup Edit Boxes:**
  - Replaced bare InputBoxTemplate with styled edit boxes for Tank/Healer/DPS inputs
  - Replaced bare InputBoxTemplate with styled edit boxes for GS/iLvl inputs
  - Edit boxes now have proper dark backgrounds and borders matching the addon style
- **Fixed Enroll Popup Achievement List:**
  - Changed from SimpleHTML to ScrollingMessageFrame for proper hyperlink support
  - Achievement links now show tooltips on hover (OnHyperlinkEnter/OnHyperlinkLeave)
  - Achievement links are clickable (OnHyperlinkClick)
  - Removed visual overlap issues with color codes
  - Added mouse wheel scrolling support
- **GearScore Consistency:**
  - All GS displays now use the same calculation function (GUI.CalculatePlayerGS)
  - Footer, Enroll popup, and Request Invite whisper all show consistent values
  - Prioritizes GearScore_GetScore from GearScoreLite when available

### v4.3.8
- Increased Add Group popup size for better element fitting
- Fixed class checkbox spacing in Add Group popup
- Increased Enroll popup size for achievement links
- Added achievement links with proper formatting in Enroll popup

### v4.3.7
- **GearScore Calculation:**
  - Implemented exact GearScoreLite formula for cases when addon is not available
  - Proper slot modifiers (2H weapon = 2.0x, ranged = 0.3164x, etc.)
  - Hunter special handling (melee weapons = 0.3164x, ranged = 5.3224x)
  - Titan's Grip dual 2H weapon handling (0.5x each)
  - Quality scaling based on item rarity
- **GS/iLvl Footer Display:**
  - Added GearScore and item level display to main window footer
  - Color-coded GS based on score tier
  - Auto-updates when equipment changes
- **Blizzard Raid Browser Integration:**
  - Hooks into WoW's SearchLFGGetResults API
  - Imports listings from Blizzard's raid browser into LFM Browser
  - Shows [LFG Tool] indicator for Blizzard-sourced listings
- **Waitlist Whisper Fix:**
  - Fixed waitlist notification whispers not being sent
  - Added pcall wrapper for SendChatMessage error handling
  - Removed duplicate message sending in Queue.lua

### v4.3.6
- Fixed Composition tab raid lockout detection
- Added waitlist whisper notifications when players are added to waitlist
- Improved error handling for chat message sending

### v4.3.5
- Fixed LFM tab tree browser refresh preserving scroll position
- Fixed Composition tab role bar calculations
- Added "Refresh" button inline with "Hide Locked" checkbox
- Cleaned up unused code paths

### v4.3.4
- **Auto-Broadcast System:**
  - Add Group and Enroll now auto-broadcast messages at configurable intervals
  - "Stop BC" button appears when broadcasting is active
  - Broadcast status shows countdown to next message
  - LFG broadcasts automatically stop when you join a group
- **Request Invite Button:**
  - Replaced Whisper/Invite buttons with "Request Invite" in details panel
  - Sends detailed whisper with class, spec, role, GS, iLvl, and achievement
  - "Quick Req" button for sending just the invite keyword
- **Enhanced LFG Messages:**
  - LFG enrollment messages now include class, spec, and iLvl
  - Format: "LFG ICC25H - Warrior (Arms) DPS, GS: 5200, iLvl: 245"

### v4.3.3
- **Spam Fix:** Broadcast now sends to ALL selected channels simultaneously
- **Response Messages:** Added configurable auto-responses for invite/reject/waitlist
- **Blacklist Mode:** Choose between "Flag" (highlight) or "Reject" (auto-decline)
- Fixed tree browser state preservation (scroll position, expand/collapse)
- Filter dropdown auto-populates with detected raid types

### v4.3.2
- **Spec-Aware Buff/Debuff Detection:**
  - Composition tab now properly checks player specs for spec-specific buffs
  - Buffs that require specific talent specs (e.g., Replenishment, Trueshot Aura) only show as available if a player with the correct spec is present
  - Player spec detection uses active talent group for accurate dual-spec support
  - Automatic inspection queue for raid members whose specs matter for buff coverage
  - Inspection results are cached for 5 minutes to avoid repeated queries
- **Composition UI Improvements:**
  - Spec-specific buffs marked with asterisk (*) in buff list
  - Orange "?" status indicator for buffs with potential providers (class match, spec unknown)
  - Potential providers shown in tooltips with reason (wrong spec or spec unknown)
  - Provider tooltips now show confirmed spec for each provider
  - Member table shows spec initial next to class (e.g., "Paladin(R)" for Retribution)
  - Member row tooltips now display detected spec with status indicator
- **Enhanced Class Breakdown Panel:**
  - Compact scrollable raid member list with class-colored names
  - New Raid Benefits panel showing buff coverage stats
  - Benefits organized by category: Stats, Attack, Spell, Haste, Crit, Debuffs, Utility
  - Visual icons with desaturated state for missing buffs
  - Coverage percentage summary at bottom of panel
  - Tooltips showing buff providers and descriptions
  - Buff category tabs updated to 6 categories matching the comprehensive buff list
- **Raid/Dungeon Dropdown Improvements:**
  - Dropdowns now use nested submenus organized by category (WotLK Raids, WotLK Dungeons, TBC Raids, etc.)
  - Easier navigation for large lists of raids and dungeons
  - Size dropdown auto-populates based on selected raid/dungeon (e.g., dungeons only show 5, Karazhan only shows 10, ICC shows 10/25)
  - Heroic checkbox automatically hidden for raids without heroic mode
  - Size dropdown disabled when only one size is valid (e.g., 5-man dungeons)
  - Added support for Classic raid sizes (20/40 player raids)
- **Comprehensive Buff/Debuff Tracking (100+ abilities):**
  - Reorganized categories: Critical, Stats, Attack Power, Spell Power, Haste, Crit, Healing/Mana, Debuffs, Utility
  - **Stats:** Kings, GotW, Fort, Intellect, Spirit, Str/Agi (Horn/SoE), HP (Commanding/Blood Pact), Shadow Protection
  - **Attack Power:** Battle Shout, Blessing of Might, Trueshot Aura, Abomination's Might, Unleashed Rage
  - **Spell Power:** Totem of Wrath, Flametongue Totem, Demonic Pact, Focus Magic
  - **Haste:** Windfury Totem, Icy Talons, Wrath of Air, Moonkin/Swift Retribution
  - **Crit:** Leader of the Pack, Rampage, Moonkin Aura, Elemental Oath
  - **Mana:** Wisdom/Mana Spring, Judgement of Wisdom, Revitalize, Hunting Party
  - **Armor Debuffs:** Sunder, Expose Armor, Acid Spit, Faerie Fire
  - **Damage Debuffs:** Curse of Elements, Earth and Moon, Ebon Plaguebringer, Blood Frenzy, Savage Combat
  - **Bleed Debuffs:** Mangle, Trauma, Stampede
  - **Hit Debuffs:** Misery, Improved Faerie Fire
  - **Spell Crit Debuffs:** Improved Scorch, Winter's Chill, Shadow Mastery
  - **Attack Speed Debuffs:** Thunder Clap, Frost Fever, Infected Wounds, Judgements of the Just
  - **AP Reduction:** Demo Shout/Roar, Vindication, Curse of Weakness
  - **Cast Speed:** Curse of Tongues, Mind-numbing Poison, Slow
  - **Healing Debuffs:** Mortal Strike, Wound Poison, Aimed Shot
  - **Utility:** Threat redirects, Combat res, Damage reduction, Emergency abilities, CC (12 types), Interrupts (10 types), Dispels (8 types), Racial abilities

### v4.3.1
- Improved Composition tab buff/debuff layout with better visual organization
- Added category color indicators to buff tabs (Critical=Red, Stats=Blue, Damage=Orange, Debuffs=Purple)
- Enhanced buff display with alternating row backgrounds and hover highlights
- Improved talent spec detection for WotLK 3.3.5a dual spec support
- Added GetActiveTalentGroup support for accurate spec detection
- Added Invite Keyword field to Add Group popup
- Keywords are now included in broadcast messages (w/ "keyword" format)
- Enhanced Quick Req button with improved keyword detection patterns
- Quick Req now shows detected keyword in tooltip before sending
- Added achievement tooltips to message display panel
- Message box now shows achievement completion status on hover
- Achievement detection extracts achievement IDs from chat messages
- **Broadcast System Improvements:**
  - Staggered channel sends (2s base delay between channels)
  - Chat throttle/ban detection with common server messages
  - Auto-tuning: increases delay and interval when throttled
  - Chat ban status indicator in footer (shows remaining cooldown)
  - Decay system: delays reset after 5 minutes without throttling
- **Queue/Waitlist Improvements:**
  - Added manual "+ Add" buttons to Queue and Waitlist tabs
  - Fixed "Move to Waitlist" (W) button functionality in queue
  - Added "Q+" button on LFG rows to add players directly to queue
  - Added "WL+" button on LFG rows to add players directly to waitlist
  - Improved tooltips for all action buttons
- **Instance Lockout Detection (Addon-wide):**
  - LFM Browser: Groups for locked instances highlighted in red with [Locked] prefix
  - LFM Browser: "Hide Locked" checkbox to filter out groups for saved instances
  - LFM Browser: Category headers show count of locked instances
  - Add Group Popup: [LOCKED] warning when selecting a raid you're saved to
  - Add Group Popup: Locked raids shown in red in dropdown menu
  - Enroll Popup: [LOCKED] warning when selecting a raid you're saved to
  - Enroll Popup: Locked raids shown in red in dropdown menu
  - Detail Panel: Shows [LOCKED] indicator when viewing a locked group
  - LFG Tab: Raid column shows locked raids in red with tooltip warning
  - Supported instances:
    - WotLK Raids: ICC, RS, TOC/TOGC, VOA, Ulduar, Naxx, OS, EoE, Onyxia
    - WotLK Dungeons: FoS, PoS, HoR, ToC5, HoL, HoS, DTK, VH, UK, UP, Nexus, Oculus, CoS, etc.
    - TBC Raids: Sunwell, Black Temple, Hyjal, TK, SSC, Gruul, Mag, Karazhan, Zul'Aman
    - TBC Dungeons: Shattered Halls, Shadow Lab, Arcatraz, Mechanar, MGT, etc.
    - Classic Raids: MC, BWL, AQ40, AQ20, ZG, Onyxia
    - Classic Dungeons: UBRS, LBRS, Stratholme, Scholomance, Dire Maul, BRD
  - Add Group/Enroll dropdowns now include TBC and Classic raids/dungeons
- Improved Composition tab layout with dynamic height adjustment
- More compact Class Breakdown and Raid Members display

### v4.3.0
- Changed default auto-invite keyword to "invme-auto"
- Added Waitlist tab to Queue/LFG panel (3 tabs: Queue, LFG, Waitlist)
- Enhanced Composition tab with comprehensive buff/debuff tracking
- Added 40+ WotLK raid buffs/debuffs organized by category (Critical, Stats, Damage, Debuffs)
- Added buff alternate detection (shows when alternate provider is available)
- Added scrollable raid member table with name, class, role, and GearScore columns
- Improved class breakdown display with tooltips
- Added buff provider tooltips showing which raid members provide each buff
- Enhanced blacklist export with 3 formats: Simple, Full (all fields), CSV (for spreadsheets)
- Enhanced blacklist import with format auto-detection and live preview
- Added import mode selection: Merge (add new only) or Replace (clear first)
- Import preview shows new entries, duplicates, and validation errors
- Fixed Settings panel opacity sliders for WotLK 3.3.5a compatibility
- Fixed Settings panel layout and default values loading

### v4.2.1
- Fixed custom field in enroll popup
- Added tooltips to queue/LFG row listings
- Added Quick Request button for auto-invite keywords
- Fixed backdrop border overlapping
- Added opacity slider and unfocused opacity feature
- Added tooltips across the addon
- Fixed dropdown strata issues

### v4.2.0
- Enhanced edit box styling for WotLK compatibility
- Fixed trigger keywords field
- Dynamic blacklist source dropdown
- Auto-tuned broadcast intervals

### v4.1.0
- Complete GUI redesign
- Integrated queue in LFM tab
- Message composer
- TBC/Classic raid templates
- Enhanced blacklist management

## Credits

- **Author**: iuGames
- **Original Code**: Martag of Greymane, Matthias Fechner
- **Framework**: Ace3

## Support

Report issues at: https://github.com/anthropics/claude-code/issues

---
*AutoInvite Plus - Making raid organization effortless since 2024*
