# Dungeon Castle — авторы и лицензии

Каждый внешний ассет записывается сюда: что это, ссылка, лицензия, автор.

## Движок и шрифт
| Что | Ссылка | Лицензия | Автор |
|---|---|---|---|
| Godot Engine 4.5.1 | https://godotengine.org | MIT | Juan Linietsky, Ariel Manzur и сообщество Godot |
| Шрифт по умолчанию Godot (Open Sans) | https://fonts.google.com/specimen/Open+Sans | OFL 1.1 | Steve Matteson |

## 3D-модели (запечены в 2D-спрайты, `assets/sprites/`)
Модели рендерятся в спрайты инструментом `tools/sprite_baker` (вид сбоку, контур, перекраска
одежды и цвета кожи). Сами 3D-файлы в игру не входят.

| Что | Где в игре | Ссылка | Лицензия | Автор |
|---|---|---|---|---|
| Ultimate Modular Men (Adventurer, Farmer, Worker, King) | жители, правитель (`m_*`) | https://quaternius.com/packs/ultimatemodularcharacters.html | CC0 1.0 | Quaternius |
| Ultimate Modular Women (Adventurer, Medieval, Witch, Worker) | жительницы (`f_*`) | https://quaternius.com/packs/ultimatemodularwomen.html | CC0 1.0 | Quaternius |
| Ultimate Monsters (GreenBlob, GreenSpikyBlob, Orc, Orc_Skull) | враги: слизни, тролль, Грызень | https://quaternius.com/packs/ultimatemonsters.html | CC0 1.0 | Quaternius |

Копии паков брались из публичных зеркал на GitHub (сайт автора из сборочной среды недоступен),
лицензии в зеркалах сохранены:
- `HamaDler/sami-park-mayhem` → `assets/characters/crowd/` (LICENSE.txt: CC0, Quaternius);
- `flawlesshappiness/EmotionCreatures` → `Assets/Quaternius/Ultimate Monsters/` (License.txt: CC0, Quaternius).

## Процедурная графика
Замок, комнаты, пещеры, иконки ресурсов и интерфейс рисуются кодом (`scripts/castle/art.gd`,
`scripts/castle/cell_view.gd`).

## Звук
Пока нет (этап 5).

## Инструменты сборки (в игру не входят)
| Что | Ссылка | Лицензия |
|---|---|---|
| uber-apk-signer | https://github.com/patrickfav/uber-apk-signer | Apache 2.0 |
