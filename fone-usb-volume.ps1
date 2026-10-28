# Fone pelo adaptador USB-C → P2 "AB13X USB Audio" (VID_001F, PID_0B21): o volume caía sozinho, aos degraus,
# até zerar, toda vez que o fone era conectado. Medido em 26/10/2026: em 20 s o volume do "Speakers (AB13X)"
# caiu 98 → 90 → 46 → 76 → 70 % sem ninguém mexer. Causa: o adaptador tem um controle de mídia (HID
# "consumer control", interface MI_03) que lê a linha do microfone/botões do fone e, com esse fone, manda
# "baixar volume" sem parar.
#
# Correção: desliga SÓ esse controle de mídia (o som e o microfone continuam) e uma regra do Windows impede que
# ele volte em qualquer porta USB-C. Perde-se apenas o botão de mídia do fio do fone.
#   -Desfazer   tira a regra e religa o controle de mídia
# Precisa de administrador.
param([switch]$Desfazer)
$ErrorActionPreference = 'Stop'
$ids = @('HID\VID_001F&PID_0B21&MI_03', 'USB\VID_001F&PID_0B21&MI_03')
$regra = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$lista = Join-Path $regra 'DenyDeviceIDs'

$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $ehAdmin) { throw 'Rode como administrador.' }

$dispositivos = Get-PnpDevice | Where-Object { $_.InstanceId -like 'HID\VID_001F&PID_0B21&MI_03*' -or $_.InstanceId -like 'USB\VID_001F&PID_0B21&MI_03*' }

if ($Desfazer) {
  if (Test-Path $lista) {
    $props = (Get-ItemProperty $lista).PSObject.Properties | Where-Object { $ids -contains $_.Value }
    foreach ($p in $props) { Remove-ItemProperty -Path $lista -Name $p.Name; "regra removida: $($p.Value)" }
  }
  foreach ($d in $dispositivos) { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue; "religado: $($d.FriendlyName)" }
  'Pronto: controle de mídia do adaptador de volta (desconecte e conecte o adaptador).'
  return
}

# regra: o Windows não instala esse controle de mídia em nenhuma porta (sem efeito retroativo em outros aparelhos)
New-Item -Path $lista -Force | Out-Null
Set-ItemProperty -Path $regra -Name 'DenyDeviceIDs' -Value 1 -Type DWord
Set-ItemProperty -Path $regra -Name 'DenyDeviceIDsRetroactive' -Value 0 -Type DWord
$usados = @((Get-ItemProperty $lista).PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object { $_.Value })
$n = @((Get-ItemProperty $lista).PSObject.Properties | Where-Object { $_.Name -match '^\d+$' }).Count
foreach ($id in $ids) {
  if ($usados -contains $id) { "regra já existia: $id"; continue }
  $n++; Set-ItemProperty -Path $lista -Name "$n" -Value $id -Type String; "regra criada: $id"
}

# o que já está instalado: desliga agora
foreach ($d in $dispositivos) {
  if ($d.Status -eq 'OK') { Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false; "desligado: $($d.FriendlyName) ($($d.InstanceId))" }
  else { "já estava desligado: $($d.FriendlyName)" }
}
'Pronto: o volume não deve mais cair sozinho. O som e o microfone do adaptador continuam funcionando.'

