# План проверки скилов devops_ue

Проверка `ue-create-project`, `ue-web-setup` и `ue-web-deploy` с нуля.

Тестовый проект: `HotShell` (C++) и `HotShellBP` (Blueprint). Каждый проект — своя папка: вы создаёте её,
делаете `git init` и добавляете `devops_ue` сабмодулем, а скил создаёт проект прямо в ней.

## 0. Папка HotShell и установка скилов

```powershell
mkdir C:\_Projects\UnrealEngine\HotShell
cd C:\_Projects\UnrealEngine\HotShell
git init
git submodule add https://github.com/life-exe/devops_ue
devops_ue\skills\install_skills.bat
```

`install_skills.bat` спросит, куда ставить: **P** — только в проект (`HotShell\.claude\skills`), **G** — глобально
(`%USERPROFILE%\.claude\skills`). Для теста выберите **P**; режим можно передать аргументом: `install_skills.bat project`.

- [ ] в `devops_ue` свежий коммит, есть папка `skills`
- [ ] в `HotShell\.claude\skills\` есть `ue-create-project`, `ue-web-setup`, `ue-web-deploy`, без `devops_source.txt`
- [ ] Claude Code открыт (или перезапущен) в `HotShell`, при вводе `/ue-` подсказываются все скилы
      (`ue-check-env`, `ue-create-project`, `ue-web-setup`, `ue-web-deploy`)
- [ ] `install_skills.bat` в конце показал таблицу `check_skills.ps1`: все копии `same`
- [ ] `/ue-check-env`: таблица `[ok]/[!!]/[XX]/[--]` с версиями и командами исправления

## 1. C++ проект: `/ue-create-project`

Скил должен сам увидеть подготовленную папку и предложить имя `HotShell` без вопроса о расположении.
Ответы: C++, компания (текстом), копирайт из готовых вариантов, движок 5.9, пустая `MainLevel`, на вопрос «упаковать сразу?» — **нет**.

- [ ] проект создан прямо в `HotShell`, вывод скрипта: `using the existing git repository`, `using the existing devops_ue`
- [ ] `HotShell.uproject` открывается, редактор стартует на `MainLevel`
- [ ] GameMode по умолчанию — `HotShellGameMode` (Project Settings > Maps & Modes)
- [ ] есть `Source\HotShell\HotShellGameMode.h/.cpp`, первая строка каждого `.h/.cpp/.cs` — ваш копирайт
- [ ] `DefaultGame.ini`: `CopyrightNotice`, `CompanyName`, `ProjectName`
- [ ] в корне: `.clang-format`, `.gitignore`, `AGENTS.md`, `CLAUDE.md`, `.claude\skills\`, bat-скрипты
- [ ] `git submodule status` показывает `devops_ue`
- [ ] `devops_data\config.bat`: правильные `EnginePath` и `COPYRIGHT_LINE`
- [ ] `generate_project_files.bat`, `format_all_files.bat`, `clean_intermediate_files.bat` отрабатывают
      без ошибки «The syntax of the command is incorrect»
- [ ] скил начал с проверки окружения (`check_env.ps1 -For create`)
- [ ] после создания спросил про LFS, первый коммит и `config.bat`; ответы: LFS — да, коммит — да, `config.bat` — локально
- [ ] `git log` — один коммит, `.gitattributes` есть, `git lfs ls-files` не пуст,
      `git check-ignore devops_data/config.bat` выводит путь; в конце вывода — таблица `Time:`

## 2. Blueprint проект из шаблона: `/ue-create-project`

Подготовить вторую папку так же; здесь проверим глобальную установку (**G**):

```powershell
mkdir C:\_Projects\UnrealEngine\HotShellBP
cd C:\_Projects\UnrealEngine\HotShellBP
git init
git submodule add https://github.com/life-exe/devops_ue
devops_ue\skills\install_skills.bat global
```

- [ ] в `%USERPROFILE%\.claude\skills\` есть все три скила, в каждом `devops_source.txt` с путём к `HotShellBP\devops_ue`

Открыть Claude Code в `HotShellBP`. Ответы: Blueprint, компания (текстом), копирайт из готовых вариантов, шаблон Third Person,
на вопрос «упаковать сразу?» — **да**.

> Зачем упаковка: в конце скил спрашивает, упаковать ли проект сразу, и при «да» запускает `package_game.bat`
> (Windows, Development). В шаге 1 проверяется ответ «нет», здесь — «да». Для веба Windows-упаковка не нужна;
> если время дорого, шаг можно пропустить и позже вручную запустить `package_game.bat` — это тот же скрипт.

- [ ] скил спросил компанию текстом и копирайт (в Blueprint-проекте тоже); варианты копирайта — готовые строки с реальными именами, без `<...>`; оба есть в итоговой сводке
- [ ] `DefaultGame.ini`: `CopyrightNotice` — ваш текст; `devops_data\config.bat`: `COPYRIGHT_LINE`
- [ ] проект открывается, персонаж бегает
- [ ] упаковка лежит в `HotShellBP\Build\Windows`, exe запускается

## 3. Веб-настройка: `/ue-web-setup`

В `HotShellBP` — так проверится добавление C++ в Blueprint-проект.

1. Сначала скил делает проверку без изменений: должен предупредить, что проект только на Blueprint и что не настроены плагины.
2. Ответы: Click, оба тира, хостинг itch/Vercel, упаковка Development; на вопрос про C++-модуль — «да».

- [ ] в `Source\HotShellBP` появился модуль, редактор открывает проект
- [ ] uproject: у `OnlineSubsystem*` запрет Wasm, `AllToolsets` и `AIAssistant` выключены
- [ ] в `DefaultEngine.ini` есть секция `[/Script/WasmTargetPlatform.WasmTargetSettings]`
- [ ] в сводке `VerifySdk ok`, `package ok`
- [ ] `run_wasm.bat` открывает игру в Chrome: после клика по обложке игра запускается, персонаж ходит

## 4. Деплой: `/ue-web-deploy`

Публичный деплой — только Shipping: `package_wasm.bat Shipping` в `HotShellBP`.

1. Скил проверит инструменты. Залогиниться где нужно: `! butler login`.
2. **itch.io**
   - создать страницу itch.io/game/new: тип HTML, видимость Draft или Restricted
   - deploy с целью itch: Claude покажет dry-run и спросит подтверждение
   - на странице игры отметить загрузку «played in the browser» и включить **SharedArrayBuffer support**
   - [ ] игра запускается на странице itch
3. **Vercel** — preview-деплой без `--prod`
   - [ ] URL открывается, игра стартует
   - [ ] в отчёте результат `webdoctor.py`
   - если упадёт на размере `.wasm` — это лимит Vercel на размер файла (не подтверждён), прислать ошибку
4. **GitHub release** — нужен репозиторий с remote:
   ```powershell
   git add . ; git commit -m "test"
   gh repo create HotShellBP --private --source . --push
   ```
   - [ ] в Releases появился zip

## 5. Уборка

- удалить проект на Vercel, черновик на itch, приватный репозиторий `HotShellBP` на GitHub
- удалить папки `HotShell` и `HotShellBP`; если не даёт длина путей:
  `rd /s /q "\\?\C:\_Projects\UnrealEngine\HotShellBP"`
- глобальные скилы помнят путь к `HotShellBP\devops_ue`: после удаления папки удалите их из
  `%USERPROFILE%\.claude\skills\` или переустановите `install_skills.bat global` из другого devops_ue
  (например, `ShootThemUp\devops_ue`)

## Время

Дольше всего идут сборка C++ и Wasm-упаковка: Development ~11 минут, Shipping дольше.
Если что-то упало — сохранить вывод скрипта или блок `Warnings:`.
