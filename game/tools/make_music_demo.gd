extends SceneTree
## Демо-запис генеративної музики без гри: кілька настроїв по три кола петлі (вступ → усі голоси).
## Зал і компресор шини Music тут не діють — їх додає ffmpeg (див. amber2d/music/ИТОГ.md).
## godot --headless --path game -s res://tools/make_music_demo.gd -- <тека для wav>

const MOODS: Array = [["theme", {}], ["city_day", {"biome": 3}], ["wild_night", {"biome": 3, "night": true}],
	["cursed", {"biome": 8, "curse": 0.5}], ["battle", {}]]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var Music: Node = root.get_node("Music")   # автозавантаження: скрипту потрібен Worlds
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var rng := RandomNumberGenerator.new()
	rng.seed = 2910
	for mc in MOODS:
		var plan: Dictionary = Music.plan_for(mc[0], mc[1], rng)
		var t0: int = Time.get_ticks_msec()
		var r: Dictionary = Music.render(plan)
		var streams: Array = r["streams"]
		var frames: int = streams[0]["stream"].loop_end
		var mix := PackedFloat32Array()
		mix.resize(frames * 2 * 3)
		var lead: bool = false
		for e in streams:
			var cat: String = e["cat"]
			var from_loop: int = 0 if cat == "h" or (cat in ["m", "x"] and not lead) else 1
			if cat in ["m", "x"]:
				lead = true
			var d: PackedByteArray = e["stream"].data
			for lp in range(from_loop, 3):
				for i in frames:
					var o: int = (lp * frames + i) * 2
					mix[o] += d.decode_s16(i * 4) / 32768.0
					mix[o + 1] += d.decode_s16(i * 4 + 2) / 32768.0
		var bytes := PackedByteArray()
		bytes.resize(mix.size() * 2)
		for i in mix.size():
			bytes.encode_s16(i * 2, int(clampf(mix[i] * 0.7, -1.0, 1.0) * 32767.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.stereo = true
		w.mix_rate = Music.RATE
		w.data = bytes
		var names: Array = []
		for id in plan["ids"] + plan["bonus"]:
			names.append(id)
		w.save_to_wav(out.path_join("%s.wav" % mc[0]))
		print("%s %s %s bpm %d: %s (%d мс)" % [mc[0], plan["mode"], plan["key"], plan["bpm"], ", ".join(names), Time.get_ticks_msec() - t0])
	quit()
