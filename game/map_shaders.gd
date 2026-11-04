class_name MapShaders
extends RefCounted
## Шейдер плоской 2D-карты: нарисованная карта мира (art/map/map_color.png) издали,
## текстуры биомов (art/map/map_biomes.png) вблизи, облака и дождь из модели атмосферы, день и ночь.
## Вода вблизи — по маске рисунка art/map/map_water.png (та же, что у подсказки под курсором в game.gd).
## Жаркие горы (+40 °C) — маска art/map/map_hot.png: охристый камень, без снега.
## Текстуры биомов вблизи — массив terrain_tex из art/terrain/*.png (исходные кадры,
## tools/make_terrain_textures.py). Текстуры неподвижны (просьба Huzzah: не «плывут»): грибы и налёт
## проклятых биомов светятся ровно, в дождь земля темнеет. Двигаются только облака.
## Мир плоский: один местный час и одна широта (MAP_LAT) на всю карту.
## Облака берутся из окна модели атмосферы (ATM_*), те же числа в game.gd (atm_of). Менять вместе.

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D rand_tex : filter_nearest, repeat_enable;
uniform sampler2D map_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D biome_tex : filter_nearest, repeat_disable;
// Вода по рисунку (море, озёра, реки): сглаженная маска 8,8 м, 0,5 — линия берега
uniform sampler2D water_tex : filter_linear, repeat_disable;
// Жаркие горы: сглаженная маска, 0,5 — край зоны (как hot в game.gd)
uniform sampler2D hot_tex : filter_linear, repeat_disable;
// Высоты (art/map/map_height.png, tools/make_height.py): 0..1 -> 0..height_max метров для светотени (с превышением)
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float height_max = 2000.0;
// Текстуры биомов (слои TEX_*), последний слой — маски свечения R лес, G пустошь, B болото
uniform sampler2DArray terrain_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_textures = false;
// Номера областей (1..31) и регионов (1..117), 0 — море и за краем
uniform sampler2D province_tex : filter_nearest, repeat_disable;
uniform sampler2D region_tex : filter_nearest, repeat_disable;
// Границы (клавиша B): 0 нет, 1 области, 2 области и регионы
uniform int border_mode = 0;
uniform vec2 cam_pos = vec2(20812.5, 18000.0);
uniform vec2 view_px = vec2(0.0);
uniform float zoom = 0.03;
uniform vec2 map_size = vec2(41625.0, 36000.0);
uniform float anim = 0.0;
uniform float show_clouds = 1.0;
// Небо и время (WorldPhysics.apply_to)
uniform float decl = 0.0;
uniform float utc_h = 6.0;
uniform float moon_decl = 0.0;
uniform float moon_phase = 0.0;
uniform float night_light = 0.10;
uniform float doy = 105.0;
uniform float seas = 0.0;
uniform float seas_m = 0.0;
uniform float summer = 0.5;
// atm_a: R хмарність, G опади (1 це 8 мм/год), B хмарна вода, A вологість; atm_b: R, G вітер (-25..25 м/с)
uniform sampler2D atm_a : filter_linear, repeat_enable;
uniform sampler2D atm_b : filter_linear, repeat_enable;
uniform float flow_phase = 0.0;
uniform float drift_scale = 0.02;

const float PI_C = 3.14159265;
const float TAU_C = 6.2831853;
const vec2 BOARD_C = vec2(20812.5, 18000.0);
const float BOARD_APO = 18000.0;
const vec2 SRC_SIZE = vec2(36000.0, 18000.0);
// Широта плоского мира (для солнца и луны) и окно модели атмосферы в прежней развёртке S
const float MAP_LAT = 0.7854;
const vec2 ATM_ORIGIN = vec2(13900.0, 2000.0);
const vec2 ATM_SPAN = vec2(8200.0, 5000.0);
// Слои terrain_tex и сколько метров земли занимает один повтор текстуры
const int TEX_WATER = 0;
const int TEX_COAST = 1;
const int TEX_FOREST = 2;
const int TEX_FIELD1 = 3;
const int TEX_FIELD2 = 4;
const int TEX_WASTE = 5;
const int TEX_SWAMP = 6;
const int TEX_MOUNT = 7;
const int TEX_HOT = 8;
const int TEX_RAD_FOREST = 9;
const int TEX_RAD_WASTE = 10;
const int TEX_RAD_SWAMP = 11;
const int TEX_GLOW = 12;
// Huzzah 2026-10-23: при самом сильном приближении (MAX_ZOOM 40 px/м в game.gd) пиксель картинки
// 512 px = пиксель экрана, при отдалении текстура только сжимается (мипмапы). 512 / 40 = 12,8 м
const float TILE_M[12] = {12.8, 12.8, 12.8, 12.8, 12.8, 12.8, 12.8, 12.8, 12.8, 12.8, 12.8, 12.8};

float board_hex_norm(vec2 v) {
	return max(abs(v.y), max(abs(0.8660254 * v.x + 0.5 * v.y), abs(-0.8660254 * v.x + 0.5 * v.y)));
}

// Гладкий тривимірний шум (як у terrain_shaders.gd): G текстури це R зі зсувом (37, 17)
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float zc = mod(i.z, 256.0);
	vec2 b = mod(i.xy + vec2(37.0, 17.0) * zc, 256.0);
	vec2 b1 = mod(b + vec2(1.0), 256.0);
	ivec2 p00 = ivec2(int(b.x), int(b.y));
	ivec2 p11 = ivec2(int(b1.x), int(b1.y));
	vec2 t00 = texelFetch(noise_tex, p00, 0).rg;
	vec2 t10 = texelFetch(noise_tex, ivec2(p11.x, p00.y), 0).rg;
	vec2 t01 = texelFetch(noise_tex, ivec2(p00.x, p11.y), 0).rg;
	vec2 t11 = texelFetch(noise_tex, p11, 0).rg;
	vec2 rg = mix(mix(t00, t10, f.x), mix(t01, t11, f.x), f.y);
	return mix(rg.x, rg.y, f.z);
}

float noise2(vec2 p) {
	return vnoise3(vec3(p, 17.0));
}

// Шум в нескольких масштабах; wl — длина волны первого слоя в метрах. Слои мельче пикселя отбрасываются
float fbm(vec2 p, float wl) {
	float px_m = 1.0 / zoom;
	float s = 0.0;
	float a = 0.5;
	float n = 0.0;
	float w = wl;
	for (int i = 0; i < 5; i++) {
		float k = smoothstep(px_m * 1.0, px_m * 3.0, w);
		s += a * k * noise2(p / w + vec2(float(i) * 7.3, float(i) * 3.1));
		n += a * k;
		w *= 0.5;
		a *= 0.5;
	}
	return n > 0.0 ? s / n : 0.5;
}

// Направление на светило в местных осях: x восток, y юг, z вверх
vec3 dir_enu(float lat, float d, float ha) {
	float e = -cos(d) * sin(ha);
	float n = sin(d) * cos(lat) - cos(d) * sin(lat) * cos(ha);
	float u = sin(lat) * sin(d) + cos(lat) * cos(d) * cos(ha);
	return vec3(e, -n, u);
}

// Свет плоского мира: одно солнце и одна луна для всей карты
vec3 world_light(out vec3 sun_dir) {
	float ha = (utc_h - 12.0) * 0.2617994;
	sun_dir = dir_enu(MAP_LAT, decl, ha);
	float sin_el = sun_dir.z;
	float sun_vis = smoothstep(-0.03, 0.12, sin_el);
	float warm = 1.0 - smoothstep(0.0, 0.35, sin_el);
	vec3 sun_col = mix(vec3(1.0, 0.97, 0.90), vec3(1.0, 0.62, 0.36), warm) * sun_vis;
	float day_amt = smoothstep(-0.18, 0.12, sin_el);
	float amb_i = mix(night_light, 0.30, day_amt);
	vec3 amb = mix(vec3(0.45, 0.55, 0.95), vec3(0.80, 0.88, 1.0), day_amt) * amb_i;
	float illum = 0.5 - 0.5 * cos(TAU_C * moon_phase);
	vec3 moon_dir = dir_enu(MAP_LAT, moon_decl, ha - TAU_C * moon_phase);
	float moon_k = illum * smoothstep(-0.05, 0.15, moon_dir.z) * (1.0 - day_amt);
	amb += vec3(0.40, 0.48, 0.70) * moon_k * 0.07;
	vec3 shade = amb + sun_col * max(sun_dir.z, 0.0) + vec3(0.62, 0.70, 0.95) * moon_k * 0.26 * max(moon_dir.z, 0.0);
	return clamp(shade / 0.75, vec3(0.10, 0.11, 0.16), vec3(1.0));
}

// Мелкие детали облаков, которые плывут с ветром модели (две фазы без разрывов)
float cnoise(vec2 p) {
	vec3 q = vec3(p - BOARD_C, 1733.0) / 3000.0;
	float s = 0.0;
	float a = 0.5;
	float n = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise3(q);
		n += a;
		q = q * 2.0 + vec3(3.17, 8.41, 1.93);
		a *= 0.5;
	}
	return s / n;
}

float cloud_detail(vec2 p, vec2 vdrift) {
	float flow_t = 7200.0;
	float ph1 = flow_phase;
	float ph2 = fract(flow_phase + 0.5);
	float w1 = 1.0 - abs(2.0 * ph1 - 1.0);
	float w2 = 1.0 - w1;
	float m = w1 * cnoise(p - vdrift * ph1 * flow_t) + w2 * cnoise(p - vdrift * ph2 * flow_t);
	return 0.5 + (m - 0.5) / sqrt(w1 * w1 + w2 * w2);
}

// Плавное чтение модели атмосферы: четыре текселя с гладкими весами (без ступенек сетки 144 x 72)
vec4 atm_smooth(sampler2D t, vec2 uv) {
	vec2 n = vec2(textureSize(t, 0));
	vec2 q = uv * n - 0.5;
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	ivec2 a = ivec2(int(mod(i.x, n.x)), int(clamp(i.y, 0.0, n.y - 1.0)));
	ivec2 b = ivec2(int(mod(i.x + 1.0, n.x)), int(clamp(i.y + 1.0, 0.0, n.y - 1.0)));
	vec4 v00 = texelFetch(t, a, 0);
	vec4 v10 = texelFetch(t, ivec2(b.x, a.y), 0);
	vec4 v01 = texelFetch(t, ivec2(a.x, b.y), 0);
	vec4 v11 = texelFetch(t, b, 0);
	return mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);
}

// Биом суши в точке: 0 за краем, 2 берег, 3 лес, 4 пустошь, 5 болото, 6 горы,
// 7 проклятый лес, 8 проклятая пустошь, 9 проклятое болото
float biome_at(vec2 p) {
	vec2 uv = clamp(p / map_size, vec2(0.0), vec2(1.0));
	return floor(textureLod(biome_tex, uv, 0.0).r * 255.0 + 0.5);
}

// Вода в точке: 0..1, от 0,5 — вода (как water_at в game.gd)
float water_at(vec2 p) {
	return textureLod(water_tex, clamp(p / map_size, vec2(0.0), vec2(1.0)), 0.0).r;
}

float id_at(sampler2D t, vec2 p) {
	vec2 uv = clamp(p / map_size, vec2(0.0), vec2(1.0));
	return floor(textureLod(t, uv, 0.0).r * 255.0 + 0.5);
}

// Цвет области по её номеру: насыщенный, различимый у соседей
vec3 province_color(float id) {
	vec3 h = fract(vec3(0.0, 0.33, 0.67) + id * 0.618034);
	return clamp(abs(h * 6.0 - 3.0) - 1.0, 0.0, 1.0) * 0.75 + 0.25;
}

// Границы областей (сплошные цветные) и регионов (светлый пунктир) поверх карты
vec3 borders(vec2 p, vec3 col) {
	float px = 1.0 / zoom;
	float w = max(px * 1.2, 8.0);
	float pr = id_at(province_tex, p);
	float prx = id_at(province_tex, p + vec2(w, 0.0));
	float pry = id_at(province_tex, p + vec2(0.0, w));
	bool pe = (pr != prx && prx > 0.5 && pr > 0.5) || (pr != pry && pry > 0.5 && pr > 0.5);
	if (pe) {
		return mix(col, province_color(max(pr, max(prx, pry))), 0.9);
	}
	if (border_mode >= 2 && pr > 0.5) {
		float rg = id_at(region_tex, p);
		float rgx = id_at(region_tex, p + vec2(w, 0.0));
		float rgy = id_at(region_tex, p + vec2(0.0, w));
		if ((rg != rgx && rgx > 0.5) || (rg != rgy && rgy > 0.5)) {
			float dash = step(0.45, fract((p.x + p.y) / (px * 14.0)));
			return mix(col, vec3(0.97, 0.94, 0.82), 0.8 * dash);
		}
	}
	return col;
}

// Высота в точке, 0..1
float height_at(vec2 p) {
	return textureLod(height_tex, clamp(p / map_size, vec2(0.0), vec2(1.0)), 0.0).r;
}

// Светотень рельефа (Huzzah 2026-10-24: «должен чувствоваться объём, когда поднимаюсь на гору»):
// склон к свету светлее, от света темнее; шаг разности — пиксель слоя высот или пиксель экрана, что крупнее
float relief(vec2 p) {
	float e = max(map_size.x / float(textureSize(height_tex, 0).x), 1.5 / zoom);
	float hx = (height_at(p + vec2(e, 0.0)) - height_at(p - vec2(e, 0.0))) * height_max / (2.0 * e);
	float hy = (height_at(p + vec2(0.0, e)) - height_at(p - vec2(0.0, e))) * height_max / (2.0 * e);
	vec3 n = normalize(vec3(-hx, -hy, 1.0));
	vec3 l = normalize(vec3(-0.6, -0.6, 0.55));
	return dot(n, l) - l.z;
}

// Жаркие горы в точке: 0..1 (от 0,5 — зона)
float hot_at(vec2 p) {
	return textureLod(hot_tex, clamp(p / map_size, vec2(0.0), vec2(1.0)), 0.0).r;
}

// Слой текстуры в точке (метры), повтор s метров. Два чтения — прямое и отражённое со сдвигом —
// смешиваются крупным шумом, чтобы повтор не бросался в глаза. Градиенты считаются из масштаба
// (вызовы бывают внутри ветвлений)
vec3 tex_s(vec2 p, int l, float s) {
	float g = 1.0 / (zoom * s);
	vec3 a = textureGrad(terrain_tex, vec3(p / s, float(l)), vec2(g, 0.0), vec2(0.0, g)).rgb;
	// Вторая копия — отражённая и сдвинутая, без поворота и масштаба: пиксели остаются 1:1
	vec2 q = vec2(-p.x, p.y) / s + vec2(0.37, 0.71);
	vec3 b = textureGrad(terrain_tex, vec3(q, float(l)), vec2(-g, 0.0), vec2(0.0, g)).rgb;
	return mix(a, b, smoothstep(0.38, 0.62, noise2(p / (s * 1.1) + vec2(float(l) * 3.1, 1.7))));
}

vec3 tex_l(vec2 p, int l) {
	return tex_s(p, l, TILE_M[min(l, 11)]);
}

// Средний цвет слоя (последний мип)
vec3 tex_mean(int l) {
	return textureLod(terrain_tex, vec3(0.5, 0.5, float(l)), 12.0).rgb;
}

// Ближний вид биома по текстурам кадров. b: 1 вода, 2 берег, 3 лес, 4 пустошь, 5 болото, 6 горы,
// 7..9 проклятые; hot — жаркие горы (0..1); wind — ветер модели, м/с (сейчас не используется: текстуры неподвижны).
// emis — свечение, оно добавляется после дня и ночи
vec3 biome_look(vec2 p, float b, vec3 base, float hot, vec2 wind, out vec3 emis) {
	emis = vec3(0.0);
	int bi = int(b + 0.5);
	vec3 col;
	int lay;
	if (bi <= 1) {
		// Вода: два неподвижных слоя текстуры (второй повёрнут), чтобы не было видно повтора
		vec3 w1 = tex_l(p, TEX_WATER);
		vec3 w2 = tex_l(vec2(p.y, -p.x) * 0.83, TEX_WATER);
		col = mix(w1, w2, 0.5);
		col *= 0.92 + 0.16 * noise2(p / 9.0);
		lay = TEX_WATER;
	} else {
		vec2 ps = p;
		if (bi == 2) {
			lay = TEX_COAST; col = tex_l(ps, lay);
		} else if (bi == 3) {
			lay = TEX_FOREST; col = tex_l(ps, lay);
			// Поляны: поле среди леса
			float clr = smoothstep(0.60, 0.72, noise2(p / 520.0 + vec2(4.3, 9.1)));
			col = mix(col, tex_l(ps, TEX_FIELD1), clr);
		} else if (bi == 4) {
			lay = TEX_WASTE; col = tex_l(ps, lay);
			// Пятна сухой травы
			float gr = smoothstep(0.62, 0.76, noise2(p / 430.0 + vec2(1.9, 6.2)));
			col = mix(col, tex_l(ps, TEX_FIELD2), gr * 0.75);
		} else if (bi == 5) {
			lay = TEX_SWAMP; col = tex_l(ps, lay);
		} else if (bi == 6) {
			lay = TEX_MOUNT; col = tex_l(ps, lay);
		} else if (bi == 7) {
			lay = TEX_RAD_FOREST; col = tex_l(ps, lay);
		} else if (bi == 8) {
			lay = TEX_RAD_WASTE; col = tex_l(ps, lay);
		} else {
			lay = TEX_RAD_SWAMP; col = tex_l(ps, lay);
		}
		if (bi >= 7) {
			// Свечение: маска своего цвета, яркость пятен разная, но не меняется во времени
			vec3 gm = tex_s(ps, TEX_GLOW, TILE_M[lay]);
			float m = bi == 7 ? gm.r : (bi == 8 ? gm.g : gm.b);
			float pulse = 0.5 + 0.5 * sin(noise2(p / 23.0 + vec2(3.3, 1.1)) * 12.0);
			emis = col * m * (0.35 + 0.9 * pulse);
		}
	}
	// Жаркие горы: выжженный охристый камень поверх любого биома зоны
	if (hot > 0.0 && bi > 1) {
		col = mix(col, tex_l(p, TEX_HOT), hot * 0.85);
		lay = hot > 0.5 ? TEX_HOT : lay;
	}
	if (bi > 1) {
		vec3 wash = bi == 3 || bi == 7 ? vec3(0.37, 0.40, 0.25) : tex_mean(lay);
		col = mix(col, wash, 0.30);
	}
	// Тон нарисованной карты сохраняется: вблизи и издали цвет места один
	vec3 mean = max(tex_mean(lay), vec3(0.04));
	col = mix(col, clamp(col * base / mean, 0.0, 1.0), 0.16);
	return col;
}

// Ближний вид биома без текстур (нет файлов art/terrain): процедурный рисунок поверх цвета карты
vec3 biome_detail(vec2 p, float b, vec3 base) {
	float n1 = fbm(p, 60.0);
	float n2 = fbm(p + vec2(311.0, 97.0), 9.0);
	float rad = b >= 6.5 ? 1.0 : 0.0;
	float kind = b >= 6.5 ? b - 4.0 : b;   // проклятые: 7 -> лес, 8 -> пустошь, 9 -> болото
	vec3 col = base;
	if (kind < 1.5) {
		float wave = noise2(p / 14.0);
		col = mix(vec3(0.12, 0.33, 0.52), vec3(0.20, 0.45, 0.62), n1) + vec3(wave - 0.5) * 0.06;
	} else if (kind < 2.5) {
		col = mix(vec3(0.80, 0.72, 0.52), vec3(0.66, 0.58, 0.42), n2);
	} else if (kind < 3.5) {
		float crown = smoothstep(0.45, 0.62, noise2(p / 6.0));
		col = mix(vec3(0.16, 0.30, 0.14), vec3(0.24, 0.42, 0.18), n1);
		col = mix(col, vec3(0.09, 0.18, 0.08), crown * 0.7);
	} else if (kind < 4.5) {
		col = mix(vec3(0.62, 0.55, 0.36), vec3(0.50, 0.46, 0.28), n1);
		col = mix(col, vec3(0.42, 0.44, 0.24), smoothstep(0.6, 0.75, n2) * 0.6);
	} else if (kind < 5.5) {
		col = mix(vec3(0.24, 0.36, 0.25), vec3(0.32, 0.42, 0.28), n2);
		col = mix(col, vec3(0.19, 0.23, 0.15), smoothstep(0.55, 0.62, n1));
	} else {
		col = mix(vec3(0.46, 0.42, 0.40), vec3(0.62, 0.58, 0.54), n1);
		col *= 0.85 + 0.3 * n2;
	}
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	col = mix(col, col * (0.6 + 0.8 * lum), 0.5);
	if (rad > 0.5) {
		col = mix(col, vec3(0.55, 0.68, 0.18), 0.35);
		float glow = smoothstep(0.70, 0.78, noise2(p / 18.0 + vec2(5.1, 2.7)));
		float pulse = 0.75 + 0.25 * sin(n1 * 6.0);
		col = mix(col, vec3(0.75, 1.0, 0.25), glow * 0.6 * pulse);
	}
	return col;
}

// Космос за краем мира
vec3 space_bg(vec2 fc, vec2 par) {
	vec2 q = (fc + par * 0.35) / 900.0;
	float neb = texture(noise_tex, q).r * 0.6 + texture(noise_tex, q * 2.3 + vec2(0.37, 0.11)).g * 0.4;
	neb = smoothstep(0.45, 0.85, neb);
	vec3 col = vec3(0.010, 0.009, 0.022) + neb * vec3(0.045, 0.022, 0.070);
	for (int i = 0; i < 3; i++) {
		float cs = 5.0 + float(i) * 6.0;
		vec2 g = (fc + par * (0.15 + 0.25 * float(i))) / cs;
		vec2 id = floor(g);
		vec4 r = textureLod(rand_tex, (mod(id + vec2(float(i) * 61.0, float(i) * 23.0), 256.0) + vec2(0.5)) / 256.0, 0.0);
		if (r.a > 0.965 - 0.01 * float(i)) {
			float d = length(fract(g) - vec2(0.25) - r.rg * 0.5) * cs;
			float star = 1.0 - smoothstep(0.35 + 0.35 * float(i) * r.b, 1.1 + 0.6 * float(i) * r.b, d);
			vec3 tint = mix(vec3(0.80, 0.86, 1.00), vec3(1.00, 0.86, 0.80), r.b);
			col += star * tint * (0.45 + 0.55 * r.r);
		}
	}
	return col;
}

void fragment() {
	vec2 vs = view_px.x > 0.0 ? view_px : 1.0 / SCREEN_PIXEL_SIZE;
	vec2 P = cam_pos + (UV - vec2(0.5)) * vs / zoom;
	float edge_n = board_hex_norm(P - BOARD_C);
	if (edge_n > BOARD_APO) {
		vec3 sp = space_bg(UV * vs, cam_pos * zoom);
		float glow = exp(-(edge_n - BOARD_APO) * zoom / 7.0);
		COLOR = vec4(sp + vec3(0.30, 0.45, 0.80) * glow * 0.35, 1.0);
	} else {
		// Облака, дождь и ветер из окна модели атмосферы
		vec2 uv_a = (ATM_ORIGIN + P / map_size * ATM_SPAN) / SRC_SIZE;
		// Крупные изгибы, чтобы края облаков не повторяли сетку модели
		uv_a += (vec2(cnoise(P * 0.5), cnoise(P * 0.5 + vec2(5000.0, 0.0))) - 0.5) * 1.5 / vec2(textureSize(atm_a, 0));
		vec4 am_a = atm_smooth(atm_a, uv_a);
		vec4 am_b = atm_smooth(atm_b, uv_a);
		vec2 wind = vec2(am_b.r, am_b.g) * 50.0 - vec2(25.0);
		vec2 wind_b = vec2(wind.x, -wind.y);
		float rain = am_a.g * 8.0;
		// Жаркие горы (без дрожания воздуха: текстуры неподвижны)
		float hot = smoothstep(0.45, 0.55, hot_at(P));
		vec2 Ph = P;
		vec3 base = texture(map_tex, Ph / map_size).rgb;
		// Harmonize the overview with the painted palette without altering geography/data masks.
		if (use_textures) {
			int bi_over = int(biome_at(P) + 0.5);
			int layer_over = bi_over <= 1 ? TEX_WATER : (bi_over == 2 ? TEX_COAST : (bi_over == 3 ? TEX_FOREST : (bi_over == 4 ? TEX_WASTE : (bi_over == 5 ? TEX_SWAMP : (bi_over == 6 ? TEX_MOUNT : (bi_over == 7 ? TEX_RAD_FOREST : (bi_over == 8 ? TEX_RAD_WASTE : TEX_RAD_SWAMP)))))));
			if (water_at(P) >= 0.5) { layer_over = TEX_WATER; }
			if (hot > 0.5 && layer_over != TEX_WATER) { layer_over = TEX_HOT; }
			vec3 painted_mean = tex_mean(layer_over);
			float old_luma = dot(base, vec3(0.299, 0.587, 0.114));
			base = mix(base, painted_mean * (0.78 + old_luma * 0.45), 0.48);
		}
		// Вода по рисунку: граница без лесенки, сглажена на один пиксель экрана
		float wv = water_at(P);
		float wa = max(fwidth(wv), 0.002);
		float wet = smoothstep(0.5 - wa, 0.5 + wa, wv);
		// Вблизи: рисунок биома суши с неровной границей (пиксель слоя биомов ~17,6 м), вода — точно по маске
		float near_k = smoothstep(0.08, 0.6, zoom);
		vec3 col = base;
		vec3 emis = vec3(0.0);
		if (near_k > 0.0) {
			vec3 near_col = vec3(0.0);
			vec3 e_land = vec3(0.0);
			vec3 e_w = vec3(0.0);
			if (wet < 1.0) {
				vec2 wp = P + (vec2(fbm(P, 70.0), fbm(P + vec2(91.0, 37.0), 70.0)) - 0.5) * 60.0;
				near_col = use_textures ? biome_look(Ph, biome_at(wp), base, hot, wind_b, e_land) : biome_detail(P, biome_at(wp), base);
			}
			if (wet > 0.0) {
				vec3 wcol = use_textures ? biome_look(P, 1.0, base, 0.0, wind_b, e_w) : biome_detail(P, 1.0, base);
				near_col = mix(near_col, wcol, wet);
			}
			emis = e_land * (1.0 - wet) * near_k;
			col = mix(base, near_col, near_k);
			// Дождь: суша вблизи темнеет и чуть отливает небом
			float rk = smoothstep(0.1, 1.0, rain) * (1.0 - wet) * near_k;
			col = mix(col, col * 0.78 + vec3(0.02, 0.03, 0.05), rk * 0.6);
		}
		// Снег зимой слегка пудрит сушу вне воды (в жарких горах снега нет)
		float winter = smoothstep(0.55, 0.95, -seas) * (1.0 - hot);
		float bb = biome_at(P);
		if (bb > 1.5 && wet < 0.5) {
			col = mix(col, vec3(0.88, 0.89, 0.92), winter * 0.35 * smoothstep(0.35, 0.65, fbm(P, 120.0)));
		}
		// Рельеф: светотень склонов, вершины светлее и холоднее, на самых высоких — снег
		float hgt = height_at(P);
		if (hgt > 0.002 && wet < 0.5) {
			col *= clamp(1.0 + relief(P) * 1.15, 0.5, 1.45);
			col = mix(col, col * 1.06 + vec3(0.02, 0.03, 0.05), hgt * 0.3);
			col = mix(col, vec3(0.90, 0.91, 0.94), smoothstep(0.82, 0.97, hgt + 0.08 * fbm(P, 90.0)) * (1.0 - hot) * 0.7);
		}
		// День и ночь
		vec3 sun_dir;
		vec3 shade = world_light(sun_dir);
		col *= shade;
		// Свечение проклятых пятен видно и днём, ночью ярче
		col += emis * mix(1.0, 0.45, smoothstep(-0.18, 0.12, sun_dir.z));
		float cn = cloud_detail(P, wind_b * drift_scale);
		float cf = am_a.r;
		float cloud = clamp(cf + (cn - 0.5) * 1.6 * (1.0 - abs(2.0 * cf - 1.0)), 0.0, 1.0);
		// Под облаками земля темнее, в дождь ещё темнее
		col *= 1.0 - 0.18 * smoothstep(0.5, 0.95, cloud) - 0.12 * smoothstep(0.1, 1.0, rain);
		float cl_a = show_clouds * smoothstep(0.62, 0.92, cloud) * (1.0 - smoothstep(0.06, 0.35, zoom)) * 0.65;
		vec3 cl_col = clamp(shade * 1.1, 0.0, 1.0) * vec3(0.93, 0.95, 0.98);
		cl_col = mix(cl_col, cl_col * 0.55, smoothstep(0.0, 0.5, rain));
		col = mix(col, cl_col, cl_a);
		if (border_mode > 0) {
			col = borders(P, col);
		}
		// Мягкая кромка у края мира
		col *= 0.75 + 0.25 * (1.0 - smoothstep(BOARD_APO - 6.0 / zoom, BOARD_APO, edge_n));
		COLOR = vec4(col, 1.0);
	}
}
"""
