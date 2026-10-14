<#
.SYNOPSIS
  Cloudflare sem login: guarda um token de API por conta e roda qualquer comando com ele.

.DESCRIPTION
  POR QUE EXISTE
  O `wrangler login` usa OAuth: abre navegador, expira, e o callback dele escuta só em IPv6
  (`[::1]:8976`) enquanto o Chrome resolve `localhost` para 127.0.0.1 — por isso o login
  falhava quatro vezes seguidas e precisou de uma ponte IPv4→IPv6 em 07/09/2026. Pior: com
  duas contas (ryzecode08, onde vive o Desbravando, e a pessoal, onde vive o Instituto), um
  `wrangler login` sobrescreve o perfil do outro. Em 14/10 os TRÊS perfis da máquina estavam
  apontando para a conta pessoal, e o Desbravando ficou sem como publicar.

  Token de API resolve: não expira (o TTL é opcional e fica em branco), é por conta, e o
  wrangler o lê de `CLOUDFLARE_API_TOKEN` sem abrir navegador nenhum.

  ONDE O TOKEN FICA
  Em `~/.cloudflare/contas.json`, FORA de qualquer repositório, criptografado por DPAPI —
  que amarra o segredo à conta Windows desta máquina. Copiar o arquivo para outro computador
  não serve de nada, e nenhum backup de repo o carrega junto. Guarde também no cofre DÜ SOL:
  isto aqui é conveniência, não a fonte da verdade.

.EXAMPLE
  .\cf.ps1 guardar ryze
  .\cf.ps1 contas
  .\cf.ps1 usar ryze npx wrangler whoami
  .\cf.ps1 usar ryze npx wrangler d1 execute eventos --remote --file=migracao_v4_6.sql
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("guardar", "contas", "usar", "remover")]
  [string]$Acao,

  [Parameter(Position = 1)]
  [string]$Conta,

  [Parameter(Position = 2, ValueFromRemainingArguments = $true)]
  [string[]]$Comando
)

$ErrorActionPreference = "Stop"
$Pasta  = Join-Path $env:USERPROFILE ".cloudflare"
$Arquivo = Join-Path $Pasta "contas.json"

function Carregar {
  if (-not (Test-Path $Arquivo)) { return @{} }
  $bruto = Get-Content $Arquivo -Raw | ConvertFrom-Json
  $m = @{}
  foreach ($p in $bruto.PSObject.Properties) { $m[$p.Name] = $p.Value }
  return $m
}

function Gravar($mapa) {
  if (-not (Test-Path $Pasta)) {
    New-Item -ItemType Directory -Path $Pasta | Out-Null
    # Só o dono lê. A criptografia já protege o conteúdo; isto evita até o arquivo ser lido.
    icacls $Pasta /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
  }
  $mapa | ConvertTo-Json -Depth 4 | Set-Content $Arquivo -Encoding UTF8
}

# DPAPI: o segredo só volta a texto na MESMA conta Windows e na MESMA máquina.
function Cifrar($texto)  { ConvertTo-SecureString $texto -AsPlainText -Force | ConvertFrom-SecureString }
function Decifrar($cifra){
  $s = ConvertTo-SecureString $cifra
  [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}

switch ($Acao) {

  "guardar" {
    if (-not $Conta) { throw "Diga o apelido da conta. Ex.: .\cf.ps1 guardar ryze" }
    Write-Host ""
    Write-Host "Token de API da conta '$Conta'." -ForegroundColor Cyan
    Write-Host "Crie em: dash.cloudflare.com > My Profile > API Tokens > Create Token > Custom token"
    Write-Host "Permissoes: Account > Workers Scripts (Edit), D1 (Edit), Workers R2 Storage (Edit),"
    Write-Host "            Account Settings (Read).  Account Resources: so esta conta.  TTL: deixe VAZIO."
    Write-Host ""
    $tok = Read-Host "Cole o token (nao aparece na tela)" -AsSecureString
    $plano = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tok))
    if (-not $plano) { throw "Token vazio." }

    # Confere ANTES de guardar: token errado guardado silenciosamente e pior que token nenhum,
    # porque o erro so aparece no meio de um deploy.
    $env:CLOUDFLARE_API_TOKEN = $plano
    Remove-Item Env:\CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue
    $saida = (npx wrangler whoami 2>&1 | Out-String)
    if ($saida -notmatch "([0-9a-f]{32})") {
      Write-Host $saida
      throw "O token nao foi aceito pela Cloudflare. Nada foi guardado."
    }
    $id = $Matches[1]
    $nome = if ($saida -match "│\s*([^│]+?)\s*│\s*$id") { $Matches[1].Trim() } else { "(sem nome)" }

    $mapa = Carregar
    $mapa[$Conta] = @{ id = $id; nome = $nome; token = (Cifrar $plano); em = (Get-Date -Format "yyyy-MM-dd") }
    Gravar $mapa
    Remove-Item Env:\CLOUDFLARE_API_TOKEN
    Write-Host ""
    Write-Host "OK. '$Conta' = $nome ($id)" -ForegroundColor Green
    Write-Host "Guarde uma copia no cofre DU SOL: este arquivo nao sai desta maquina."
  }

  "contas" {
    $mapa = Carregar
    if ($mapa.Count -eq 0) { Write-Host "Nenhuma conta guardada. Use: .\cf.ps1 guardar <apelido>"; break }
    $mapa.GetEnumerator() | ForEach-Object {
      [pscustomobject]@{ Apelido = $_.Key; Conta = $_.Value.nome; Id = $_.Value.id; Guardado = $_.Value.em }
    } | Format-Table -AutoSize
  }

  "remover" {
    $mapa = Carregar
    if (-not $mapa.ContainsKey($Conta)) { throw "Nao conheco a conta '$Conta'." }
    $mapa.Remove($Conta); Gravar $mapa
    Write-Host "'$Conta' removida." -ForegroundColor Green
  }

  "usar" {
    $mapa = Carregar
    if (-not $mapa.ContainsKey($Conta)) {
      throw "Nao conheco a conta '$Conta'. As que conheco: $($mapa.Keys -join ', ')"
    }
    if (-not $Comando) { throw "Diga o comando. Ex.: .\cf.ps1 usar ryze npx wrangler whoami" }

    $env:CLOUDFLARE_API_TOKEN  = Decifrar $mapa[$Conta].token
    $env:CLOUDFLARE_ACCOUNT_ID = $mapa[$Conta].id
    # O wrangler prefere o OAuth guardado se ele existir; apontar o XDG para uma pasta vazia
    # garante que o token do ambiente e quem manda, e que a conta e a que foi pedida.
    $env:XDG_CONFIG_HOME = Join-Path $Pasta "sem-oauth"
    if (-not (Test-Path $env:XDG_CONFIG_HOME)) { New-Item -ItemType Directory -Path $env:XDG_CONFIG_HOME | Out-Null }

    Write-Host "[$Conta · $($mapa[$Conta].nome)]" -ForegroundColor DarkCyan
    & $Comando[0] @($Comando[1..($Comando.Length - 1)])
    $codigo = $LASTEXITCODE
    Remove-Item Env:\CLOUDFLARE_API_TOKEN, Env:\CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue
    exit $codigo
  }
}
