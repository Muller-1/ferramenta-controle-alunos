#!/usr/bin/env bash
# =============================================================================
# lab-desempenho-mint.sh — deixa os PCs do lab mais leves (Linux Mint, XFCE ou Cinnamon)
#   1. zram: ~50% da RAM vira swap comprimida na memória (zstd), usada antes do swapfile do disco.
#      Com Brave + Minecraft os 8 GB não "estouram" e o PC não engasga.
#   2. Memória: swappiness 100 (usa a zram cedo, é barata), page-cluster 0.
#   3. Brave: economia de memória (abas paradas são descarregadas) e não fica rodando depois de fechado.
#   4. Atualizador do Mint fora da sessão do aluno (o aluno não instala nada; ~100 MB de RAM + rede).
#   5. Serviços sem uso no lab desligados: ModemManager (modem 3G), kerneloops (relatórios),
#      cups-browsed (procura impressoras na rede), notícias do motd e verificação de firmware.
#   6. Registro do sistema (journal) limitado a 150 MB.
# Não fecha nada do aluno; o que depende de login vale no próximo login. Admins não são afetados.
# Uso:   sudo bash lab-desempenho-mint.sh             (aplica)
#        sudo bash lab-desempenho-mint.sh --desfazer  (devolve tudo)
# Seguro para rodar de novo.
# =============================================================================
set -euo pipefail
ALUNO=aluno
BASE=/var/lib/lab/perfil-base
ZRAM_UNIT=/etc/systemd/system/lab-zram.service
SYSCTL=/etc/sysctl.d/90-lab-desempenho.conf
BRAVE=/etc/brave/policies/managed/97-lab-leve.json
JOURNAL=/etc/systemd/journald.conf.d/90-lab.conf
SERVICOS=(ModemManager.service kerneloops.service cups-browsed.service)
TIMERS=(motd-news.timer fwupd-refresh.timer)
AUTOSTART_OFF=(mintupdate.desktop)
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

pastas_autostart() { echo "/home/$ALUNO/.config/autostart"; [[ -d "$BASE" ]] && echo "$BASE/.config/autostart"; }

if [[ "${1:-}" == "--desfazer" ]]; then
  systemctl disable --now lab-zram.service 2>/dev/null || true
  rm -f "$ZRAM_UNIT" "$SYSCTL" "$BRAVE" "$JOURNAL" /usr/local/lib/lab/zram; systemctl daemon-reload
  sysctl -q -w vm.swappiness=60 vm.page-cluster=3 || true
  systemctl restart systemd-journald || true
  for s in "${SERVICOS[@]}" "${TIMERS[@]}"; do systemctl enable --now "$s" 2>/dev/null || true; done
  while read -r d; do for a in "${AUTOSTART_OFF[@]}"; do
    grep -q "lab-desempenho" "$d/$a" 2>/dev/null && rm -f "$d/$a"; done; done < <(pastas_autostart)
  ok "desempenho: tudo devolvido ao padrão"; exit 0
fi

info "1) zram (swap comprimida na RAM)"
install -d -m 755 /usr/local/lib/lab
cat > /usr/local/lib/lab/zram <<'EOF'
#!/bin/sh
# zram ligar|desligar (usado pelo lab-zram.service)
set -e
if [ "$1" = ligar ]; then
  [ -s /run/lab-zram ] && exit 0
  modprobe zram
  T=$(awk '/MemTotal/{print int($2/2)}' /proc/meminfo)
  D=$(zramctl --find --algorithm zstd --size "${T}KiB")
  mkswap -q "$D"; swapon -p 100 "$D"; echo "$D" > /run/lab-zram
else
  D=$(cat /run/lab-zram 2>/dev/null) || exit 0
  swapoff "$D" 2>/dev/null || true; zramctl --reset "$D" 2>/dev/null || true; rm -f /run/lab-zram
fi
EOF
chmod 755 /usr/local/lib/lab/zram
cat > "$ZRAM_UNIT" <<'EOF'
[Unit]
Description=Lab: swap comprimida na RAM (zram, zstd, 50% da memória)
DefaultDependencies=no
Before=swap.target
After=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/lib/lab/zram ligar
ExecStop=/usr/local/lib/lab/zram desligar

[Install]
WantedBy=swap.target
EOF
systemctl daemon-reload
systemctl enable lab-zram.service >/dev/null 2>&1
systemctl is-active -q lab-zram.service || systemctl start lab-zram.service
ok "$(swapon --show=NAME,SIZE,PRIO --noheadings | tr -s ' ' | tr '\n' ';')"

info "2) Memória"
printf '# lab-desempenho-mint.sh\nvm.swappiness = 100\nvm.page-cluster = 0\n' > "$SYSCTL"
sysctl -q -p "$SYSCTL"
ok "swappiness $(cat /proc/sys/vm/swappiness), page-cluster $(cat /proc/sys/vm/page-cluster)"

info "3) Brave leve"
install -d -m 755 "$(dirname "$BRAVE")"
cat > "$BRAVE" <<'EOF'
{
  "HighEfficiencyModeEnabled": true,
  "MemorySaverModeSavings": 2,
  "BackgroundModeEnabled": false
}
EOF
chmod 644 "$BRAVE"
ok "economia de memória ligada, sem rodar em segundo plano (vale ao abrir o Brave de novo)"

info "4) Atualizador do Mint fora da sessão do aluno"
while read -r d; do
  install -d -o $ALUNO -g $ALUNO "$d"
  for a in "${AUTOSTART_OFF[@]}"; do
    printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\nX-GNOME-Autostart-enabled=false\n# lab-desempenho\n' "${a%.desktop}" > "$d/$a"
    chown $ALUNO:$ALUNO "$d/$a"
  done
done < <(pastas_autostart)
ok "${AUTOSTART_OFF[*]} desligado para o aluno (próximo login)"

info "5) Serviços sem uso"
for s in "${SERVICOS[@]}" "${TIMERS[@]}"; do
  systemctl list-unit-files "$s" >/dev/null 2>&1 || continue
  systemctl disable --now "$s" >/dev/null 2>&1 || true
done
ok "desligados: ${SERVICOS[*]} ${TIMERS[*]}"

info "6) Journal limitado"
install -d -m 755 "$(dirname "$JOURNAL")"
printf '[Journal]\nSystemMaxUse=150M\n' > "$JOURNAL"
systemctl restart systemd-journald
journalctl --vacuum-size=150M -q 2>/dev/null || true
ok "$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.,]*[MG]')"

echo "Pronto. Para desfazer: sudo bash $0 --desfazer"
