"""Configuração do painel: um JSON por usuário, editável pela janela "Configurar"."""
import json, os, re, sys

APP = "LabPainel"


def pasta_config():
    if sys.platform.startswith("win"):
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, APP)
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "lab-painel")


def caminho_config():
    return os.environ.get("LAB_PAINEL_CONFIG") or os.path.join(pasta_config(), "config.json")


PADRAO = {
    "titulo": "Laboratório de Informática",
    "chave_ssh": os.path.join("~", ".ssh", "lab_nopass_ed25519"),
    "porta_ssh": 22,
    "usuario_padrao": "",          # vazio = usuário igual ao nome do PC (a1, b2...)
    "broadcast": "192.168.0.255",  # para o Wake-on-LAN
    "pasta_ferramentas": "/usr/local/lib/lab",  # onde o instalador deixou os comandos nos PCs
    "corredor_apos": "",           # ex.: "D" desenha um corredor entre as colunas D e E
    "pcs": [],                     # [{"nome": "a1", "ip": "192.168.0.101", "mac": "", "usuario": ""}]
}

RE_NOME = re.compile(r"^[a-z]\d{1,2}$")
RE_MAC = re.compile(r"^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$")
RE_HOST = re.compile(r"^[\w.\-]+$")


def carregar():
    cfg = json.loads(json.dumps(PADRAO))
    try:
        with open(caminho_config(), encoding="utf-8") as f:
            cfg.update(json.load(f))
    except FileNotFoundError:
        cfg["_primeira_vez"] = True
    except (OSError, ValueError):
        cfg["_erro"] = True
    return cfg


def salvar(cfg):
    cfg = {k: v for k, v in cfg.items() if not k.startswith("_")}
    caminho = caminho_config()
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    tmp = caminho + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    os.replace(tmp, caminho)


def pcs_para_texto(pcs):
    linhas = []
    for p in pcs:
        campos = [p["nome"], p.get("ip") or "-", p.get("mac", ""), p.get("usuario", "")]
        linhas.append(" ".join(c for c in campos if c))
    return "\n".join(linhas)


def texto_para_pcs(texto):
    """Uma linha por PC: `nome ip [mac] [usuario]`.
    Aceita também o formato antigo `a1: 192.168.0.101  (Info-A1)`. Retorna (pcs, erros)."""
    pcs, erros, vistos = [], [], set()
    for n, linha in enumerate(texto.splitlines(), 1):
        linha = re.sub(r"\(.*?\)", " ", linha.split("#")[0])
        linha = re.sub(r"^\s*(\S+?):", r"\1 ", linha)
        partes = linha.split()
        if not partes:
            continue
        nome = partes[0].lower()
        if not RE_NOME.match(nome):
            erros.append(f"linha {n}: o nome '{partes[0]}' deve ser uma letra + número (a1, b12...)")
            continue
        if nome in vistos:
            erros.append(f"linha {n}: nome repetido ({nome})")
            continue
        vistos.add(nome)
        ip = partes[1] if len(partes) > 1 and partes[1] != "-" else ""
        if ip and not RE_HOST.match(ip):
            erros.append(f"linha {n}: endereço inválido '{ip}'")
            continue
        resto = partes[2:]
        mac = resto.pop(0) if resto and RE_MAC.match(resto[0]) else ""
        pcs.append({"nome": nome, "ip": ip, "mac": mac, "usuario": resto[0] if resto else ""})
    return pcs, erros
