# Publica as revisões de 01/11/2026 que já estão no main (juntadas e testadas em 04/11) e
# reagenda o Hermes. Rodar no PowerShell 7 (pwsh), fora do VS Code:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\Users\olive\Projetos\manutencao-xps\publicar-revisoes-2026-11.ps1
#
# Eventos vai por último, com pausa para testar o staging antes da produção.
# Fica de fora de propósito: Expert Work (quem publica é o Valdir), Commagente
# (VPS fora do ar), Maryhouse (não roda em servidor) e Liturgia (rotina da CNBB, decisão sua).
$ErrorActionPreference = "Stop"
$P  = "C:\Users\olive\Projetos"
$cf = "$P\manutencao-xps\cf.ps1"

function Passo($titulo) { Write-Host "`n=== $titulo" -ForegroundColor Cyan }
function Status($url, $esperado) {
  try { $c = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -SkipHttpErrorCheck).StatusCode }
  catch { $c = "erro: $($_.Exception.Message)" }
  $ok = "$c" -eq "$esperado"
  Write-Host ("  {0} {1} -> {2} (esperado {3})" -f ($(if ($ok) { "OK " } else { "XX " })), $url, $c, $esperado) `
    -ForegroundColor $(if ($ok) { "Green" } else { "Red" })
}

Passo "1/5 Mini Drive (conta Desbravando): chave só no cabeçalho e CORS só para o Estúdio"
Push-Location "$P\minidrive-desbravando-utv"; & $cf usar ryze npx wrangler deploy; Pop-Location
Status "https://minidrive.desbravando-utv.workers.dev/" 200
Status "https://minidrive.desbravando-utv.workers.dev/list" 401

Passo "2/5 JMS (conta RYZE): endereço novo, sem o nome de outro cliente. O antigo segue no ar."
Push-Location "$P\jms-refrigeracao"; & $cf usar pessoal npx wrangler deploy; Pop-Location
Status "https://jms-refrigeracao.ryzecode.workers.dev/" 200

Passo "3/5 Bailado (prévia, conta RYZE): canônica e noindex"
Push-Location "$P\bailado-da-sanfona"; & $cf usar pessoal npx wrangler deploy --env staging; Pop-Location

Passo "4/5 Hermes: tarefas com a regra nova (7 ciclos por dia, das 8h às 20h)"
& "$P\hermes\agendar\instalar-tarefas.ps1"
Get-ScheduledTask -TaskName Hermes-Ciclo | Get-ScheduledTaskInfo | ForEach-Object { "  próximo ciclo: $($_.NextRunTime)" }

Passo "5/5 Eventos (conta Desbravando): revisão de segurança + o que estava só no ar desde 21/10"
Push-Location "$P\eventos-desbravando-utv"
git checkout -q main; git pull -q --ff-only
npm test; if ($LASTEXITCODE) { throw "testes do Eventos falharam" }
npm run travas; if ($LASTEXITCODE) { throw "travas do Eventos falharam" }
& $cf usar ryze npx wrangler deploy --env staging
Write-Host "  Teste agora o staging: abrir a tela, entrar, abrir um anexo e a aba Comunicação." -ForegroundColor Yellow
Write-Host "`n  Versão ativa na produção (tem de ser 9ff53cdf, a de 21/10):"
& $cf usar ryze npx wrangler deployments list | Select-String "\(100%\)" | Select-Object -Last 1
Write-Host "`n  Usuários sem perfil (entre 15 e 21/10 não conseguiam entrar; com esta versão voltam a entrar):"
& $cf usar ryze npx wrangler d1 execute eventos --remote --command "SELECT COUNT(*) AS sem_perfil FROM usuarios WHERE perfil_id IS NULL"
$r = Read-Host "`n  Staging certo e versão ativa 9ff53cdf? Digite PUBLICAR para seguir (qualquer outra coisa para)"
if ($r -eq "PUBLICAR") {
  $bkp = "$P\..\Arquivo-projetos\eventos-desbravando-utv\backup-antes-revisao-2026-11-04.sql"
  & $cf usar ryze npx wrangler d1 export eventos --remote --output $bkp
  if (-not (Test-Path $bkp) -or (Get-Item $bkp).Length -lt 1000) { throw "backup não saiu; nada publicado" }
  Write-Host "  backup: $bkp ($([math]::Round((Get-Item $bkp).Length/1KB)) KB)"
  & $cf usar ryze npx wrangler deploy
  Status "https://eventos.desbravando-utv.workers.dev/" 200
  Write-Host "  Se algo der errado: npx wrangler rollback (volta para a de 21/10)." -ForegroundColor Yellow
} else { Write-Host "  Eventos NÃO publicado." -ForegroundColor Yellow }
Pop-Location

Write-Host "`nPronto. O Instituto publica sozinho pelo GitHub Actions." -ForegroundColor Green
