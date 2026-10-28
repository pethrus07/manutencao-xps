# esconder-janelas-tarefas.ps1: faz as tarefas agendadas do Pedro rodarem sem piscar cmd na tela.
# Não precisa de admin (as tarefas são do usuário). Rodar de novo é seguro: só reescreve a ação.
#   pwsh -File .\esconder-janelas-tarefas.ps1            aplica
#   pwsh -File .\esconder-janelas-tarefas.ps1 -Desfazer  volta as ações originais
#
# Diagnóstico de 19/10/2026: as três disparavam juntas ~8 min depois de ligar (horário perdido +
# "rodar assim que possível") e cada uma abria janela:
#   QA-Radar-Diario        python.exe          console visível o tempo todo
#   Sinapse-Diario-Semanal pyw.exe             sem console, mas cada `git` abria um cmd (9 chamadas)
#   Instituto ... Redação  pwsh -WindowStyle Hidden  pisca antes de esconder
# Todas passam a rodar por rodar-escondido.vbs. Só a AÇÃO muda; gatilhos e configurações ficam.
param([switch]$Desfazer)

$vbs = Join-Path $PSScriptRoot 'rodar-escondido.vbs'
$py  = "$env:LOCALAPPDATA\Programs\Python"
$tarefas = @(
  @{ Nome = 'QA-Radar-Diario'
     Original = @("$py\Python314\python.exe", "$env:USERPROFILE\Projetos\qa-parresia\scripts\rotina.py daily")
     Escondido = "`"$py\Python314\python.exe`" `"$env:USERPROFILE\Projetos\qa-parresia\scripts\rotina.py`" daily" }
  @{ Nome = 'Sinapse-Diario-Semanal'
     Original = @("$py\Launcher\pyw.exe", "-X utf8 `"$env:USERPROFILE\Projetos\sinapse\scripts\diario-semana.py`" --commit --agendado")
     Escondido = "`"$py\Launcher\py.exe`" -X utf8 `"$env:USERPROFILE\Projetos\sinapse\scripts\diario-semana.py`" --commit --agendado" }
  @{ Nome = 'Instituto Automacao - Redacao do dia'
     Original = @('pwsh.exe', "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:USERPROFILE\Projetos\_redacao-instituto\redacao-local.ps1`"")
     Escondido = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$env:USERPROFILE\Projetos\_redacao-instituto\redacao-local.ps1`"" }
)

foreach ($t in $tarefas) {
  $tarefa = Get-ScheduledTask -TaskName $t.Nome -ErrorAction SilentlyContinue
  if (-not $tarefa) { Write-Host "não existe: $($t.Nome)" -ForegroundColor Yellow; continue }
  $wd = $tarefa.Actions[0].WorkingDirectory
  if ($Desfazer) {
    $acao = New-ScheduledTaskAction -Execute $t.Original[0] -Argument $t.Original[1]
  } else {
    $acao = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wscript.exe" -Argument "`"$vbs`" $($t.Escondido)"
  }
  if ($wd) { $acao.WorkingDirectory = $wd }
  Set-ScheduledTask -TaskName $t.Nome -Action $acao | Out-Null
  $a = (Get-ScheduledTask -TaskName $t.Nome).Actions[0]
  Write-Host "$($t.Nome)`n   $($a.Execute) $($a.Arguments)"
}
