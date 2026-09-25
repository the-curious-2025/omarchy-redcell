<div align="center">

```
 ___ ___ ___   ___ ___ _    _
| _ \ __|   \ / __| __| |  | |
|   / _|| |) | (__| _|| |__| |__
|_|_\___|___/ \___|___|____|____|
```

### Omarchy -> Red Team Edition

One command turns a fresh [Omarchy](https://omarchy.org) install into a
penetration testing workstation - without losing Omarchy.

[![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Target: Arch / Omarchy](https://img.shields.io/badge/target-Arch%20%2F%20Omarchy-1793D1?logo=archlinux&logoColor=white)](https://archlinux.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-informational)](LICENSE)
[![Shellcheck](https://img.shields.io/badge/shellcheck-clean-brightgreen)](https://www.shellcheck.net/)

</div>

---

## What this is

RedCell installs pentest tooling on Arch/Omarchy using BlackArch as one
of its sources. It adds a category picker in Omarchy's own visual style,
a Kali-style menu structure, and a resolver that checks pacman, then
BlackArch, then the AUR for each tool.

- Categories match the Kali menu: Information Gathering, Web Apps,
  Password Attacks, Wireless, Exploitation, Sniffing, Post-Exploitation,
  Forensics, Reverse Engineering, Vulnerability Analysis.
- Resolver order: official repos -> BlackArch -> AUR, per tool.
- TUI built on [`gum`](https://github.com/charmbracelet/gum), themed with
  the Catppuccin palette common on Omarchy/Hyprland setups. Falls back to
  plain text if `gum` isn't installed.
- A tool failing to install is logged and skipped; the run continues.
- Idempotent: already-installed tools are skipped on re-run.
- Every install is tracked in a local ledger, so RedCell always knows
  exactly what it put on your system - and only ever touches that.
- `--update` upgrades every tool RedCell has installed, in one command.
- `--uninstall=category,category` removes RedCell-tracked tools by
  category, and nothing else.
- `--status` shows what's installed, by category, without touching
  anything.
- Every run writes a markdown report alongside the log, summarizing what
  was installed, skipped and failed.
- `--dry-run` simulates a full run without changing anything.

---

## Install

```bash
git clone https://github.com/the-curious-2025/omarchy-redcell.git
cd omarchy-redcell
./install.sh
```

You'll be walked through:

1. Optional install of `gum` (for the full visual experience).
2. Optional enabling of the BlackArch repo (one line added to `pacman.conf`,
   via BlackArch's own official `strap.sh`).
3. Optional bootstrap of an AUR helper (`paru`) if you don't already have
   `paru` or `yay`.
4. A category picker - space to toggle, enter to confirm.
5. A live install run with a progress bar, then a summary.

Nothing here needs to be run as root. RedCell calls `sudo` itself, only for
the commands that actually need it.

---

## Usage

```text
Usage: install.sh [options]

Options:
  --categories=a,b,c   Install these categories non-interactively.
                        Valid ids: exploitation,forensics,password,postexploit,
                        recon,reversing,sniffing,vuln,web,wireless
  --update              Upgrade every tool RedCell has installed.
  --uninstall=a,b,c     Remove RedCell-tracked tools in these categories.
  --status              Show what RedCell has installed, by category.
  --list                List every tool in every category, then exit.
  --dry-run             Simulate the run without changing anything.
  --yes                 Skip confirmation prompts.
  --help                Show this help and exit.
  --version             Show version and exit.
```

**Examples**

```bash
# Interactive picker (recommended for the first run)
./install.sh

# Just the web + password categories, no prompts - good for scripting
./install.sh --yes --categories=web,password

# See what RedCell has already installed
./install.sh --status

# Upgrade everything RedCell has installed, in one command
./install.sh --update

# Remove everything RedCell installed under wireless and password
./install.sh --uninstall=wireless,password

# See every tool RedCell knows about without installing anything
./install.sh --list

# Preview a full run with zero side effects
./install.sh --dry-run
```

---

## Managing installed tools

RedCell keeps a ledger of exactly what it installed and how (pacman,
BlackArch or AUR), at `~/.local/state/redcell/installed.tsv`. It never
touches a package it didn't install itself.

- **`--status`** - a per-category breakdown of what's tracked.
- **`--update`** - re-syncs and upgrades every tracked tool: a plain
  `pacman -S --needed` pass for pacman/BlackArch packages, and a rebuild
  pass through your AUR helper for AUR packages.
- **`--uninstall=category,category`** - removes only the tracked tools in
  the categories you name, then drops them from the ledger. Everything
  else on your system is left alone.

Every run - install, update or uninstall - also writes a markdown report
next to its log, at `logs/redcell-<run-id>-report.md`.

---

## How resolution works

For every tool in the categories you picked, RedCell tries, in order:

| Step | Source          | What happens                                           |
|------|-----------------|---------------------------------------------------------|
| 1    | Already installed | Skipped instantly.                                    |
| 2    | Official Arch repos | `pacman -S <tool>`                                   |
| 3    | BlackArch        | Same `pacman -S` call - enabling the repo is what widens what `pacman` can see. |
| 4    | AUR              | Installed via your detected AUR helper (`paru`/`yay`). |
| 5    | Nowhere          | Logged as failed with a reason. The run continues.     |

Nothing is ever silently skipped - the end-of-run summary and the log file
(`logs/redcell-<timestamp>.log`) account for every tool.

---

## Categories

<details>
<summary><strong>Information Gathering</strong> - nmap, whois, dnsenum, theHarvester, amass, dnsrecon, fierce, recon-ng, sublist3r, masscan</summary>

See <a href="data/categories/recon.txt">data/categories/recon.txt</a>.
</details>

<details>
<summary><strong>Vulnerability Analysis</strong> - nikto, lynis, nuclei, legion</summary>

See <a href="data/categories/vuln.txt">data/categories/vuln.txt</a>.
</details>

<details>
<summary><strong>Web Application Analysis</strong> - Burp Suite, sqlmap, gobuster, ffuf, wpscan, ZAP, wfuzz, whatweb</summary>

See <a href="data/categories/web.txt">data/categories/web.txt</a>.
</details>

<details>
<summary><strong>Password Attacks</strong> - hashcat, John the Ripper, Hydra, crunch, CeWL, Medusa, SecLists</summary>

See <a href="data/categories/password.txt">data/categories/password.txt</a>.
</details>

<details>
<summary><strong>Wireless Attacks</strong> - aircrack-ng, Reaver, Wifite, Kismet, Bully, hcxtools</summary>

See <a href="data/categories/wireless.txt">data/categories/wireless.txt</a>.
</details>

<details>
<summary><strong>Exploitation Tools</strong> - Metasploit, ExploitDB, SET, sqlmap, MSFPC</summary>

See <a href="data/categories/exploitation.txt">data/categories/exploitation.txt</a>.
</details>

<details>
<summary><strong>Sniffing & Spoofing</strong> - Wireshark, tcpdump, Ettercap, Bettercap, mitmproxy, macchanger</summary>

See <a href="data/categories/sniffing.txt">data/categories/sniffing.txt</a>.
</details>

<details>
<summary><strong>Post-Exploitation</strong> - CrackMapExec, Responder, evil-winrm, Chisel</summary>

See <a href="data/categories/postexploit.txt">data/categories/postexploit.txt</a>.
</details>

<details>
<summary><strong>Digital Forensics</strong> - Autopsy, Sleuth Kit, binwalk, foremost, Volatility 3</summary>

See <a href="data/categories/forensics.txt">data/categories/forensics.txt</a>.
</details>

<details>
<summary><strong>Reverse Engineering</strong> - Ghidra, radare2, gdb, apktool, Cutter</summary>

See <a href="data/categories/reversing.txt">data/categories/reversing.txt</a>.
</details>

Want a tool that isn't listed? Add a `package|description` line to the
matching file in `data/categories/` and open a PR - no code changes needed.

---

## Project layout

```
install.sh                 entry point
lib/
  ui.sh                    gum-based presentation layer
  resolver.sh              pacman -> BlackArch -> AUR resolution
  categories.sh            category registry
  state.sh                 install ledger (for --update / --uninstall / --status)
data/categories/*.txt      one file per category, package|description
assets/banner.txt          ASCII banner
```

---

## Disclaimer

RedCell installs publicly available, legitimate security tooling - the same
packages BlackArch and Kali ship. It performs no exploitation itself. Use
these tools only against systems you own or are explicitly authorized to
test. You are responsible for complying with the laws that apply to you.

---

## License

[MIT](LICENSE) - see the file for details.

See [CHANGELOG.md](CHANGELOG.md) for release history.
