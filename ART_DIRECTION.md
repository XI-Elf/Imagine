# Amber World — художнє оновлення

Стиль: мальована 2D fantasy/storybook-ілюстрація з нерівними контурами тушшю, акварельною фактурою, теплими земляними тонами та вертикальними об'єктами у ракурсі три чверті. Це опис художнього напряму, а не назва конкретної техніки покадрової анімації.

## Референси та походження

Сім наданих користувачем зображень використані як художній орієнтир. Day R — орієнтир читабельності тактичної сцени; [Watabou](https://watabou.itch.io/medieval-fantasy-city-generator) — орієнтир кварталів, проходів і міських осередків. Їхні ігрові текстури та програмний код не включалися. План міста адаптований з вихідного проєкту; це не інтеграція генератора Watabou.

Нові растрові зображення створені засобом генерації зображень, потім розділені на спрайти, підготовлені з альфа-каналом, масштабовані й інтегровані в Godot. Атласи збережені в `game/art/source_atlases`. Вони не імпортуються рушієм завдяки `.gdignore`. Оригінальні дані карти й комплектний Windows-рушій залишені з користувацького архіву.

## Завдання для генерації (редакційний опис)

- Terrain: 4×4 atlas, hand-painted ink and watercolor game surfaces; water, coast, forest litter, wasteland, swamp, mountain ground, fields and radioactive variants; four architectural materials; restrained palette, no perspective objects or text.
- Nature: isolated upright oak, light tree, flowering and berry bushes, gray and warm mountains, rock, market stall and well; coherent front/three-quarter angle, transparent background, painted contours, no labels.
- Buildings: six isolated upright medieval house, inn, hall, temple, smithy and healer buildings; readable facade, coherent warm light, ink-watercolor finish, transparent background.
- People: six isolated traveler, woman, villager, guard, bandit and hound sprites; readable silhouette, coherent illustrated treatment, transparent background.
- Variants: three distinct gray mountain forms, two warm mountain forms and a crooked tree; match the existing atlas palette and upright perspective.
- Menu: wide illustrated fantasy landscape, matching the supplied storybook references, reserved composition for menu controls.

Це опис напрямів запитів, а не дослівний журнал інструмента.

## Інтеграція

12 базових текстур поверхні замінено; маску світіння перебудовано. Додано 31 PNG, зокрема 6 варіантів гір і дерев. Фон меню замінено. Матеріали мають узгоджений фізичний масштаб, фільтрацію та повторення. Об'єкти світу детерміновано розміщуються за біомом, відсікаються поза екраном і з'являються залежно від масштабу. Місто та бій використовують сортування за вертикальною координатою опори спрайта.

Місто розширене до 51 будівлі та 28 NPC, додано 38 декоративних насаджень. Збережено логіку взаємодій і пошуку шляху. Додано легке похитування дерев, дим і рух спрайтів під час переміщення. Окремих покадрових циклів ходи немає; не-людські супротивники використовують спрайт звіра.

Географія, маски води та біомів, бойові формули й комплектні виконувані файли не замінювалися. Це графічне оновлення існуючого проєкту.

## Валідація

Godot 4.5.1 Linux: імпорт ресурсів, перевірка сцен і шляхів до 51 входу, 28 NPC; фактичний OpenGL-рендер міста, бою, лісу та гір на кількох масштабах. Фінальний рендер без помилок ресурсів чи шейдерів. Є лише попередження про V-Sync в тестовому програмному відеодрайвері. Windows-рушій з вихідного архіву збережений; запуск EXE напряму не перевірявся.

`game/qa/check_storybook.gd` та `game/qa/render_storybook.gd` містять відтворювані перевірки. Знімки у Preview отримані з рушія, а не є концептами.
