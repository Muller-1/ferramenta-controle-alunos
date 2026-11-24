#!/usr/bin/env bash
# =============================================================================
# lab-wol-mint.sh — Wake-on-LAN do lado do sistema (Linux Mint): a placa de rede fica pronta para ligar o PC
# pela rede (botão "Iniciar" do painel). Falta a parte da BIOS (Wake on LAN), que é manual em cada PC.
#   - NetworkManager: 802-3-ethernet.wake-on-lan = magic (fica gravado, vale em todo boot)
#   - ethtool: wol g agora (sem reiniciar a rede, sem derrubar nada)
# Uso:   sudo bash lab-wol-mint.sh              (aplica e mostra o estado)
#        sudo bash lab-wol-mint.sh --desfazer   (volta ao padrão do NetworkManager)
# =============================================================================
set -euo pipefail
echo "Máquina: $(hostname)"
[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
VALOR="magic"; [[ "${1:-}" == "--desfazer" ]] && VALOR="default"
achou=0
for d in /sys/class/net/*; do
  n="$(basename "$d")"
  [[ -e "$d/device" && ! -d "$d/wireless" ]] || continue
  achou=1
  con="$(nmcli -g GENERAL.CONNECTION device show "$n" 2>/dev/null || true)"
  if [[ -n "$con" ]]; then nmcli connection modify "$con" 802-3-ethernet.wake-on-lan "$VALOR"; fi
  [[ "$VALOR" == magic ]] && ethtool -s "$n" wol g 2>/dev/null || true
  suporta="$(ethtool "$n" 2>/dev/null | awk '/Supports Wake-on/{print $3}')"; atual="$(ethtool "$n" 2>/dev/null | awk '/^[[:space:]]+Wake-on:/{print $2}')"
  echo "  [ok] $n ($(cat "$d/address")): NetworkManager=$(nmcli -g 802-3-ethernet.wake-on-lan connection show "$con" 2>/dev/null) | placa suporta '$suporta', ativo agora '$atual'"
done
(( achou )) || echo "  [aviso] nenhuma placa de rede cabeada encontrada"
echo "Lembrete: ligue também 'Wake on LAN' na BIOS (Dell: F2 > Power Management > Wake on LAN > LAN Only) e desligue 'Deep Sleep Control'."
