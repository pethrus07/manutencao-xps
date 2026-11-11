# Organiza as sessões do Claude Code (11/11/2026): títulos por frente/assunto, desarquiva e agrupa.
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

# A extensão não tem "fixar"/"favoritar": o atalho é um grupo no TOPO, sempre aberto, com o que está em uso.
# Uma sessão fica em um grupo só: a que está aqui sai do grupo da origem. Para trocar, edite esta lista.
# Critério de 11/11/2026: as centrais (canais por cliente) + o que teve conversa nos últimos 3 dias.
ATIVOS_NOME = "★ Ativos"
ATIVOS = [
    "882197a8",  # planejamento
    "9746f500",  # Parresia: Central 01 (Desk, WhatsApp, daily)
    "e9c8eabc",  # Parresia: Central 02 (lançamento do Unio)
    "f6c0b658",  # Parresia: Central 03 (Frota WP, UltraPack)
    "098e7720",  # Parresia: feedbacks do Unio
    "c8974836",  # Celiware: Central do Valdir
    "e1917436",  # Desbravando: Central 02
    "6bf320c9",  # Retífica: pedidos do James
    "acbc1356",  # Faculdade: grupo CodeCare
    "78ce7d1f",  # Faculdade: seminário do Grupo 2
    "e51e9ec8",  # Pessoal: presente da Duda (aniversário 17/11)
]

# Título sem "[origem]": o grupo já diz a origem. Começa pela frente ou pelo assunto, que se reconhece
# sozinho também no ★ Ativos, onde as origens se misturam ("Unio ·", "Central Parresia 02 ·", "APS ·").
# grupo -> {prefixo do id: título}. A ordem dos grupos é a ordem na barra lateral.
GRUPOS = {
    "Planejamento": {
        "882197a8": "Planejamento nov/2026 · revisão, captação, finanças e Hermes",
    },
    "Parresia": {
        "9746f500": "Central Parresia 01 · Desk, WhatsApp e daily",
        "e9c8eabc": "Central Parresia 02 · Lançamento do Unio",
        "f6c0b658": "Central Parresia 03 · Frota WP: rollout do UltraPack",
        "dc7fd131": "ClickUp · faxina dos cards e contas de QA",
        "098e7720": "Unio · feedbacks de usabilidade do grupo",
        "64168bfb": "Unio · QA nível 1 e 2 em produção",
        "8cec31ca": "Koynus · planejamento M28/M30 e WhatsApp",
        "93c8b09f": "Koynus · Desk: StackLab Kanban Pro e tema",
        "8d0aae10": "Frota WP · padrão de plugins v1 e dailys",
        "7c209d23": "Frota WP · chave SSH dos servidores e acessos no DÜ SOL",
        "301f6217": "Mettria · tutoriais em vídeo: roteiro, notas e card",
        "2794475e": "CNBB · Liturgia das Horas: falha e publicação até jan/27",
        "23682d7f": "SUP-1025 · lentidão da Rádio Frei Galvão",
        "fc244b2e": "SUP-1055 · QA do site da Paróquia de Iconha",
        "7c431743": "QA Itapetininga · de-para, checklist e evidências",
    },
    "Celiware": {
        "c8974836": "Central Valdir 01",
        "8e56f520": "Parceria Valdir · contrato de 6 meses",
        "95d8559b": "Ware IoT · versões 1.4/1.5, site e Play Store",
        "0b4f8dc7": "Fábrica de Conteúdo · briefing e piloto Padrão TEX",
        "b5c31e67": "Inovance · site: viabilidade e preço",
        "090d91e7": "ManagementAI · orçamento do MVP (Thiago)",
        "19a0f650": "Instituto · esteira de artigos e falhas do Publicar",
        "fbba2f2f": "Instituto · teste automático (responda ok)",
    },
    "Desbravando": {
        "811c36d0": "Central Desbravando 01",
        "e1917436": "Central Desbravando 02",
        "cba9a24f": "Desbravando · artes: crachá, camiseta, cardápio e formulários",
    },
    "Retífica": {
        "6bf320c9": "Retífica · aceite, mensalidade e pedidos do James",
    },
    "Faculdade": {
        "2e6f9f35": "APS · projeto final Rufus Bank",
        "a1c9b5cb": "Itinerário Extensionista · backend do Conecta+",
        "78ce7d1f": "Seminário Grupo 2 · transferência confiável",
        "dcdafea1": "Avaliações online de 30/10 · Cálculo II e outras",
        "71bd1b21": "NoSQL · prova: MongoDB, SQLite e Redis",
        "f9b5686e": "Eng. de Software · caso de uso do app de eventos",
        "26c7f2c5": "Perícia Forense · prática de aquisição (aula 04)",
        "510e4eab": "Perícia Forense · práticas forenses (aula 05)",
        "acbc1356": "CodeCare · proposta ao grupo e mensagem ao professor",
    },
    "Sistemas": {
        "60be9ed0": "Faxina geral · Ágora, Sinapse, esteira, Cosmos, PC",
        "115141a0": "Esteira de QA universal · construção e pesquisa",
        "cb1b6068": "Sessões do Claude · títulos, memória e Sinapse",
        "ab7f8db8": "Máquina · janelas de cmd piscando no boot",
    },
    "Pessoal": {
        "e51e9ec8": "Presente da Duda · boinas (aniversário 17/11)",
        "25868821": "Rolê de sexta à noite em JP",
        "b337c786": "Golpe de emprego pelo WhatsApp",
        "3326949b": "Galeria de fotos com IA local",
        "dfb2c04f": "TV AOC 55 · compra, análise e devolução",
        "67bec197": "Fantasia a partir do corte de cabelo",
        "f5b299e3": "Foto de perfil do WhatsApp · edição RYZE",
    },
}


def vscode_aberto():
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Code.exe", "/NH"], capture_output=True, text=True)
    return "Code.exe" in r.stdout


def resolver(prefixo):
    achados = [f[:-6] for f in os.listdir(POOL) if f.startswith(prefixo) and f.endswith(".jsonl")]
    return achados[0] if len(achados) == 1 else None


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # o terminal do Windows (cp1252) não escreve "★"
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
        # os grupos deste script são refeitos a cada execução; grupo vazio ("New group") sai; grupo que você
        # criou à mão com outro nome fica, e as sessões dele não são mexidas
        meus = set(GRUPOS) | {ATIVOS_NOME}
        manter = [g for g in antigos if g.get("sessionIds") and g.get("name") not in meus]
        ja_agrupadas = {s for g in manter for s in g["sessionIds"]}
        ativos = [sid for p in ATIVOS for sid in [resolver(p)] if sid and sid not in ja_agrupadas]
        topo = [{"id": str(uuid.uuid4()), "name": ATIVOS_NOME, "collapsed": False, "sessionIds": ativos}]
        novos = [{"id": str(uuid.uuid4()), "name": nome, "collapsed": True,
                  "sessionIds": [sid for sid, _ in itens if sid not in ja_agrupadas and sid not in ativos]}
                 for nome, itens in grupos.items()]
        novos = topo + [g for g in novos if g["sessionIds"]]
        estado[chave_g] = novos + manter
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
