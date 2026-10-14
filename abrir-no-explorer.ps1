<#
    abrir-no-explorer.ps1 — abre a pasta no Explorer com o arquivo SELECIONADO.

        .\abrir-no-explorer.ps1 "C:\caminho\arquivo.pdf"

    Por que não `explorer.exe /select,"caminho"`:

    Aquele comando falha quando NÃO HÁ nenhuma janela do Explorer aberta. O processo
    novo repassa o pedido ao explorer.exe da sessão e morre; no caminho, o argumento
    /select se perde, e o que abre é a pasta padrão do usuário (nesta máquina,
    OneDrive\Attachments\Documentos) — sem erro, sem código de saída, sem nada
    selecionado. Com uma janela já aberta o mesmo comando acerta, e é isso que fazia o
    defeito parecer intermitente e a correção parecer questão de aspas.

    Medido em 25/09/2026, conferindo a pasta e a seleção por COM depois de cada
    tentativa:

      explorer.exe "/select,<caminho>"   (aspas em tudo)      -> Documentos
      explorer.exe /select,"<caminho>"   com janela aberta    -> certo
      explorer.exe /select,"<caminho>"   SEM janela (frio)    -> Documentos, nada selecionado
      SHOpenFolderAndSelectItems (esta)  SEM janela (frio)    -> certo, arquivo selecionado

    SHOpenFolderAndSelectItems é a API que o próprio /select usa por baixo. Chamada
    daqui, de um processo vivo, não passa pelo repasse que perde o argumento.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Caminho
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Caminho)) {
    throw "não existe: $Caminho"
}
# resolve para caminho absoluto do Windows: caminho relativo ou com / não é aceito pela API
$item = (Resolve-Path -LiteralPath $Caminho).ProviderPath
$pasta = Split-Path $item -Parent

Add-Type -Namespace Shell32 -Name Api -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern int SHParseDisplayName(string pszName, IntPtr pbc, out IntPtr ppidl, uint sfgaoIn, out uint psfgaoOut);
[DllImport("shell32.dll", SetLastError = true)]
public static extern int SHOpenFolderAndSelectItems(IntPtr pidlFolder, uint cidl, IntPtr[] apidl, uint dwFlags);
[DllImport("ole32.dll")]
public static extern void CoTaskMemFree(IntPtr pv);
'@

$attrPasta = 0; $attrItem = 0
$pidlPasta = [IntPtr]::Zero; $pidlItem = [IntPtr]::Zero
try {
    $hr = [Shell32.Api]::SHParseDisplayName($pasta, [IntPtr]::Zero, [ref]$pidlPasta, 0, [ref]$attrPasta)
    if ($hr -ne 0) { throw ("SHParseDisplayName falhou na pasta: 0x{0:X8}" -f $hr) }
    $hr = [Shell32.Api]::SHParseDisplayName($item, [IntPtr]::Zero, [ref]$pidlItem, 0, [ref]$attrItem)
    if ($hr -ne 0) { throw ("SHParseDisplayName falhou no arquivo: 0x{0:X8}" -f $hr) }

    $hr = [Shell32.Api]::SHOpenFolderAndSelectItems($pidlPasta, 1, @($pidlItem), 0)
    if ($hr -ne 0) { throw ("SHOpenFolderAndSelectItems falhou: 0x{0:X8}" -f $hr) }
}
finally {
    # os PIDL saem do heap do COM; sem isto cada chamada vaza memória
    if ($pidlItem -ne [IntPtr]::Zero) { [Shell32.Api]::CoTaskMemFree($pidlItem) }
    if ($pidlPasta -ne [IntPtr]::Zero) { [Shell32.Api]::CoTaskMemFree($pidlPasta) }
}

"aberto: $(Split-Path $item -Leaf)  em  $pasta"
