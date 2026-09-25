# Changelog

## v2.0.0

Added a persistent install ledger and the commands built on top of it.

- **Ledger**: every tool RedCell installs is recorded at
  `~/.local/state/redcell/installed.tsv` (package, category, source,
  timestamp). RedCell only ever acts on packages it tracked itself.
- **`--update`**: upgrades every tracked tool in one command - a scoped
  `pacman -S --needed` pass for pacman/BlackArch packages, and a rebuild
  pass through the detected AUR helper for AUR packages.
- **`--uninstall=category,category`**: removes tracked tools by category
  and drops them from the ledger. Nothing outside the ledger is touched.
- **`--status`**: read-only breakdown of what's installed, by category.
- **Run reports**: every install, update or uninstall run now writes a
  markdown summary next to its log, at
  `logs/redcell-<run-id>-report.md`.
- **Category picker** now shows a live tool count per category.
- Fixed: `--yes` wasn't being honored by the BlackArch/AUR-helper
  bootstrap prompts, which could hang a non-interactive run waiting on
  input that would never arrive.

## v1.0.0

Initial release: category-based installer with a pacman -> BlackArch ->
AUR resolver, a `gum`-based TUI, and `--dry-run`/`--list`/`--categories`
support.
