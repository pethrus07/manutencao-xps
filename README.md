# Manutenção do XPS 15 9510

Scripts gerados na limpeza de **07/09/2026**. Cada um pede UAC sozinho e grava um `log-*.txt` nesta pasta.

| Script | O que faz | Rodar quando |
|---|---|---|
| `1-limpeza-admin.ps1` | Ponto de restauração; recria o `hiberfil.sys` e desliga o Fast Startup (correção dos "desligamentos inesperados"); **pergunta** se suspende o BitLocker por 1 reinício para relacrar a chave no TPM (só depois de você confirmar a chave de recuperação); liga e sincroniza o relógio (NTP.br); Limpeza de Disco do Windows nas categorias seguras; `DISM StartComponentCleanup`; TRIM; ~20 atualizações seguras via winget (pula Git/Node/Python se o VS Code estiver aberto e o Docker se estiver rodando); drivers Dell, incluindo o Intel RST. Resumo final lido do sistema. **Só usa ferramentas do próprio Windows e não toca em arquivo seu.** Revisto em 19/10/2026. | Na tomada, VS Code fechado. 15 a 30 min, e reiniciar no fim. |
| `1-limpeza-admin.ps1 -DesligarHibernacao` | Plano B: desliga a hibernação de vez (ganha 12,7 GB) e troca a ação de bateria crítica de Hibernar para Desligar. | Só se o teste do `shutdown /h` falhar depois do reinício. |
| `esconder-janelas-tarefas.ps1` + `rodar-escondido.vbs` | Faz as tarefas agendadas (QA-Radar, Sinapse, Redação do Instituto) rodarem sem piscar cmd: o `.vbs` roda o comando com o console escondido, espera e devolve o código de saída ao Agendador. `-Desfazer` volta ao original. Sem admin. **Aplicado em 19/10/2026.** | Já aplicado. Rodar de novo se recriar alguma dessas tarefas. |
| `2-remocoes-opcionais.ps1` | Menu S/N item a item: bloatware Dell, Killer Control Center, apps de loja da Microsoft, instalador do RDR2 em Downloads (91,6 GB), uTorrent Web, cache de shaders NVIDIA, cache do Opera GX, WebStorage do VS Code, compactar disco do Docker. **Nada roda sem você responder S.** | Quando tiver 10 min para decidir. |
| `3-powershell-76.ps1` | Atualiza o PowerShell 7.4 (suporte acaba em **10/11/2026**) para o **7.6 LTS** pelo MSI do winget, no mesmo `C:\Program Files\PowerShell\7`, e confere versão, PATH e PSReadLine depois. Roda no Windows PowerShell 5.1 (o pwsh 7 não pode estar aberto). | Com o **VS Code fechado** e nenhuma janela do PowerShell 7 aberta. 2 a 5 min. |

## Depois de rodar o 1

1. **Reinicie.** Drivers e o relacre do BitLocker entram nesse reinício.
2. Teste a hibernação: abra umas janelas e rode `shutdown /h`. Ao ligar, as janelas têm que voltar.
3. Se voltar como boot frio de novo: `1-limpeza-admin.ps1 -DesligarHibernacao`. O BIOS 1.48 (15/10) já não resolveu; as suspeitas são o Intel RST/VMD de 2022 (o disco aparece como `BusType RAID`) e a chave do BitLocker que não sai do TPM na retomada (erro 24641).
3. Apague manualmente a pasta `C:\Drivers` (1,2 GB): são os pacotes de driver de fábrica de 2021, já instalados.

## Ainda pendente, fora dos scripts

- Bumpar `commagente/e2e` para Playwright 1.62 e apagar `chromium-1228` + `chromium_headless_shell-1228` (685 MB).
- Driver Wi-Fi Killer AX1650s com 15 erros internos em 14 dias: atualizar pelo Intel Driver & Support Assistant.
- Windows Update tem um driver Realtek pendente: ao instalar, conferir se o mic voltou a ter processamento (Waves APO) e refazer o `Disable_SysFx` se precisar.
- Docker Desktop 4.83 → 4.90: atualizar à mão, com containers parados. (PowerShell 7.6: ver `3-powershell-76.ps1`.)

## Bateria (medida em 01/11/2026)
`powercfg /batteryreport`: projeto **84.292 mWh**, carga cheia hoje **46.808 mWh**, ou seja **55,5%** de
saúde. Fabricante BYD, modelo DELL M59JH18 (a de 86 Wh, 6 células).
- **Saúde perdida não volta.** Calibrar, descarregar até zero ou "resetar" não recupera capacidade: só
  muda o que o medidor mostra.
- **O conserto é trocar a bateria.** Códigos da peça original: **M59JH / 8FCTC / 69KF2 / 70N2F** (86 Wh,
  11,4 V). Lá fora sai por volta de US$ 60–100; no Brasil, procurar por "M59JH" ou "8FCTC" e conferir se é
  original. "69KF2" aparece muito em paralela. A troca é por baixo (tampa com parafusos Torx); fazer
  com o notebook desligado e a bateria desconectada antes de mexer em qualquer coisa.
- **O que protege a bateria (atual e a próxima):** o notebook vive na tomada, e ficar em 100% o tempo
  todo é o que mais envelhece. No BIOS (F2 ao ligar) → *Power* → *Battery Charge Configuration* →
  **Custom, iniciar em 50% e parar em 80%** (ou *Primarily AC use*). Não precisa de programa nenhum.

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
