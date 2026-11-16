# Dungeon Castle

Мобильная игра на Godot 4.5: замок в разрезе и бесконечное подземелье под ним. Полностью офлайн,
без покупок. Концепция: [docs/CONCEPT.md](docs/CONCEPT.md).

## Структура
```
scenes/    сцены (.tscn)
scripts/   логика: autoload/ (данные, состояние, сохранение), model/, castle/ (вид замка)
ui/        интерфейс (HUD, тема)
data/      баланс в JSON и строки локализации (data/i18n/strings.csv)
assets/    графика (на этапе 1 пусто, всё процедурное)
audio/     звук (этап 5)
tests/     дымовой тест со скриншотами
tools/     скрипт сборки APK
```

## Запуск на ПК
Откройте папку `dungeon_castle` в Godot 4.5.1 и нажмите F5. Мышь эмулирует касания, колесо
зумирует.

Дымовой тест: `godot --path . res://tests/smoke_test.tscn` (скриншоты сохраняются в `user://shots`).

## Сборка APK
1. Установите Godot 4.5.1 и шаблоны экспорта: Editor → Manage Export Templates → Download.
2. Установите Android SDK (Android Studio или command-line tools) и JDK 17.
3. Пропишите в Editor Settings → Export → Android пути к SDK и JDK; debug.keystore Godot создаст сам.
4. Project → Export → Android → Export Project, либо `tools/build_apk.sh`.
5. GitHub Actions (`.github/workflows/godot-apk.yml`) собирает APK при каждом пуше в `dungeon_castle/`
   и выкладывает его в артефакты.

## Установка на телефон
```
adb devices                      # телефон с включённой отладкой по USB
adb install -r DungeonCastle.apk
```
Без компьютера: скачайте `apk/dungeon-castle-0.1.0.apk` с GitHub на телефон и откройте его
(разрешите установку из неизвестных источников).
