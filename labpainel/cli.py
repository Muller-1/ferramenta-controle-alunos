"""Linha de comando:  lab-painel lab <acao> [todos | a1 b2 ...]   (mesmos comandos do painel)."""
import concurrent.futures, getpass, sys

from . import config, core

ACOES = ["fechar-roblox", "tirar-conta-roblox", "fechar-apps", "bloquear-input", "liberar-input", "travar-tela",
         "liberar-tela", "reiniciar", "desligar", "sair", "entrar", "estado", "reiniciar-veyon", "abrir-app"]
USO = ("uso: lab-painel lab <acao> [-m \"mensagem\" | -a \"app\"] [todos | a1 b2 ...]\n"
       "  travar-tela -m \"texto\"   cobre a tela com a mensagem (sem -m, a padrão)\n"
       "  abrir-app -a \"nome\"      abre o aplicativo na tela dos alunos\n"
       "  acoes: " + " | ".join(ACOES) + "\n"
       "  status      mostra quais PCs estão no ar\n"
       "  implantar   instala as ferramentas nos PCs (pede a senha do sudo dos admins)\n")


def main(argv):
    if not argv or argv[0] not in ACOES + ["status", "implantar"]:
        print(USO)
        return 1
    acao, nomes, extra = argv[0], argv[1:], ""
    if nomes[:1] and nomes[0] in ("-m", "--mensagem", "-a", "--app"):
        extra, nomes = (nomes[1] if len(nomes) > 1 else ""), nomes[2:]
    if acao == "abrir-app" and not extra:
        print('Diga o app: lab abrir-app -a "nome do app" [todos | a1 b2 ...]')
        return 1
    cfg = config.carregar()
    pcs = [core.PC(d) for d in cfg["pcs"] if d.get("ip")]
    if nomes and nomes != ["todos"]:
        pcs = [p for p in pcs if p.nome in nomes]
    if not pcs:
        print("nenhum PC encontrado em", config.caminho_config())
        return 1
    senha = getpass.getpass("Senha do sudo dos admins dos PCs: ") if acao == "implantar" else None

    def uma(p):
        if acao == "status":
            return p, ("ligado" if core.tcp_ok(p.ip, cfg["porta_ssh"]) else "desligado"), True
        if acao == "implantar":
            return (p,) + core.implantar(cfg, p, senha)
        return (p,) + core.ssh_exec(cfg, p, core.comando_remoto(cfg, acao, extra))

    ok_geral = True
    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as ex:
        for p, linha, ok in sorted(ex.map(uma, pcs), key=lambda r: (r[0].col, r[0].lin)):
            print(f"{p.nome}: {linha}")
            ok_geral &= ok
    return 0 if ok_geral else 2
