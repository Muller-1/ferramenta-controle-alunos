#!/usr/bin/env bash
# Reinstala no Bazzite (ou em outro PC do professor) todos os comandos e configurações do laboratório.
# Uso: bash instalar-no-bazzite.sh      (dentro desta pasta; NÃO precisa de sudo)
# O que faz: comandos lab/lab-backup/lab-gui em ~/.local/bin, atalhos "Lab: ..." no menu Personalizado,
# timer do backup (a cada 2 h, na tomada) e bloco do ~/.ssh/config. Mapa de PCs em ~/.ssh/ips-lab-testados.txt.
# NÃO inclui as chaves: copie do cofre de senhas para ~/.ssh/ (modo 600):
#     lab_nopass_ed25519      (chave privada SEM senha do lab)
#     lab-trabalhos.cred      (usuário/senha do compartilhamento trabalhos-alunos; só para reinstalar nos PCs)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ~/.local/bin ~/.local/share/applications ~/.config/systemd/user ~/.ssh
install -m 755 bin/lab bin/lab-backup bin/lab-gui bin/lab-painel ~/.local/bin/
for f in menu/*.desktop; do sed "s#__HOME__#$HOME#g" "$f" > ~/.local/share/applications/"$(basename "$f")"; done
for f in systemd/*; do sed "s#__HOME__#$HOME#g" "$f" > ~/.config/systemd/user/"$(basename "$f")"; done
[[ -f ~/.ssh/ips-lab-testados.txt ]] || cp ssh/ips-lab-testados.txt ~/.ssh/
[[ -f ~/.ssh/LEIA-ME-chave-lab.txt ]] || cp ssh/LEIA-ME-chave-lab.txt ~/.ssh/
if ! grep -q 'lab_nopass_ed25519' ~/.ssh/config 2>/dev/null; then
  { echo; cat ssh/config-lab.txt; } >> ~/.ssh/config; chmod 600 ~/.ssh/config
fi
# pasta "Laboratório" dentro de Personalizado (painel fixado no topo)
mkdir -p ~/.config/menus/applications-merged ~/.local/share/desktop-directories
[[ -f ~/.config/menus/applications-merged/personalizado.menu ]] && cp ~/.config/menus/applications-merged/personalizado.menu ~/.config/menus/applications-merged/personalizado.menu.bak
cp menu-config/personalizado.menu ~/.config/menus/applications-merged/
cp menu-config/*.directory ~/.local/share/desktop-directories/
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
systemctl --user daemon-reload
systemctl --user enable --now lab-backup.timer
[[ -f ~/.ssh/lab_nopass_ed25519 ]] || echo "ATENÇÃO: falta ~/.ssh/lab_nopass_ed25519 (chave do lab); copie do cofre de senhas e rode: chmod 600 ~/.ssh/lab_nopass_ed25519"
echo "Pronto. Teste: lab status"
