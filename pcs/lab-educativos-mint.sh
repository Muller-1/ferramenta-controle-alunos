#!/usr/bin/env bash
# =============================================================================
# lab-educativos-mint.sh — aplicativos educativos para os alunos (Linux Mint, XFCE ou Cinnamon)
#   GCompris  : mais de 100 atividades para crianças (ler, contar, lógica, mouse e teclado)
#   Tux Paint : desenho para crianças
#   TuxMath   : jogo de matemática (contas para destruir meteoros)
#   Klavaro   : curso de digitação
#   Scratch 3 : programação com blocos (funciona sem internet; abre os arquivos .sb3)
# Ficam no menu (categoria Educação). Funcionam sem internet. Não fecha nem abre nada do aluno.
# Uso:  sudo bash lab-educativos-mint.sh   [--desfazer]
# =============================================================================
set -euo pipefail
APT_PKGS=(gcompris-qt tuxpaint tuxmath klavaro)
FLAT=edu.mit.Scratch
ok() { echo "  [ok] $*"; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"
export DEBIAN_FRONTEND=noninteractive

if [[ "${1:-}" == "--desfazer" ]]; then
  apt-get remove -y "${APT_PKGS[@]}" >/dev/null 2>&1 || true
  flatpak uninstall --system -y --noninteractive "$FLAT" >/dev/null 2>&1 || true
  ok "apps educativos removidos"; exit 0
fi

# espera outro apt terminar (ex.: atualização automática)
for i in $(seq 1 60); do fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break; sleep 5; done
nice -n 10 apt-get update -qq || true
nice -n 10 apt-get install -y -qq --no-install-recommends "${APT_PKGS[@]}" >/dev/null
ok "instalados: ${APT_PKGS[*]}"
nice -n 10 flatpak install --system -y --noninteractive flathub "$FLAT" >/dev/null 2>&1
ok "instalado: Scratch 3 ($FLAT)"
# .sb3 abre no Scratch
if [[ -f /var/lib/flatpak/exports/share/applications/$FLAT.desktop ]] && id aluno >/dev/null 2>&1; then
  runuser -u aluno -- env HOME=/home/aluno xdg-mime default "$FLAT.desktop" application/x-scratch-project 2>/dev/null || true
fi
for a in org.kde.gcompris tuxpaint tuxmath klavaro "$FLAT"; do
  f=$(ls /usr/share/applications/$a.desktop /var/lib/flatpak/exports/share/applications/$a.desktop 2>/dev/null | head -1)
  echo "    no menu: $(grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2) ${f:+($a)}"
done
