# Organiza as sessões do Claude Code (11/11/2026): títulos "[origem] tema", desarquiva e agrupa.
#
#   1. Título: acrescenta uma linha custom-title no fim de cada .jsonl do pool (a última vale; nada é apagado).
#   2. Desarquiva: tira da lista hiddenSessionIds do VS Code as sessões que existem e limpa as que já sumiram
#      (o Claude Code apaga sessão com mais de 30 dias); marca sessionUnarchivedAt para o auto-arquivar não
#      esconder de novo na hora.
#   3. Agrupa (opcional): cria os grupos nativos da lista de sessões do VS Code, um por origem.
#
# Os passos 2 e 3 mexem no state.vscdb do VS Code. O VS Code guarda isso na memória e regrava ao fechar:
# FECHE O VS CODE ANTES, rode num terminal fora dele, e abra de novo depois. O script recusa rodar com o
# VS Code aberto e faz cópia do state.vscdb antes de gravar.
#
#   python C:\Users\olive\Projetos\manutencao-xps\organizar-sessoes-2026-11-11.py --simular     (só mostra)
#   python C:\Users\olive\Projetos\manutencao-xps\organizar-sessoes-2026-11-11.py               (aplica)
#   python C:\Users\olive\Projetos\manutencao-xps\organizar-sessoes-2026-11-11.py --sem-grupos  (sem o passo 3)
import json, os, shutil, sqlite3, subprocess, sys, time, uuid

POOL = os.path.expanduser(r"~\.claude\projects\C--Users-olive")
VSDB = os.path.join(os.environ["APPDATA"], r"Code\User\globalStorage\state.vscdb")
CHAVE = "Anthropic.claude-code"
WORKSPACE = r"C:\Users\olive"  # a lista de sessões desta pasta (sessionGroups:<pasta>)

# grupo -> {prefixo do id: título}. A ordem dos grupos é a ordem na barra lateral.
GRUPOS = {
    "Planejamento": {
        "882197a8": "[planejamento] Nov/2026: revisão geral, captação, finanças e Hermes",
    },
    "Parresia": {
        "9746f500": "[parresia] Central 01 · Desk, WhatsApp e daily",
        "e9c8eabc": "[parresia] Central 02 · Lançamento do Unio",
        "f6c0b658": "[parresia] Central 03 · Frota WP: rollout do UltraPack",
        "dc7fd131": "[parresia] Faxina dos cards no ClickUp e contas de QA",
        "098e7720": "[parresia/unio] Feedbacks de usabilidade do grupo",
        "64168bfb": "[parresia/unio] QA nível 1 e 2 em produção",
        "8cec31ca": "[parresia/koynus] Planejamento: M28/M30 e WhatsApp",
        "93c8b09f": "[parresia/koynus] Desk: StackLab Kanban Pro e tema",
        "8d0aae10": "[parresia/frota] Padrão de plugins v1 e dailys",
        "7c209d23": "[parresia/frota] Chave SSH dos servidores WP e acessos no DÜ SOL",
        "301f6217": "[parresia/mettria] Tutoriais em vídeo: roteiro, notas e card",
        "2794475e": "[parresia/cnbb] Liturgia das Horas: falha e publicação até jan/27",
        "23682d7f": "[parresia/suporte] SUP-1025: lentidão da Rádio Frei Galvão",
        "fc244b2e": "[parresia/suporte] SUP-1055: QA do site da Paróquia de Iconha",
        "7c431743": "[parresia/suporte] QA Itapetininga: de-para, checklist e evidências",
    },
    "Celiware": {
        "c8974836": "[celiware] Central 01 · Valdir",
        "8e56f520": "[celiware] Parceria com o Valdir: contrato de 6 meses",
        "95d8559b": "[celiware] Ware IoT: versões 1.4/1.5, site e Play Store",
        "0b4f8dc7": "[celiware] Fábrica de Conteúdo: briefing e piloto Padrão TEX",
        "b5c31e67": "[celiware] Site Inovance Brasil: viabilidade e preço",
        "090d91e7": "[celiware] Orçamento do MVP ManagementAI (Thiago)",
        "19a0f650": "[celiware/instituto] Esteira de artigos e falhas do Publicar",
        "fbba2f2f": "[celiware/instituto] Teste automático (responda ok)",
    },
    "Desbravando": {
        "811c36d0": "[desbravando] Central 01",
        "e1917436": "[desbravando] Central 02",
        "cba9a24f": "[desbravando] Artes: crachá, camiseta, cardápio e formulários",
    },
    "Retífica": {
        "6bf320c9": "[retífica] Aceite, mensalidade e pedidos do James",
    },
    "Faculdade": {
        "2e6f9f35": "[faculdade] APS: projeto final Rufus Bank",
        "a1c9b5cb": "[faculdade] Itinerário Extensionista: backend do Conecta+",
        "78ce7d1f": "[faculdade] Seminário Grupo 2: transferência confiável",
        "dcdafea1": "[faculdade] Avaliações online de 30/10 (Cálculo II e outras)",
        "71bd1b21": "[faculdade] Prova de NoSQL: MongoDB, SQLite e Redis",
        "f9b5686e": "[faculdade] Eng. de Software: caso de uso do app de eventos",
        "26c7f2c5": "[faculdade] Perícia Forense: prática de aquisição (aula 04)",
        "510e4eab": "[faculdade] Perícia Forense: práticas forenses (aula 05)",
        "acbc1356": "[faculdade] Grupo CodeCare: proposta e mensagem ao professor",
    },
    "Sistemas": {
        "60be9ed0": "[sistemas] Faxina geral: Ágora, Sinapse, esteira, Cosmos, PC",
        "115141a0": "[sistemas] Esteira de QA universal: construção e pesquisa",
        "cb1b6068": "[sistemas] Títulos das sessões, memória e Sinapse",
        "ab7f8db8": "[sistemas] Máquina: janelas de cmd piscando no boot",
    },
    "Pessoal": {
        "e51e9ec8": "[pessoal] Presente de aniversário da Duda (boinas)",
        "25868821": "[pessoal] Rolê de sexta à noite em JP",
        "b337c786": "[pessoal] Golpe de emprego pelo WhatsApp",
        "3326949b": "[pessoal] Galeria de fotos com IA local",
        "dfb2c04f": "[pessoal] TV AOC 55: compra, análise e devolução",
        "67bec197": "[pessoal] Fantasia a partir do corte de cabelo",
        "f5b299e3": "[pessoal] Foto de perfil do WhatsApp (edição RYZE)",
    },
}


def vscode_aberto():
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Code.exe", "/NH"], capture_output=True, text=True)
    return "Code.exe" in r.stdout


def resolver(prefixo):
    achados = [f[:-6] for f in os.listdir(POOL) if f.startswith(prefixo) and f.endswith(".jsonl")]
    return achados[0] if len(achados) == 1 else None


def main():
    simular = "--simular" in sys.argv
    sem_grupos = "--sem-grupos" in sys.argv
    if not simular and vscode_aberto():
        print("O VS Code está aberto. Feche todas as janelas dele e rode de novo (num terminal fora do VS Code).")
        return 1

    # ids completos
    grupos, faltam = {}, []
    for nome, sessoes in GRUPOS.items():
        grupos[nome] = []
        for pref, titulo in sessoes.items():
            sid = resolver(pref)
            if sid: grupos[nome].append((sid, titulo))
            else: faltam.append(pref)
    total = sum(len(v) for v in grupos.values())
    if faltam: print("Não achei no pool:", ", ".join(faltam))

    # 1. títulos
    for nome, itens in grupos.items():
        for sid, titulo in itens:
            if not simular:
                linha = json.dumps({"type": "custom-title", "customTitle": titulo, "sessionId": sid}, ensure_ascii=False)
                with open(os.path.join(POOL, sid + ".jsonl"), "a", encoding="utf-8") as f: f.write(linha + "\n")
    print(f"1. títulos: {total} sessões" + (" (simulado)" if simular else ""))

    # 2 e 3. estado do VS Code
    con = sqlite3.connect(f"file:{VSDB}?mode={'ro' if simular else 'rw'}", uri=True)
    estado = json.loads(con.execute("select value from ItemTable where key=?", (CHAVE,)).fetchone()[0])
    ocultas = estado.get("hiddenSessionIds", [])
    existem = {f[:-6] for f in os.listdir(POOL) if f.endswith(".jsonl")}
    desarquivar = [i for i in ocultas if i in existem]
    sumidas = [i for i in ocultas if i not in existem]
    estado["hiddenSessionIds"] = []
    agora = int(time.time() * 1000)
    estado.setdefault("sessionUnarchivedAt", {}).update({i: agora for i in desarquivar})
    print(f"2. desarquivar: {len(desarquivar)} sessões; {len(sumidas)} da lista já não existem (apagadas pelo limite de 30 dias)")

    if not sem_grupos:
        chave_g = f"sessionGroups:{WORKSPACE}"
        antigos = estado.get(chave_g, [])
        manter = [g for g in antigos if g.get("sessionIds")]  # grupo vazio ("New group") sai
        ja_agrupadas = {s for g in manter for s in g["sessionIds"]}
        novos = [{"id": str(uuid.uuid4()), "name": nome, "collapsed": True,
                  "sessionIds": [sid for sid, _ in itens if sid not in ja_agrupadas]}
                 for nome, itens in grupos.items()]
        estado[chave_g] = manter + novos
        print(f"3. grupos: " + " · ".join(f"{g['name']} ({len(g['sessionIds'])})" for g in novos)
              + (f"; mantidos {len(manter)} grupos que você já tinha" if manter else ""))

    if simular:
        print("\nSimulação: nada foi gravado.")
        return 0
    copia = VSDB + f".antes-organizar-{time.strftime('%Y%m%d-%H%M%S')}"
    con.close(); shutil.copy2(VSDB, copia)
    con = sqlite3.connect(VSDB)
    con.execute("update ItemTable set value=? where key=?", (json.dumps(estado, ensure_ascii=False), CHAVE))
    con.commit(); con.close()
    print(f"\nPronto. Cópia do estado anterior: {copia}\nAbra o VS Code de novo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
