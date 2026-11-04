extends RefCounted
## Основная сюжетная кампания Amber World. Состояние хранится в Worlds и переживает загрузку слота.
## Сюжетные главы открываются событиями уже существующих систем; побочные поручения не заменяются.

const CHAPTERS: Array = [
	{"id":"ashwick_signal", "title":"Глава I. Сигнал из Эшвика", "text":"На старом тракте ловится короткий повторяющийся сигнал. Староста Эшвика знает о нём больше, чем говорит. Доберитесь до поселения.", "event":"visit_ashwick", "need":1, "reward":8},
	{"id":"town_trust", "title":"Глава II. Доверие за стеной", "text":"В Эшвике не верят чужакам. Помогите жителям с одним настоящим делом, прежде чем спрашивать о сигнале.", "event":"town_quest", "need":1, "reward":12},
	{"id":"amber_trace", "title":"Глава III. Янтарный след", "text":"В старой записке упоминается янтарный резонатор. Найдите и прочтите хотя бы одну запись прошлого мира.", "event":"codex", "need":1, "reward":15},
	{"id":"road_threat", "title":"Глава IV. Дорога помнит кровь", "text":"Сигнал привлекает не только людей. Переживите три сражения: путь к источнику не будет безопасным.", "event":"battle_win", "need":3, "reward":20},
	{"id":"resonance", "title":"Глава V. Где гаснет эхо", "text":"След ведёт за пределы обжитых земель. Пройдите десять километров и помогите жителям ещё дважды. Тогда станет ясно, откуда идёт зов.", "event":"final_mix", "need":1, "reward":35}
]

static func new_state() -> Dictionary:
	return {"chapter":0, "events":{}, "completed":[], "finished":false}

static func record(state: Dictionary, event_id: String, amount: int = 1) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	var events: Dictionary = out.get("events", {}).duplicate()
	events[event_id] = int(events.get(event_id, 0)) + amount
	out["events"] = events
	return out

static func current(state: Dictionary) -> Dictionary:
	var i: int = int(state.get("chapter", 0))
	return CHAPTERS[i].duplicate(true) if i >= 0 and i < CHAPTERS.size() else {}

static func progress(state: Dictionary, km: float) -> Array:
	var q: Dictionary = current(state)
	if q.is_empty():
		return [0, 1]
	var events: Dictionary = state.get("events", {})
	var value: int = 0
	match String(q["event"]):
		"final_mix":
			value = 1 if float(km) >= 10.0 and int(events.get("town_quest", 0)) >= 3 else 0
		"visit_ashwick": value = int(events.get("visit_ashwick", 0))
		_: value = int(events.get(String(q["event"]), 0))
	return [mini(value, int(q["need"])), int(q["need"])]

static func ready(state: Dictionary, km: float) -> bool:
	var p: Array = progress(state, km)
	return p[0] >= p[1] and not current(state).is_empty()

## Возвращает {state, rewards}; вызывается после события и при открытии вкладки заданий.
static func advance(state: Dictionary, km: float) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	var rewards: int = 0
	var safety: int = 0
	while ready(out, km) and safety < CHAPTERS.size():
		var q: Dictionary = current(out)
		out["completed"].append(String(q["id"]))
		out["chapter"] = int(out.get("chapter", 0)) + 1
		rewards += int(q.get("reward", 0))
		safety += 1
	if int(out.get("chapter", 0)) >= CHAPTERS.size():
		out["finished"] = true
	return {"state":out, "rewards":rewards}
