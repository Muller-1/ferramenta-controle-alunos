#!/usr/bin/env bash
# =============================================================================
# lab-horario-mint.sh — o PC liga e desliga sozinho no horário da aula (Linux Mint)
#   - Ligar: o relógio interno do PC (RTC) fica programado para o próximo horário de ligar; funciona com o PC
#     desligado e sem precisar do computador do professor. (O professor também manda Wake-on-LAN como reserva.)
#   - Desligar: no horário marcado o PC desliga sozinho; 5 minutos antes aparece um aviso na tela do aluno.
#   - Se o PC for ligado fora do horário (evento à noite, manutenção), ele NÃO desliga sozinho: só desliga
#     nos 3 minutos depois do horário de desligar.
# Padrão: segunda a sexta, liga 08:00 e desliga 16:57; sábado e domingo não liga.
# Comandos (no PC, como admin; o professor usa "lab horario ..." ou o painel):
#   sudo /usr/local/lib/lab/horario mostrar
#   sudo /usr/local/lib/lab/horario definir "seg=08:00-16:57,ter=08:00-16:57,sab=-"   (dias não citados ficam como estão)
#   sudo /usr/local/lib/lab/horario adiar 60        (hoje desliga 60 min depois do horário; "adiar 0" cancela)
# Uso:  sudo bash lab-horario-mint.sh  [--desfazer]
# =============================================================================
set -euo pipefail
LIB=/usr/local/lib/lab; CONF=/etc/lab/horario.conf
ok()   { echo "  [ok] $*"; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

if [[ "${1:-}" == "--desfazer" ]]; then
  systemctl disable --now lab-horario.timer >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/lab-horario.{timer,service} /etc/sudoers.d/lab-horario "$LIB/horario" /var/lib/lab/horario-adiado
  echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
  systemctl daemon-reload; ok "horário automático removido (a configuração $CONF foi mantida)"; exit 0
fi

install -d -m 755 "$LIB" /etc/lab /var/lib/lab
if [[ ! -f "$CONF" ]]; then
  cat > "$CONF" <<'EOF'
# Horário automático do laboratório: dia  ligar  desligar   ("-" = neste dia o PC não liga nem desliga sozinho)
seg 08:00 16:57
ter 08:00 16:57
qua 08:00 16:57
qui 08:00 16:57
sex 08:00 16:57
sab - -
dom - -
EOF
fi
chmod 644 "$CONF"

cat > "$LIB/horario" <<'EOF'
#!/usr/bin/env bash
# horario mostrar | definir "seg=08:00-16:57,..." | adiar MINUTOS | tick (usado pelo timer a cada minuto)
CONF=/etc/lab/horario.conf; ADI=/var/lib/lab/horario-adiado; LOG=/var/log/lab-horario.log
DIAS=(seg ter qua qui sex sab dom)
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
campo() { awk -v d="$1" -v c="$2" '$1==d{print $c}' "$CONF"; }          # campo DIA 2=ligar 3=desligar
quando() {   # quando DATA(AAAA-MM-DD) HH:MM -> epoch
  date -d "$1 $2" +%s 2>/dev/null; }
dia_de() { local u; u=$(date -d "$1" +%u); echo "${DIAS[$((u-1))]}"; }
proximo_ligar() {   # próximo horário de ligar a partir de agora (epoch), ou vazio
  local agora i d h e; agora=$(date +%s)
  for i in 0 1 2 3 4 5 6 7; do
    d=$(date -d "today +$i day" +%F); h=$(campo "$(dia_de "$d")" 2)
    [[ "$h" =~ ^[0-9]{2}:[0-9]{2}$ ]] || continue
    e=$(quando "$d" "$h"); (( e > agora + 90 )) && { echo "$e"; return; }
  done; }
desligar_hoje() {   # horário efetivo de desligar hoje (epoch), considerando o adiamento; vazio se não desliga
  local d h e a; d=$(date +%F); h=$(campo "$(dia_de "$d")" 3)
  [[ "$h" =~ ^[0-9]{2}:[0-9]{2}$ ]] || return
  e=$(quando "$d" "$h"); a=$(cat "$ADI" 2>/dev/null)
  [[ "$a" =~ ^[0-9]+$ && $(date -d "@$a" +%F) == "$d" && $a -gt $e ]] && e=$a
  echo "$e"; }
programa_rtc() {
  local p atual; p=$(proximo_ligar); [[ -n "$p" ]] || { echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null; return; }
  atual=$(cat /sys/class/rtc/rtc0/wakealarm 2>/dev/null)
  if [[ "$atual" != "$p" ]]; then echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null; echo "$p" > /sys/class/rtc/rtc0/wakealarm 2>/dev/null && log "relógio programado para ligar em $(date -d "@$p" '+%a %F %H:%M')"; fi; }
mostrar() {
  local d linha="" p o
  for d in "${DIAS[@]}"; do l=$(campo "$d" 2); s=$(campo "$d" 3); [[ "$l" == - || -z "$l" ]] && linha+="$d=- " || linha+="$d=$l-$s "; done
  p=$(proximo_ligar); o=$(desligar_hoje)
  echo "$(hostname): ${linha% } | próximo ligar: $( [[ -n "$p" ]] && date -d "@$p" '+%a %d/%m %H:%M' || echo nenhum) | desliga hoje: $( [[ -n "$o" && $o -gt $(date +%s) ]] && date -d "@$o" +%H:%M || echo não)$( [[ -s $ADI ]] && echo " (adiado)")"; }
case "${1:-mostrar}" in
  mostrar|status) mostrar ;;
  definir)
    shift; spec="$*"; spec="${spec//,/ }"; [[ -n "${spec// /}" ]] || { echo "uso: horario definir \"seg=08:00-16:57,sab=-\""; exit 2; }
    tmp=$(mktemp); cp "$CONF" "$tmp"
    for t in $spec; do
      if [[ "$t" =~ ^(seg|ter|qua|qui|sex|sab|dom)=-$ ]]; then d=${BASH_REMATCH[1]}; l=-; s=-
      elif [[ "$t" =~ ^(seg|ter|qua|qui|sex|sab|dom)=([01][0-9]|2[0-3]):([0-5][0-9])-([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        d=${BASH_REMATCH[1]}; l="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"; s="${BASH_REMATCH[4]}:${BASH_REMATCH[5]}"
        [[ "$l" < "$s" ]] || { echo "$(hostname): em $d o horário de ligar precisa ser antes do de desligar"; rm -f "$tmp"; exit 2; }
      else echo "$(hostname): não entendi \"$t\" (use dia=HH:MM-HH:MM ou dia=-)"; rm -f "$tmp"; exit 2; fi
      awk -v d="$d" -v l="$l" -v s="$s" '$1==d{print d, l, s; next}{print}' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    install -m 644 "$tmp" "$CONF"; rm -f "$tmp"; log "horário alterado: $spec"; programa_rtc; mostrar ;;
  adiar)
    m="${2:-}"; [[ "$m" =~ ^[0-9]{1,3}$ ]] && (( 10#$m <= 240 )) || { echo "uso: horario adiar MINUTOS (0 a 240; 0 cancela)"; exit 2; }
    rm -f "$ADI"
    if (( 10#$m > 0 )); then o=$(desligar_hoje); [[ -n "$o" ]] || { echo "$(hostname): hoje não tem desligamento automático"; exit 0; }
      echo $(( o + 10#$m * 60 )) > "$ADI"; log "desligamento de hoje adiado $m min"; fi
    mostrar ;;
  tick)
    programa_rtc
    o=$(desligar_hoje); [[ -n "$o" ]] || exit 0
    agora=$(date +%s)
    if (( agora >= o - 300 && agora < o - 240 )) && [[ ! -e /run/lab-horario-avisado ]]; then
      touch /run/lab-horario-avisado
      /usr/local/lib/lab/mensagem 280 "Este computador vai desligar às $(date -d "@$o" +%H:%M). Salve seu trabalho na sua pasta (trabalhos-alunos)." >/dev/null 2>&1 || true
    fi
    boot=$(date -d "$(uptime -s)" +%s)          # só desliga se já estava ligado antes do horário (religado depois = fica ligado)
    if (( agora >= o && agora < o + 180 && boot < o )); then
      log "desligando no horário ($(date -d "@$o" +%H:%M))"; rm -f "$ADI" /run/lab-horario-avisado; programa_rtc; systemctl poweroff
    fi ;;
  *) echo "uso: horario mostrar | definir \"seg=08:00-16:57,sab=-\" | adiar MINUTOS"; exit 2 ;;
esac
EOF
chmod 755 "$LIB/horario"; ok "comando $LIB/horario"

cat > /etc/systemd/system/lab-horario.service <<EOF
[Unit]
Description=Horário automático do laboratório (aviso, desligar e programar o ligar)
[Service]
Type=oneshot
KillMode=process
KillMode=process
ExecStart=$LIB/horario tick
EOF
cat > /etc/systemd/system/lab-horario.timer <<'EOF'
[Unit]
Description=Confere o horário automático a cada minuto
[Timer]
OnCalendar=*:*:05
AccuracySec=1s
Persistent=false
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload; systemctl enable --now lab-horario.timer >/dev/null 2>&1
ok "timer lab-horario (a cada minuto)"

printf '%%sudo ALL=(root) NOPASSWD: %s/horario\n' "$LIB" > /etc/sudoers.d/lab-horario
chmod 440 /etc/sudoers.d/lab-horario; visudo -cf /etc/sudoers.d/lab-horario >/dev/null
ok "sudo sem senha só para $LIB/horario"
"$LIB/horario" tick >/dev/null 2>&1 || true
"$LIB/horario" mostrar
