#!/usr/bin/env bash
# =============================================================================
# lab-perfil-limpo-mint.sh — "perfil limpo": a conta aluno volta ao estado original a CADA BOOT (Linux Mint)
# Tira uma foto (snapshot) da pasta /home/aluno limpa e, antes do login automático de cada boot, devolve tudo ao
# estado da foto: arquivos, downloads, imagens, histórico/cookies do navegador, login do Roblox, configurações que o
# aluno tenha mexido. O que fica salvo é só a pasta pública (trabalhos-alunos), que não está no PC.
# Rápido: o rsync só copia o que mudou (os 5 GB do Roblox, que não mudam, não são recopiados).
#
# Uso (como admin, com sudo):
#   sudo bash lab-perfil-limpo-mint.sh              instala e tira a foto agora (liga o perfil limpo neste PC)
#   sudo perfil-limpo snapshot                       tira a foto de novo (depois de mudar algo de propósito no perfil)
#   sudo perfil-limpo restaurar --simular            mostra o que seria apagado/restaurado, sem mexer em nada
#   sudo perfil-limpo status                         estado e tamanho da foto
#   sudo touch /var/lib/lab/perfil-limpo.off         desliga temporariamente (apague o arquivo para religar)
#   sudo bash lab-perfil-limpo-mint.sh --desfazer    remove tudo (serviço e foto)
# A restauração só roda com NINGUÉM logado como aluno (no boot, antes da tela de login).
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR
LIB="/usr/local/lib/lab"; BASE="/var/lib/lab/perfil-base"
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

if [[ "${1:-}" == "--desfazer" ]]; then
  systemctl disable --now lab-perfil-limpo.service >/dev/null 2>&1 || true
  chattr -i "$LIB/perfil-limpo" 2>/dev/null || true
  rm -f /etc/systemd/system/lab-perfil-limpo.service "$LIB/perfil-limpo" /usr/local/sbin/perfil-limpo
  rm -rf "$BASE"; rmdir /var/lib/lab 2>/dev/null || true
  systemctl daemon-reload; ok "perfil limpo removido (serviço e foto apagados)"; exit 0
fi

info "1) Programa perfil-limpo"
install -d -m 755 "$LIB" /var/lib/lab
chattr -i "$LIB/perfil-limpo" 2>/dev/null || true
cat > "$LIB/perfil-limpo" <<'EOF'
#!/usr/bin/env bash
# perfil-limpo snapshot | restaurar [--simular] [--forcar] | status
ALUNO=aluno; H=/home/$ALUNO; BASE=/var/lib/lab/perfil-base; LOG=/var/log/lab-perfil-limpo.log
IMUTAVEIS=("$H/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml")      # arquivos travados com chattr +i
FILTRO=(--exclude='/.cache' --exclude='/.Xauthority' --exclude='/.ICEauthority' --exclude='/.xsession-errors*' --exclude='/.local/share/Trash')
log() { echo "$(date '+%F %T') $*" | tee -a "$LOG" >&2; }
logado() { loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$ALUNO" '$3==u && $6!="closing"{f=1} END{exit !f}'; }
limpa_base() {   # tira da FOTO o que é do aluno (a foto fica "de fábrica"); o /home/aluno em uso não é tocado
  local d
  for d in Documentos Documents Downloads Imagens Vídeos Músicas Modelos Público Desktop "Área de trabalho"; do
    [[ -d "$BASE/$d" ]] && find "$BASE/$d" -mindepth 1 ! -type l -delete 2>/dev/null
  done
  local sd="$BASE/.var/app/org.vinegarhq.Sober/data/sober"
  rm -f "$sd/cookies" "$sd/appData/LocalStorage/appStorage.json" "$sd/appData/LocalStorage/memProfStorage3.json"      # sem conta do Roblox
  local b="$BASE/.config/BraveSoftware/Brave-Browser" p
  for p in "$b"/Default "$b"/Profile*; do
    [[ -d "$p" ]] || continue
    rm -rf "$p"/{History*,Cookies*,"Login Data"*,"Web Data"*,Sessions,"Current Session","Current Tabs","Last Session","Last Tabs",Favicons*,"Top Sites"*,"Local Storage",IndexedDB,"Session Storage",Cache,"Code Cache","Service Worker",Network,"Network Action Predictor","Shortcuts"*,"Visited Links"} 2>/dev/null
  done
  rm -f "$b"/Singleton* "$BASE/.config/libreoffice/4/.lock" 2>/dev/null
  find "$BASE/.config/libreoffice" -name '.~lock*' -delete 2>/dev/null
  rm -rf "$BASE/.config/libreoffice/4/user/backup"/* 2>/dev/null
}
case "${1:-status}" in
  snapshot)
    ini=$(date +%s)
    log "foto do perfil: copiando $H -> $BASE"
    nice -n 19 ionice -c3 rsync -a --delete --delete-excluded --numeric-ids "${FILTRO[@]}" "$H/" "$BASE/"
    limpa_base
    log "foto pronta em $(( $(date +%s) - ini ))s ($(du -sh "$BASE" | cut -f1))"
    ;;
  restaurar)
    shift; sim=0; forca=0
    for a in "$@"; do [[ "$a" == --simular ]] && sim=1; [[ "$a" == --forcar ]] && forca=1; done
    [[ -d "$BASE" ]] || { log "sem foto em $BASE: nada a restaurar"; exit 0; }
    [[ -e /var/lib/lab/perfil-limpo.off ]] && { log "perfil limpo desligado (perfil-limpo.off): nada feito"; exit 0; }
    if logado && (( ! forca )); then log "o aluno está logado: não restauro (use --simular para só ver)"; (( sim )) || exit 0; fi
    ini=$(date +%s)
    if (( sim )); then
      echo "(simulação: nada será alterado) o que seria apagado/restaurado em $H:"
      rsync -a -n -i --delete --delete-excluded --numeric-ids "${FILTRO[@]}" "$BASE/" "$H/" | grep -v -E '^\.|^\*deleting +\.cache/' | head -200
      echo "(fim da lista)"
    else
      for f in "${IMUTAVEIS[@]}"; do [[ -e "$f" ]] && chattr -i "$f" 2>/dev/null; done
      rsync -a --delete --delete-excluded --numeric-ids "${FILTRO[@]}" "$BASE/" "$H/" ; rc=$?
      for f in "${IMUTAVEIS[@]}"; do [[ -e "$f" ]] && chattr +i "$f" 2>/dev/null; done
      log "perfil restaurado em $(( $(date +%s) - ini ))s (rsync código $rc)"
    fi
    ;;
  status)
    echo "foto: $( [[ -d $BASE ]] && du -sh $BASE | cut -f1 || echo nenhuma ) | desligado: $( [[ -e /var/lib/lab/perfil-limpo.off ]] && echo sim || echo não ) | aluno logado: $(logado && echo sim || echo não)"
    tail -3 "$LOG" 2>/dev/null ;;
  *) echo "uso: perfil-limpo snapshot | restaurar [--simular] [--forcar] | status"; exit 2 ;;
esac
EOF
chmod 755 "$LIB/perfil-limpo"; ln -sf "$LIB/perfil-limpo" /usr/local/sbin/perfil-limpo
ok "instalado em $LIB/perfil-limpo (comando: sudo perfil-limpo ...)"

info "2) Serviço que restaura a cada boot (antes da tela de login)"
cat > /etc/systemd/system/lab-perfil-limpo.service <<EOF
[Unit]
Description=Perfil limpo do aluno (restaura /home/aluno a cada boot)
After=local-fs.target
Before=display-manager.service lightdm.service
ConditionPathExists=$BASE
ConditionPathExists=!/var/lib/lab/perfil-limpo.off
[Service]
Type=oneshot
ExecStart=-$LIB/perfil-limpo restaurar
TimeoutStartSec=900
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable lab-perfil-limpo.service >/dev/null 2>&1
ok "serviço lab-perfil-limpo ativado (roda sozinho em cada boot)"

info "3) Foto do perfil limpo agora"
"$LIB/perfil-limpo" snapshot
chattr +i "$LIB/perfil-limpo"
echo
"$LIB/perfil-limpo" status
echo "Pronto. A cada boot o /home/aluno volta a esta foto. Para refazer a foto: sudo perfil-limpo snapshot"
