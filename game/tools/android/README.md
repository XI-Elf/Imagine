# Збірка APK (Android)

Потрібні: Godot 4.7.2, export templates (`android_*.apk`), JDK 17+, Android SDK (на ПК Huzzah — звичайний).
У хмарі SDK недоступний, тому `apksigner_v2.py` підписує APK схемою v2 (python3-cryptography, ключ PKCS12) —
покласти його як `<sdk>/build-tools/<ver>/apksigner` (обгортка `exec python3 apksigner_v2.py "$@"`), а `adb`, `zipalign`, `sdkmanager` — порожні заглушки, `platforms/android-35` — порожня тека.

    godot --headless --path game --import
    # debug: ключ Godot (editor settings)
    godot --headless --path game --export-debug Android ../dist/android/AmberWorld-debug.apk
    # release: свій ключ
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... GODOT_ANDROID_KEYSTORE_RELEASE_USER=amberworld \
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=... godot --headless --path game --export-release Android ../dist/android/AmberWorld.apk

Release-ключ: /mnt/project-files/android/ (проєктна тека, не в репозиторії); без нього оновлення поверх встановленого не пройде.
Сенсорний режим: `ui/mobile_controls.gd` (на ПК вмикається аргументом `-- --touch`). Тест: `tests/mobile_controls_checks.gd`.
