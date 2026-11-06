# Amber World — Pass 6

- Added the campaign «Пепел помнит имена»: six chapters, authored dialogue scenes, five named characters with motives and speech profiles, four decisions with persistent flags/effects, and an epilogue.
- Added two story locations to the overworld map; they appear when their chapters unlock.
- Added two boss BattleCreature resources with bespoke weapon/ability resources and victory events. Boss fights can be launched only within their location radius.
- Added three story items to the live item registry and illustrated them in the item-art atlas; campaign choices award them.
- Persisted campaign state in Worlds save data. Old saves without a campaign key initialize safely without altering other save fields.
- Ashwick's Amber Eye emblem now changes field, tincture and charge according to the player's decisions and ending. Additional emblem glyphs are available for future towns.
- NPC dialogue portraits now use existing hand-painted character assets where a role match exists; clothing hatching and item icon dry-brush details align the UI with the project art direction.
- No settlement coordinates, city plan, movement, collision or existing item/quest mechanics were removed.

## Verification

- 23 JSON data files parse. Story item, boss creature, weapon and ability references resolve to files.
- Added `tests/story_campaign_checks.gd` for the full campaign progression path. It was not run because Godot 4.7 is not installed in the work environment.
- Godot project import, GDScript parse, battle runtime, UI rendering and in-engine screenshots remain unverified.
