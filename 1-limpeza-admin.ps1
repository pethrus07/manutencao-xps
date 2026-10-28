# 1-limpeza-admin.ps1 — correção da hibernação + relógio + limpeza de SISTEMA pelas ferramentas do próprio Windows.
# Precisa de admin (auto-eleva, pede UAC). Não apaga nenhum arquivo seu: usa a Limpeza de Disco (cleanmgr),
# o DISM, o powercfg e o winget, que só tocam em caches, componentes substituídos do Windows e programas.
#
# Rodar (de qualquer terminal; ele abre a própria janela de admin):
#     pwsh -File C:\Users\olive\Projetos\manutencao-xps\1-limpeza-admin.ps1
# Plano B, SÓ se depois do reinício a hibernação ainda voltar como boot frio:
#     pwsh -File C:\Users\olive\Projetos\manutencao-xps\1-limpeza-admin.ps1 -DesligarHibernacao
#
# Duração: 15 a 30 minutos (DISM, cleanmgr e Dell Command Update são lentos). Na tomada.
# Antes: feche o VS Code (Git, Node e Python são atualizados e ficam presos se estiverem em uso).
# Ao final pede para REINICIAR. Revisto em 19/10/2026.
param([switch]$DesligarHibernacao)

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $extra = if ($DesligarHibernacao) { ' -DesligarHibernacao' } else { '' }
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$extra"
    exit
}
$ErrorActionPreference = 'Continue'
$log = "$PSScriptRoot\log-admin-$(Get-Date -Format 'yyyy-MM-dd-HHmm').txt"   # log-*.txt está no .gitignore
Start-Transcript -Path $log | Out-Null
function Passo($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Aviso($t) { Write-Host "   $t" -ForegroundColor Yellow }
function Ok($t) { Write-Host "   $t" -ForegroundColor Green }
function GB($b) { [math]::Round($b / 1GB, 2) }
function SimNao($p) { (Read-Host "   $p (s/N)") -match '^[sSyY]' }
$PowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'

# ═════════════ PLANO B: desligar a hibernação de vez (só com -DesligarHibernacao) ═════════════
# Use se, DEPOIS de rodar este script sem parâmetro e reiniciar, o teste 'shutdown /h' ainda voltar como boot frio.
# Efeito: some o hiberfil.sys (12,7 GB), o notebook fica só com o Modern Standby e, em bateria crítica,
# DESLIGA em vez de tentar hibernar (hoje a ação crítica é Hibernar, que é justamente o que falha).
if ($DesligarHibernacao) {
    Passo "PLANO B) Desligando a hibernação"
    powercfg /h off
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BATTERY BATACTIONCRIT 3   # 3 = desligar
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BATTERY BATACTIONCRIT 3
    powercfg /setactive SCHEME_CURRENT
    Write-Host ""; powercfg /a | Select-Object -First 8
    Ok "Pronto. Hibernação desligada; bateria crítica = desligar. Não precisa reiniciar."
    Stop-Transcript | Out-Null
    Read-Host "Enter para fechar"
    exit
}

# ═════════════ Pré-voo ═════════════
$free0 = (Get-PSDrive C).Free
Write-Host "C: livre no início: $(GB $free0) GB" -ForegroundColor Green
Write-Host @"

O que vai acontecer (nada apaga arquivo seu):
  A) hibernação: recria o hiberfil.sys e desliga o Fast Startup      A1) BitLocker: pergunta antes
  A2) relógio: liga o serviço de hora e sincroniza no NTP.br         A3) Dell Hardware Support -> Manual
  B-E) limpeza do Windows (Delivery Optimization, cleanmgr, DISM, TRIM)
  F) atualiza apps pelo winget                                       G) drivers Dell (inclui o Intel RST)
"@
if ((Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).BatteryStatus -ne 2) {
    Aviso "O notebook está na BATERIA. O Dell Command Update recusa driver sem tomada e o DISM é longo."
    if (-not (SimNao "Continuar mesmo assim?")) { Stop-Transcript | Out-Null; exit }
}
if (Get-Process Code -ErrorAction SilentlyContinue) {
    Aviso "O VS Code está aberto: Git, Node e Python ficam presos se forem atualizados agora."
    Read-Host "   Feche o VS Code e aperte Enter (se continuar aberto, esses três ficam para depois)"
}
$codeAberto = [bool](Get-Process Code -ErrorAction SilentlyContinue)

Passo "Ponto de restauração (seguro antes de mexer em energia, BitLocker e drivers)"
# Checkpoint-Computer só existe no Windows PowerShell 5.1, por isso a chamada externa.
powershell.exe -NoProfile -Command "try { Checkpoint-Computer -Description 'Antes da manutencao XPS' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; 'criado' } catch { 'nao criado: ' + `$_.Exception.Message }"

# ───────────── A) HIBERNAÇÃO QUEBRADA ─────────────
# Evidência (07/09 → 19/10/2026): TODO boot dos últimos 10 dias é um Kernel-Power 41 com SleepInProgress=6,
# Bugcheck=0, botão=0 e BootAppStatus=0xC00000D4, logo depois de Kernel-Boot 29 (Fast Startup falhou).
# Ou seja: o notebook hiberna (Modern Standby estoura o orçamento de bateria) e o winresume não consegue
# retomar → boot frio, trabalho aberto perdido, e todas as tarefas atrasadas disparam juntas.
# O BIOS 1.48 (aplicado em 15/10) NÃO resolveu. Junto vêm 70 erros BitLocker 24641 em 10 dias:
# "erro ao obter a chave mestra do volume durante o reinício" — ver A1.
Passo "A) Recriando hiberfil.sys e desligando o Fast Startup (usa o mesmo mecanismo e também falha)"
powercfg /h off
powercfg /h on
powercfg /h /type full
Set-ItemProperty $PowerKey -Name HiberbootEnabled -Value 0 -Type DWord
$hb = (Get-ItemProperty $PowerKey).HiberbootEnabled
if ($hb -eq 0) { Ok "Fast Startup desligado (HiberbootEnabled=0)" } else { Aviso "HiberbootEnabled ainda = $hb" }

# ───────────── A1) BITLOCKER: renovar o lacre no TPM (opcional, pergunta) ─────────────
# Na retomada da hibernação o Windows precisa pegar a chave do BitLocker no TPM, e é isso que falha (24641).
# A correção padrão (a mesma que a Dell usa em atualização de BIOS) é SUSPENDER a proteção por 1 reinício:
# no boot seguinte o BitLocker volta sozinho e relacra a chave com as medições atuais do firmware.
# Risco: se der errado, o PC pede a CHAVE DE RECUPERAÇÃO no boot. Por isso o script confere antes.
Passo "A1) BitLocker"
$st = manage-bde -status C: 2>&1 | Out-String
if ($st -match '(Protection On|Proteção Ativada|Proteção ativada)') {
    $prot = manage-bde -protectors -get C: -Type RecoveryPassword 2>&1 | Out-String   # NÃO imprimir: contém a chave
    $idChave = [regex]::Match($prot, '\{[0-9A-Fa-f-]{36}\}').Value
    if (-not $idChave) { Aviso "BitLocker ativo mas SEM chave de recuperação numérica. NÃO suspenda: pulei o A1." }
    else {
    Write-Host "   BitLocker ATIVO no C:. ID da chave de recuperação: $idChave"
    Write-Host "   Antes de responder S, confira que ESSE ID aparece em https://account.microsoft.com/devices/recoverykey"
    Write-Host "   (ou que você tem a chave anotada / no 1Password)."
    if (SimNao "Achou a chave e quer suspender o BitLocker por 1 reinício para relacrar?") {
        manage-bde -protectors -disable C: -RebootCount 1
        Ok "Suspenso por 1 reinício; volta sozinho no próximo boot."
    } else { Write-Host "   Pulado. A hibernação pode continuar falhando por esse motivo." }
    }
} elseif ($st -match '(Protection Off|Proteção Desativada|Proteção desativada)') {
    Write-Host "   BitLocker com proteção desligada; nada a fazer."
} else { Aviso "Não consegui ler o estado do BitLocker:"; Write-Host $st }

# ───────────── A2) RELÓGIO (44,9 s atrasado em 14/10; w32time DESABILITADO desde então) ─────────────
# Já gerou falso achado de QA ("servidor adiantado"). Liga o serviço, aponta para o NTP.br e ressincroniza.
Passo "A2) Relógio: ligando o serviço de hora e sincronizando com o NTP.br"
Set-Service w32time -StartupType Automatic
Start-Service w32time -ErrorAction SilentlyContinue
w32tm /config /manualpeerlist:"a.ntp.br,0x8 b.ntp.br,0x8 time.windows.com,0x8" /syncfromflags:manual /reliable:no /update
Restart-Service w32time
w32tm /resync /force
w32tm /stripchart /computer:a.ntp.br /samples:2 /dataonly

# ───────────── A3) Serviço "Dell Hardware Support" falha em TODO boot ─────────────
# Vai para Manual (não remove nada; o SupportAssist abre ele se precisar). Remover o SupportAssist é decisão do 2-remocoes-opcionais.ps1.
Passo "A3) Dell Hardware Support: Automático -> Manual"
Set-Service 'Dell Hardware Support' -StartupType Manual -ErrorAction SilentlyContinue
Write-Host "   agora: $((Get-Service 'Dell Hardware Support' -ErrorAction SilentlyContinue).StartType)"

# ───────────── B) Delivery Optimization ─────────────
Passo "B) Cache do Delivery Optimization"
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue

# ───────────── C) Limpeza de Disco (cleanmgr) nas categorias seguras ─────────────
# Cobre: logs de upgrade (C:\Windows\Panther, 1,4 GB), relatórios de erro, temporários do sistema, cache do Windows Update,
# pacotes de driver antigos, miniaturas. Fica de FORA de propósito: Lixeira, Downloads, arquivos ESD de reset, cache de shaders DirectX.
Passo "C) Limpeza de Disco do Windows (abre uma janelinha de progresso)"
$cats = 'Active Setup Temp Folders', 'BranchCache', 'Delivery Optimization Files', 'Device Driver Packages', 'Diagnostic Data Viewer database files',
        'Downloaded Program Files', 'Internet Cache Files', 'Old ChkDsk Files', 'Previous Installations', 'RetailDemo Offline Content', 'Setup Log Files',
        'System error memory dump files', 'System error minidump files', 'Temporary Files', 'Temporary Setup Files', 'Thumbnail Cache', 'Update Cleanup',
        'Upgrade Discarded Files', 'User file versions', 'Windows Defender', 'Windows Error Reporting Files', 'Windows Upgrade Log Files'
$vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
Get-ChildItem $vc | ForEach-Object { Set-ItemProperty $_.PSPath -Name StateFlags0099 -Value 0 -Type DWord }
foreach ($c in $cats) { if (Test-Path "$vc\$c") { Set-ItemProperty "$vc\$c" -Name StateFlags0099 -Value 2 -Type DWord } }
Start-Process cleanmgr.exe -ArgumentList '/sagerun:99' -Wait

# ───────────── D) WinSxS: componentes substituídos ─────────────
Passo "D) DISM StartComponentCleanup (demora; mantém a possibilidade de desinstalar a última atualização)"
Dism.exe /Online /Cleanup-Image /StartComponentCleanup

# ───────────── E) TRIM do SSD ─────────────
Passo "E) TRIM (Optimize-Volume -ReTrim)"
Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue

# ───────────── F) Atualizações seguras via winget ─────────────
# Lista revista em 19/10/2026 contra 'winget upgrade' (27 pendentes). Ficam de fora de propósito:
# PowerShell 7.6 (troca de linha: é o 3-powershell-76.ps1), Claude Desktop e Claude Code (em uso pelo Claude),
# Outlook e MongoDB (candidatos a remoção, decisão pendente), Visual Studio Build Tools (pelo Visual Studio Installer).
# Python e o launcher foram instalados POR USUÁRIO (AppData): --scope user evita uma segunda cópia em Program Files.
Passo "F) winget: atualizações de apps em uso"
$ids = @('AgileBits.1Password', 'AgileBits.1Password.CLI', 'GitHub.cli', '7zip.7zip', 'Microsoft.PowerToys', 'REALiX.HWiNFO',
         'Microsoft.VCRedist.2013.x64', 'Microsoft.VCRedist.2013.x86', 'Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86',
         'Nvidia.PhysX', 'errata-ai.Vale', 'ClassicDIY.ModbusTool', 'EpicGames.EpicGamesLauncher', 'Microsoft.WindowsTerminal')
$devIds = @('Git.Git', 'OpenJS.NodeJS.LTS', 'Python.Python.3.14', 'Python.Launcher')
if ($codeAberto) { Aviso "VS Code aberto: pulando $($devIds -join ', ')." } else { $ids += $devIds }
if (Get-Process 'Docker Desktop', 'com.docker.backend' -ErrorAction SilentlyContinue) { Aviso "Docker aberto: pulando Docker Desktop." }
else { $ids += 'Docker.DockerDesktop' }
foreach ($i in $ids) {
    Write-Host "   -> $i"
    $scope = if ($i -like 'Python.*') { @('--scope', 'user') } else { @() }
    winget upgrade --id $i --exact @scope --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Select-Object -Last 1
}

# ───────────── G) Drivers Dell (Intel RST/VMD 18.7 de 09/2022 — suspeito da hibernação —, Intel DTT de 2021, Thunderbolt de 2022) ─────────────
# Só DRIVERS (o BIOS já está no 1.48). Sem reiniciar aqui: o reinício é no fim, um só.
Passo "G) Dell Command Update: drivers"
$rst0 = (Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceName -match 'VMD' | Select-Object -First 1).DriverVersion
$dcu = 'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
if (Test-Path $dcu) {
    & $dcu /applyUpdates -updateType=driver -reboot=disable -silent "-outputLog=$PSScriptRoot\log-dcu-$(Get-Date -Format 'yyyy-MM-dd-HHmm').log"
    Write-Host "   dcu-cli saiu com código $LASTEXITCODE (0 = aplicou; 1 ou 5 = precisa reiniciar; 500 = nada a atualizar; outro = ver log-dcu)"
} else { Aviso "dcu-cli não encontrado" }
Write-Host "   Intel RST/VMD antes: $rst0 (a versão nova só aparece depois do reinício)"

# ───────────── Resumo (lido do sistema, não presumido) ─────────────
$free1 = (Get-PSDrive C).Free
Passo "RESUMO"
Write-Host "C: livre: $(GB $free0) GB -> $(GB $free1) GB  (liberado $(GB ($free1 - $free0)) GB)" -ForegroundColor Green
Write-Host "hiberfil.sys: $(GB (Get-Item C:\hiberfil.sys -Force -ErrorAction SilentlyContinue).Length) GB | Fast Startup: $(if ((Get-ItemProperty $PowerKey).HiberbootEnabled -eq 0) { 'desligado' } else { 'LIGADO' })"
Write-Host "Hora: serviço $((Get-Service w32time).Status)/$((Get-Service w32time).StartType) | $(w32tm /query /status | Select-String 'Source|Fonte')"
Write-Host "BitLocker: $((manage-bde -status C: | Select-String 'Protection Status|Status da Proteção|Estado da Proteção') -replace '\s+', ' ')"
Write-Host "Pontos de restauração (os ~60 GB sem explicação de 14/10):"
vssadmin list shadowstorage | Select-String 'Used|Usado|Allocated|Alocado|Maximum|Máximo'
Write-Host ""
Write-Host "Falta manual (Explorer): apagar a pasta C:\Drivers (1,2 GB de pacotes de driver de fábrica, 2021)."
Write-Host ""
Write-Host "AGORA:" -ForegroundColor Yellow
Write-Host "  1. REINICIE (Iniciar > Reiniciar). Drivers e o relacre do BitLocker entram nesse reinício." -ForegroundColor Yellow
Write-Host "  2. Depois, teste: abra umas janelas e rode 'shutdown /h'. Ao ligar, as janelas TÊM que voltar." -ForegroundColor Yellow
Write-Host "  3. Se voltar como boot frio de novo: plano B = rodar este script com -DesligarHibernacao." -ForegroundColor Yellow
Write-Host "Log em: $log"
Stop-Transcript | Out-Null
Read-Host "Enter para fechar"
