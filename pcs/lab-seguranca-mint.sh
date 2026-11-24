#!/usr/bin/env bash
# =============================================================================
# lab-seguranca-mint.sh — fecha as brechas dos alunos (Linux Mint, XFCE ou Cinnamon)
#   1. Navegadores e e-mail fora do filtro (Firefox, Thunderbird): só para admins; o Brave é o navegador do lab.
#   2. Terminais e "executar comando" (Alt+F2) só para admins; Looking Glass do Cinnamon desligado.
#   3. Instaladores (Gerenciador de Programas, Synaptic, gdebi, fontes de software, web apps) só para admins.
#   4. Atalhos desses programas somem dos menus (os admins ainda os abrem pelo terminal/sudo).
#   5. Ctrl+Alt+F1..F7 não troca para tela de texto (vale ao reiniciar a tela gráfica / o PC).
# Não fecha nada que o aluno esteja usando; só impede de abrir de novo. Admins (grupo sudo) continuam livres.
# Uso:   sudo bash lab-seguranca-mint.sh              (aplica)
#        sudo bash lab-seguranca-mint.sh --desfazer   (devolve tudo)
# Seguro para rodar de novo.
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR

DB="/etc/dconf/db/local.d"
OVR="/usr/local/share/applications"
XCONF="/etc/X11/xorg.conf.d/90-lab-sem-vt.conf"
BLOQUEAR=(
  /usr/bin/firefox /usr/lib/firefox/firefox /usr/lib/firefox/firefox-bin /usr/bin/thunderbird /usr/lib/thunderbird/thunderbird
  /usr/bin/gnome-terminal /usr/bin/gnome-terminal.real /usr/bin/gnome-terminal.wrapper /usr/bin/xfce4-terminal /usr/bin/xfce4-terminal.wrapper
  /usr/bin/mate-terminal /usr/bin/xterm /usr/bin/uxterm /usr/bin/kitty /usr/bin/tilix /usr/bin/konsole /usr/bin/alacritty /usr/bin/terminator
  /usr/bin/lxterminal /usr/bin/qterminal /usr/bin/xfrun4
  /usr/bin/mintinstall /usr/bin/webapp-manager /usr/bin/synaptic /usr/bin/synaptic-pkexec /usr/bin/gdebi-gtk /usr/bin/software-properties-gtk /usr/bin/mintsources
)
ESCONDER=(firefox thunderbird org.gnome.Terminal xfce4-terminal xfce4-terminal-settings mate-terminal xterm uxterm kitty tilix
          mintinstall webapp-manager synaptic gdebi software-properties-gtk mintsources xfce4-run)
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }
restringe() { local b="$1"; [[ -e "$b" && ! -L "$b" ]] || return 0; dpkg-statoverride --list "$b" >/dev/null 2>&1 || dpkg-statoverride --update --add root sudo 750 "$b"; }
libera() { local b="$1"; if dpkg-statoverride --list "$b" >/dev/null 2>&1; then dpkg-statoverride --remove "$b"; chmod 755 "$b"; fi; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

if [[ "${1:-}" == "--desfazer" ]]; then
  info "Desfazendo"
  for b in "${BLOQUEAR[@]}"; do libera "$b"; done
  for i in "${ESCONDER[@]}"; do [[ -f "$OVR/$i.desktop" ]] && grep -q 'lab-seguranca' "$OVR/$i.desktop" && rm -f "$OVR/$i.desktop"; done
  rm -f "$XCONF" "$DB/14-lab-seguranca" "$DB/locks/14-lab-seguranca"; dconf update 2>/dev/null || true
  update-desktop-database "$OVR" 2>/dev/null || true
  ok "desfeito"; exit 0
fi

info "1-3) Navegadores, terminais e instaladores só para admins"
n=0; for b in "${BLOQUEAR[@]}"; do if [[ -e "$b" && ! -L "$b" ]]; then restringe "$b"; echo "    só admins: $b"; n=$((n+1)); fi; done
ok "$n programas restritos (quem já está com um aberto continua; novos não abrem)"

info "3b) Navegador padrão do aluno = Brave (links de documentos e apps abrem no Brave)"
if id aluno >/dev/null 2>&1 && [[ -f /usr/share/applications/brave-browser.desktop ]]; then
  runuser -u aluno -- env HOME=/home/aluno xdg-settings set default-web-browser brave-browser.desktop 2>/dev/null || true
  ok "navegador padrão: $(runuser -u aluno -- env HOME=/home/aluno xdg-settings get default-web-browser 2>/dev/null)"
fi

info "4) Atalhos escondidos dos menus"
install -d -m 755 "$OVR"
h=0
for i in "${ESCONDER[@]}"; do
  src=""; for d in /usr/share/applications /var/lib/flatpak/exports/share/applications; do [[ -f "$d/$i.desktop" ]] && src="$d/$i.desktop"; done
  [[ -n "$src" ]] || continue
  printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n# lab-seguranca: atalho escondido dos menus dos alunos\n' "$i" > "$OVR/$i.desktop"
  h=$((h+1))
done
update-desktop-database "$OVR" 2>/dev/null || true
ok "$h atalhos escondidos (/usr/local/share/applications)"

info "2b) Cinnamon: sem 'executar comando' e sem Looking Glass"
if command -v cinnamon >/dev/null 2>&1; then
  install -d -m 755 "$DB" "$DB/locks" /etc/dconf/profile
  grep -qs '^system-db:local' /etc/dconf/profile/user || printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
  printf '[org/cinnamon/desktop/lockdown]\ndisable-command-line=true\n\n[org/cinnamon]\ndevelopment-tools=false\n' > "$DB/14-lab-seguranca"
  printf '%s\n' /org/cinnamon/desktop/lockdown/disable-command-line /org/cinnamon/development-tools > "$DB/locks/14-lab-seguranca"
  dconf update
  ok "Cinnamon: Alt+F2 (executar) e Looking Glass desligados e travados"
fi

info "5) Sem troca para tela de texto (Ctrl+Alt+F1..F7)"
install -d -m 755 /etc/X11/xorg.conf.d
printf 'Section "ServerFlags"\n    Option "DontVTSwitch" "true"\nEndSection\n' > "$XCONF"
ok "DontVTSwitch ligado (vale quando a tela gráfica reiniciar, por exemplo no próximo boot)"

echo
echo "Pronto. Para o aluno abrir de novo o que foi bloqueado: sudo bash lab-seguranca-mint.sh --desfazer"
