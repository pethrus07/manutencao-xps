# Tarefas agendadas do XPS (inventário)

Levantado em 01/11/2026 com `Get-ScheduledTask` e `Get-ScheduledTaskInfo` (só leitura; nada foi mudado).
Atualize esta página sempre que criar, mudar ou apagar uma tarefa.

Para conferir de novo:

```powershell
Get-ScheduledTask -TaskPath '\' | ForEach-Object { $i = $_ | Get-ScheduledTaskInfo
  '{0,-40} {1,-8} última {2:dd/MM HH:mm} (0x{3:X})  próxima {4:dd/MM HH:mm}' -f $_.TaskName, $_.State, $i.LastRunTime, $i.LastTaskResult, $i.NextRunTime }
```

Pausar uma tarefa sem apagar: `Disable-ScheduledTask -TaskName '<nome>'` (volta com `Enable-ScheduledTask`).

## As do Pedro

Todas rodam escondidas (sem piscar janela) por um `rodar-escondido.vbs`, sem admin, como o usuário `olive`.

| Tarefa | O que faz | Quando roda | Dono (projeto) | Último resultado (01/11) | Desligar se... |
|---|---|---|---|---|---|
| `Hermes-Ciclo` | Lê o 99Freelas logado, avalia, precifica e prepara propostas. Nunca envia. | A cada 30 min, 08:00 a 22:00 (29 por dia), até 3 min de atraso | `~/Projetos/hermes` (`agendar/instalar-tarefas.ps1`) | 0x0 | o critério de corte bater (30/11/2026, 20 envios curtos sem fechamento) ou a conta do 99Freelas receber aviso. Pausa normal: botão Pausar no painel (cria `dados/PARAR`) |
| `Hermes-Vigia` | Confere respostas, aceites e o saldo de conexões, e avisa. | A cada 2 h, o dia todo | `~/Projetos/hermes` | 0x0 | o Hermes for desligado. Pausa: painel › Mais (cria `dados/PARAR-VIGIA`) |
| `Cosmos-Dados` | Commits, notas do Sinapse e propostas do Hermes do dia viram estrelas no papel de parede. | A cada 10 min | `~/Projetos/cosmos` (`agendar/`) | 0x0 | o papel de parede Cosmos sair do Lively, ou para economizar bateria fora da tomada |
| `Cosmos-Spotify` | Atualiza as capas do papel de parede pelo Spotify (mais ouvidos e recentes). Só leitura. | A cada 3 h | `~/Projetos/cosmos` | 0x0 | o Cosmos sair do ar ou o token do Spotify for revogado |
| `Instituto Automacao - Redacao do dia` | Escreve, confere e publica as notícias do Instituto Automação. | Todo dia 07:30 e 15:30 | `~/Projetos/_redacao-instituto` (`redacao-local.ps1`; regras em `docs/REDACAO.md` do Instituto) | 0x0 (falhou em 31/10 e na manhã de 01/11 com o notebook desligado) | o site do Instituto parar de publicar notícia, ou a redação mudar para um servidor |
| `QA-Radar-Diario` | Captura diária da série de QA da Parresia (`rotina.py daily`). Só leitura no ClickUp. | Seg a sex, 08:47 | `~/Projetos/qa-parresia` (trabalho) | 0x0 (30/10) | a série de QA deixar de ser usada. A memória diz "rotinas pausadas" desde 03/09, mas esta segue rodando: decidir |
| `Sinapse-Diario-Semanal` | Gera o resumo da semana do Sinapse (`01-DIARIO/semana-AAAA-Wnn.md`) de commits, atas e prazos, sem IA; commit e push só desse arquivo. | Domingo 21:00; no logon só se a de domingo falhou | `~/Projetos/sinapse` (`scripts/diario-semana.py`) | 0x0 | o diário semanal deixar de ser lido |
| `MicPin100` | Mantém o volume do microfone em 100% (impede o controle automático de Teams, Meet e Opera de baixar). | No logon | `%LOCALAPPDATA%\mic-pin` (memória "Mic sem processamento") | 0x0 | trocar de microfone ou o Windows ganhar um jeito nativo de travar o volume |
| `NoSQL-Desafio-GeoLog` | Lembrete de 13/09/2026: Desafio GeoLog e atividades de NoSQL. | Uma vez, 13/09/2026 09:00 (já passou) | `~/Projetos/faculdade/nosql-persistencia` | 0x0 | já pode apagar: a disciplina foi entregue em 30/09 |

### Ajuste pendente: Hermes-Ciclo

A revisão de 01/11/2026 deixou no branch `revisao-2026-11` do Hermes a agenda nova: a cada 2 h, 08:00 a
20:00 (7 ciclos por dia em vez de 29), com até 10 min de atraso. O Agendador só muda quando o Pedro mandar.
Depois do merge no `main` do Hermes:

```powershell
pwsh -NoProfile -File C:\Users\olive\Projetos\hermes\agendar\instalar-tarefas.ps1
```

O script lê o `config.json`, recria `Hermes-Ciclo` e `Hermes-Vigia` com `-Force` e mostra a próxima execução.

## De terceiros (instaladas por programas)

Ficam aqui só para saber o que é. Não são do Pedro.

| Tarefa | De quem | Quando | Observação |
|---|---|---|---|
| `Dell SupportAssistAgent AutoUpdate` | Dell | Sábado, 17:49 | último resultado 0x80070002 (arquivo não encontrado): o instalador sumiu. Pode desligar se o SupportAssist foi removido |
| `NVIDIA App SelfUpdate_{...}` | NVIDIA | Por evento | nunca rodou (0x41303) |
| `OneDrive Per-Machine Standalone Update Task` | Microsoft | Diário | último resultado 0x8004EE04 |
| `OneDrive Reporting Task-<SID>` | Microsoft | Diário | |
| `OneDrive Startup Task-<SID>` | Microsoft | No logon | |
| `Opera GX scheduled Autoupdate ...` | Opera | Diário 09:02 e no logon | |
| `Opera GX scheduled assistant Autoupdate ...` | Opera | Diário 09:02 e no logon | |
| `\PowerToys\Autorun for olive` | Microsoft PowerToys | No logon | |
| `\SoftLanding\<SID>\SoftLandingCreativeManagementTask` | Windows (dicas e conteúdo) | Diário | |

## Duas cópias do `rodar-escondido.vbs`

Redação do Instituto, QA-Radar e Sinapse usam o `rodar-escondido.vbs` desta pasta (`esconder-janelas-tarefas.ps1`).
Hermes e Cosmos têm o seu, dentro de cada repositório (`agendar/rodar-escondido.vbs`). Mover ou apagar esta pasta
quebra as três primeiras.
