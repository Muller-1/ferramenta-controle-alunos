#!/usr/bin/env python3
"""preparar-pacote.py — monta o pacote do Minecraft do lab (roda no PC do professor, uma vez por versão).

Baixa SÓ de fontes oficiais e confere o hash de cada arquivo:
  Mojang (jogo, bibliotecas, sons/texturas, Java oficial), Fabric (loader) e Modrinth (mods de desempenho).
Resultado: PACOTE/ com runtime/ libraries/ assets/ versions/ mods/ versao.json  (~800 MB).
Depois o instalar-minecraft-mint.sh copia esse pacote pela rede local para /opt/lab-minecraft dos PCs.

Uso: python3 preparar-pacote.py PACOTE [--versao 26.3] [--cache PASTA_.minecraft_antiga]
"""
import argparse, hashlib, json, os, shutil, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

MODS = ["sodium", "lithium", "ferrite-core", "immediatelyfast", "entityculling", "fabric-api"]
UA = {"User-Agent": "lab-minecraft-preparar/1.0"}


def baixar_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def hash_arq(path, alg):
    h = hashlib.new(alg)
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def obter(url, dest, sha=None, alg="sha1", cache=None):
    """Garante dest com o hash certo: usa o que já existe, depois o cache, depois baixa."""
    if os.path.isfile(dest) and (not sha or hash_arq(dest, alg) == sha):
        return "ok"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if cache and os.path.isfile(cache) and sha and hash_arq(cache, alg) == sha:
        shutil.copyfile(cache, dest)
        return "cache"
    tmp = dest + ".part"
    for tentativa in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f)
            if sha and hash_arq(tmp, alg) != sha:
                raise IOError("hash não confere")
            os.replace(tmp, dest)
            return "baixado"
        except Exception as e:  # noqa: BLE001
            err = e
    raise SystemExit(f"ERRO baixando {url}: {err}")


def regra_ok(regras):
    if not regras:
        return True
    ok = False
    for r in regras:
        os_ = r.get("os", {}).get("name")
        if "features" in r:
            continue
        if os_ is None or os_ == "linux":
            ok = r["action"] == "allow"
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pacote")
    ap.add_argument("--versao", default="26.3")
    ap.add_argument("--cache", help="pasta .minecraft antiga para reaproveitar arquivos (só se o hash bater)")
    a = ap.parse_args()
    P = os.path.abspath(a.pacote)
    C = a.cache
    tarefas = []  # (url, dest, sha, alg, cache)

    man = baixar_json("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    ent = next(v for v in man["versions"] if v["id"] == a.versao)
    vdir = f"{P}/versions/{a.versao}"
    obter(ent["url"], f"{vdir}/{a.versao}.json", ent["sha1"])
    vj = json.load(open(f"{vdir}/{a.versao}.json"))
    cl = vj["downloads"]["client"]
    tarefas.append((cl["url"], f"{vdir}/{a.versao}.jar", cl["sha1"], "sha1", C and f"{C}/versions/{a.versao}/{a.versao}.jar"))

    def libs(lista):
        for lib in lista:
            if not regra_ok(lib.get("rules")):
                continue
            art = lib.get("downloads", {}).get("artifact")
            if art:
                tarefas.append((art["url"], f"{P}/libraries/{art['path']}", art["sha1"], "sha1", C and f"{C}/libraries/{art['path']}"))
            elif "url" in lib:  # estilo maven (Fabric)
                g, n, v = lib["name"].split(":")[:3]
                path = f"{g.replace('.', '/')}/{n}/{v}/{n}-{v}.jar"
                tarefas.append((lib["url"].rstrip("/") + "/" + path, f"{P}/libraries/{path}", lib.get("sha1"), "sha1", None))
    libs(vj["libraries"])

    # sons/texturas
    ai = vj["assetIndex"]
    obter(ai["url"], f"{P}/assets/indexes/{ai['id']}.json", ai["sha1"])
    for obj in json.load(open(f"{P}/assets/indexes/{ai['id']}.json"))["objects"].values():
        h = obj["hash"]
        rel = f"objects/{h[:2]}/{h}"
        tarefas.append((f"https://resources.download.minecraft.net/{h[:2]}/{h}", f"{P}/assets/{rel}", h, "sha1", C and f"{C}/assets/{rel}"))
    # log config
    lg = vj.get("logging", {}).get("client", {}).get("file")
    if lg:
        tarefas.append((lg["url"], f"{P}/assets/log_configs/{lg['id']}", lg["sha1"], "sha1", None))

    # Java oficial da Mojang
    comp = vj["javaVersion"]["component"]
    rt_all = baixar_json("https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json")
    rt = rt_all["linux"][comp][0]
    rtm = baixar_json(rt["manifest"]["url"])
    rdir = f"{P}/runtime/{comp}"
    execs = []
    for path, f in rtm["files"].items():
        dest = f"{rdir}/{path}"
        if f["type"] == "directory":
            os.makedirs(dest, exist_ok=True)
        elif f["type"] == "link":
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if not os.path.lexists(dest):
                os.symlink(f["target"], dest)
        else:
            raw = f["downloads"]["raw"]
            tarefas.append((raw["url"], dest, raw["sha1"], "sha1", C and f"{C}/runtime/{comp}/linux/{comp}/{path}"))
            if f.get("executable"):
                execs.append(dest)

    # Fabric
    fl = baixar_json(f"https://meta.fabricmc.net/v2/versions/loader/{a.versao}")
    loader = next(x for x in fl if x["loader"]["stable"])["loader"]["version"]
    fid = f"fabric-loader-{loader}-{a.versao}"
    fj = baixar_json(f"https://meta.fabricmc.net/v2/versions/loader/{a.versao}/{loader}/profile/json")
    os.makedirs(f"{P}/versions/{fid}", exist_ok=True)
    json.dump(fj, open(f"{P}/versions/{fid}/{fid}.json", "w"), indent=1)
    libs(fj["libraries"])

    # mods (Modrinth, sha512)
    mods_info = []
    for proj in MODS:
        vs = baixar_json(f'https://api.modrinth.com/v2/project/{proj}/version?loaders=%5B%22fabric%22%5D&game_versions=%5B%22{a.versao}%22%5D')
        vs = [v for v in vs if v["version_type"] == "release"]
        if not vs:
            raise SystemExit(f"ERRO: {proj} não tem versão para {a.versao}")
        f = next(x for x in vs[0]["files"] if x["primary"])
        tarefas.append((f["url"], f"{P}/mods/{f['filename']}", f["hashes"]["sha512"], "sha512", None))
        mods_info.append(f["filename"])
    # tira mods antigos
    if os.path.isdir(f"{P}/mods"):
        for x in os.listdir(f"{P}/mods"):
            if x not in mods_info:
                os.remove(f"{P}/mods/{x}")

    print(f"{len(tarefas)} arquivos para conferir/baixar...", flush=True)
    cont = {}
    with ThreadPoolExecutor(8) as ex:
        for r in ex.map(lambda t: obter(t[0], t[1], t[2], t[3], t[4]), tarefas):
            cont[r] = cont.get(r, 0) + 1
    for e in execs:
        os.chmod(e, 0o755)
    # ícone oficial (dos assets) + arquivos do lab (abridor e opções leves) dentro do pacote
    idx = json.load(open(f"{P}/assets/indexes/{ai['id']}.json"))["objects"]
    h = idx["icons/icon_128x128.png"]["hash"]
    shutil.copyfile(f"{P}/assets/objects/{h[:2]}/{h}", f"{P}/icone.png")
    aqui = os.path.dirname(os.path.abspath(__file__))
    shutil.copyfile(f"{aqui}/jogar-minecraft.py", f"{P}/jogar")
    os.chmod(f"{P}/jogar", 0o755)
    shutil.copyfile(f"{aqui}/options-padrao.txt", f"{P}/options-padrao.txt")
    json.dump({"minecraft": a.versao, "fabric": fid, "java": comp, "mods": mods_info, "assetIndex": ai["id"]},
              open(f"{P}/versao.json", "w"), indent=1)
    print("pronto:", cont, "| versão:", fid, "| mods:", " ".join(mods_info))


if __name__ == "__main__":
    main()
