# Вечерняя крепость — Android

Офлайн-игра в WebView. Сеть и сервер не нужны.

## Как собрать APK
1. Установи Android Studio (бесплатно).
2. File → Open → выбери эту папку `android`.
3. Дождись синхронизации Gradle (первый раз скачает инструменты).
4. Build → Build App Bundle(s) / APK(s) → Build APK(s).
5. Готовый файл: `app/build/outputs/apk/debug/app-debug.apk` — перекинь на телефон и установи
   (разреши установку из неизвестных источников).

Обновить игру: замени `app/src/main/assets/index.html` новой версией и пересобери.
