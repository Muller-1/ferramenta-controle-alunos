#!/usr/bin/env bash
# =============================================================================
# lab-rede-pronta-mint.sh — a pasta pública abre certinho logo depois de ligar (Linux Mint)
# Problema: ao ligar, o sistema avisa "rede pronta" alguns segundos antes de a placa de rede ter rota;
# a pasta pública (trabalhos-alunos, no A1) tentava montar nesse instante e falhava ("Network is unreachable").
# Correção: um serviço que só deixa a "rede pronta" acontecer quando o roteador (ou o A1) responde de verdade
# (espera no máximo 60 s; não atrasa a tela de login nem o login automático).
# Uso:  sudo bash lab-rede-pronta-mint.sh   [--desfazer]
# =============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"
if [[ "${1:-}" == "--desfazer" ]]; then
  systemctl disable lab-rede-pronta.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/lab-rede-pronta.service; systemctl daemon-reload; echo "  [ok] removido"; exit 0
fi
GW=$(ip route show default 2>/dev/null | awk '{print $3; exit}'); GW=${GW:-192.168.0.1}
SRV=$(awk '/trabalhos-alunos/ && $1 ~ /^\/\// {split($1,a,"/"); print a[3]; exit}' /etc/fstab); SRV=${SRV:-$GW}
cat > /etc/systemd/system/lab-rede-pronta.service <<EOF
[Unit]
Description=Espera a rede do lab responder de verdade (para a pasta pública montar no boot)
After=NetworkManager-wait-online.service
Before=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for i in \$(seq 1 60); do ping -c1 -W1 $SRV >/dev/null 2>&1 && exit 0; ping -c1 -W1 $GW >/dev/null 2>&1 && exit 0; sleep 1; done; exit 0'
TimeoutStartSec=90
[Install]
WantedBy=network-online.target
EOF
systemctl daemon-reload; systemctl enable lab-rede-pronta.service >/dev/null 2>&1
echo "  [ok] lab-rede-pronta: espera $SRV ou $GW responder antes da \"rede pronta\" (máx. 60 s)"
