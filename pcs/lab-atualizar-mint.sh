#!/usr/bin/env bash
# =============================================================================
# lab-atualizar-mint.sh — o PC se atualiza sozinho de manhã, logo depois de ligar (Linux Mint)
#   - Roda uma vez por dia, quando o PC liga antes das 08:25 (o horário automático liga às 08:00; aula às 08:30).
#   - Se o PC ficou mais de 7 dias sem atualizar (ex.: não ligou de manhã), atualiza no próximo boot, a qualquer hora.
#   - Atualiza os programas do sistema (apt) e os da loja Flatpak (Roblox/Sober, Scratch), com prioridade baixa.
#   - Nunca reinicia sozinho: o que precisar de reinício (ex.: kernel) vale no próximo boot.
#   - Registro: /var/log/lab-atualizar.log
# Uso:  sudo bash lab-atualizar-mint.sh   [--desfazer]
#       sudo /usr/local/lib/lab/atualizar --agora     (atualiza já, sem esperar o boot)
# =============================================================================
set -euo pipefail
LIB=/usr/local/lib/lab
ok() { echo "  [ok] $*"; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

if [[ "${1:-}" == "--desfazer" ]]; then
  systemctl disable lab-atualizar.timer lab-atualizar.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/lab-atualizar.{service,timer} "$LIB/atualizar"; systemctl daemon-reload
  ok "atualização no boot removida"; exit 0
fi
install -d -m 755 "$LIB" /var/lib/lab

cat > "$LIB/atualizar" <<'EOF'
#!/usr/bin/env bash
# atualizar [--agora]: atualização do PC do lab (apt + flatpak), uma vez por dia de manhã
LOG=/var/log/lab-atualizar.log; MARCA=/var/lib/lab/ultima-atualizacao
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
hoje=$(date +%F); ultima=$(cat "$MARCA" 2>/dev/null || echo 1970-01-01)
dias=$(( ( $(date +%s) - $(date -d "$ultima" +%s 2>/dev/null || echo 0) ) / 86400 ))
if [[ "${1:-}" != --agora ]]; then
  [[ "$ultima" == "$hoje" ]] && exit 0                                  # já atualizou hoje
  if (( 10#$(date +%H%M) >= 825 && dias < 7 )); then log "ligou depois das 08:25: fica para amanhã (última: $ultima)"; exit 0; fi
fi
for i in $(seq 1 24); do getent hosts deb.debian.org >/dev/null 2>&1 || getent hosts packages.linuxmint.com >/dev/null 2>&1 && break; sleep 5; done
export DEBIAN_FRONTEND=noninteractive
for i in $(seq 1 60); do fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break; sleep 5; done
ini=$(date +%s); log "início"
apt-get update -qq >>"$LOG" 2>&1
n=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst')
apt-get -y -qq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade >>"$LOG" 2>&1; rc=$?
apt-get -y -qq autoremove >>"$LOG" 2>&1 || true
flatpak update --system -y --noninteractive >>"$LOG" 2>&1; rf=$?
(( rc == 0 )) && echo "$hoje" > "$MARCA"
log "fim em $(( $(date +%s) - ini ))s: $n pacote(s) do sistema (código $rc), flatpak (código $rf)"
[[ -e /var/run/reboot-required ]] && log "alguma atualização vale só depois de reiniciar (fica para o próximo boot)"
exit 0
EOF
chmod 755 "$LIB/atualizar"

cat > /etc/systemd/system/lab-atualizar.service <<EOF
[Unit]
Description=Atualização do PC do laboratório (de manhã, depois de ligar)
Wants=network-online.target
After=network-online.target lab-perfil-limpo.service
[Service]
Type=oneshot
ExecStart=$LIB/atualizar
Nice=15
IOSchedulingClass=idle
TimeoutStartSec=2400
EOF
# disparado por timer 90 s depois do boot: não atrasa a tela de login nem o login automático
cat > /etc/systemd/system/lab-atualizar.timer <<'EOF'
[Unit]
Description=Atualização do PC do laboratório 90 s depois de ligar
[Timer]
OnBootSec=90s
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload; systemctl disable lab-atualizar.service >/dev/null 2>&1 || true; systemctl enable lab-atualizar.timer >/dev/null 2>&1
ok "atualização automática 90 s depois de ligar, de manhã (lab-atualizar.timer; registro em /var/log/lab-atualizar.log)"
