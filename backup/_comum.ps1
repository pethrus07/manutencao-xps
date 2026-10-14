# _comum.ps1 — funções do backup (carregado com "." pelos outros scripts; não rodar sozinho).
#
# Credenciais ficam no Gerenciador de Credenciais do Windows (cofre do usuário, cifrado pelo
# DPAPI da conta do Windows) — nunca em arquivo. Dois itens genéricos:
#   backup-xps/restic : usuário = endereço do repositório (s3:https://<conta>.r2.cloudflarestorage.com/backup-xps)
#                       senha   = senha do repositório restic
#   backup-xps/r2     : usuário = Access Key ID do token R2
#                       senha   = Secret Access Key do token R2
# Para ver/apagar à mão: Painel de Controle > Gerenciador de Credenciais > Credenciais do Windows.

$script:ALVO_RESTIC = 'backup-xps/restic'
$script:ALVO_R2     = 'backup-xps/r2'

# O que entra no backup (pastas e arquivos). Ajuste aqui, não nos outros scripts.
$script:ORIGENS = @(
    "$env:USERPROFILE\Projetos"          # inclui o cofre DÜ SOL (Projetos\DU-SOL, com o cofre.md em texto puro)
    "$env:USERPROFILE\.claude"           # histórico de sessões (.jsonl), memória, skills, settings
    "$env:USERPROFILE\.git-hooks"        # hook global de segredos (gitleaks)
    "$env:USERPROFILE\.gitleaks.toml"
)

if (-not ('BackupXps.Cred' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace BackupXps {
  public static class Cred {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL {
      public int Flags; public int Type; public string TargetName; public string Comment;
      public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
      public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
      public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
    }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredWriteW(ref CREDENTIAL c, int flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredReadW(string target, int type, int flags, out IntPtr c);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern void CredFree(IntPtr c);
    const int GENERIC = 1, PERSIST_LOCAL_MACHINE = 2;

    public static void Write(string target, string user, string secret) {
      byte[] b = Encoding.Unicode.GetBytes(secret);
      var c = new CREDENTIAL { Type = GENERIC, TargetName = target, UserName = user,
                               Persist = PERSIST_LOCAL_MACHINE, CredentialBlobSize = b.Length,
                               CredentialBlob = Marshal.AllocHGlobal(b.Length) };
      try {
        Marshal.Copy(b, 0, c.CredentialBlob, b.Length);
        if (!CredWriteW(ref c, 0)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      } finally { Marshal.FreeHGlobal(c.CredentialBlob); Array.Clear(b, 0, b.Length); }
    }
    // devolve null se não existir; [0] = usuário, [1] = segredo
    public static string[] Read(string target) {
      IntPtr p;
      if (!CredReadW(target, GENERIC, 0, out p)) return null;
      try {
        var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
        string s = c.CredentialBlobSize > 0 ? Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2) : "";
        return new[] { c.UserName, s };
      } finally { CredFree(p); }
    }
  }
}
'@
}

function Get-Restic {
    $cmd = Get-Command restic -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $achado = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\restic.restic_*\restic*.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($achado) { return $achado.FullName }
    throw "restic não encontrado. Instale: winget install --id restic.restic --scope user"
}

function Test-CredenciaisBackup {
    return ($null -ne [BackupXps.Cred]::Read($script:ALVO_RESTIC)) -and ($null -ne [BackupXps.Cred]::Read($script:ALVO_R2))
}

# Põe as credenciais no ambiente DESTE processo (some quando o processo termina).
function Set-AmbienteRestic {
    $r = [BackupXps.Cred]::Read($script:ALVO_RESTIC)
    $k = [BackupXps.Cred]::Read($script:ALVO_R2)
    if (-not $r -or -not $k) {
        throw "Credenciais do backup ausentes no Gerenciador de Credenciais. Rode antes: pwsh -File configurar-backup.ps1"
    }
    $env:RESTIC_REPOSITORY     = $r[0]
    $env:RESTIC_PASSWORD       = $r[1]
    $env:AWS_ACCESS_KEY_ID     = $k[0]
    $env:AWS_SECRET_ACCESS_KEY = $k[1]
    $env:AWS_DEFAULT_REGION    = 'auto'   # o R2 aceita/espera "auto"
}

function Clear-AmbienteRestic {
    foreach ($v in 'RESTIC_REPOSITORY','RESTIC_PASSWORD','AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_DEFAULT_REGION') {
        Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    }
}

# Lê um segredo do 1Password pela SESSÃO DO APP (não pelo service account da Parresia,
# que só enxerga o cofre "Frota WP"). Devolve $null se não conseguir.
function Read-1Password([string]$ref) {
    $op = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\AgileBits.1Password.CLI_*\op.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $op) { $c = Get-Command op -ErrorAction SilentlyContinue; if ($c) { $op = $c.Source } else { return $null } }
    $sa = $env:OP_SERVICE_ACCOUNT_TOKEN
    try {
        Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
        $v = & $op read --no-newline $ref 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return $v }
        return $null
    } finally {
        if ($sa) { $env:OP_SERVICE_ACCOUNT_TOKEN = $sa }
    }
}
