# Outline Manager

## Running

Чтобы запустить Outline Manager:
```
yarn do server_manager/electron_app/run
```

## Debug an existing binary

Вы можете запустить существующий двоичный файл в режиме отладки, установив `OUTLINE_DEBUG=true`.
Это активирует меню разработчика в окне приложения..

## Packaging

Для сборки двоичного файла приложения:
```
yarn do server_manager/electron_app/package_${PLATFORM}
```

Where `${PLATFORM}` is one of `linux`, `macos`, `only_windows`.

Отдельные приложения для каждой платформы будут на `build/electron_app/static/dist`.

- Windows: zip files. Генерируется только если у вас есть [wine](https://www.winehq.org/download) установлены.
- Linux: tar.gz files.
- macOS: файлы dmg, если они созданы из macOS, в противном случае файлы zip.

## Releases

Чтобы выполнить релиз, используйте
```
yarn do server_manager/electron_app/release
```

Это выполнит очистку и переустановит все зависимости, чтобы убедиться, что сборка не испорчена.
