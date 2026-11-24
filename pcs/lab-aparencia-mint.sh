#!/usr/bin/env bash
# =============================================================================
# lab-aparencia-mint.sh — modo escuro e trava do painel/personalização (Linux Mint XFCE ou Cinnamon)
#   1. Modo noturno (tema escuro Mint-Y-Dark-Aqua) para a conta "aluno", já na sessão aberta.
#   2. Painel travado: o aluno não adiciona, remove, move nem muda nada do painel.
#   3. Personalização travada: tema, ícones, cursor, janelas, applets, desklets, efeitos.
#   4. As telas de configuração (aparência, painel, menu, etc.) só abrem para admins (grupo sudo).
# Não reinicia nada; o tema muda ao vivo. Os admins continuam podendo mudar tudo.
# Uso:   sudo bash lab-aparencia-mint.sh              (aplica)
#        sudo bash lab-aparencia-mint.sh --desfazer   (devolve a liberdade ao aluno; tema volta ao claro)
# Seguro para rodar de novo.
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR

ALUNO="aluno"
TEMA="Mint-Y-Dark-Aqua"
TEMA_CLARO="Mint-Y-Aqua"
XDIR_ANTIGO="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"    # onde versões anteriores deste script gravaram (ignorada pelo Mint)
XDIR="/etc/xdg/xdg-xfce/xfce4/xfconf/xfce-perchannel-xml"  # o Mint XFCE lê esta pasta ANTES de /etc/xdg (XDG_CONFIG_DIRS)
[[ -d "$XDIR" ]] || XDIR="$XDIR_ANTIGO"
CANAIS=(xfce4-panel xsettings xfwm4)
restaura_canais() {   # devolve os arquivos originais do Mint e limpa o que versões antigas deixaram
  for c in "${CANAIS[@]}"; do
    if [[ -f "$XDIR/$c.xml.orig-lab" ]]; then cp -a "$XDIR/$c.xml.orig-lab" "$XDIR/$c.xml"
    elif [[ "$XDIR" == "$XDIR_ANTIGO" ]]; then [[ "$c" == xsettings ]] || rm -f "$XDIR/$c.xml"; fi
  done
  if [[ "$XDIR" != "$XDIR_ANTIGO" ]]; then
    rm -f "$XDIR_ANTIGO/xfce4-panel.xml" "$XDIR_ANTIGO/xfwm4.xml"
    [[ -f "$XDIR_ANTIGO/xsettings.xml.orig-lab" ]] && cp -a "$XDIR_ANTIGO/xsettings.xml.orig-lab" "$XDIR_ANTIGO/xsettings.xml" || true
  fi
}
UDIR="/home/$ALUNO/.config/xfce4/xfconf/xfce-perchannel-xml"
DCONF_FILE="/etc/dconf/db/local.d/20-lab-aparencia"
DCONF_LOCK="/etc/dconf/db/local.d/locks/20-lab-aparencia"
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }
aviso(){ echo "  [aviso] $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
UID_ALUNO="$(id -u "$ALUNO")"
BUS="unix:path=/run/user/$UID_ALUNO/bus"
SESSAO=0; [[ -S "/run/user/$UID_ALUNO/bus" ]] && SESSAO=1
echo "Máquina: $(hostname)"

# programas de configuração que só os admins podem abrir
FERRAMENTAS=(/usr/bin/cinnamon-settings /usr/bin/cinnamon-menu-editor /usr/bin/cinnamon-settings-users
             /usr/bin/xfce4-settings-manager /usr/bin/xfce4-appearance-settings /usr/bin/xfwm4-settings
             /usr/bin/xfce4-settings-editor /usr/bin/xfce4-session-settings)
restringe() { for b in "${FERRAMENTAS[@]}"; do
  [[ -x "$b" ]] || continue
  dpkg-statoverride --list "$b" >/dev/null 2>&1 || dpkg-statoverride --update --add root sudo 750 "$b"
  echo "    só admins: $b"; done; }
libera() { for b in "${FERRAMENTAS[@]}"; do
  if dpkg-statoverride --list "$b" >/dev/null 2>&1; then dpkg-statoverride --remove "$b"; chmod 755 "$b"; fi; done; }
bus_aluno() { runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" "$@"; }

# ------------------------------------------------------------------ desfazer --
if [[ "${1:-}" == "--desfazer" ]]; then
  info "Desfazendo (modo escuro e travas)"
  libera; ok "telas de configuração liberadas"
  if [[ -f "$DCONF_FILE" ]]; then
    rm -f "$DCONF_FILE" "$DCONF_LOCK"; dconf update
    if (( SESSAO )); then
      bus_aluno dconf write /org/cinnamon/desktop/interface/gtk-theme "'$TEMA_CLARO'" 2>/dev/null || true
      bus_aluno dconf write /org/cinnamon/desktop/wm/preferences/theme "'Mint-Y'" 2>/dev/null || true
    fi
    ok "Cinnamon: travas removidas, tema claro"
  fi
  restaura_canais
  if (( SESSAO )) && command -v xfconf-query >/dev/null && [[ -d "$UDIR" ]]; then
    bus_aluno xfconf-query -c xsettings -p /Net/ThemeName -s "$TEMA_CLARO" 2>/dev/null || true
    bus_aluno xfconf-query -c xfwm4 -p /general/theme -s "$TEMA_CLARO" 2>/dev/null || true
  fi
  ok "XFCE: travas removidas"
  exit 0
fi

restringe_msg() { info "Telas de configuração só para admins"; restringe; }

# ---------------------------------------------------------------- Cinnamon -----
if command -v cinnamon >/dev/null 2>&1 && [[ -d /etc/dconf ]]; then
  info "Cinnamon: modo escuro e travas"
  install -d -m 755 /etc/dconf/db/local.d /etc/dconf/db/local.d/locks /etc/dconf/profile
  grep -qs '^system-db:local' /etc/dconf/profile/user || printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
  lerv() { runuser -u "$ALUNO" -- dconf read "$1" 2>/dev/null || true; }   # valor atual do aluno (vazio = padrão)
  PAINEL=(enabled-applets enabled-desklets enabled-extensions panels-enabled panels-height panels-autohide
          panels-hide-delay panels-show-delay panel-zone-icon-sizes panel-zone-symbolic-icon-sizes
          panel-zone-text-sizes panel-launchers favorite-apps desktop-layout lock-desklets desklet-decorations desklet-snap)
  {
    echo "# Gerado por lab-aparencia-mint.sh: modo escuro e painel travados"
    echo "[org/cinnamon]"
    for k in "${PAINEL[@]}"; do v="$(lerv "/org/cinnamon/$k")"; [[ -n "$v" ]] && echo "$k=$v"; done
    echo "panel-edit-mode=false"
    echo "panel-launchers-draggable=false"
    echo "[org/cinnamon/desktop/interface]"
    echo "gtk-theme='$TEMA'"
    for k in icon-theme cursor-theme; do v="$(lerv "/org/cinnamon/desktop/interface/$k")"; [[ -n "$v" ]] && echo "$k=$v"; done
    echo "[org/cinnamon/theme]"
    echo "name='$TEMA'"
    echo "[org/cinnamon/desktop/wm/preferences]"
    echo "theme='$TEMA'"
  } > "$DCONF_FILE"
  {
    for k in "${PAINEL[@]}" panel-edit-mode panel-launchers-draggable; do echo "/org/cinnamon/$k"; done
    echo /org/cinnamon/desktop/interface/gtk-theme
    echo /org/cinnamon/desktop/interface/icon-theme
    echo /org/cinnamon/desktop/interface/cursor-theme
    echo /org/cinnamon/theme/name
    echo /org/cinnamon/desktop/wm/preferences/theme
  } > "$DCONF_LOCK"
  dconf update
  if (( SESSAO )); then   # aplica já na sessão aberta
    bus_aluno dconf write /org/cinnamon/desktop/interface/gtk-theme "'$TEMA'" 2>/dev/null || true
    bus_aluno dconf write /org/cinnamon/theme/name "'$TEMA'" 2>/dev/null || true
    bus_aluno dconf write /org/cinnamon/desktop/wm/preferences/theme "'$TEMA'" 2>/dev/null || true
  fi
  ok "tema escuro ($TEMA) e painel/aparência travados no dconf (vale já para o que está aberto; travas completas no próximo login)"
fi

# ------------------------------------------------------------------- XFCE ------
if [[ -d "$XDIR" ]] && command -v xfce4-panel >/dev/null 2>&1; then
  info "XFCE: modo escuro e travas"
  for c in "${CANAIS[@]}"; do   # guarda o original do Mint (uma vez) para o --desfazer
    [[ -f "$XDIR/$c.xml" && ! -f "$XDIR/$c.xml.orig-lab" ]] && cp -a "$XDIR/$c.xml" "$XDIR/$c.xml.orig-lab" || true
  done
  HELP="$(mktemp --suffix=.py)"; WORK="$(mktemp -d)"; chmod 644 "$HELP"
  trap 'rm -rf "$HELP" "$WORK"' EXIT
  cat > "$HELP" <<'PY'
# dump <canal>: imprime em JSON todas as propriedades (com tipo) que o xfconfd da sessão atual tem.
# xml <json> <canal>: gera o xml do canal a partir desse JSON, travado para a conta aluno.
import sys, json
import gi
from gi.repository import Gio, GLib
import xml.etree.ElementTree as ET
TIPOS = {"s": "string", "i": "int", "u": "uint", "b": "bool", "d": "double", "x": "int64", "t": "uint64", "y": "uchar", "n": "int16", "q": "uint16"}
def conv(v):
    ts = v.get_type_string()
    if ts.startswith("a") and ts != "ay":
        filhos = []
        for i in range(v.n_children()):
            c = v.get_child_value(i)
            filhos.append(conv(c.get_variant() if c.get_type_string() == "v" else c))
        return {"t": "array", "v": filhos}
    return {"t": TIPOS.get(ts, ts), "v": v.unpack()}
def dump(canal):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    r = bus.call_sync("org.xfce.Xfconf", "/org/xfce/Xfconf", "org.xfce.Xfconf", "GetAllProperties",
                      GLib.Variant("(ss)", (canal, "/")), GLib.VariantType("(a{sv})"), Gio.DBusCallFlags.NONE, 8000, None)
    d = r.get_child_value(0); out = {}
    for i in range(d.n_children()):
        e = d.get_child_value(i)
        out[e.get_child_value(0).get_string()] = conv(e.get_child_value(1).get_variant())
    return out
def txt(t, v):
    return ("true" if v else "false") if t == "bool" else str(v)
def gerar(dados, canal):
    raiz = ET.Element("channel", {"name": canal, "version": "1.0", "locked": "aluno"})
    nos = {}
    for caminho in sorted(dados):
        pai, atual = raiz, ""
        for seg in caminho.strip("/").split("/"):
            atual += "/" + seg
            if atual not in nos:
                nos[atual] = ET.SubElement(pai, "property", {"name": seg, "type": "empty"})
            pai = nos[atual]
        no, d = pai, dados[caminho]
        no.set("type", d["t"])
        if d["t"] == "array":
            for it in d["v"]:
                ET.SubElement(no, "value", {"type": it["t"], "value": txt(it["t"], it["v"])})
        else:
            no.set("value", txt(d["t"], d["v"]))
    ET.indent(raiz, space="  ")
    return ET.tostring(raiz, encoding="unicode")
if sys.argv[1] == "dump":
    print(json.dumps(dump(sys.argv[2]), sort_keys=True))
else:
    print('<?xml version="1.0" encoding="UTF-8"?>\n' + gerar(json.load(open(sys.argv[2])), sys.argv[3]))
PY
  travado=0
  if (( SESSAO )) && command -v xfconf-query >/dev/null; then
    # 0) tira travas de uma aplicação anterior e faz o xfconfd da sessão esquecê-las (senão ele recusaria o passo 1)
    restaura_canais
    pkill -u "$ALUNO" -x xfconfd 2>/dev/null || true; sleep 2
    # 1) tema escuro ao vivo (antes de tirar o retrato da configuração)
    bus_aluno xfconf-query -c xsettings -p /Net/ThemeName -s "$TEMA" 2>/dev/null || bus_aluno xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "$TEMA" || true
    bus_aluno xfconf-query -c xfwm4 -p /general/theme -s "$TEMA" 2>/dev/null || bus_aluno xfconf-query -c xfwm4 -p /general/theme -n -t string -s "$TEMA" || true
    sleep 1
    # 1b) painel sem controle de volume: tira o plugin "pulseaudio" do painel (o volume é do professor, lab-audio-mint.sh)
    ids="$(bus_aluno xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | grep -E '^[0-9]+$' || true)"
    pa=""
    for i in $ids; do [[ "$(bus_aluno xfconf-query -c xfce4-panel -p "/plugins/plugin-$i" 2>/dev/null)" == pulseaudio ]] && pa="$i"; done
    if [[ -n "$pa" ]]; then
      args=(); for i in $ids; do [[ "$i" != "$pa" ]] && args+=(-t int -s "$i"); done
      bus_aluno xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids "${args[@]}" 2>/dev/null || true
      bus_aluno xfconf-query -c xfce4-panel -p "/plugins/plugin-$pa" -r -R 2>/dev/null || true
      echo "    painel: plugin de volume (pulseaudio) removido"
    fi
    sleep 1
    # 2) para cada canal: retrato da configuração viva -> xml travado -> conferência numa sessão descartável
    for ch in xfce4-panel xsettings xfwm4; do
      if ! bus_aluno python3 -I "$HELP" dump "$ch" > "$WORK/$ch.vivo.json" 2>"$WORK/$ch.err"; then aviso "$ch: não consegui ler a configuração viva ($(tail -1 "$WORK/$ch.err"))"; continue; fi
      python3 -I "$HELP" xml "$WORK/$ch.vivo.json" "$ch" > "$WORK/$ch.xml"
      mkdir -p "$WORK/cfg/xfce4/xfconf/xfce-perchannel-xml" "$WORK/home"
      cp "$WORK/$ch.xml" "$WORK/cfg/xfce4/xfconf/xfce-perchannel-xml/$ch.xml"
      HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" XDG_CONFIG_DIRS="$WORK/cfg" \
        dbus-run-session -- python3 -I "$HELP" dump "$ch" > "$WORK/$ch.teste.json" 2>/dev/null || true
      rm -rf "$WORK/cfg"
      if python3 -I - "$WORK/$ch.vivo.json" "$WORK/$ch.teste.json" "$([[ $ch == xsettings ]] && echo sub || echo igual)" <<'PY'
import json, sys
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
sub = len(sys.argv) > 3 and sys.argv[3] == "sub"   # sub: tudo do vivo precisa estar igual no teste (o teste pode ter padrões a mais)
chaves = sorted(a) if sub else sorted(set(a) | set(b))
dif = [k for k in chaves if a.get(k) != b.get(k)]
for k in dif:
    sys.stderr.write("      diferença em %s: vivo=%s teste=%s\n" % (k, a.get(k), b.get(k)))
sys.exit(0 if not dif and len(a) > 0 else 1)
PY
      then
        install -m 644 -o root -g root "$WORK/$ch.xml" "$XDIR/$ch.xml"
        echo "    $ch: $(python3 -I -c "import json;print(len(json.load(open('$WORK/$ch.vivo.json'))))") propriedades, conferidas e travadas"
        travado=$((travado + 1))
      else
        aviso "$ch: cópia diferente da configuração viva; este canal ficou SEM trava (nada foi alterado; o tema escuro vale mesmo assim)"
      fi
    done
  else
    aviso "XFCE: sem sessão do $ALUNO aberta; só deixei o tema escuro como padrão. Rode de novo com o aluno logado para travar o painel."
  fi
  python3 -I - "$XDIR/xsettings.xml" "$TEMA" <<'PY'
import sys, xml.etree.ElementTree as ET
p, tema = sys.argv[1:3]
t = ET.parse(p); r = t.getroot()
no = r
for nome in ("Net", "ThemeName"):
  f = [x for x in no.findall("property") if x.get("name") == nome]
  no = f[0] if f else ET.SubElement(no, "property", {"name": nome, "type": "empty"})
no.set("type", "string"); no.set("value", tema)
ET.indent(t, space="  "); t.write(p, encoding="UTF-8", xml_declaration=True)
PY
  if (( travado > 0 )); then
    # reinicia só o serviço de configurações da sessão do aluno: ele relê os arquivos e passa a recusar mudanças.
    # O painel e os programas continuam abertos (o xfconfd volta sozinho no primeiro acesso).
    pkill -u "$ALUNO" -x xfconfd 2>/dev/null || true
    ok "XFCE: tema escuro ($TEMA); $travado canal(is) travado(s) para a conta $ALUNO (painel, tema e janelas)"
  fi
fi

restringe_msg
ok "pronto. Admins continuam livres; para o aluno: tema escuro fixo, painel fixo."
