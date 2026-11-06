# Вырезанный модуль: квесты 2D 12 (кампания «Пепел помнит имена»)

Вырезано из Amber World 2D 12 (ветка `claude/project-thread-ezaind`, сборка «Amber Game — 2D 12.zip») 2026-11-04.
Игра без модуля: ветка `claude/project-thread-5zivt9`. Этот модуль лежит там же в `modules_cut/quests_2d12/` (вне `game/`, в экспорт не попадает).

## Что именно вырезано (граница)

«Новые квесты» = всё квестовое, что 2D 12 добавила к 2D 11. В коде 2D 12 это одна система: сюжетная кампания из архива Pass6
(Pass5 `quest_campaign.gd` в 2D 12 не брали ещё при слиянии, поэтому вырезать там нечего).

| Часть | Где была |
|---|---|
| Логика кампании: главы, цели, развилки, флаги, эффекты, миграция состояния | `game/story/campaign.gd` |
| Данные: 6 глав, 5 персонажей, 4 развилки, 2 локации, 2 босса, 3 сюжетных предмета | `game/data/story/campaign.json` |
| Боссы и их бой: «Сторож без лица», «Эхо протокола» | `game/data/battle/creatures/amber_warden.tres`, `beacon_echo.tres`; способности `abilities/amber_pulse.tres`, `root_snare.tres`; оружие `weapons/amber_blast.tres` |
| Сюжетные предметы: фрагмент янтарного ключа, страница журнала водосброса, линза маяка | `game/data/cities/items.json` (3 записи, категория `quest`) → `items_story.json.txt`; значки — `item_art.gd` |
| Раздел кампании в меню героя (I → 6 «Задания»): глава, реплики, цель, кнопки выбора, «Особые противники» с кнопкой «Вступить в бой», действующие лица, история решений | `game/characters/hero_window.gd` |
| События кампании: пройденный км, вход в Эшвик, сданное поручение, услышанная байка, победа над боссом | `worlds.gd`, `city_world.gd` |
| Запуск боя с боссом у сюжетной локации | `worlds.gd` `start_story_boss()` |
| Метки сюжетных мест на общей карте после открытия главы | `world/settlements.gd` `_draw()` |
| Герб Эшвика, меняющийся по решениям кампании, + фигура «thorn» (нужна только ему) | `world/settlements.gd` `_emblem_for()`, `_draw_charge()` |
| Репутация и флаги кампании в состоянии Эшвика | `worlds.gd` `_leave_now()`, `hero_window.gd` `_choose_story()` |
| Сохранение: ключ `campaign` и миграция | `worlds.gd` `to_dict()` / `load_dict()` / `_attach()` |
| Обучение: подсказки «Сюжет» и «Решение по сюжету», строка механики «Сюжет и справочник», упоминание сюжета в F1 | `tutorial/tutorial.gd` |
| Категория «Сюжетные» в справочнике выжившего | `characters/field_guide.gd` |
| Переводы (114 строк uk) | `game/i18n/uk.po` → `i18n_uk_quests.po` |
| Тест кампании; проверки кампании в тесте сохранений и обучения | `tests/story_campaign_checks.gd`, `save_compat_checks.gd`, `tutorial_checks.gd` |
| Описание Pass6 | `docs/2d12/CAMPAIGN_AND_EMBLEMS_PASS6.md` → `docs/` |

**Оставлено в игре (это не квесты):** поручения и рост города 2D 11, бесконечные поручения, список «Принятые поручения Эшвика»
в разделе «Задания» (из QuestPass: показывает только поручения 2D 11, от кампании не зависит), справочник выжившего,
описания 69 предметов, эмблемы поселений из данных (в т.ч. «янтарное око» Эшвика в `settlements.json` и фигуры wolf/bell),
портреты NPC, руины, штрихи города.

## Состав архива

```
README.md                    этот файл
return_quests_2d12.patch     одна заплатка: вернуть ВСЁ (файлы + точки подключения + uk.po + тесты)
game/...                     вырезанные файлы целиком, по их местам в game/
items_story.json.txt         3 записи сюжетных предметов для data/cities/items.json
i18n_uk_quests.po            114 строк перевода модуля
hooks/*.diff                 точки подключения по файлам (тот же патч, разрезанный по файлам — для ручного возврата)
docs/CAMPAIGN_AND_EMBLEMS_PASS6.md
```

## Как вернуть модуль

Быстро (из корня репозитория, на ветке без модуля):

```
git apply modules_cut/quests_2d12/return_quests_2d12.patch
godot --headless --path game --import
```

Патч создаёт файлы в `game/` и возвращает все точки подключения ровно к состоянию 2D 12. Если код вокруг с тех пор менялся
и патч не ложится, возвращать вручную по списку ниже (номера строк — по 2D 12, ветка ezaind).

### Точки подключения (вручную)

1. Скопировать `game/` из архива поверх `game/` игры.
2. `data/cities/items.json`: вставить содержимое `items_story.json.txt` в конец словаря `items` (после `repair_kit`, не забыть запятую).
3. `worlds/worlds.gd` (`hooks/worlds.gd.diff`):
   - `const StoryCampaign := preload("res://story/campaign.gd")` рядом с прочими preload;
   - вместо `var _cut_campaign` — `var campaign_state: Dictionary = StoryCampaign.fresh()`;
   - `_attach()`: `campaign_state = StoryCampaign.fresh()`;
   - `_on_hero_km()`: `campaign_event("travel_km", "", 1)` после первой проверки;
   - `_enter_city_now()`: после `stack.append(...)` — `if city_id == "s001": campaign_event("city_enter", city_id)`;
   - `_apply_battle_result()`: при `outcome == "win"` — разбор `origin` `story_boss:<id>` и `campaign_event("boss_defeated", id)`;
   - функции `campaign_event()` и `start_story_boss()` (после `_apply_battle_result`);
   - `_leave_now()`: для `s001` записать `story_reputation` / `story_flags` в `city_states`;
   - `to_dict()`: `"campaign": campaign_state.duplicate(true)`;
   - `load_dict()`: `campaign_state = StoryCampaign.migrate(d.get("campaign", null))`; блок совместимости
     (`_cut_campaign`, `_drop_unknown_items`, пропуск боя `story_boss:`) и `const TradeRef` убрать.
4. `characters/hero_window.gd` (`hooks/hero_window.gd.diff`): `const StoryCampaign`; в `refresh()` подпись вкладки `quests`
   с `campaign_state`; в `_fill_quests()` первыми строками `_fill_story()` и `HSeparator`; функции `_fill_story()` и `_choose_story()`.
5. `world/settlements.gd` (`hooks/settlements.gd.diff`): `const StoryCampaign`; в `_draw()` цикл меток сюжетных мест
   (перед подсказкой «вибір закритий»); функция `_emblem_for()` и её вызовы вместо `s.get("emblem", {})` в `_draw()` и
   `_draw_medallion()`; ветка `"thorn"` в `_draw_charge()`.
6. `city/city_world.gd` (`hooks/city_world.gd.diff`): `hear_tale()` — `w.campaign_event("codex")`; `turn_in()` — после
   `Growth.complete` `campaign_event("city_quest", city_id)` для небесконечных поручений.
7. `characters/item_art.gd`: три записи в `SPECS` и фигуры `key_fragment`, `ledger_page`, `lens` в `_shape()`.
8. `characters/field_guide.gd`: категория `"quest": I18n.t("Сюжетные")`.
9. `tutorial/tutorial.gd`: подсказки `story`, `story_choice`, функция `_story_waits()`, у `guide` — `"after": "story"`;
   строки F1 и механик — по `hooks/tutorial.gd.diff`.
10. `i18n/uk.po`: дописать `i18n_uk_quests.po` (или вернуть файлы и запустить `python3 -I game/tools/i18n.py extract`,
    затем перенести переводы из `i18n_uk_quests.po`); проверка — `i18n.py check`, должно быть 0 без перевода.
11. Тесты: `tests/story_campaign_checks.gd` (вернётся из `game/`), прежние версии `save_compat_checks.gd` и `tutorial_checks.gd` — в патче.

## Зависимости модуля

- Использует из игры: `Worlds` (автозагрузка: `game`, `inventory`, `city_states`, `start_battle`, `stack`), `Trade` (`city/trade.gd`),
  `I18n`, `Actor`, бой (`battle/res/battle_creature.gd`, `BattleData` — боссы как обычные существа), `city_growth.gd`
  (поручения как событие), рисование гербов `settlements.gd`.
- Игра от модуля не зависит: после вырезания ни один файл в `game/` не ссылается на `res://story/`, `campaign_state`,
  `campaign_event`, боссов или сюжетные предметы (проверено поиском).

## Совместимость сохранений без модуля

- Сохранение 2D 11 — загружается как раньше.
- Сохранение 2D 12 с ключом `campaign` — загружается без ошибок. Ключ не читается, но **переносится в новое сохранение без
  изменений**, поэтому если модуль вернуть, прогресс кампании не пропадёт.
- Сюжетные предметы в сумке старого сохранения убираются при загрузке (их нет в каталоге). При возврате модуля их придётся
  выдать заново (это три вещи-награды за выбор; на ход кампании не влияют).
- Сохранение посреди боя с сюжетным боссом — бой не восстанавливается, герой остаётся на карте.
- Всё это проверяет `tests/save_compat_checks.gd` (14 проверок).
