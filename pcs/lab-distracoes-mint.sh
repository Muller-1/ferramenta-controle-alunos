#!/usr/bin/env bash
# =============================================================================
# lab-distracoes-mint.sh — tira as distrações dos alunos (Linux Mint, XFCE ou Cinnamon)
#   1. Notificações desligadas (Cinnamon: travado no dconf; XFCE: "não perturbe" ligado) e sino fora do painel.
#   2. Bluetooth desligado (serviço, rádio e ícone/programas do blueman só para admins).
#   3. Ícone do Veyon escondido da bandeja (o Veyon continua funcionando).
#   4. Avisos do Mint desligados: ícone de atualizações escondido, relatório do sistema, boas-vindas,
#      alarmes do Evolution, avisos de impressora e do disco (programas de autostart só para admins).
#   5. Brave sem pedidos de notificação, sem anúncios do navegador e sem rodar em segundo plano.
#   6. Pendrive/disco ligado não abre janela sozinho.
# Nada aqui reinicia a sessão ou fecha programas do aluno. Admins continuam livres.
# Uso:   sudo bash lab-distracoes-mint.sh              (aplica)
#        sudo bash lab-distracoes-mint.sh --desfazer   (devolve tudo)
# Seguro para rodar de novo.
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR

ALUNO="aluno"
UID_ALUNO="$(id -u "$ALUNO")"
BUS="unix:path=/run/user/$UID_ALUNO/bus"
SESSAO=0; [[ -S "/run/user/$UID_ALUNO/bus" ]] && SESSAO=1
DB="/etc/dconf/db/local.d"
BRAVE="/etc/brave/policies/managed/98-lab-sem-distracoes.json"
BLUEMAN=(/usr/bin/blueman-applet /usr/bin/blueman-tray /usr/bin/blueman-manager /usr/bin/blueman-adapters /usr/bin/blueman-sendto /usr/bin/blueman-services /usr/bin/blueberry /usr/bin/blueberry-tray)
AUTOSTART=(blueman.desktop mintreport.desktop mintwelcome.desktop print-applet.desktop org.gnome.Evolution-alarm-notify.desktop
           cinnamon-settings-daemon-print-notifications.desktop org.gnome.SettingsDaemon.DiskUtilityNotify.desktop)
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }
aviso(){ echo "  [aviso] $*" >&2; }
bus_aluno() { runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="/run/user/$UID_ALUNO" "$@"; }
restringe() { local b="$1"; [[ -x "$b" ]] || return 0; dpkg-statoverride --list "$b" >/dev/null 2>&1 || dpkg-statoverride --update --add root sudo 750 "$b"; }
libera() { local b="$1"; if dpkg-statoverride --list "$b" >/dev/null 2>&1; then dpkg-statoverride --remove "$b"; chmod 755 "$b"; fi; }
# programa executado por um item de autostart
exec_do_autostart() {
  local f="/etc/xdg/autostart/$1" e
  [[ -f "$f" ]] || return 0
  e="$(grep -m1 '^Exec=' "$f" | cut -d= -f2- | awk '{print $1}')"
  [[ -n "$e" ]] || return 0
  [[ "$e" == /* ]] && echo "$e" || command -v "$e" || true
}

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

# ------------------------------------------------------------------ desfazer --
if [[ "${1:-}" == "--desfazer" ]]; then
  info "Desfazendo (distrações de volta)"
  rm -f "$DB/13-lab-sem-distracoes" "$DB/locks/13-lab-sem-distracoes" "$BRAVE"; dconf update 2>/dev/null || true
  for b in "${BLUEMAN[@]}"; do libera "$b"; done
  for a in "${AUTOSTART[@]}"; do b="$(exec_do_autostart "$a")"; [[ -n "$b" ]] && libera "$b"; done
  systemctl unmask bluetooth.service >/dev/null 2>&1 || true; systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
  rfkill unblock bluetooth 2>/dev/null || true
  veyon-cli config set Service/HideTrayIcon false >/dev/null 2>&1 || true
  (( SESSAO )) && command -v xfconf-query >/dev/null && bus_aluno xfconf-query -c xfce4-notifyd -p /do-not-disturb -s false 2>/dev/null || true
  ok "desfeito (reinicie o Veyon e refaça o painel com lab-aparencia-mint.sh --desfazer para voltar sino e ícones)"
  exit 0
fi

# ---------------------------------------------------------------------- dconf --
install -d -m 755 "$DB" "$DB/locks" /etc/dconf/profile
grep -qs '^system-db:local' /etc/dconf/profile/user || printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
CHAVES=()      # caminhos dconf a travar
{
  echo "# Gerado por lab-distracoes-mint.sh"
  if command -v cinnamon >/dev/null 2>&1; then
    echo "[org/cinnamon/desktop/notifications]"; echo "display-notifications=false"
    echo "[org/cinnamon/desktop/media-handling]"; echo "automount-open=false"; echo "autorun-never=true"
    CHAVES+=(/org/cinnamon/desktop/notifications/display-notifications /org/cinnamon/desktop/media-handling/automount-open /org/cinnamon/desktop/media-handling/autorun-never)
  fi
  echo "[com/linuxmint/updates]"; echo "hide-systray=true"
  echo "[org/gnome/desktop/notifications]"; echo "show-banners=false"
} > "$DB/13-lab-sem-distracoes"
{
  command -v cinnamon >/dev/null 2>&1 && printf '%s\n' /org/cinnamon/desktop/notifications/display-notifications /org/cinnamon/desktop/media-handling/automount-open /org/cinnamon/desktop/media-handling/autorun-never
  printf '%s\n' /com/linuxmint/updates/hide-systray /org/gnome/desktop/notifications/show-banners
} > "$DB/locks/13-lab-sem-distracoes"

# ------------------------------------------------------------- 1. notificações --
info "1) Notificações desligadas"
if command -v cinnamon >/dev/null 2>&1; then
  # tira o sino (notifications@cinnamon.org) do painel: arquivo do lab-aparencia (se existir) e sessão aberta
  python3 -I - "$ALUNO" "$UID_ALUNO" <<'PY'
import re, subprocess, os, sys
aluno, uid = sys.argv[1:3]
bus = "unix:path=/run/user/%s/bus" % uid
r = subprocess.run(["runuser", "-u", aluno, "--", "env", "DBUS_SESSION_BUS_ADDRESS=" + bus, "gsettings", "get", "org.cinnamon", "enabled-applets"], capture_output=True, text=True)
itens = re.findall(r"'([^']*)'", r.stdout)
novos = [i for i in itens if "notifications@cinnamon.org" not in i]
if novos and novos != itens:
    texto = "[" + ", ".join("'%s'" % i for i in novos) + "]"
    arq = "/etc/dconf/db/local.d/20-lab-aparencia"
    if os.path.exists(arq):
        t = open(arq, encoding="utf-8").read()
        open(arq, "w", encoding="utf-8").write(re.sub(r"^enabled-applets=.*$", "enabled-applets=" + texto, t, flags=re.M))
    subprocess.run(["runuser", "-u", aluno, "--", "env", "DBUS_SESSION_BUS_ADDRESS=" + bus, "dconf", "write", "/org/cinnamon/enabled-applets", texto], capture_output=True)
    print("    sino de notificações removido do painel")
PY
  dconf update
  (( SESSAO )) && bus_aluno dconf write /org/cinnamon/desktop/notifications/display-notifications false 2>/dev/null || true
  ok "Cinnamon: notificações desligadas (travadas no dconf) e sino fora do painel"
fi
if command -v xfce4-notifyd >/dev/null 2>&1 || [[ -d /usr/lib/x86_64-linux-gnu/xfce4/notifyd ]]; then
  if (( SESSAO )) && command -v xfconf-query >/dev/null; then
    bus_aluno xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s true 2>/dev/null || true
  fi
  restringe /usr/bin/xfce4-notifyd-config
  ok "XFCE: 'não perturbe' ligado (o sino do painel sai pelo lab-aparencia-mint.sh) e a tela de ajustes só para admins"
fi
dconf update

# ------------------------------------------------------------------ 2. bluetooth --
info "2) Bluetooth desligado"
systemctl disable --now bluetooth.service >/dev/null 2>&1 || true
systemctl mask bluetooth.service >/dev/null 2>&1 || true
rfkill block bluetooth 2>/dev/null || true
for b in "${BLUEMAN[@]}"; do restringe "$b"; done
pkill -u "$ALUNO" -x blueman-applet 2>/dev/null || true; pkill -u "$ALUNO" -x blueman-tray 2>/dev/null || true
pkill -u "$ALUNO" -x blueberry-tray 2>/dev/null || true
ok "serviço desativado e mascarado, rádio bloqueado, programas do blueman/blueberry só para admins, ícone da bandeja encerrado"

# --------------------------------------------------------------- 3. ícone do Veyon --
info "3) Ícone do Veyon escondido"
if command -v veyon-cli >/dev/null 2>&1; then
  atual="$(veyon-cli config get Service/HideTrayIcon 2>/dev/null | head -1 || true)"
  if [[ "$atual" != "true" ]]; then
    veyon-cli config set Service/HideTrayIcon true >/dev/null
    systemctl restart veyon >/dev/null 2>&1 || true   # só o Veyon; a sessão do aluno não é tocada
    ok "Veyon: HideTrayIcon=true (Veyon reiniciado; o ícone some da bandeja)"
  else
    ok "Veyon já estava com o ícone escondido"
  fi
fi

# ------------------------------------------------------- 4. avisos do Mint e afins --
info "4) Avisos do Mint, atualizações, alarmes e impressora"
for a in "${AUTOSTART[@]}"; do
  b="$(exec_do_autostart "$a")"
  [[ -n "$b" ]] || continue
  nome="$(basename "$b")"
  restringe "$b"; pkill -u "$ALUNO" -x "${nome:0:15}" 2>/dev/null || true     # o nome do processo tem no máximo 15 letras
  echo "    só admins: $b"
done
restringe /usr/bin/mintwelcome
pkill -u "$ALUNO" -f '/usr/lib/linuxmint/mintwelcome/mintwelcome.py' 2>/dev/null || true     # janela "Bem-vindo ao Linux Mint" que ficou aberta
if (( SESSAO )); then bus_aluno dconf write /com/linuxmint/updates/hide-systray true 2>/dev/null || true; fi
ok "ícone do gerenciador de atualizações escondido; relatório, boas-vindas, alarmes, avisos de impressora e do disco desligados"

# ----------------------------------------------------------------------- 5. brave --
info "5) Brave sem distrações"
if [[ -d /etc/brave/policies/managed || -d /opt/brave.com/brave ]]; then
  install -d -m 755 /etc/brave/policies/managed
  cat > "$BRAVE" <<'EOF'
{
  "DefaultNotificationsSetting": 2,
  "PromotionalTabsEnabled": false,
  "BackgroundModeEnabled": false,
  "DefaultPopupsSetting": 2
}
EOF
  chmod 644 "$BRAVE"
  ok "Brave: sem pedidos/avisos de sites, sem abas promocionais, sem pop-ups e sem rodar em segundo plano (vale ao abrir o Brave de novo)"
fi

# ------------------------------------------------------------ 6. mídia removível --
info "6) Pendrive não abre janela sozinho"
if (( SESSAO )) && command -v xfconf-query >/dev/null && ! command -v cinnamon >/dev/null 2>&1; then
  bus_aluno xfconf-query -c thunar-volman -p /autobrowse/enabled -n -t bool -s false 2>/dev/null || true
  bus_aluno xfconf-query -c thunar-volman -p /autorun/enabled -n -t bool -s false 2>/dev/null || true
fi
ok "mídia removível: sem abrir pasta nem executar sozinha (Cinnamon travado no dconf; XFCE no thunar-volman)"

echo
echo "Pronto. Alguns efeitos (Brave, programas de autostart) valem no próximo login ou ao reabrir o programa."
