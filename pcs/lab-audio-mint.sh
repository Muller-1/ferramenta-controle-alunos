#!/usr/bin/env bash
# =============================================================================
# lab-audio-mint.sh — volume dos PCs sob controle do professor (Linux Mint, XFCE ou Cinnamon)
#   1. O aluno NÃO controla o volume: um guarda (serviço lab-audio, roda como root) trava o volume do
#      PipeWire/ALSA no valor definido pelo professor, a cada 1 s e na hora que algo muda no mixer.
#   2. Ferramentas de áudio (pactl, wpctl, amixer, alsamixer, pavucontrol, pw-cli, pw-metadata) só para admins.
#   3. Sem controle de volume na tela: applet de som tirado do painel (Cinnamon), teclas de volume desligadas.
#      (No XFCE o plugin de volume do painel é tirado pelo lab-aparencia-mint.sh.)
#   4. O professor muda o volume de longe (comando "volume", ver lab-ferramentas-mint.sh): lab volume 60 todos
# Configuração do professor: /etc/lab-audio.conf  (volume=0..100, mudo=0|1, caixas=0|1)
#   caixas=0: alto-falantes internos sempre mudos (só o fone toca), como antes; caixas=1: alto-falantes liberados.
# Substitui o antigo mutar-alto-falantes.service. Não reinicia nada do aluno.
# Uso:   sudo bash lab-audio-mint.sh              (aplica)
#        sudo bash lab-audio-mint.sh --desfazer   (devolve o controle ao aluno e religa o serviço antigo)
# Seguro para rodar de novo.
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR

ALUNO="aluno"
LIB="/usr/local/lib/lab"
CONF="/etc/lab-audio.conf"
FERRAMENTAS=(/usr/bin/pactl /usr/bin/wpctl /usr/bin/amixer /usr/bin/alsamixer /usr/bin/pavucontrol /usr/bin/pw-cli /usr/bin/pw-metadata)
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }
aviso(){ echo "  [aviso] $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
UID_ALUNO="$(id -u "$ALUNO")"
BUS="unix:path=/run/user/$UID_ALUNO/bus"
SESSAO=0; [[ -S "/run/user/$UID_ALUNO/bus" ]] && SESSAO=1
echo "Máquina: $(hostname)"

# ------------------------------------------------------------------ desfazer --
if [[ "${1:-}" == "--desfazer" ]]; then
  info "Desfazendo controle de volume"
  systemctl disable --now lab-audio.service >/dev/null 2>&1 || true
  chattr -i "$LIB/audio-guarda.py" 2>/dev/null || true
  rm -f /etc/systemd/system/lab-audio.service "$LIB/audio-guarda.py" /etc/dconf/db/local.d/12-lab-sem-volume /etc/dconf/db/local.d/locks/12-lab-sem-volume
  for b in "${FERRAMENTAS[@]}"; do
    if dpkg-statoverride --list "$b" >/dev/null 2>&1; then dpkg-statoverride --remove "$b"; chmod 755 "$b"; fi
  done
  systemctl daemon-reload; dconf update 2>/dev/null || true
  systemctl enable --now mutar-alto-falantes.service >/dev/null 2>&1 || true
  ok "guarda removido, ferramentas liberadas, serviço antigo de mudo religado (o applet de som volta pelo lab-aparencia-mint.sh --desfazer)"
  exit 0
fi

# ---------------------------------------------------------------- configuração --
info "1) Configuração do professor ($CONF)"
if [[ ! -f "$CONF" ]]; then
  printf '# Volume dos PCs do laboratório (mude pelo comando: lab volume 60 todos)\nvolume=50\nmudo=0\ncaixas=0\n' > "$CONF"
  ok "criada com volume=50, mudo=0, caixas=0 (alto-falantes mudos, só o fone toca)"
else
  ok "já existe: $(tr '\n' ' ' < "$CONF" | sed 's/#[^v]*//')"
fi
chown root:root "$CONF"; chmod 644 "$CONF"

# ------------------------------------------------------------------------ guarda --
info "2) Guarda do volume (serviço lab-audio, a cada 1 s)"
install -d -m 755 "$LIB"
chattr -i "$LIB/audio-guarda.py" 2>/dev/null || true
cat > "$LIB/audio-guarda.py" <<'EOF'
#!/usr/bin/env python3
# Mantém o volume do PC no valor do professor (/etc/lab-audio.conf), a cada 1 s e quando o mixer mudar.
# - alto-falantes internos (controles ALSA "Speaker"): mudos, a menos que caixas=1
# - volume e mudo do PipeWire do aluno: sempre iguais aos do professor (o aluno não consegue mudar)
import os, re, subprocess, signal, threading, pwd
CONF, ALUNO = "/etc/lab-audio.conf", "aluno"
ev = threading.Event()
signal.signal(signal.SIGUSR1, lambda *a: ev.set())

def conf():
    c = {"volume": "50", "mudo": "0", "caixas": "0"}
    try:
        for l in open(CONF):
            m = re.match(r"^\s*(volume|mudo|caixas)\s*=\s*([0-9]+)\s*$", l)
            if m: c[m.group(1)] = m.group(2)
    except OSError:
        pass
    return max(0, min(100, int(c["volume"]))), c["mudo"] == "1", c["caixas"] == "1"

def sh(args, env=None):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=6, env=env)
        return r.returncode, r.stdout
    except Exception:
        return 1, ""

def placas():
    try: return re.findall(r"^\s*(\d+) \[", open("/proc/asound/cards").read(), re.M)
    except OSError: return []

def alsa(caixas):
    """Trata os 'Speaker' e diz se há fone plugado."""
    fone = False
    for p in placas():
        _, out = sh(["amixer", "-c", p, "scontrols"])
        for linha in out.splitlines():
            m = re.match(r"Simple mixer control '(.+)',(\d+)", linha)
            if m and "Speaker" in m.group(1):
                alvo = "%s,%s" % (m.group(1), m.group(2))
                if caixas: sh(["amixer", "-c", p, "-q", "sset", alvo, "unmute"])
                else:
                    rc, _ = sh(["amixer", "-c", p, "-q", "sset", alvo, "mute"])
                    if rc: sh(["amixer", "-c", p, "-q", "sset", alvo, "0%"])
        _, cont = sh(["amixer", "-c", p, "contents"])
        for bloco in re.split(r"(?=numid=)", cont):
            if re.search(r"name='[^']*Headphone Jack'", bloco) and ": values=on" in bloco: fone = True
    return fone

def pipewire(vol, mudo, som_livre):
    try: uid = pwd.getpwnam(ALUNO).pw_uid
    except KeyError: return
    rt = "/run/user/%d" % uid
    if not os.path.exists(rt + "/pipewire-0"): return
    env = dict(os.environ, XDG_RUNTIME_DIR=rt)
    _, out = sh(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], env)
    m = re.search(r"Volume:\s*([0-9.]+)(\s*\[MUTED\])?", out)
    if not m: return
    atual, mutado = float(m.group(1)), bool(m.group(2))
    alvo = vol / 100.0
    if abs(atual - alvo) > 0.004: sh(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "%.2f" % alvo], env)
    if mudo and not mutado: sh(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"], env)
    elif not mudo and mutado and som_livre: sh(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"], env)

def monitor():
    try:
        p = subprocess.Popen(["alsactl", "monitor"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        for _ in p.stdout: ev.set()
    except Exception:
        pass
threading.Thread(target=monitor, daemon=True).start()

while True:
    vol, mudo, caixas = conf()
    fone = alsa(caixas)
    pipewire(vol, mudo, fone or caixas)
    ev.wait(1.0); ev.clear()
EOF
chmod 755 "$LIB/audio-guarda.py"; chown root:root "$LIB/audio-guarda.py"
cat > /etc/systemd/system/lab-audio.service <<EOF
[Unit]
Description=Guarda do volume do laboratório (professor define, aluno não muda)
After=sound.target
[Service]
ExecStart=/usr/bin/python3 $LIB/audio-guarda.py
Restart=always
RestartSec=2
Nice=-5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl disable --now mutar-alto-falantes.service >/dev/null 2>&1 || true   # o guarda faz o trabalho dele
systemctl enable --now lab-audio.service >/dev/null 2>&1
systemctl restart lab-audio.service
chattr +i "$LIB/audio-guarda.py"
ok "guarda ativo (substitui o mutar-alto-falantes)"

# ------------------------------------------------------- ferramentas só para admins --
info "3) Ferramentas de áudio só para admins"
for b in "${FERRAMENTAS[@]}"; do
  [[ -x "$b" ]] || continue
  dpkg-statoverride --list "$b" >/dev/null 2>&1 || dpkg-statoverride --update --add root sudo 750 "$b"
  echo "    só admins: $b"
done

# ----------------------------------------------------- sem controle de volume na tela --
info "4) Sem controle de volume na tela"
if command -v cinnamon >/dev/null 2>&1 && [[ -d /etc/dconf ]]; then
  install -d -m 755 /etc/dconf/db/local.d /etc/dconf/db/local.d/locks
  M=/org/cinnamon/desktop/keybindings/media-keys
  KEYS=(volume-up volume-down volume-mute volume-up-quiet volume-down-quiet)
  { echo "[org/cinnamon/desktop/keybindings/media-keys]"; for k in "${KEYS[@]}"; do echo "$k=@as []"; done; } > /etc/dconf/db/local.d/12-lab-sem-volume
  for k in "${KEYS[@]}"; do echo "$M/$k"; done > /etc/dconf/db/local.d/locks/12-lab-sem-volume
  # tira o applet de som do painel (arquivo do lab-aparencia, se existir, e a sessão aberta)
  python3 -I - "$ALUNO" "$UID_ALUNO" <<'PY'
import re, subprocess, sys, os
aluno, uid = sys.argv[1], sys.argv[2]
env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/%s/bus" % uid)
def lerv():
    r = subprocess.run(["runuser", "-u", aluno, "--", "env", "DBUS_SESSION_BUS_ADDRESS=" + env["DBUS_SESSION_BUS_ADDRESS"], "gsettings", "get", "org.cinnamon", "enabled-applets"], capture_output=True, text=True)
    return r.stdout.strip()
atual = lerv()
itens = re.findall(r"'([^']*)'", atual)
novos = [i for i in itens if "sound@cinnamon.org" not in i]
if novos != itens and novos:
    texto = "[" + ", ".join("'%s'" % i for i in novos) + "]"
    arq = "/etc/dconf/db/local.d/20-lab-aparencia"
    if os.path.exists(arq):
        t = open(arq, encoding="utf-8").read()
        t = re.sub(r"^enabled-applets=.*$", "enabled-applets=" + texto, t, flags=re.M)
        open(arq, "w", encoding="utf-8").write(t)
    subprocess.run(["runuser", "-u", aluno, "--", "env", "DBUS_SESSION_BUS_ADDRESS=" + env["DBUS_SESSION_BUS_ADDRESS"], "dconf", "write", "/org/cinnamon/enabled-applets", texto])
    print("applet de som removido do painel")
else:
    print("painel já está sem o applet de som")
PY
  dconf update
  if (( SESSAO )); then   # teclas de volume desligadas já na sessão aberta
    for k in "${KEYS[@]}"; do runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" dconf write "$M/$k" "@as []" 2>/dev/null || true; done
  fi
  ok "Cinnamon: teclas de volume desligadas (travadas no dconf) e applet de som fora do painel"
fi
if command -v xfce4-panel >/dev/null 2>&1; then
  ok "XFCE: o plugin de volume do painel e as teclas saem pelo lab-aparencia-mint.sh (rode-o depois deste)"
fi

echo
echo "Pronto. Mude o volume de longe com: lab volume 60 todos   |   lab volume mudo todos   |   lab volume som todos"
