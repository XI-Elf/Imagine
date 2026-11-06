extends RefCounted
## Топографічна модель огляду регіону (world/region_view.gd; Huzzah 2026-11-06: «карта регіону — в топографічному стилі,
## дані з Місцевості переносити на неї вже в топографічній моделі»).
## Тут дві речі:
##  1) SHADER — основа листа — затверджена топокарта світу (map_topo_clean.png), поверх неї дані гри: висоти (map_height.png) -> гіпсометричне забарвлення, світлотінь, горизонталі з потовщеними
##     основними; вода (map_water.png) -> берегова лінія, мілина, ріки не тонші за 2 px; біоми (map_biomes.png) ->
##     умовні знаки (листяне/хвойне дерево, купини болота, крапки пустки), штрих проклятих земель, червоний штрих
##     спекотних гір; межа регіону штрих-пунктиром, кілометрова сітка; туман війни — «біла пляма»: невідоме не
##     малюється зовсім (ні горизонталей, ні знаків), а не закривається хмарами поверх готової картинки.
##  2) Чисті функції без стану: крок горизонталей, масштабна лінійка, висотні відмітки (локальні максимуми) і місця
##     підписів основних горизонталей — рахуються по тих самих шарах, що й гра (game.height_at / water_at), без шейдера.
## Палітра — як у затвердженої Huzzah топокарти світу (art/map/map_topo.png, 2026-10-29): кремовий берег, зелена низина,
## охристо-коричневе нагір'я, бордові берегові лінії й дороги, фіолетовий штрих проклятих земель, синьо-сіра вода.

const HEIGHT_MAX_M: float = 900.0
## Горизонталі: крок у метрах і кожна N-та основна (з підписом). Далі від карти — рідше, ближче — частіше.
const STEPS: Array = [[40.0, 5], [20.0, 5], [10.0, 5]]
const CELL_PX: float = 24.0         # клітинка знаків біому на екрані 1080 px при огляді всього регіону

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D water_tex : filter_linear, repeat_disable;
uniform sampler2D biome_tex : filter_nearest, repeat_disable;
uniform sampler2D hot_tex : filter_linear, repeat_disable;
uniform sampler2D province_tex : filter_nearest, repeat_disable;
uniform sampler2D topo_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(41625.0, 36000.0);
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_px = vec2(1280.0, 720.0);
uniform float zoom = 0.1;
uniform float region_id = 0.0;
uniform float height_max = 900.0;
uniform float contour_m = 40.0;
uniform float index_every = 5.0;
uniform float sym_m = 200.0;
uniform float fog_on = 0.0;
uniform float grid_m = 1000.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
	return vec2(hash12(p), hash12(p + vec2(41.7, 13.3)));
}
// значення-шум: один піксель текстури шуму = wl метрів
float vn(vec2 P, float wl) {
	return textureLod(noise_tex, P / (wl * 256.0), 0.0).r;
}
vec2 uvp(vec2 P) {
	return clamp(P / map_size, vec2(0.0), vec2(1.0));
}
float biome_at(vec2 P) {
	return floor(textureLod(biome_tex, uvp(P), 0.0).r * 255.0 + 0.5);
}
float water_at(vec2 P) {
	return textureLod(water_tex, uvp(P), 0.0).r;
}
float prov_at(vec2 P) {
	vec2 Q = P / map_size;
	if (Q.x < 0.0 || Q.y < 0.0 || Q.x > 1.0 || Q.y > 1.0) { return 0.0; }
	return floor(textureLod(province_tex, Q, 0.0).r * 255.0 + 0.5);
}
float h_raw(vec2 P) {
	return textureLod(height_tex, uvp(P), 0.0).r;
}
// висота в метрах: 9 вибірок з радіусом ~1,3 клітинки шару, щоб 8-бітні сходинки не ламали горизонталі й світлотінь
float hm(vec2 P) {
	float e = map_size.x / float(textureSize(height_tex, 0).x) * 1.3;
	float d = e * 0.7071;
	float s = h_raw(P) * 3.0 + h_raw(P + vec2(e, 0.0)) + h_raw(P - vec2(e, 0.0)) + h_raw(P + vec2(0.0, e)) + h_raw(P - vec2(0.0, e))
		+ (h_raw(P + vec2(d, d)) + h_raw(P + vec2(-d, d)) + h_raw(P + vec2(d, -d)) + h_raw(P + vec2(-d, -d))) * 0.7;
	return s / 9.8 * height_max;
}
vec3 land_col(float b) {
	int bi = int(b + 0.5);
	if (bi == 2) { return vec3(0.80, 0.74, 0.55); }
	if (bi == 3) { return vec3(0.55, 0.64, 0.36); }
	if (bi == 4) { return vec3(0.76, 0.69, 0.47); }
	if (bi == 5) { return vec3(0.46, 0.58, 0.42); }
	if (bi == 6) { return vec3(0.74, 0.62, 0.50); }
	if (bi == 7) { return vec3(0.49, 0.53, 0.47); }
	if (bi == 8) { return vec3(0.65, 0.58, 0.54); }
	if (bi == 9) { return vec3(0.42, 0.48, 0.52); }
	return vec3(0.56, 0.64, 0.38);
}
// діагональний штрих: spacing — відстань між лініями (метри), w_px — товщина лінії на екрані
float hatch(vec2 P, float spacing, float dir, float w_px) {
	float t = (P.x + dir * P.y) / (spacing * 1.4142);
	float dpx = (0.5 - abs(fract(t) - 0.5)) * spacing * zoom;
	return 1.0 - smoothstep(w_px * 0.5 - 0.35, w_px * 0.5 + 0.35, dpx);
}

float rid_at(vec2 P) {
	return step(abs(prov_at(P) - region_id), 0.5);
}
// Чи точка належить регіону: межа згладжена (шар областей — 17-метрові сходинки); вода всередині регіону (озера, ріки, прибережна смуга
// до ~360 м) — своя, хоча шар областей на воді порожній; велике озеро — коли з більшості боків навкруги регіон
float in_region(vec2 P) {
	float e = map_size.x / float(textureSize(province_tex, 0).x) * 0.8;
	float a = rid_at(P) * 0.4 + (rid_at(P + vec2(e, 0.0)) + rid_at(P - vec2(e, 0.0)) + rid_at(P + vec2(0.0, e)) + rid_at(P - vec2(0.0, e))) * 0.15;
	float r = smoothstep(0.3, 0.7, a);
	if (r < 0.5 && water_at(P) > 0.5) {
		float n_in = 0.0;
		float near = 0.0;
		for (int i = 0; i < 8; i++) {
			float an = float(i) * 0.7853982;
			vec2 dir = vec2(cos(an), sin(an));
			n_in += rid_at(P + dir * 1500.0);
			near = max(near, max(rid_at(P + dir * 70.0), max(rid_at(P + dir * 180.0), rid_at(P + dir * 360.0))));
		}
		r = max(step(5.5, n_in), near);
	}
	return r;
}

void fragment() {
	vec2 P = cam_pos + (UV - vec2(0.5)) * view_px / zoom;
	float px = 1.0 / zoom;
	// «від руки»: ледь хвиляста лінія (амплітуда ~пів-піксельна, не зсуває дані більше ніж на кілька метрів)
	vec2 Pw = P + (vec2(vn(P, 260.0), vn(P + vec2(7919.0, 3571.0), 260.0)) - vec2(0.5)) * (4.0 + px * 1.6);
	float b0 = biome_at(Pw);
	float rid = region_id;
	float ins = in_region(P);

	// --- основа: затверджена топокарта світу (art/map/map_topo_clean.png: гіпсометрія, світлотінь, береги, ріки, дороги, штрих
	// проклятих земель і жарких гір), дані гри лише уточнюють її: чіткі горизонталі, берегова лінія, знаки, біла пляма
	vec3 col = texture(topo_tex, uvp(P)).rgb;
	float hh = hm(Pw);

	// --- вода: маска малюнка; берегова мілина, ріки не тонші за ~2 px
	float wv = water_at(Pw);
	float wa = max(fwidth(wv), 0.004);
	float wet = smoothstep(0.5 - wa, 0.5 + wa, wv);
	float rv = max(max(water_at(Pw + vec2(px * 1.3, 0.0)), water_at(Pw - vec2(px * 1.3, 0.0))), max(water_at(Pw + vec2(0.0, px * 1.3)), water_at(Pw - vec2(0.0, px * 1.3))));

	// --- умовні знаки біомів: клітинки по сітці sym_m, поза водою й у межах біому
	vec2 g = P / sym_m;
	vec2 id = floor(g);
	vec2 d = fract(g) - (hash22(id) * 0.44 + vec2(0.28));
	float bc = biome_at((id + vec2(0.5)) * sym_m);
	float dry_c = 1.0 - step(0.5, water_at((id + vec2(0.5)) * sym_m));
	float roll = hash12(id + vec2(11.0, 5.0));
	float roll2 = hash12(id + vec2(3.0, 71.0));
	float aa = 1.2 / (sym_m * zoom);
	vec3 ink = vec3(0.0);
	float ink_a = 0.0;
	int bi = int(bc + 0.5);
	if (dry_c > 0.5) {
		if (bi == 3 || bi == 7) {
			float dens = 0.8 - 0.35 * vn((id + vec2(0.5)) * sym_m, 1500.0);
			if (roll < dens) {
				vec3 fill_c = bi == 7 ? vec3(0.50, 0.46, 0.58) : vec3(0.36, 0.52, 0.28);
				vec3 line_c = bi == 7 ? vec3(0.27, 0.20, 0.36) : vec3(0.16, 0.30, 0.14);
				float s;
				d *= 1.0 + (roll2 - 0.5) * 0.5;
				if (roll2 < 0.42) {
					// хвойне: трикутник
					s = max(abs(d.x) - (d.y + 0.24) * 0.46, max(-0.24 - d.y, d.y - 0.16));
				} else {
					// листяне: кружальце
					s = length(d - vec2(0.0, -0.04)) - 0.19;
				}
				float in_a = 1.0 - smoothstep(-aa, aa, s);
				float out_a = (1.0 - smoothstep(0.0, aa * 1.4, abs(s))) ;
				ink = mix(fill_c, line_c, out_a);
				ink_a = max(in_a * 0.85, out_a) * 0.95;
			}
		} else if (bi == 5 || bi == 9) {
			// купина болота: три рисочки й стебла
			vec3 lc = bi == 9 ? vec3(0.28, 0.30, 0.45) : vec3(0.20, 0.38, 0.40);
			float a = 0.0;
			for (int k = -1; k <= 1; k++) {
				float yy = float(k) * 0.1;
				a = max(a, (1.0 - smoothstep(aa * 0.4, aa * 1.5, abs(d.y - yy))) * (1.0 - smoothstep(0.2 - abs(float(k)) * 0.07, 0.24 - abs(float(k)) * 0.07, abs(d.x))));
			}
			for (int k = -1; k <= 1; k++) {
				float xx = float(k) * 0.12;
				a = max(a, (1.0 - smoothstep(aa * 0.4, aa * 1.5, abs(d.x - xx))) * step(-0.2, d.y) * step(d.y, -0.1));
			}
			if (roll < 0.62) { ink = lc; ink_a = a * 0.85; }
		} else if (bi == 4 || bi == 8 || bi == 2) {
			// крапки пустки / піску
			float a = 1.0 - smoothstep(0.02, 0.02 + aa * 1.6, length(d));
			a = max(a, 1.0 - smoothstep(0.02, 0.02 + aa * 1.6, length(d - vec2(0.17, 0.12) * (roll2 - 0.5) * 2.0)));
			if (roll < 0.5) { ink = bi == 8 ? vec3(0.40, 0.28, 0.46) : vec3(0.50, 0.38, 0.20); ink_a = a * 0.75; }
		}
	}
	col = mix(col, ink, ink_a * (1.0 - wet));

	// --- горизонталі (лише на суші; рівнина = нуль, ліній нема)
	float lv = hh / contour_m;
	float fr = abs(fract(lv + 0.5) - 0.5);
	float w_l = max(fwidth(lv), 0.00002);
	float line_m = 1.0 - smoothstep(0.0, w_l * 0.95, fr);
	float lvi = hh / (contour_m * index_every);
	float fri = abs(fract(lvi + 0.5) - 0.5);
	float w_i = max(fwidth(lvi), 0.00002);
	float line_i = 1.0 - smoothstep(0.0, w_i * 1.7, fri);
	float spacing_px = 1.0 / w_l;
	float dens_k = smoothstep(2.2, 5.5, spacing_px);
	float dens_i = smoothstep(2.2, 5.5, spacing_px * index_every);
	float up = smoothstep(contour_m * 0.6, contour_m * 1.1, hh) * (1.0 - wet);
	col = mix(col, vec3(0.48, 0.30, 0.17), line_m * dens_k * up * 0.62);
	col = mix(col, vec3(0.34, 0.19, 0.10), line_i * dens_i * up * 0.85);

	// --- вода зверху: тло, берегова лінія (бордова, як на топокарті світу), ріки
	// жирної берегової лінії немає: товсті лінії лишено лише для меж регіонів

	// --- кілометрова сітка
	float gx = abs(fract(P.x / grid_m + 0.5) - 0.5) * grid_m * zoom;
	float gy = abs(fract(P.y / grid_m + 0.5) - 0.5) * grid_m * zoom;
	float gl = max(1.0 - smoothstep(0.35, 1.0, gx), 1.0 - smoothstep(0.35, 1.0, gy));
	float g5x = abs(fract(P.x / (grid_m * 5.0) + 0.5) - 0.5) * grid_m * 5.0 * zoom;
	float g5y = abs(fract(P.y / (grid_m * 5.0) + 0.5) - 0.5) * grid_m * 5.0 * zoom;
	float g5 = max(1.0 - smoothstep(0.5, 1.4, g5x), 1.0 - smoothstep(0.5, 1.4, g5y));
	col = mix(col, vec3(0.26, 0.38, 0.52), gl * 0.20 + g5 * 0.14);

	// --- туман війни: «біла пляма» — невідоме не малюється; рваний край
	float qx = 110.0 / map_size.x;
	float qy = 110.0 / map_size.y;
	vec2 Q = P / map_size;
	float known = texture(fog_mask, Q).r * 0.4 + (texture(fog_mask, Q + vec2(qx, 0.0)).r + texture(fog_mask, Q - vec2(qx, 0.0)).r
		+ texture(fog_mask, Q + vec2(0.0, qy)).r + texture(fog_mask, Q - vec2(0.0, qy)).r) * 0.15;
	float unk = (1.0 - smoothstep(0.38, 0.62, known + (vn(P, 220.0) - 0.5) * 0.35)) * fog_on * ins;
	vec3 blank = vec3(0.76, 0.71, 0.58) * (0.94 + 0.08 * vn(P, 40.0));
	float hb2 = max(hatch(P, 150.0, 1.0, 0.8), hatch(P, 150.0, -1.0, 0.8));
	blank = mix(blank, vec3(0.50, 0.42, 0.30), hb2 * 0.28);
	col = mix(col, blank, unk);

	// --- за межею регіону: сусіди приглушені, межа регіону штрих-пунктиром
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, mix(vec3(lum), col, 0.35) * 0.5, (1.0 - ins) * 0.85);
	float eo = px * 2.6;
	// межа лише там, де по той бік інша область; порожній шар (вода, озерця) межі не дає
	float p0 = prov_at(P);
	float a_in = step(abs(p0 - rid), 0.5);
	vec2 offs[4] = vec2[4](vec2(eo, 0.0), vec2(-eo, 0.0), vec2(0.0, eo), vec2(0.0, -eo));
	float edge = 0.0;
	for (int i = 0; i < 4; i++) {
		float pn = prov_at(P + offs[i]);
		float n_in = step(abs(pn - rid), 0.5);
		float n_other = step(0.5, pn) * (1.0 - n_in);
		float c_other = step(0.5, p0) * (1.0 - a_in);
		edge = max(edge, max(a_in * n_other, c_other * n_in));
	}
	float dash = step(0.22, fract((P.x + P.y) / (px * 30.0))) * step(0.12, fract((P.x - P.y) / (px * 400.0)));
	edge *= 1.0 - smoothstep(0.3, 0.6, max(wv, rv));   // по воді межі не малюємо: шар областей на воді порожній
	col = mix(col, vec3(0.40, 0.07, 0.09), edge * dash);

	// --- папір: легке зерно
	col *= 0.95 + 0.1 * vn(P, max(5.0, px * 1.2));
	COLOR = vec4(col, 1.0);
}
"""


## Крок горизонталей [метри, кожна N-та основна] за наближенням огляду (1 — увесь регіон)
static func contour_steps(uz: float) -> Array:
	if uz >= 3.2:
		return STEPS[2]
	if uz >= 1.7:
		return STEPS[1]
	return STEPS[0]


## Масштабна лінійка: «кругла» довжина в метрах, що займає близько target_px пікселів, і її довжина в пікселях
static func scale_bar(px_per_m: float, target_px: float) -> Array:
	var raw: float = target_px / maxf(px_per_m, 0.00001)
	var mag: float = pow(10.0, floorf(log(raw) / log(10.0)))
	var best: float = mag
	for k in [1.0, 2.0, 5.0, 10.0]:
		if k * mag <= raw * 1.15:
			best = k * mag
	return [best, best * px_per_m]


## Підпис довжини: метри до 1 км, далі кілометри
static func length_text(m: float, km: String, mt: String) -> String:
	if m >= 1000.0:
		return "%s %s" % [str(snappedf(m / 1000.0, 0.1)).trim_suffix(".0"), km]
	return "%d %s" % [int(m), mt]


## Сітка висот регіону (метри) з кроком step_m: Dictionary {origin, step, nx, ny, h: PackedFloat32Array, ok: PackedByteArray}
## (ok — клітинка суходолу всередині регіону)
static func height_grid(game: Node, bbox: Rect2, region_id: int, step_m: float) -> Dictionary:
	var nx: int = maxi(2, ceili(bbox.size.x / step_m) + 1)
	var ny: int = maxi(2, ceili(bbox.size.y / step_m) + 1)
	var h := PackedFloat32Array()
	h.resize(nx * ny)
	var ok := PackedByteArray()
	ok.resize(nx * ny)
	for y in ny:
		for x in nx:
			var p := bbox.position + Vector2(x, y) * step_m
			var i: int = y * nx + x
			h[i] = game.height_at(p)
			ok[i] = 1 if game.province_at(p) == region_id and game.water_at(p) < 0.5 else 0
	return {"origin": bbox.position, "step": step_m, "nx": nx, "ny": ny, "h": h, "ok": ok}


## Висотні відмітки: локальні максимуми суходолу (не нижче min_h), розріджені так, щоб поряд не стояли дві
static func spot_heights(grid: Dictionary, min_h: float, gap_m: float, limit: int) -> Array:
	var nx: int = grid["nx"]
	var ny: int = grid["ny"]
	var h: PackedFloat32Array = grid["h"]
	var ok: PackedByteArray = grid["ok"]
	var cand: Array = []
	for y in range(1, ny - 1):
		for x in range(1, nx - 1):
			var i: int = y * nx + x
			if ok[i] == 0 or h[i] < min_h:
				continue
			var peak: bool = true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var j: int = i + dy * nx + dx
					# строго більша сусідка — не вершина; рівні — перша в порядку обходу виграє
					if h[j] > h[i] or (h[j] == h[i] and j < i):
						peak = false
			if peak:
				cand.append([h[i], Vector2(grid["origin"]) + Vector2(x, y) * float(grid["step"])])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for c in cand:
		var far: bool = true
		for o in out:
			if (o["pos"] as Vector2).distance_to(c[1]) < gap_m:
				far = false
				break
		if far:
			out.append({"pos": c[1], "h": c[0]})
			if out.size() >= limit:
				break
	return out


## Місця підписів основних горизонталей: точки, де сітка перетинає рівень кратний index_m; кут — вздовж лінії
## (читабельно: у межах -90..90°). Розріджено на gap_m, без підписів у кількох метрах від вершини.
static func contour_labels(grid: Dictionary, index_m: float, gap_m: float, limit: int) -> Array:
	var nx: int = grid["nx"]
	var ny: int = grid["ny"]
	var h: PackedFloat32Array = grid["h"]
	var ok: PackedByteArray = grid["ok"]
	var step: float = grid["step"]
	var cand: Array = []
	for y in range(1, ny - 1):
		for x in range(1, nx - 1):
			var i: int = y * nx + x
			var j: int = i + 1
			if ok[i] == 0 or ok[j] == 0:
				continue
			var a: float = h[i]
			var b: float = h[j]
			var la: int = floori(a / index_m)
			var lb: int = floori(b / index_m)
			if la == lb or maxf(a, b) < index_m * 0.9:
				continue
			var lvl: int = maxi(la, lb)
			var t: float = clampf((float(lvl) * index_m - a) / (b - a), 0.0, 1.0)
			var gx: float = (h[i + 1] - h[i - 1]) / (2.0 * step)
			var gy: float = (h[i + nx] - h[i - nx]) / (2.0 * step)
			if absf(gx) + absf(gy) < 0.03:
				continue   # майже плато: напрямок лінії невизначений
			var ang: float = atan2(gx, -gy)
			while ang > PI * 0.5:
				ang -= PI
			while ang < -PI * 0.5:
				ang += PI
			var pos := Vector2(grid["origin"]) + Vector2(float(x) + t, float(y)) * step
			cand.append([hash(Vector2i(x, y)) & 0xffff, pos, ang, lvl * int(index_m)])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for c in cand:
		var far: bool = true
		for o in out:
			if (o["pos"] as Vector2).distance_to(c[1]) < gap_m:
				far = false
				break
		if far:
			out.append({"pos": c[1], "angle": c[2], "h": c[3]})
			if out.size() >= limit:
				break
	return out
