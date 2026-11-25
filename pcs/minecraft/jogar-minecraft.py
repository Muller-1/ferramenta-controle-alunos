#!/usr/bin/env python3
"""Abre o Minecraft do lab direto, sem launcher (leve: nada fica aberto além do jogo).

- Modo offline (sem conta): o aluno só escolhe um apelido. Todos os PCs têm a mesma versão,
  então "Abrir para LAN" funciona entre eles.
- Jogo e mods ficam em /opt/lab-minecraft (só leitura); mundos e opções em /var/lib/lab-minecraft/jogo
  (fora do /home, por isso o perfil limpo não apaga e não precisa baixar nada de novo).
- O jogo roda num "cercado" do systemd: no máximo ~3,6 GB de RAM e prioridade de CPU menor,
  para não travar o PC nem o Veyon. Se passar do limite, só o jogo fecha.
- Se o professor bloquear (lab minecraft bloquear), mostra um aviso e não abre.
"""
import hashlib, json, os, re, socket, subprocess, sys, uuid

BASE = "/opt/lab-minecraft"
JOGO = "/var/lib/lab-minecraft/jogo"
BLOQ = "/etc/lab/minecraft-bloqueado"
TITULO = "Minecraft"


def zen(*args):
    try:
        return subprocess.run(["zenity", f"--title={TITULO}", "--width=380", *args], capture_output=True, text=True)
    except FileNotFoundError:
        print(" ".join(args), file=sys.stderr)
        return subprocess.CompletedProcess(args, 1, "", "")


def aviso(t):
    zen("--info", "--text", t)


def rodando():
    r = subprocess.run(["pgrep", "-u", str(os.getuid()), "-f", f"{BASE}/runtime/"], capture_output=True)
    return r.returncode == 0


def regra_ok(regras):
    if not regras:
        return True
    ok = False
    for r in regras:
        if "features" in r:
            return False
        nome = r.get("os", {}).get("name")
        arch = r.get("os", {}).get("arch")
        if (nome in (None, "linux")) and (arch in (None, "x86_64", "x64")):
            ok = r["action"] == "allow"
    return ok


def args_de(lista):
    out = []
    for a in lista:
        if isinstance(a, str):
            out.append(a)
        elif regra_ok(a.get("rules")):
            v = a["value"]
            out += v if isinstance(v, list) else [v]
    return out


def chave_lib(nome):
    p = nome.split(":")
    return ":".join([p[0], p[1]] + p[3:])  # grupo:artefato[:classificador], sem a versão


def caminho_lib(lib):
    art = lib.get("downloads", {}).get("artifact")
    if art:
        return f"{BASE}/libraries/{art['path']}"
    g, n, v = lib["name"].split(":")[:3]
    return f"{BASE}/libraries/{g.replace('.', '/')}/{n}/{v}/{n}-{v}.jar"


def apelido_padrao():
    h = re.sub(r"[^A-Za-z0-9]", "", socket.gethostname().replace("Info-", ""))
    return f"Aluno{h}"[:16]


def uuid_offline(nome):  # igual ao UUID.nameUUIDFromBytes do Java ("OfflinePlayer:" + nome)
    b = bytearray(hashlib.md5(f"OfflinePlayer:{nome}".encode()).digest())
    b[6] = (b[6] & 0x0F) | 0x30
    b[8] = (b[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(b)))


def main():
    if os.path.exists(BLOQ):
        aviso("O Minecraft está fechado agora.\nO professor libera quando for a hora. 🙂")
        return 0
    if rodando():
        aviso("O Minecraft já está aberto.")
        return 0
    if not os.access(JOGO, os.W_OK):
        aviso(f"A pasta do jogo não está pronta ({JOGO}). Chame o professor.")
        return 1

    info = json.load(open(f"{BASE}/versao.json"))
    arq_apelido = f"{JOGO}/apelido.txt"
    ultimo = open(arq_apelido).read().strip() if os.path.exists(arq_apelido) else apelido_padrao()
    apelido = None
    env_ap = os.environ.get("LAB_MC_APELIDO", "")  # para testes/abrir remoto sem perguntar
    if re.fullmatch(r"[A-Za-z0-9_]{3,16}", env_ap):
        apelido = env_ap
    while apelido is None:
        r = zen("--entry", "--text", "Seu apelido no jogo (3 a 16 letras ou números, sem espaço):", "--entry-text", ultimo)
        if r.returncode != 0:
            return 0  # cancelou
        n = r.stdout.strip()
        if re.fullmatch(r"[A-Za-z0-9_]{3,16}", n):
            apelido = n
        else:
            aviso("Use só letras sem acento, números ou _ (de 3 a 16).")
            ultimo = re.sub(r"[^A-Za-z0-9_]", "", n)[:16] or apelido_padrao()
    with open(arq_apelido, "w") as f:
        f.write(apelido + "\n")

    # pasta do jogo: mods sempre os do lab (só leitura); opções leves na primeira vez
    mods = f"{JOGO}/mods"
    if os.path.islink(mods) or os.path.exists(mods):
        if os.path.realpath(mods) != f"{BASE}/mods":
            subprocess.run(["rm", "-rf", mods])
    if not os.path.exists(mods):
        os.symlink(f"{BASE}/mods", mods)
    opts = f"{JOGO}/options.txt"
    if not os.path.exists(opts) and os.path.exists(f"{BASE}/options-padrao.txt"):
        with open(f"{BASE}/options-padrao.txt") as s, open(opts, "w") as d:
            d.write(s.read())
    nat = f"{JOGO}/.nativos"
    os.makedirs(f"{JOGO}/logs", exist_ok=True)

    mc, fab = info["minecraft"], info["fabric"]
    vj = json.load(open(f"{BASE}/versions/{mc}/{mc}.json"))
    fj = json.load(open(f"{BASE}/versions/{fab}/{fab}.json"))

    cp, vistos = [], set()
    for lib in fj["libraries"] + vj["libraries"]:  # Fabric primeiro (ganha em caso de repetição)
        if not regra_ok(lib.get("rules")):
            continue
        k = chave_lib(lib["name"])
        if k in vistos:
            continue
        vistos.add(k)
        p = caminho_lib(lib)
        if os.path.exists(p):
            cp.append(p)
    cp.append(f"{BASE}/versions/{mc}/{mc}.jar")

    var = {
        "auth_player_name": apelido, "version_name": fab, "game_directory": JOGO,
        "assets_root": f"{BASE}/assets", "assets_index_name": info["assetIndex"],
        "auth_uuid": uuid_offline(apelido), "auth_access_token": "0", "clientid": "0", "auth_xuid": "0",
        "user_type": "legacy", "version_type": "release", "natives_directory": nat,
        "launcher_name": "lab-minecraft", "launcher_version": "1.0", "classpath": ":".join(cp),
        "classpath_separator": ":", "library_directory": f"{BASE}/libraries",
    }
    sub = lambda s: re.sub(r"\$\{(\w+)\}", lambda m: var.get(m.group(1), ""), s)

    jvm = ["-Xms768m", "-Xmx2G", "-XX:+UseG1GC", "-XX:MaxGCPauseMillis=50"]
    jvm += [sub(a) for a in args_de(vj["arguments"]["jvm"]) + args_de(fj.get("arguments", {}).get("jvm", []))]
    jogo = [sub(a) for a in args_de(vj["arguments"]["game"]) + args_de(fj.get("arguments", {}).get("game", []))]
    java = f"{BASE}/runtime/{info['java']}/bin/java"
    cmd = [java, *jvm, fj["mainClass"], *jogo]

    # cercado do systemd (limite de RAM/CPU); gamemode deixa a CPU em desempenho só enquanto joga
    pre = []
    if subprocess.run(["systemd-run", "--user", "--scope", "--quiet", "true"], capture_output=True).returncode == 0:
        pre = ["systemd-run", "--user", "--scope", "--quiet", f"--unit=lab-minecraft-{os.getpid()}",
               "-p", "MemoryHigh=3G", "-p", "MemoryMax=3700M", "-p", "CPUWeight=60", "--"]
    if os.path.exists("/usr/games/gamemoderun"):
        pre += ["/usr/games/gamemoderun"]
    pre += ["nice", "-n", "5"]
    os.chdir(JOGO)
    log = open(f"{JOGO}/logs/lancador.log", "w")
    log.write(" ".join(pre + cmd[:1]) + " ...\n")
    log.flush()
    os.dup2(log.fileno(), 1)
    os.dup2(log.fileno(), 2)
    os.execvp(pre[0], pre + cmd)


if __name__ == "__main__":
    sys.exit(main())
