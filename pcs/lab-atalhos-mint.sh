#!/usr/bin/env bash
# lab-atalhos-mint.sh — devolve os atalhos de apps (Brave, Writer, Calc, Impress, Draw, Roblox) à área de trabalho do aluno,
# na tela atual e na foto do perfil limpo (voltam a cada boot), marca como confiáveis e faz o perfil limpo preservar atalhos.
# Uso: sudo bash lab-atalhos-mint.sh   (não fecha nem minimiza nada; seguro para rodar de novo)
set -u
B=/var/lib/lab/arquivos-do-aluno-antes-do-perfil-limpo; BASE=/var/lib/lab/perfil-base; L=/usr/local/lib/lab/perfil-limpo
D=$(runuser -u aluno -- env HOME=/home/aluno xdg-user-dir DESKTOP 2>/dev/null); D=${D:-/home/aluno/Desktop}; R=${D#/home/aluno/}
APPS="brave-browser libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw org.vinegarhq.Sober"
src() { for d in "$B/Desktop" "$B/Área de trabalho" /usr/share/applications /var/lib/flatpak/exports/share/applications; do [ -f "$d/$1.desktop" ] && { echo "$d/$1.desktop"; return; }; done; }
n=0
for a in $APPS; do s=$(src $a); [ -n "$s" ] || { echo "  sem fonte: $a"; continue; }
  for alvo in "$D" "$BASE/$R"; do [ -d "$BASE" ] || [ "$alvo" = "$D" ] || continue
    install -d -o aluno -g aluno "$alvo"; [ -e "$alvo/$a.desktop" ] || { cp -p "$s" "$alvo/$a.desktop"; chown aluno:aluno "$alvo/$a.desktop"; chmod 755 "$alvo/$a.desktop"; }
  done; n=$((n+1))
done
# confiar nos atalhos (Cinnamon/Nemo e XFCE) na sessão aberta
BUS=unix:path=/run/user/$(id -u aluno)/bus
for a in $APPS; do f="$D/$a.desktop"; [ -f "$f" ] || continue
  runuser -u aluno -- env DBUS_SESSION_BUS_ADDRESS=$BUS gio set "$f" metadata::trusted true 2>/dev/null
  runuser -u aluno -- env DBUS_SESSION_BUS_ADDRESS=$BUS gio set -t string "$f" metadata::xfce-exe-checksum "$(sha256sum "$f" | cut -d' ' -f1)" 2>/dev/null
done
# a foto passa a levar a confiança (metadados do gvfs) atual
sleep 1; [ -d "$BASE/.local/share/gvfs-metadata" ] && cp -a /home/aluno/.local/share/gvfs-metadata/. "$BASE/.local/share/gvfs-metadata/" 2>/dev/null
# perfil limpo: ao refazer a foto, não apagar atalhos (.desktop) nem links da área de trabalho
if [ -f "$L" ] && ! grep -q "name '\*.desktop'" "$L"; then chattr -i "$L"; sed -i "s|find \"\$BASE/\$d\" -mindepth 1 ! -type l -delete|find \"\$BASE/\$d\" -mindepth 1 ! -type l ! -name '*.desktop' -delete|" "$L"; chattr +i "$L"; fi
echo "  $n atalhos em $D e na foto | perfil-limpo preserva atalhos: $(grep -c "name '\*.desktop'" $L)"
echo "  na tela agora: $(ls "$D" | tr '\n' ' ')"
echo "  na foto: $(ls "$BASE/$R" 2>/dev/null | tr '\n' ' ')"
echo "  confiável (exemplo): $(runuser -u aluno -- env DBUS_SESSION_BUS_ADDRESS=$BUS gio info -a metadata::trusted "$D/libreoffice-writer.desktop" 2>/dev/null | grep trusted | tr -s ' ')"
