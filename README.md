# Manutenção do XPS 15 9510

Scripts gerados na limpeza de **07/09/2026**. Cada um pede UAC sozinho e grava um `log-*.txt` nesta pasta.

| Script | O que faz | Rodar quando |
|---|---|---|
| `1-limpeza-admin.ps1` | Recria o `hiberfil.sys` e desliga o Fast Startup (correção dos "desligamentos inesperados"); Limpeza de Disco do Windows nas categorias seguras (logs de upgrade, relatórios de erro, temporários do sistema, cache do Windows Update, drivers antigos); `DISM StartComponentCleanup`; TRIM; 13 atualizações seguras via winget. **Só usa ferramentas do próprio Windows e não toca em arquivo seu.** | Agora. Leva 10 a 25 min. |
| `2-remocoes-opcionais.ps1` | Menu S/N item a item: bloatware Dell, Killer Control Center, apps de loja da Microsoft, instalador do RDR2 em Downloads (91,6 GB), uTorrent Web, cache de shaders NVIDIA, cache do Opera GX, WebStorage do VS Code, compactar disco do Docker. **Nada roda sem você responder S.** | Quando tiver 10 min para decidir. |
| `3-powershell-76.ps1` | Atualiza o PowerShell 7.4 (suporte acaba em **10/11/2026**) para o **7.6 LTS** pelo MSI do winget, no mesmo `C:\Program Files\PowerShell\7`, e confere versão, PATH e PSReadLine depois. Roda no Windows PowerShell 5.1 (o pwsh 7 não pode estar aberto). | Com o **VS Code fechado** e nenhuma janela do PowerShell 7 aberta. 2 a 5 min. |

## Depois de rodar o 1

1. Teste a hibernação: Iniciar > Desligar > **Hibernar** (ou `shutdown /h`). Ao ligar, as janelas têm que voltar.
2. Se voltar como boot frio de novo: `powercfg /h off` (ganha 12,7 GB) e atualize **BIOS + Intel RST** no site da Dell. A causa provável é o controlador Intel VMD (o disco aparece como `BusType RAID`).
3. Apague manualmente a pasta `C:\Drivers` (1,2 GB): são os pacotes de driver de fábrica de 2021, já instalados.

## Ainda pendente, fora dos scripts

- Bumpar `commagente/e2e` para Playwright 1.62 e apagar `chromium-1228` + `chromium_headless_shell-1228` (685 MB).
- Driver Wi-Fi Killer AX1650s com 15 erros internos em 14 dias: atualizar pelo Intel Driver & Support Assistant.
- Windows Update tem um driver Realtek pendente: ao instalar, conferir se o mic voltou a ter processamento (Waves APO) e refazer o `Disable_SysFx` se precisar.
- Docker Desktop 4.83 → 4.90: atualizar à mão, com containers parados. (PowerShell 7.6: ver `3-powershell-76.ps1`.)

## Backup externo (preparado em 14/10/2026, sem admin)

Pasta `backup/`: backup diário com **restic** para o **Cloudflare R2** (conta pessoal) de `Projetos`
(inclui o cofre DÜ SOL), `.claude` (histórico de sessões e memória) e o hook de segredos. Credenciais vêm
do 1Password e ficam no Gerenciador de Credenciais do Windows, nunca em arquivo. **Falta você:** criar o
bucket `backup-xps` e o token R2, guardar no 1Password e rodar `backup\configurar-backup.ps1`.
Passo a passo, custo (~US$ 0,60–1,35/mês para 50–100 GB; 10 GB grátis) e teste de restauração em
[`backup/README.md`](backup/README.md).

## Hook global de segredos (gitleaks, 14/10/2026)

- `gitleaks` 8.30.1 instalado por usuário (`winget install --id Gitleaks.Gitleaks --scope user`).
- `git config --global core.hooksPath C:/Users/olive/.git-hooks`. O `pre-commit` de lá roda
  `gitleaks git --pre-commit --staged --redact` e, se passar, **encadeia** o hook local do repo
  (`.git/hooks/pre-commit` e `.githooks/pre-commit`). Os outros nomes de hook (commit-msg, pre-push,
  post-checkout…) só encadeiam — sem isso o hooksPath global desligaria os `.git/hooks` de todos os repos.
- Config: `~/.gitleaks.toml` = regras padrão + allowlist mínima (sitekey de reCAPTCHA, `fileToken` de `.pen`).
  Repo com `.gitleaks.toml` próprio usa o dele. Falso positivo pontual: `gitleaks:allow` na linha ou o
  fingerprint em `.gitleaksignore`. **Nunca `--no-verify`.**
- Repo com `core.hooksPath` **local** não passa pelo global: hoje só o `sinapse` (`.githooks`), onde o
  gitleaks **não** roda até alguém decidir (ver a pendência no relatório de 14/10).
