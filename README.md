# Manutenção do XPS 15 9510

Scripts gerados na limpeza de **07/09/2026**. Cada um pede UAC sozinho e grava um `log-*.txt` nesta pasta.

| Script | O que faz | Rodar quando |
|---|---|---|
| `1-limpeza-admin.ps1` | Recria o `hiberfil.sys` e desliga o Fast Startup (correção dos "desligamentos inesperados"); Limpeza de Disco do Windows nas categorias seguras (logs de upgrade, relatórios de erro, temporários do sistema, cache do Windows Update, drivers antigos); `DISM StartComponentCleanup`; TRIM; 13 atualizações seguras via winget. **Só usa ferramentas do próprio Windows e não toca em arquivo seu.** | Agora. Leva 10 a 25 min. |
| `2-remocoes-opcionais.ps1` | Menu S/N item a item: bloatware Dell, Killer Control Center, apps de loja da Microsoft, instalador do RDR2 em Downloads (91,6 GB), uTorrent Web, cache de shaders NVIDIA, cache do Opera GX, WebStorage do VS Code, compactar disco do Docker. **Nada roda sem você responder S.** | Quando tiver 10 min para decidir. |

## Depois de rodar o 1

1. Teste a hibernação: Iniciar > Desligar > **Hibernar** (ou `shutdown /h`). Ao ligar, as janelas têm que voltar.
2. Se voltar como boot frio de novo: `powercfg /h off` (ganha 12,7 GB) e atualize **BIOS + Intel RST** no site da Dell. A causa provável é o controlador Intel VMD (o disco aparece como `BusType RAID`).
3. Apague manualmente a pasta `C:\Drivers` (1,2 GB): são os pacotes de driver de fábrica de 2021, já instalados.

## Ainda pendente, fora dos scripts

- Bumpar `commagente/e2e` para Playwright 1.62 e apagar `chromium-1228` + `chromium_headless_shell-1228` (685 MB).
- Driver Wi-Fi Killer AX1650s com 15 erros internos em 14 dias: atualizar pelo Intel Driver & Support Assistant.
- Windows Update tem um driver Realtek pendente: ao instalar, conferir se o mic voltou a ter processamento (Waves APO) e refazer o `Disable_SysFx` se precisar.
- Docker Desktop 4.83 → 4.90 e PowerShell 7.4 → 7.6: atualizar à mão, com containers parados e o VS Code fechado.
