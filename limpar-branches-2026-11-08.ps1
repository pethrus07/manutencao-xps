# Limpa os branches que já estão no main (conferido com `git cherry` em 08/11/2026) e arquiva em TAG
# os que guardam trabalho antigo, antes de apagar. Nada se perde: tag aponta para o mesmo commit.
#   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\Users\olive\Projetos\manutencao-xps\limpar-branches-2026-11-08.ps1
$ErrorActionPreference = "Continue"
$P = "C:\Users\olive\Projetos"

# 1) revisao-2026-11: conteúdo todo no main (as 8 pastas deram só "-" no git cherry; pethrus07 tinha um
#    rascunho de README já substituído pelo perfil novo)
foreach ($r in "bailado-da-sanfona","commagente","jms-refrigeracao","liturgia-horas","minidrive-desbravando-utv","expertwork","pethrus07","instituto-automacao") {
  Push-Location "$P\$r"
  git branch -D revisao-2026-11 2>$null | Out-Null
  git push origin --delete revisao-2026-11 2>$null | Out-Null
  git fetch --prune -q
  Write-Host ("{0}: {1} branch(es) revisao restantes" -f $r, ((git branch -a) -match "revisao").Count)
  Pop-Location
}

# 2) eventos: os dois branches de 14/10 (fonte recuperado + economia interna) viram tags de arquivo
Push-Location "$P\eventos-desbravando-utv"
foreach ($b in "trabalho-14-10","historico-interno-14-10") {
  git tag -f "arquivo/$b-2026-11-08" $b | Out-Null
  git push -q origin "arquivo/$b-2026-11-08"
  git branch -D $b | Out-Null
  git push origin --delete $b 2>$null | Out-Null
  Write-Host "eventos: $b arquivado em tag arquivo/$b-2026-11-08"
}
Pop-Location

# 3) lead-lakehouse: refactor/v1-multi-fonte é anterior ao main (só docs de 29/10 ficaram diferentes)
Push-Location "$P\lead-lakehouse"
git tag -f "arquivo/refactor-v1-multi-fonte-2026-11-08" refactor/v1-multi-fonte | Out-Null
git push -q origin "arquivo/refactor-v1-multi-fonte-2026-11-08"
git branch -D refactor/v1-multi-fonte | Out-Null
git push origin --delete refactor/v1-multi-fonte 2>$null | Out-Null
Write-Host "lead-lakehouse: branch arquivado em tag"
Pop-Location

# 4) atas (Ágora): v2.1-analises é resto, o conteúdo já está no main desde 06/10 (conferido em 09/11)
Push-Location "$P\atas"
git tag -f "arquivo/v2.1-analises-2026-11-09" v2.1-analises | Out-Null
git push -q origin "arquivo/v2.1-analises-2026-11-09"
git branch -D v2.1-analises | Out-Null
git push origin --delete v2.1-analises 2>$null | Out-Null
Write-Host "atas: v2.1-analises arquivado em tag"
Pop-Location

Write-Host "`nPronto. Para desfazer qualquer um: git checkout -b <nome> <tag>." -ForegroundColor Green
