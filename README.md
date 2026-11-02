# XPS 15 9510 maintenance

English · [Português](README.pt-BR.md)

Maintenance scripts for a Dell XPS 15 9510 laptop running Windows 11, and a record of what was measured on it.
Status: in use (2026-11). No system, no diagram. License: MIT, see [LICENSE](LICENSE).

Scheduled task inventory (what each one does, when, owner, when to turn it off):
[TAREFAS-AGENDADAS.md](TAREFAS-AGENDADAS.md) (Portuguese).

Scripts written during the clean-up of **2026-09-07**. Each one asks for UAC by itself and writes a `log-*.txt`
in this folder.

| Script | What it does | Run when |
|---|---|---|
| `1-limpeza-admin.ps1` | Restore point; rebuilds `hiberfil.sys` and turns off Fast Startup (fix for the "unexpected shutdowns"); **asks** whether to suspend BitLocker for 1 reboot so the key is resealed in the TPM (only after you confirm the recovery key); turns on and syncs the clock (NTP.br); Windows Disk Cleanup on the safe categories; `DISM StartComponentCleanup`; TRIM; ~20 safe updates via winget (skips Git/Node/Python if VS Code is open and Docker if it is running); Dell drivers, including Intel RST. Final summary read from the system. **Only uses Windows' own tools and does not touch your files.** Reviewed on 2026-10-19. | Plugged in, VS Code closed. 15 to 30 min, then reboot. |
| `1-limpeza-admin.ps1 -DesligarHibernacao` | Plan B: turns hibernation off for good (frees 12.7 GB) and changes the critical battery action from Hibernate to Shut down. | Only if the `shutdown /h` test fails after the reboot. |
| `esconder-janelas-tarefas.ps1` + `rodar-escondido.vbs` | Makes the scheduled tasks (QA-Radar, Sinapse, Instituto newsroom) run without flashing a console: the `.vbs` runs the command with the console hidden, waits, and returns the exit code to the Task Scheduler. `-Desfazer` restores the original. No admin. **Applied on 2026-10-19.** | Already applied. Run again if one of those tasks is recreated. |
| `2-remocoes-opcionais.ps1` | Item-by-item Y/N menu: Dell bloatware, Killer Control Center, Microsoft Store apps, the RDR2 installer in Downloads (91.6 GB), uTorrent Web, NVIDIA shader cache, Opera GX cache, VS Code WebStorage, compacting the Docker disk. **Nothing runs unless you answer Y.** | When you have 10 min to decide. |
| `3-powershell-76.ps1` | Upgrades PowerShell 7.4 (support ends on **2026-11-10**) to **7.6 LTS** with the winget MSI, in the same `C:\Program Files\PowerShell\7`, then checks version, PATH and PSReadLine. Runs in Windows PowerShell 5.1 (pwsh 7 cannot be open). | With **VS Code closed** and no PowerShell 7 window open. 2 to 5 min. |

## After running script 1

1. **Reboot.** Drivers and the BitLocker reseal happen on that reboot.
2. Test hibernation: open a few windows and run `shutdown /h`. When it powers on, the windows must come back.
3. If it comes back as a cold boot again: `1-limpeza-admin.ps1 -DesligarHibernacao`. BIOS 1.48 (2026-10-15) did not fix
   it; the suspects are the 2022 Intel RST/VMD driver (the disk shows up as `BusType RAID`) and the BitLocker key
   that does not leave the TPM on resume (error 24641).
4. Delete the `C:\Drivers` folder by hand (1.2 GB): factory driver packages from 2021, already installed.

## Still pending, outside the scripts

- Bump `commagente/e2e` to Playwright 1.62 and delete `chromium-1228` + `chromium_headless_shell-1228` (685 MB).
- Killer AX1650s Wi-Fi driver with 15 internal errors in 14 days: update through Intel Driver & Support Assistant.
- Windows Update has a pending Realtek driver: after installing it, check whether the mic got its processing back
  (Waves APO) and redo `Disable_SysFx` if needed.
- Docker Desktop 4.83 to 4.90: update by hand, with containers stopped. (PowerShell 7.6: see `3-powershell-76.ps1`.)

## Battery (measured on 2026-11-01)

`powercfg /batteryreport`: design capacity **84,292 mWh**, full charge today **46,808 mWh**, so **55.5%** health.
Maker BYD, model DELL M59JH18 (the 86 Wh, 6-cell one).
- **Lost health does not come back.** Calibrating, draining to zero or "resetting" does not recover capacity: it
  only changes what the gauge shows.
- **The fix is replacing the battery.** Original part codes: **M59JH / 8FCTC / 69KF2 / 70N2F** (86 Wh, 11.4 V).
  Abroad it costs around US$ 60 to 100; in Brazil, search for "M59JH" or "8FCTC" and check it is original. "69KF2"
  shows up a lot on third-party parts. The swap is from the bottom (cover with Torx screws); do it with the laptop
  off and the battery disconnected before touching anything else.
- **What protects the battery (this one and the next):** the laptop lives on the charger, and sitting at 100% all
  the time is what ages it most. In the BIOS (F2 at power on) > *Power* > *Battery Charge Configuration* >
  **Custom, start at 50% and stop at 80%** (or *Primarily AC use*). No software needed.

## Off-site backup (prepared on 2026-10-14, no admin)

Folder `backup/`: daily backup with **restic** to **Cloudflare R2** (personal account) of `Projetos` (including the
DÜ SOL vault), `.claude` (session history and memory) and the secrets hook. Credentials come from 1Password and
live in the Windows Credential Manager, never in a file. **Still on you:** create the `backup-xps` bucket and the R2
token, store them in 1Password and run `backup\configurar-backup.ps1`. Step by step, cost (~US$ 0.60 to 1.35 a month
for 50 to 100 GB; 10 GB free) and restore test in [`backup/README.md`](backup/README.md) (Portuguese).

## Global secrets hook (gitleaks, 2026-10-14)

- `gitleaks` 8.30.1 installed per user (`winget install --id Gitleaks.Gitleaks --scope user`).
- `git config --global core.hooksPath C:/Users/olive/.git-hooks`. The `pre-commit` there runs
  `gitleaks git --pre-commit --staged --redact` and, if it passes, **chains** the repo's local hook
  (`.git/hooks/pre-commit` and `.githooks/pre-commit`). The other hook names (commit-msg, pre-push, post-checkout...)
  only chain: without that, the global hooksPath would switch off `.git/hooks` in every repo.
- Config: `~/.gitleaks.toml` = default rules + a minimal allowlist (reCAPTCHA sitekey, `fileToken` in `.pen` files).
  A repo with its own `.gitleaks.toml` uses that one. One-off false positive: `gitleaks:allow` on the line or the
  fingerprint in `.gitleaksignore`. **Never `--no-verify`.**
- A repo with a **local** `core.hooksPath` skips the global one: today only `sinapse` (`.githooks`), where gitleaks
  does **not** run until someone decides (see the pending item in the 2026-10-14 report).
