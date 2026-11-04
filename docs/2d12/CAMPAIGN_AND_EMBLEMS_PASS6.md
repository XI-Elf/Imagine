# Amber World — Campaign & Emblems Pass 6

## Added
- Data-driven campaign `game/data/story/campaign.json`: six chapters, dialogue scenes, five named characters with motives/voice notes, four meaningful decisions, two boss encounters, two story locations, three quest-item definitions.
- `game/story/campaign.gd`: deterministic campaign state, objective event routing, decision flags/effects, boss unlock rules.
- `Worlds.campaign_state` is serialized in `worlds.to_dict()` and restored in `load_dict()`. Old saves without this key receive a fresh campaign state; other save fields remain untouched.
- Story events: entering Ashwick, handing in a city quest, travelling kilometres, and defeating a named story boss.
- Hero menu receives a `Кампания` tab with current chapter, authored dialogue, objective progress, decisions, cast, boss/location records and launch controls.
- Two `BattleCreature` boss templates are wired to the existing battle actor pipeline. Boss fight can start only within the configured radius of its story location.
- Ashwick emblem changed to the Amber Eye; emblem drawing now supports unique wolf, bell and thorn charges for future settlements.
- NPC portraits gain ink contours, cloth hatching and role-specific facial silhouettes, retaining the current role/seed variation.

## Compatibility / limitations
- Existing settlement ID `s001`, world coordinates, city layout, movement and collision systems are unchanged.
- No old assets or mechanics were removed.
- Story items are registered in the live city item catalog and are awarded by the corresponding campaign decisions. Automatic world loot placement remains a later task.
- Both bosses use dedicated `BattleCreature`, `BattleWeapon`, and `BattleAbility` resources; their attacks are wired to the existing combat pipeline.
- The current source archive contains one registered settlement (Ashwick), so only its emblem is changed. Additional emblem glyphs are implemented for future settlements.
- Godot 4.7 executable is not available in this environment; GDScript parsing/runtime tests were not executed. Static JSON and archive checks only.
