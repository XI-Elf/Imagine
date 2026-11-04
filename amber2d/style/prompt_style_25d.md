# Промт единого стиля изображений Amber Game: 2.5D, близко к реализму

Сеттинг: тёмная научная фантастика в средневековом мире (dark sci-fi fantasy). Европейское средневековье, радиальные города с рынком и стеной, серая приглушённая палитра, рядом с обычными вещами лежат техно-артефакты (уцелевшие пластины, купола, обломки). Тон «серость»: бедно, устало, без героики.

## Как пользоваться

1. Вставьте **базовый промт** (английский, модели его понимают лучше) в генератор один раз как стиль-якорь.
2. В конце добавьте строку **«Предмет»** из шаблонов ниже.
3. Первую удачную картинку сохраните и дальше подавайте как референс стиля (style reference / image reference). Это держит единый вид лучше любых слов.
4. Один и тот же сид и одни и те же настройки на всю серию.

## Базовый промт (стиль-якорь)

```
Game asset in a unified 2.5D style, close to realism: physically based painted look, semi-realistic proportions, believable materials (worn leather, dull iron, rough wool, weathered wood, cracked stone, corroded alloy). Slightly top-down three-quarter view, camera about 35 to 40 degrees above the horizon, same angle for every asset, subject centered with a little margin. Soft directional light from the upper left, one clear soft cast shadow falling to the lower right, gentle ambient occlusion, subtle rim light. Dark sci-fi fantasy setting: medieval European world with remnants of lost technology. Muted desaturated palette (ash grey, mud brown, dark olive, rust, cold steel blue), small accents of amber glow only on technology and amber stones. Fine surface detail, scratches, dust, wear, no cartoon outlines, no cel shading, no pixel art, no glossy plastic, no neon, no text, no watermark, no logo.
Background: plain transparent or flat neutral mid-grey (#808080) background, nothing else in frame.
```

## Негативный промт (если генератор поддерживает)

```
cartoon, comic outline, cel shading, anime, pixel art, flat vector, oversaturated colors, neon, glossy plastic, text, letters, watermark, logo, frame, border, multiple objects, cropped subject, extreme perspective, fisheye, blur, low detail, modern clothing, guns, cars
```

## Шаблоны строки «Предмет»

- **Предмет в сумке (иконка 1:1):** `Subject: single inventory item, [название, материал, состояние], centered, square 1:1, three-quarter top view, fills about 75% of the frame.`
- **Одежда и броня:** `Subject: single clothing piece laid out flat with slight volume, [название, цвет, ткань], square 1:1.`
- **Персонаж или NPC:** `Subject: full-body character, [кто, возраст, одежда, поза], standing neutral pose, facing slightly to the viewer, 3/4 top view, tall 2:3 frame.`
- **Зверь или противник:** `Subject: [wolf, boar, wild dog, bandit], full body, alert pose, 3/4 top view, 3:2 frame.`
- **Здание или постройка:** `Subject: [house, inn, smithy, temple, well], isometric-leaning 3/4 top view, roof visible, stone and timber, 1:1 frame.`
- **Местность (тайл):** `Subject: seamless tileable top-down terrain texture, [forest floor, field, wasteland, swamp, mountain rock], no objects, even lighting, no shadows from outside, 1:1.` Для тайлов уберите из базового промта строки про ракурс, тень и фон.
- **Техно-артефакт:** `Subject: [dome, tower, wreck, plate] of lost technology half buried and overgrown, corroded alloy, faint amber glow in seams.`

## Примеры готовых строк

- `Subject: single inventory item, loaf of dark rye bread, rough crust, centered, square 1:1, three-quarter top view, fills about 75% of the frame.`
- `Subject: single inventory item, iron mace with a spiked head and a worn wooden handle, centered, square 1:1, three-quarter top view.`
- `Subject: full-body character, middle-aged village herbalist woman, patched wool dress and apron, standing neutral pose, tall 2:3 frame.`

## Правила единства серии

- Один ракурс (35–40° сверху) и один свет (сверху-слева) для всех картинок.
- Размер без фона 1024 px, потом уменьшаем до 256 для значков. Для карты и интерфейса отдельные размеры.
- Янтарное свечение допустимо только у техно и янтаря, чтобы оно читалось как знак «артефакт».
- В кадре один предмет, без рук и подставок.
- Не называть другие игры и художников в промте (правило проекта).

## Что проверить после первых 5 картинок

1. Все ли предметы выглядят как из одной игры, если сложить их в сетку 5×1.
2. Читаются ли значки при 64 px.
3. Совпадает ли палитра с текущими 12 текстурами местности в игре.
