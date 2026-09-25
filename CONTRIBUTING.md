# Contributing

## Adding a tool

Open `data/categories/<category>.txt` and add a line:

```
package-name|Short description of what it does
```

`package-name` must be the exact pacman/AUR package name. No code changes
needed - the installer picks it up automatically.

## Adding a category

1. Add an `id` -> `label` pair to `CATEGORY_LABELS` in `lib/categories.sh`.
2. Create `data/categories/<id>.txt` with the same `package|description`
   format as the others.

## Before opening a PR

```bash
shellcheck install.sh lib/*.sh
./install.sh --dry-run --yes --categories=<your-category>
./install.sh --list
./install.sh --status
```

Both `shellcheck` and the dry run should complete clean. The CI workflow
runs ShellCheck on every PR automatically.
