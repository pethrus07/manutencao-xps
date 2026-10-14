# configurar-backup.ps1 — prepara o backup diário do XPS para o Cloudflare R2 com restic.
# NÃO precisa de admin. Rodar UMA vez (e de novo só para trocar credencial ou horário):
#     pwsh -File .\configurar-backup.ps1
#
# O que faz, em ordem:
#   1. acha o restic (winget, por usuário);
#   2. pega as credenciais no 1Password (sessão do app) e grava no Gerenciador de Credenciais
#      do Windows — se o 1Password não responder, pede para colar (entrada oculta);
#   3. confere o repositório no R2 e, se ainda não existir, cria (restic init) depois de perguntar;
#   4. cria a tarefa agendada diária "Backup XPS (restic)" para o seu usuário;
#   5. roda restic check.
# Não roda o backup em si. O primeiro backup: pwsh -File .\rodar-backup.ps1
#
# Os nomes de item do 1Password abaixo são PLACEHOLDERS: crie os itens com esses nomes
# (ou passe os seus por parâmetro). Ver README.md desta pasta.

[CmdletBinding()]
param(
    # Item tipo "Login" com a senha do repositório restic (gerada pelo 1Password, 32+ caracteres)
    [string]$RefSenhaRestic  = 'op://Pessoal/backup-xps restic/password',
    # Item tipo "Login" do token R2: usuário = Access Key ID, senha = Secret Access Key
    [string]$RefR2KeyId      = 'op://Pessoal/backup-xps R2/username',
    [string]$RefR2Secret     = 'op://Pessoal/backup-xps R2/password',
    # Account ID da conta Cloudflare pessoal (não é segredo; aparece no painel do R2)
    [string]$AccountId,
    [string]$Bucket          = 'backup-xps',
    # Horário diário (o notebook precisa estar ligado e logado; se perder, roda quando ligar)
    [string]$Horario         = '12:30',
    # Regrava as credenciais mesmo se já existirem
    [switch]$Reconfigurar,
    # Só cria/atualiza a tarefa agendada
    [switch]$SoTarefa
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_comum.ps1"
function Passo($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }

function Ler-Segredo([string]$rotulo, [string]$ref) {
    $v = Read-1Password $ref
    if ($v) { Write-Host "   $rotulo : lido do 1Password ($ref)"; return $v }
    Write-Host "   $rotulo : o 1Password não respondeu para '$ref' (app bloqueado ou item com outro nome)." -ForegroundColor Yellow
    $s = Read-Host "   Cole $rotulo (não aparece na tela)" -AsSecureString
    $v = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($s))
    if (-not $v) { throw "$rotulo vazio — abortado." }
    return $v
}

$restic = Get-Restic
Passo "1) restic"
& $restic version

if (-not $SoTarefa) {
    Passo "2) Credenciais (Gerenciador de Credenciais do Windows)"
    if ((Test-CredenciaisBackup) -and -not $Reconfigurar) {
        Write-Host "   Já configuradas. Para trocar: -Reconfigurar"
    } else {
        if (-not $AccountId) { $AccountId = Read-Host "   Account ID da conta Cloudflare pessoal (painel R2 > Overview)" }
        if ($AccountId -notmatch '^[0-9a-f]{32}$') { throw "Account ID com formato inesperado (esperado 32 caracteres hexadecimais)." }
        $repo   = "s3:https://$AccountId.r2.cloudflarestorage.com/$Bucket"
        $senha  = Ler-Segredo 'a senha do repositório restic' $RefSenhaRestic
        $keyId  = Ler-Segredo 'o Access Key ID do token R2'   $RefR2KeyId
        $secret = Ler-Segredo 'o Secret Access Key do token R2' $RefR2Secret
        [BackupXps.Cred]::Write($ALVO_RESTIC, $repo, $senha)
        [BackupXps.Cred]::Write($ALVO_R2, $keyId, $secret)
        Remove-Variable senha, keyId, secret
        Write-Host "   Gravadas: $ALVO_RESTIC e $ALVO_R2 (repositório: $repo)" -ForegroundColor Green
    }

    Passo "3) Repositório no R2"
    Set-AmbienteRestic
    try {
        & $restic cat config *> $null
        $rc = $LASTEXITCODE
        if ($rc -eq 0) {
            Write-Host "   Repositório existe e a senha abre." -ForegroundColor Green
        } elseif ($rc -eq 10) {
            Write-Host "   O repositório ainda não existe em $env:RESTIC_REPOSITORY" -ForegroundColor Yellow
            if ((Read-Host "   Criar agora (restic init)? [s/N]") -match '^[sS]') {
                & $restic init
                if ($LASTEXITCODE -ne 0) { throw "restic init falhou (rc=$LASTEXITCODE)." }
            } else { throw "Sem repositório não há backup. Rode de novo quando quiser criar." }
        } elseif ($rc -eq 12) {
            throw "A senha não abre este repositório (rc=12). Confira o item do 1Password e rode com -Reconfigurar."
        } else {
            throw "Não consegui acessar o repositório (rc=$rc). Confira bucket, Account ID e o token R2 (precisa de Object Read & Write no bucket)."
        }
    } finally { Clear-AmbienteRestic }
}

Passo "4) Tarefa agendada diária (só para o seu usuário, sem admin)"
$nome  = 'Backup XPS (restic)'
$pwsh  = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = 'powershell.exe' }
$acao  = New-ScheduledTaskAction -Execute $pwsh `
           -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\rodar-backup.ps1`"" `
           -WorkingDirectory $PSScriptRoot
$gatilho = New-ScheduledTaskTrigger -Daily -At $Horario
$config  = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable `
             -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -ExecutionTimeLimit (New-TimeSpan -Hours 6) -MultipleInstances IgnoreNew
$quem    = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $nome -Action $acao -Trigger $gatilho -Settings $config -Principal $quem `
    -Description 'Backup diário de Projetos, .claude e hooks para o Cloudflare R2 (restic). Scripts em Projetos\manutencao-xps\backup.' -Force | Out-Null
$t = Get-ScheduledTask -TaskName $nome
Write-Host "   '$nome' registrada: todo dia às $Horario (ou assim que o notebook ligar, se perdeu o horário). Estado: $($t.State)" -ForegroundColor Green

if (-not $SoTarefa) {
    Passo "5) restic check"
    Set-AmbienteRestic
    try {
        & $restic check
        if ($LASTEXITCODE -eq 0) { Write-Host "   check OK." -ForegroundColor Green }
        else { Write-Host "   check falhou (rc=$LASTEXITCODE). Não confie no backup até resolver." -ForegroundColor Red }
    } finally { Clear-AmbienteRestic }
}

Write-Host ""
Write-Host "Pronto. Primeiro backup (demora: sobe tudo):  pwsh -File `"$PSScriptRoot\rodar-backup.ps1`"" -ForegroundColor Cyan
Write-Host "Depois faça o teste de restauração do README." -ForegroundColor Cyan
