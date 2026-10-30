# KubeBar

Приложение в строке меню macOS, которое собирает команду `kubectl` / `stern` / любой другой CLI-утилиты из выбранных контекста, namespace и приложения — и открывает её в терминале (Ghostty, Terminal.app или iTerm2).

- выпадающие списки с поиском: утилита → контекст (из `~/.kube/config`) → namespace → приложение (Deployment/StatefulSet/DaemonSet);
- предпросмотр команды, который можно поправить перед запуском;
- **Запустить** — открыть терминал и выполнить; **Подготовить** — открыть терминал с набранной, но не запущенной командой;
- свои шаблоны утилит с плейсхолдерами `{executable} {context} {namespace} {app}`;
- история последних 10 команд с повторным запуском;
- интерфейс на русском и английском — по языку системы (или вручную: **Настройки KubeBar → Общие → Язык**).

Требуется macOS 14+ и установленный `kubectl` (плюс `stern` и т.п. — по желанию).

## Установка

```sh
brew install --cask svclimb/tap/kubebar
```

Обновление — `brew upgrade --cask kubebar`, удаление — `brew uninstall --cask kubebar` (с `--zap` — вместе с настройками).

Иконка появится в строке меню (значок терминала); в Dock приложения нет. При первом запуске команды macOS спросит разрешение на управление терминалом — нажмите «Разрешить». Если случайно отказали: **Системные настройки → Конфиденциальность и безопасность → Автоматизация → KubeBar**.

<details>
<summary>Без Homebrew</summary>

1. Скачайте `KubeBar-<версия>.zip` со страницы [Releases](https://github.com/svclimb/KubeBar/releases), распакуйте и перетащите `KubeBar.app` в «Программы».
2. Приложение не подписано сертификатом Apple Developer, поэтому при первом запуске macOS его заблокирует. Либо запустите один раз и нажмите **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»**, либо выполните `xattr -dr com.apple.quarantine /Applications/KubeBar.app`. Homebrew-установка делает это сама.

</details>

## Настройка

Шестерёнка в окне KubeBar открывает настройки:

- **Утилиты** — шаблоны команд. В качестве исполняемого файла можно указать полный путь, если утилита не находится автоматически (KubeBar ищет в PATH вашего login-shell, `/opt/homebrew/bin` и `/usr/local/bin`).
- **Терминал** — какой терминал использовать. Для своего терминала `{{command}}` в шаблоне заменяется на собранную команду.
- **Namespaces / Apps** — сохранённые списки. Кнопка ↻ рядом с полем в меню подтягивает их из кластера; найденные так namespaces/apps показываются только для своего контекста.
- **Общие** — запуск при входе в систему.

Настройки хранятся в `~/Library/Application Support/KubeBar/config.json`.

## Сборка из исходников

Нужны Xcode Command Line Tools (`xcode-select --install`).

```sh
Packaging/build-app.sh          # собрать dist/KubeBar.app и запустить его вместо текущего KubeBar
Packaging/build-app.sh --zip    # собрать dist/KubeBar-<версия>.zip для раздачи
```

Сборка универсальная (Apple Silicon + Intel), подпись ad-hoc. Скрипт не трогает `/Applications` — там живёт копия, установленная через brew; чтобы вернуться к ней после проверки, закройте dev-сборку и выполните `open -a /Applications/KubeBar.app`.

## Выпуск новой версии

```sh
git tag v1.1 && git push origin v1.1
```

GitHub Actions (`.github/workflows/release.yml`) соберёт `KubeBar-1.1.zip` (версия берётся из тега), опубликует релиз и обновит cask в [svclimb/homebrew-tap](https://github.com/svclimb/homebrew-tap). Для последнего нужен секрет `HOMEBREW_TAP_TOKEN` в настройках репозитория — fine-grained token с правом «Contents: Read and write» на `svclimb/homebrew-tap`.

Строки интерфейса в коде — на английском, они же ключи перевода; русский перевод в `Packaging/Localization/ru.lproj/Localizable.strings`. При `swift run` интерфейс всегда английский: переводы подключаются только в собранный `.app`.
