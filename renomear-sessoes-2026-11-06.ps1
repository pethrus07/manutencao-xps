# Renomeia sessões do Claude Code no padrão "[origem] tema" (06/11/2026).
# Acrescenta uma linha custom-title no fim de cada .jsonl; não apaga nem altera nada do que já existe.
# Rodar com a sessão fechada ou não, tanto faz; o título novo aparece ao recarregar a lista.
#   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\Users\olive\Projetos\manutencao-xps\renomear-sessoes-2026-11-06.ps1
$pool = "C:\Users\olive\.claude\projects\C--Users-olive"
$titulos = [ordered]@{
  "882197a8" = "[planejamento] Nov/2026: Retífica, captação, Métis, Aion, GitHub e retrato aos 20"
  "a1c9b5cb" = "[faculdade] Itinerário Extensionista: backend do Conecta+"
  "510e4eab" = "[faculdade] Perícia Forense: práticas forenses (aula 05)"
  "2e6f9f35" = "[faculdade] APS: projeto final Rufus Bank"
}
foreach ($id in $titulos.Keys) {
  $arq = Get-ChildItem $pool -Filter "$id*.jsonl" | Select-Object -First 1
  if (-not $arq) { Write-Host "não achei a sessão $id" -ForegroundColor Yellow; continue }
  $sessao = [IO.Path]::GetFileNameWithoutExtension($arq.Name)
  $linha = @{ type = "custom-title"; customTitle = $titulos[$id]; sessionId = $sessao } | ConvertTo-Json -Compress
  Add-Content -LiteralPath $arq.FullName -Value $linha -Encoding utf8NoBOM
  Write-Host "ok  $id  ->  $($titulos[$id])" -ForegroundColor Green
}
