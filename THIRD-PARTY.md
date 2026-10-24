# Сторонние компоненты

Сторонние приложения загружаются из официальных источников. Версии и SHA-256
зафиксированы в `dependencies.json`. Это не меняет их лицензии.

| Компонент | Источник / лицензия |
|---|---|
| GlazeWM | https://github.com/glzr-io/glazewm — GPL-3.0 |
| Zebar | https://github.com/glzr-io/zebar — GPL-3.0 |
| bar-rose-pine | https://github.com/thearturca/zebar-rose-pine-bar — MIT, thearturca; изменённая версия, LICENSE сохранён в src/bar |
| Yazi, значки и плагины | https://github.com/sxyazi/yazi — MIT; лицензии сохранены |
| Alacritty | https://github.com/alacritty/alacritty — Apache-2.0 |
| Tacky Borders | https://github.com/luke-you/tacky-borders — MIT |
| Poppler Windows | https://github.com/oschwartz10612/poppler-windows — GPL-2.0-or-later и лицензии зависимостей внутри пакета |
| Chafa | https://hpjansson.org/chafa/ — LGPL-3.0-or-later |
| Portable Git / file | https://github.com/git-for-windows/git — GPL-2.0 и лицензии включённых инструментов; используется только file для определения типов, системный Git не устанавливается |
| 7-Zip | https://www.7-zip.org — LGPL-2.1 и ограничения unRAR |
| JetBrains Mono Nerd Font | https://github.com/ryanoasis/nerd-fonts — SIL OFL-1.1 |
| ConPTY | https://github.com/microsoft/terminal — MIT |
| Bibata | https://github.com/ful1e5/Bibata_Cursor — GPL-3.0 |

Node-зависимости панели перечислены и зафиксированы в `src/bar/package-lock.json`.
Их исходные уведомления включаются сборщиком в `licenses/npm-NOTICES.txt`.
Истории, секреты и пользовательские кэши в проект не включаются.
