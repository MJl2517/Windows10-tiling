# Desktop configuration

- Every new or changed shortcut must work on the same physical key in English and Russian layouts, including Shift/Ctrl variants.
- For Yazi, update the English binding first, then regenerate and verify Russian aliases using `scripts/sync-russian-keymap.py` and the matching version's `scripts/yazi-26.9.1-default-keymap.toml`. Back up the installed keymap before writing it.
- Preserve normal Russian typing in filename, rename, search and command input fields. Do not remap all terminal text globally.
- GlazeWM letter shortcuts and native WPF keys use Windows virtual keys; verify existing behavior before adding duplicate bindings.
