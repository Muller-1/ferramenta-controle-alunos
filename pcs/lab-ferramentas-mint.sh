#!/usr/bin/env bash
# =============================================================================
# lab-ferramentas-mint.sh — ferramentas do professor em cada PC do laboratório
# Instala em /usr/local/lib/lab (root, imutáveis, a conta "aluno" não altera):
#   fechar-roblox       fecha o Roblox (Sober)
#   tirar-conta-roblox  fecha o Roblox e apaga o login da conta (próximo uso pede login)
#   fechar-apps         fecha TODOS os programas abertos e mostra a área de trabalho
#   bloquear-input      desliga teclado e mouse/touchpad físicos (o Veyon continua mandando)
#   liberar-input       religa teclado e mouse
#   travar-tela [MENSAGEM]  cobre a tela com uma mensagem e bloqueia teclado/mouse (não fecha nem minimiza nada)
#   liberar-tela        tira o aviso e libera teclado/mouse
#   reiniciar | desligar   reinicia/desliga o PC (daqui a 3 s)
#   sair | entrar       aluno sai (sem login automático por 60 min) / aluno entra de novo
#   estado              uma linha com o estado do PC (usada pelo painel)
#   abrir-app NOME      abre um aplicativo pelo nome (primeiro resultado da busca nos aplicativos instalados)
#   reiniciar-veyon     reinicia só o Veyon (limpa x11vnc preso) para as telas voltarem a aparecer
# Todos funcionam de três jeitos:
#   a) pelo SSH do professor:  lab <acao> [todos|a1 b2 ...]   (comando "lab" do Bazzite)
#   b) como admin no PC:       sudo /usr/local/lib/lab/<acao>
#   c) pelo Veyon ("Executar programa"): /usr/local/lib/lab/<acao>
# O sudo sem senha vale SÓ para esses 5 arquivos, sem argumentos (/etc/sudoers.d/lab-comandos).
# Uso:  sudo bash lab-ferramentas-mint.sh  |  sudo bash lab-ferramentas-mint.sh --desfazer
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR
ALUNO="aluno"
LIB="/usr/local/lib/lab"
SUDOERS="/etc/sudoers.d/lab-comandos"
CMDS=(fechar-roblox tirar-conta-roblox fechar-apps bloquear-input liberar-input travar-tela liberar-tela reiniciar desligar sair entrar estado reiniciar-veyon abrir-app)
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

if [[ "${1:-}" == "--desfazer" ]]; then
  rm -f "$SUDOERS"
  for c in "${CMDS[@]}" _comum overlay-tela.py abrir-app.py; do chattr -i "$LIB/$c" 2>/dev/null || true; rm -f "$LIB/$c"; done
  ok "ferramentas e sudoers removidos"; exit 0
fi

install -d -m 755 "$LIB"
for c in "${CMDS[@]}" _comum overlay-tela.py abrir-app.py; do chattr -i "$LIB/$c" 2>/dev/null || true; done

# ------------------------------------------------------------------- comum -----
cat > "$LIB/_comum" <<'EOF'
# Incluído por todos os comandos. Se chamado como root (sudo/SSH), reexecuta como o aluno
# com o ambiente da sessão gráfica dele.
ALUNO="aluno"
if [[ $EUID -eq 0 ]]; then
  U="$(id -u "$ALUNO")"
  cd "/home/$ALUNO" 2>/dev/null || cd /      # o aluno não consegue entrar na pasta do admin (diretório atual do SSH)
  exec runuser -u "$ALUNO" -- env HOME="/home/$ALUNO" USER="$ALUNO" LOGNAME="$ALUNO" DISPLAY="${DISPLAY:-:0}" XAUTHORITY="/home/$ALUNO/.Xauthority" \
       XDG_RUNTIME_DIR="/run/user/$U" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$U/bus" "$0" "$@"
fi
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
SOBER="org.vinegarhq.Sober"
SOBERDATA="$HOME/.var/app/$SOBER/data/sober"
EOF

# ----------------------------------------------------------------- fechar-roblox
cat > "$LIB/fechar-roblox" <<'EOF'
#!/usr/bin/env bash
# Fecha o Roblox (Sober).
source "$(dirname "$(readlink -f "$0")")/_comum"
flatpak kill "$SOBER" 2>/dev/null || true
sleep 1
pkill -u "$(id -u)" -f "sober" 2>/dev/null || true
if flatpak ps --columns=application 2>/dev/null | grep -q "$SOBER"; then echo "Roblox ainda aberto"; exit 1; fi
echo "$(hostname): Roblox fechado"
EOF

# ------------------------------------------------------------ tirar-conta-roblox
cat > "$LIB/tirar-conta-roblox" <<'EOF'
#!/usr/bin/env bash
# Fecha o Roblox e apaga o login (cookies e dados da conta). Na próxima abertura pede login de novo.
source "$(dirname "$(readlink -f "$0")")/_comum"
flatpak kill "$SOBER" 2>/dev/null || true
sleep 2
rm -f "$SOBERDATA/cookies" \
      "$SOBERDATA/appData/LocalStorage/appStorage.json" \
      "$SOBERDATA/appData/LocalStorage/memProfStorage3.json" 2>/dev/null || true
echo "$(hostname): conta do Roblox removida (Roblox fechado)"
EOF

# ------------------------------------------------------------------ fechar-apps
cat > "$LIB/fechar-apps" <<'EOF'
#!/usr/bin/env bash
# Fecha todos os programas abertos (primeiro com educação, depois à força) e mostra a área de trabalho.
source "$(dirname "$(readlink -f "$0")")/_comum"
command -v wmctrl >/dev/null || { echo "wmctrl não instalado"; exit 1; }
# janelas de programas (ignora painel, área de trabalho, docks e o Veyon)
janelas() {
  wmctrl -lp | while read -r id desk pid host title; do
    t="$(xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null)"
    case "$t" in *DESKTOP*|*DOCK*|*MENU*|*NOTIFICATION*|*TOOLTIP*|*SPLASH*) continue ;; esac
    cl="$(xprop -id "$id" WM_CLASS 2>/dev/null | tr 'A-Z' 'a-z')"
    case "$cl" in *veyon*|*xfdesktop*|*nemo-desktop*|*cinnamon*|*xfce4-panel*|*plank*) continue ;; esac
    echo "$id $pid"
  done
}
flatpak kill "$SOBER" 2>/dev/null || true
for id in $(janelas | awk '{print $1}'); do wmctrl -ic "$id" 2>/dev/null || true; done
sleep 4
for _ in 1 2; do   # o que sobrou: termina e, se insistir, mata
  janelas | awk '$2>1{print $2}' | sort -u | while read -r p; do kill -TERM "$p" 2>/dev/null || true; done
  sleep 2
done
janelas | awk '$2>1{print $2}' | sort -u | while read -r p; do kill -KILL "$p" 2>/dev/null || true; done
sleep 1
wmctrl -k on 2>/dev/null || true
restam="$(janelas | wc -l)"
echo "$(hostname): programas fechados (janelas restantes: $restam), área de trabalho à mostra"
EOF

# --------------------------------------------------------------- bloquear-input
cat > "$LIB/bloquear-input" <<'EOF'
#!/usr/bin/env bash
# Desliga teclado e mouse/touchpad FÍSICOS: solta (xinput float) os aparelhos dos teclados/mouses virtuais.
# O teclado/mouse virtual do Veyon (XTEST) continua funcionando. Fica reaplicando a cada 2 s
# (pega aparelhos USB espetados depois) até rodar liberar-input.
source "$(dirname "$(readlink -f "$0")")/_comum"
command -v xinput >/dev/null || { echo "xinput não instalado"; exit 1; }
RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
FLAG="$RUN/lab-input-bloqueado"; MAP="$RUN/lab-input-mapa"
aplica() {
  xinput list | grep -E 'slave +(keyboard|pointer)' \
    | grep -viE 'XTEST|Virtual core|Power Button|Sleep Button|Video Bus|Lid Switch' | while read -r linha; do
      id="$(sed -E 's/.*id=([0-9]+).*/\1/' <<<"$linha")"
      k=keyboard; grep -qE 'slave +pointer' <<<"$linha" && k=pointer
      grep -qxF "$id $k" "$MAP" 2>/dev/null || echo "$id $k" >> "$MAP"
      xinput float "$id" 2>/dev/null || true
    done
}
if [[ "${1:-}" == "--laco" ]]; then
  while [[ -f "$FLAG" ]]; do aplica; sleep 2; done; exit 0
fi
touch "$FLAG"
aplica
if ! pgrep -u "$(id -u)" -f '[b]loquear-input --laco' >/dev/null; then
  setsid nohup "$0" --laco >/dev/null 2>&1 < /dev/null &
fi
echo "$(hostname): teclado e mouse bloqueados"
EOF

# ---------------------------------------------------------------- liberar-input
cat > "$LIB/liberar-input" <<'EOF'
#!/usr/bin/env bash
# Religa teclado e mouse: reanexa os aparelhos soltos aos teclados/mouses virtuais.
source "$(dirname "$(readlink -f "$0")")/_comum"
RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
FLAG="$RUN/lab-input-bloqueado"; MAP="$RUN/lab-input-mapa"
rm -f "$FLAG"
sleep 3
pkill -u "$(id -u)" -f '[b]loquear-input --laco' 2>/dev/null || true
KM="$(xinput list --id-only 'Virtual core keyboard' 2>/dev/null)"; PM="$(xinput list --id-only 'Virtual core pointer' 2>/dev/null)"
if [[ -f "$MAP" ]]; then
  while read -r id k; do
    m="$KM"; [[ "$k" == pointer ]] && m="$PM"
    xinput enable "$id" 2>/dev/null || true
    xinput reattach "$id" "$m" 2>/dev/null || true
  done < "$MAP"
  rm -f "$MAP"
fi
echo "$(hostname): teclado e mouse liberados"
EOF

# ------------------------------------------------------------------ overlay-tela
cat > "$LIB/overlay-tela.py" <<'EOF'
#!/usr/bin/env python3
# Cobre TODAS as telas com uma janela opaca por cima de tudo (sem moldura, fora do gerenciador de janelas).
# O que acontecer por baixo não aparece. Sai quando o arquivo-sinal sumir ou depois do limite de segurança.
import os, sys, subprocess, gi
gi.require_version('Gtk', '3.0'); gi.require_version('Gdk', '3.0')
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf
FLAG = sys.argv[1]
LIMITE_MIN = 90                      # segurança: solta tudo sozinho depois disso
IMG = '/usr/share/backgrounds/lab/fundo-lab.jpg'
MSG = 'Tela bloqueada pelo professor\nAguarde, por favor'          # padrão (quando não é informada outra)
if len(sys.argv) > 2 and sys.argv[2].strip():
    MSG = sys.argv[2].strip().replace('\\n', '\n')
tam = 44 if len(MSG) <= 60 else (34 if len(MSG) <= 140 else 26)
css = Gtk.CssProvider()
css.load_from_data(('window { background-color: #0b2a4a; } label { color: white; font-size: %dpx; font-weight: bold; }' % tam).encode())
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
display = Gdk.Display.get_default()
wins = []
for i in range(display.get_n_monitors()):
    g = display.get_monitor(i).get_geometry()
    w = Gtk.Window(type=Gtk.WindowType.POPUP)      # POPUP = override-redirect no X11
    w.set_decorated(False); w.set_keep_above(True)
    w.move(g.x, g.y); w.set_default_size(g.width, g.height); w.resize(g.width, g.height)
    box = Gtk.Overlay()
    if os.path.exists(IMG):
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(IMG, g.width, g.height, False)
            box.add(Gtk.Image.new_from_pixbuf(pb))
        except Exception: pass
    lab = Gtk.Label(label=MSG); lab.set_justify(Gtk.Justification.CENTER); lab.set_line_wrap(True); lab.set_max_width_chars(46)
    lab.set_halign(Gtk.Align.CENTER); lab.set_valign(Gtk.Align.CENTER)
    box.add_overlay(lab); w.add(box)
    w.show_all()
    gw = w.get_window()
    if gw: gw.set_cursor(Gdk.Cursor.new_from_name(display, 'none')); gw.raise_()
    wins.append(w)
def vigia():
    if not os.path.exists(FLAG): Gtk.main_quit(); return False
    for w in wins:
        gw = w.get_window()
        if gw: gw.raise_()
    return True
def limite():
    subprocess.run(['/usr/local/lib/lab/liberar-input'], check=False)
    try: os.remove(FLAG)
    except OSError: pass
    Gtk.main_quit(); return False
GLib.timeout_add_seconds(1, vigia)
GLib.timeout_add_seconds(LIMITE_MIN * 60, limite)
Gtk.main()
EOF

# ------------------------------------------------------------------- travar-tela
cat > "$LIB/travar-tela" <<'EOF'
#!/usr/bin/env bash
# travar-tela [MENSAGEM]: cobre a tela com uma mensagem por cima de tudo e bloqueia teclado e mouse.
# NÃO fecha nem minimiza nada: os apps continuam como estão por baixo (e rodando); só não aparecem nem respondem.
# Sem mensagem, usa a padrão ("Tela bloqueada pelo professor / Aguarde, por favor").
# Use \n na mensagem para quebrar linha. Libera com: liberar-tela. Segurança: solta sozinho em 90 minutos.
source "$(dirname "$(readlink -f "$0")")/_comum"
LIBDIR="$(dirname "$(readlink -f "$0")")"
RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
FLAG="$RUN/lab-tela-travada"
MSG="$(printf '%s' "${1:-}" | tr -d '\000-\010\013\014\016-\037' | cut -c1-400)"
touch "$FLAG"
pkill -u "$(id -u)" -f '[o]verlay-tela.py' 2>/dev/null || true   # trocar a mensagem de uma tela já travada
sleep 0.5
setsid nohup python3 "$LIBDIR/overlay-tela.py" "$FLAG" "$MSG" >/dev/null 2>&1 < /dev/null &
sleep 1
"$LIBDIR/bloquear-input" >/dev/null 2>&1
echo "$(hostname): tela travada (mensagem na tela, teclado e mouse bloqueados; apps intactos por baixo)"
EOF

# ------------------------------------------------------------------ liberar-tela
cat > "$LIB/liberar-tela" <<'EOF'
#!/usr/bin/env bash
# Tira o aviso da tela e libera teclado e mouse.
source "$(dirname "$(readlink -f "$0")")/_comum"
LIBDIR="$(dirname "$(readlink -f "$0")")"
RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
rm -f "$RUN/lab-tela-travada"
"$LIBDIR/liberar-input" >/dev/null 2>&1
sleep 1
pkill -u "$(id -u)" -f '[o]verlay-tela.py' 2>/dev/null || true
echo "$(hostname): tela liberada"
EOF

# ---------------------------------------------- reiniciar / desligar / sair / entrar / estado
cat > "$LIB/reiniciar" <<'EOF'
#!/usr/bin/env bash
# Reinicia o PC em 3 s (o comando volta antes, para o SSH não ficar pendurado).
systemd-run --quiet --no-block --on-active=3s systemctl reboot -i
echo "$(hostname): reiniciando em 3 s"
EOF
cat > "$LIB/desligar" <<'EOF'
#!/usr/bin/env bash
# Desliga o PC em 3 s.
systemd-run --quiet --no-block --on-active=3s systemctl poweroff -i
echo "$(hostname): desligando em 3 s"
EOF
cat > "$LIB/sair" <<'EOF'
#!/usr/bin/env bash
# Encerra a sessão do aluno (fecha tudo) e deixa na tela de login. O vigia não religa o aluno por 60 min
# (ou até rodar "entrar").
mkdir -p /run/lab-vigia; touch /run/lab-vigia/sem-autologin
loginctl terminate-user aluno 2>/dev/null || true
echo "$(hostname): aluno saiu (sem login automático por 60 min)"
EOF
cat > "$LIB/entrar" <<'EOF'
#!/usr/bin/env bash
# Faz o aluno entrar (login automático) se a máquina estiver na tela de login.
rm -f /run/lab-vigia/sem-autologin
if loginctl list-sessions --no-legend | awk '$4=="seat0" && $3!="lightdm" && ($6=="active"||$6=="online")' | grep -q .; then
  echo "$(hostname): já tem alguém logado"
else
  systemctl restart lightdm
  echo "$(hostname): entrando (login automático do aluno)"
fi
EOF
cat > "$LIB/estado" <<'EOF'
#!/usr/bin/env bash
# Uma linha: estado=aluno|login|saiu tela=active|online|- travada=0|1 input=0|1  (usada pelo painel)
U="$(id -u aluno)"
tela="$(loginctl list-sessions --no-legend | awk '$4=="seat0" && $3=="aluno" && ($6=="active"||$6=="online"){print $6; exit}')"
if [[ -n "$tela" ]]; then est=aluno; else est=login; [[ -f /run/lab-vigia/sem-autologin ]] && est=saiu; fi
tr=0; ip=0
[[ -f "/run/user/$U/lab-tela-travada" ]] && tr=1
[[ -f "/run/user/$U/lab-input-bloqueado" ]] && ip=1
echo "estado=$est tela=${tela:--} travada=$tr input=$ip"
EOF

# ---------------------------------------------------------------------- abrir-app
cat > "$LIB/abrir-app.py" <<'EOF'
#!/usr/bin/env python3
# abrir-app.py [--listar] NOME...: procura nos aplicativos instalados e abre o melhor resultado na sessão do aluno.
# Ordem: nome igual > começa com > palavras no nome > contém no nome > id/arquivo > nome+palavras-chave > comando.
import sys, os, re, glob, socket, subprocess, unicodedata, configparser

def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return " ".join(re.findall(r"[a-z0-9]+", s))

HOME = "/home/aluno"
DIRS = ["/usr/share/applications", "/usr/local/share/applications", "/var/lib/flatpak/exports/share/applications",
        HOME + "/.local/share/applications", HOME + "/.local/share/flatpak/exports/share/applications"]

def ler(caminho):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    try:
        cp.read(caminho, encoding="utf-8")
        d = dict(cp["Desktop Entry"])
    except Exception:
        return None
    if d.get("type") != "Application" or d.get("hidden", "").lower() == "true" or not d.get("name"):
        return None
    nomes = [d.get("name", "")] + [v for k, v in d.items() if k.startswith("name[")]
    return {"path": caminho, "id": os.path.basename(caminho)[:-8], "nome": d["name"], "nomes": [norm(n) for n in nomes if n],
            "generico": norm(d.get("genericname", "")), "chaves": norm(d.get("keywords", "") + " " + d.get("comment", "")),
            "exec": norm(re.sub(r"%[a-zA-Z]", "", d.get("exec", ""))), "cats": d.get("categories", ""), "oculto": d.get("nodisplay", "").lower() == "true"}

ALIAS = {   # nomes em português / apelidos comuns -> o que procurar
    "planilha": "libreoffice calc", "excel": "libreoffice calc", "texto": "libreoffice writer", "documento": "libreoffice writer",
    "word": "libreoffice writer", "apresentacao": "libreoffice impress", "slides": "libreoffice impress", "powerpoint": "libreoffice impress",
    "desenho": "libreoffice draw", "roblox": "sober", "internet": "brave", "navegador": "brave", "chrome": "brave", "calculadora": "calculator",
    "bloco de notas": "text editor", "editor de texto": "text editor", "gerenciador de arquivos": "files", "terminal": "terminal",
}

def pontos(q, e):
    toks = q.split()
    melhor = 0
    for n in e["nomes"]:
        if n == q: melhor = max(melhor, 1000)
        elif all(t in n.split() for t in toks): melhor = max(melhor, 900)      # palavras inteiras (ex.: "calc" em "LibreOffice Calc")
        elif n.startswith(q): melhor = max(melhor, 800)
        elif q in n: melhor = max(melhor, 650)
        elif all(t in n for t in toks): melhor = max(melhor, 600)
    if melhor == 0:
        idn = norm(e["id"])
        if q in idn or all(t in idn for t in toks): melhor = 500
        elif all(t in (e["nomes"][0] + " " + e["generico"] + " " + e["chaves"]) for t in toks): melhor = 400
        elif q in e["exec"] or all(t in e["exec"] for t in toks): melhor = 300
    if melhor:
        cats = set(c.lower() for c in e["cats"].split(";") if c)
        if cats & {"office", "webbrowser", "game", "education", "graphics", "audiovideo", "network"}: melhor += 60   # apps do dia a dia
        if cats & {"settings", "system", "packagemanager", "hardwaresettings", "monitor"}: melhor -= 60              # ferramentas de sistema
        if e["oculto"]: melhor -= 150                                                                              # escondidos do menu só se não houver outro
    return melhor

def main():
    args = sys.argv[1:]
    listar = bool(args) and args[0] == "--listar"
    if listar: args = args[1:]
    q = norm(" ".join(args)); q = ALIAS.get(q, q)
    if not q:
        print("%s: diga o nome do app (ex.: calc, writer, brave, sober)" % socket.gethostname()); return 2
    vistos, achados = set(), []
    for d in DIRS:
        for c in sorted(glob.glob(d + "/*.desktop")):
            e = ler(c)
            if not e or e["id"] in vistos: continue
            vistos.add(e["id"]); s = pontos(q, e)
            if s: achados.append((s, -len(e["nome"]), e))
    if not achados:
        print("%s: nenhum aplicativo encontrado para '%s'" % (socket.gethostname(), " ".join(args))); return 1
    achados.sort(key=lambda x: (x[0], x[1]), reverse=True)
    unicos, nomes_vistos = [], set()
    for a in achados:
        if a[2]["nome"].lower() in nomes_vistos: continue
        nomes_vistos.add(a[2]["nome"].lower()); unicos.append(a)
    achados = unicos
    top = achados[0][2]
    outros = ", ".join(a[2]["nome"] for a in achados[1:4])
    if listar:
        for s, _l, e in achados[:8]: print("%4d  %s  (%s)" % (s, e["nome"], e["id"]))
        return 0
    subprocess.Popen(["gio", "launch", top["path"]], start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("%s: abriu «%s»%s" % (socket.gethostname(), top["nome"], ("  (outros parecidos: %s)" % outros) if outros else ""))
    return 0

sys.exit(main())
EOF

# abrir-app: entra como o aluno (variáveis da sessão) e roda o python
cat > "$LIB/abrir-app" <<'EOF'
#!/usr/bin/env bash
# abrir-app NOME...: abre o aplicativo (primeiro resultado da busca) na tela do aluno. --listar NOME mostra os candidatos.
source "$(dirname "$(readlink -f "$0")")/_comum"
exec python3 "$(dirname "$(readlink -f "$0")")/abrir-app.py" "$@"
EOF

# ------------------------------------------------------------------ reiniciar-veyon
cat > "$LIB/reiniciar-veyon" <<'EOF'
#!/usr/bin/env bash
# Reinicia SÓ o Veyon (não mexe na sessão nem nos programas do aluno): mata o x11vnc preso, reinicia o serviço
# e confere a porta 11100. Resolve PC que não aparece/não responde no Veyon.
pkill -9 -x x11vnc 2>/dev/null || true
echo 0 > /run/lab-vigia/veyon 2>/dev/null || true
systemctl restart veyon
for _ in $(seq 1 25); do
  ss -ltn 'sport = :11100' 2>/dev/null | grep -q LISTEN && break
  sleep 1
done
if ss -ltn 'sport = :11100' 2>/dev/null | grep -q LISTEN; then
  echo "$(hostname): Veyon reiniciado (porta 11100 aberta)"
else
  echo "$(hostname): Veyon reiniciado, mas a porta 11100 ainda não abriu (o vigia tenta de novo em 1-2 min)"; exit 1
fi
EOF

for c in "${CMDS[@]}"; do chmod 755 "$LIB/$c"; done
chmod 644 "$LIB/_comum"; chmod 755 "$LIB/overlay-tela.py" "$LIB/abrir-app.py"
for c in "${CMDS[@]}" _comum overlay-tela.py abrir-app.py; do chown root:root "$LIB/$c"; done

# --------------------------------------------------------------------- sudoers
{
  echo "# Gerado por lab-ferramentas-mint.sh: admins rodam SÓ estas ferramentas sem senha, sem argumentos."
  for c in "${CMDS[@]}"; do
    if [[ "$c" == travar-tela || "$c" == abrir-app ]]; then echo "%sudo ALL=(root) NOPASSWD: $LIB/$c"; else echo "%sudo ALL=(root) NOPASSWD: $LIB/$c \"\""; fi
  done
} > "$SUDOERS"
chmod 440 "$SUDOERS"
visudo -cf "$SUDOERS" >/dev/null
ok "sudoers: $SUDOERS (sem senha só para ${CMDS[*]})"

for c in "${CMDS[@]}" _comum overlay-tela.py abrir-app.py; do chattr +i "$LIB/$c"; done
ok "ferramentas instaladas em $LIB (imutáveis)"
echo "Uso no PC: sudo $LIB/fechar-apps   |   do Bazzite: lab fechar-apps todos"
