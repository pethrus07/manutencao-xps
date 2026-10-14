# Backup externo do XPS → Cloudflare R2 (restic)

Backup diário, cifrado no notebook antes de sair, para um bucket R2 na conta Cloudflare **pessoal**.
Preparado em 14/10/2026. **Ainda não roda:** falta você criar o bucket e o token (passo a passo abaixo).

## O que entra

| Origem | Por quê |
|---|---|
| `C:\Users\olive\Projetos` (todas as pastas, faculdade incluída) | código **e** o que o GitHub não guarda: `.env`, `.dev.vars`, gravações, dados locais |
| `Projetos\DU-SOL` (dentro do anterior) | o cofre "Rufus": o `cofre.md` em texto puro, que nunca vai ao GitHub |
| `C:\Users\olive\.claude` | histórico de sessões (`projects\*\*.jsonl`, ~1,2 GB), memória, skills, settings |
| `C:\Users\olive\.git-hooks` e `.gitleaks.toml` | hook global de segredos |

Fica de fora (`excluir.txt`): o que se regenera (`node_modules`, `.venv`, `.dart_tool`, `build`, `dist`,
`.wrangler`, `saidas`, caches, relatórios do Playwright), qualquer arquivo **> 200 MB** (vídeo renderizado,
instaladores) e, no `.claude`, cache, sessão viva e o `.credentials.json` (o login se refaz).
**Não** se exclui pelo `.gitignore`: o que é ignorado e não se regenera é justamente o que precisa de backup.

As origens ficam em `_comum.ps1` (`$ORIGENS`). As chaves SSH (`~\.ssh`) **não** entram; se quiser,
acrescente a linha lá (o repositório é cifrado de ponta a ponta, mas a decisão é sua).

## Onde ficam as credenciais

Nenhum segredo em arquivo. Fonte = **1Password**; cópia local = **Gerenciador de Credenciais do Windows**
(cifrado com a sua conta do Windows), que é o que a tarefa diária lê sem você estar olhando.

| Item no 1Password (placeholder) | Campos | Vai para |
|---|---|---|
| `backup-xps restic` (cofre `Pessoal`) | senha = senha do repositório restic | `backup-xps/restic` |
| `backup-xps R2` (cofre `Pessoal`) | usuário = Access Key ID · senha = Secret Access Key | `backup-xps/r2` |

Nomes diferentes: passe `-RefSenhaRestic`, `-RefR2KeyId`, `-RefR2Secret` (formato `op://Cofre/Item/campo`).
O script lê pela **sessão do app** do 1Password (tira o `OP_SERVICE_ACCOUNT_TOKEN` da Parresia do caminho,
porque o service account só enxerga o cofre `Frota WP`). Se o app não responder, ele pede para colar.

⚠️ **Sem a senha do repositório restic o backup é irrecuperável.** Guarde em dois lugares:
no 1Password **e** no `cofre.md` do DÜ SOL (e rode o `salvar.ps1` dele).

## Passo a passo (uma vez, ~15 min)

1. **Bucket.** dash.cloudflare.com, conta **pessoal** → R2 Object Storage → *Create bucket* →
   nome `backup-xps`, localização automática, classe *Standard*. (Se o R2 ainda não estiver ativo na
   conta, ele pede um cartão; o plano gratuito cobre os primeiros 10 GB.)
2. **Token só desse bucket.** R2 → *Manage R2 API Tokens* → *Create API token* → permissão
   **Object Read & Write**, *Apply to specific buckets only* → `backup-xps`, sem expiração (ou 1 ano,
   com lembrete). Copie o **Access Key ID** e o **Secret Access Key** (só aparecem uma vez) e anote o
   **Account ID** (aparece na mesma tela e na *Overview* do R2).
3. **1Password.** Crie `backup-xps R2` (Login: usuário = Access Key ID, senha = Secret) e
   `backup-xps restic` (Login: gere uma senha de 32+ caracteres). Copie a senha do restic também para o DÜ SOL.
4. **Configurar** (PowerShell normal, sem admin):
   ```powershell
   cd C:\Users\olive\Projetos\manutencao-xps\backup
   pwsh -File .\configurar-backup.ps1 -AccountId <account-id>
   ```
   Ele grava as credenciais no Windows, cria o repositório (pergunta antes), registra a tarefa
   **"Backup XPS (restic)"** todo dia às 12:30 e roda `restic check`.
5. **Primeiro backup** (o mais demorado; os seguintes só sobem o que mudou):
   ```powershell
   pwsh -File .\rodar-backup.ps1
   pwsh -File .\rodar-backup.ps1 -Status
   ```
6. **Teste de restauração** (abaixo). Backup que nunca foi restaurado não é backup.

## Teste de restauração

```powershell
cd C:\Users\olive\Projetos\manutencao-xps\backup
. .\_comum.ps1; Set-AmbienteRestic; $r = Get-Restic
& $r snapshots
& $r ls latest /C/Users/olive/Projetos/manutencao-xps
& $r restore latest --target C:\Temp\teste-restauracao --include /C/Users/olive/Projetos/manutencao-xps
Clear-AmbienteRestic
```
Confira que `C:\Temp\teste-restauracao\C\Users\olive\Projetos\manutencao-xps` tem os arquivos, compare
um ou dois com o original e apague a pasta. Restaurar tudo num notebook novo: instale o restic, rode o
`configurar-backup.ps1` (ele só precisa das credenciais), `restore latest --target C:\Restauracao` e
mova as pastas de `C:\Restauracao\C\Users\olive\` para o lugar. No restic do Windows o caminho dentro
do snapshot é `/C/Users/...`, e o restore recria essa árvore embaixo do `--target`.

## Rotina e limites

- Todo dia: backup. Domingo: `forget --prune` (7 diários, 4 semanais, 12 mensais). Dia 1: `check`
  lendo 5% dos dados. Logs em `%LOCALAPPDATA%\backup-xps\logs\` (últimos 60); último OK em
  `%LOCALAPPDATA%\backup-xps\ultimo-ok.txt`.
- A tarefa roda só com você logado (sem guardar senha do Windows) e, se o notebook estava desligado às
  12:30, roda quando ligar. Precisa de rede.
- **Sem VSS** (cópia de sombra exige admin): arquivo aberto e travado na hora sai como aviso (rc=3) e
  entra no backup seguinte. Para um backup "frio", feche o VS Code e rode à mão.
- Junctions do `.claude\projects` (52 apontam para o mesmo pool): o restic não multiplica o volume
  (deduplicação); testado em dry-run, ~1,8 GB para todo o `.claude`.
- Isto é backup de **arquivos**. Imagem do disco inteiro (Windows + programas) é outra coisa: Veeam
  Agent Free em SSD externo, mensal (pesquisa de 14/10).

## Custo estimado (R2, preços de out/2026)

Armazenamento US$ 0,015/GB-mês, **10 GB grátis**; sem taxa de saída (restaurar não custa banda);
operações dentro da cota gratuita no uso diário.

| Volume no bucket | Custo/mês |
|---|---|
| até 10 GB | US$ 0 |
| 50 GB | ~US$ 0,60 |
| 100 GB | ~US$ 1,35 |

O restic comprime e deduplica: o volume no bucket costuma ficar bem abaixo do tamanho das pastas.
