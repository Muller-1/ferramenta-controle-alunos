#!/usr/bin/env bash
# =============================================================================
# lab-sistema-mint.sh — ajustes de sistema do laboratório (Linux Mint, XFCE/Cinnamon)
#   1. Energia: NUNCA suspender/hibernar/desligar por inatividade (a tela pode apagar). Sem protetor de tela
#      nem tela de bloqueio: o PC fica aberto exatamente onde o aluno deixou.
#   2. Veyon: prioridade máxima de CPU/disco/memória e de rede, imutável para alunos.
#   3. Vigia (a cada 1 min): religa o Veyon se cair e volta o login do aluno se a
#      máquina ficar parada na tela de login.
#   4. LibreOffice: salvamento automático a cada 1 min e pasta padrão fixa = trabalhos-alunos.
#   5. Backup: libera leitura das pastas de trabalho ao admin (rsync feito do Bazzite).
# Nada aqui reinicia sessão, tela de login ou programas em uso pelos alunos.
# Uso:   sudo bash lab-sistema-mint.sh              (aplica)
#        sudo bash lab-sistema-mint.sh --desfazer   (desfaz 1, 2, 3 e 4)
# Seguro para rodar de novo.
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR

ALUNO="aluno"
LIB="/usr/local/lib/lab"
ADMIN="${ADMIN_USER:-${SUDO_USER:-}}"
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }
aviso(){ echo "  [aviso] $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
[[ -n "$ADMIN" && "$ADMIN" != "root" ]] || { echo "Rode logado como admin usando sudo." >&2; exit 1; }
UID_ALUNO="$(id -u "$ALUNO")"
BUS="unix:path=/run/user/$UID_ALUNO/bus"
echo "Máquina: $(hostname) | admin: $ADMIN"

unlock() { for f in "$@"; do [[ -e "$f" ]] && chattr -i "$f" 2>/dev/null || true; done; }
lock()   { for f in "$@"; do [[ -e "$f" ]] && chattr +i "$f" 2>/dev/null || true; done; }

# ------------------------------------------------------------------ desfazer --
if [[ "${1:-}" == "--desfazer" ]]; then
  info "Desfazendo"
  systemctl disable --now lab-vigia.timer lab-veyon-rede.service >/dev/null 2>&1 || true
  F="/etc/systemd/system/veyon.service.d/10-lab-prioridade.conf"
  unlock "$F" "$LIB/vigia" "$LIB/rede-prioridade-veyon" "$LIB/libreoffice-autosave"
  rm -f "$F" /etc/systemd/system/lab-vigia.* /etc/systemd/system/lab-veyon-rede.service \
        /etc/NetworkManager/dispatcher.d/90-lab-veyon-rede /etc/xdg/autostart/lab-libreoffice-autosave.desktop \
        "$LIB/vigia" "$LIB/rede-prioridade-veyon" "$LIB/libreoffice-autosave" \
        /etc/systemd/logind.conf.d/10-lab-energia.conf /etc/dconf/db/local.d/10-lab-energia /etc/dconf/db/local.d/locks/10-lab-energia
  chattr -i /etc/libreoffice/registry/lab-paths.xcd 2>/dev/null; rm -f /etc/libreoffice/registry/lab-paths.xcd
  rm -f /etc/polkit-1/rules.d/21-lab-sem-desligar.rules /etc/apt/apt.conf.d/99-lab-sem-reiniciar
  rm -f /etc/dconf/db/local.d/11-lab-sem-protetor /etc/dconf/db/local.d/locks/11-lab-sem-protetor /etc/xdg/autostart/lab-sem-protetor.desktop "$LIB/sem-protetor-xorg"
  for b in /usr/bin/light-locker /usr/bin/light-locker-command /usr/bin/light-locker-settings /usr/bin/xflock4; do
    if dpkg-statoverride --list "$b" >/dev/null 2>&1; then dpkg-statoverride --remove "$b"; chmod 755 "$b"; fi
  done
  tc qdisc del dev "$(ip route show default | awk '/default/{print $5; exit}')" root 2>/dev/null || true
  systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target >/dev/null 2>&1 || true
  systemctl daemon-reload; dconf update 2>/dev/null || true
  ok "desfeito (energia, prioridade do Veyon, vigia, autosave)"
  exit 0
fi

# ------------------------------------------------------------------ 1. energia
info "1) Energia: sem suspender/desligar por inatividade"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target >/dev/null 2>&1
ok "suspender/hibernar bloqueados no sistema (sleep/suspend/hibernate.target mascarados)"
install -d -m 755 /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-lab-energia.conf <<'EOF'
# Gerado por lab-sistema-mint.sh
[Login]
IdleAction=ignore
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
HandleRebootKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl kill --kill-whom=main -s HUP systemd-logind 2>/dev/null || true   # relê a config sem derrubar sessões
ok "logind: ação por inatividade e tampa = ignorar (a tela continua apagando sozinha)"

if command -v cinnamon >/dev/null 2>&1; then
  install -d -m 755 /etc/dconf/db/local.d /etc/dconf/db/local.d/locks /etc/dconf/profile
  grep -qs '^system-db:local' /etc/dconf/profile/user || printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
  cat > /etc/dconf/db/local.d/10-lab-energia <<'EOF'
[org/cinnamon/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
lid-close-ac-action='nothing'
lid-close-battery-action='nothing'
lid-close-suspend-with-external-monitor=false
button-power='nothing'
button-sleep='nothing'
button-suspend='nothing'
button-hibernate='nothing'
EOF
  P=/org/cinnamon/settings-daemon/plugins/power
  printf '%s\n' $P/sleep-inactive-ac-type $P/sleep-inactive-battery-type $P/lid-close-ac-action $P/lid-close-battery-action $P/button-power $P/button-sleep $P/button-suspend $P/button-hibernate > /etc/dconf/db/local.d/locks/10-lab-energia
  dconf update
  if [[ -S "/run/user/$UID_ALUNO/bus" ]]; then   # aplica já na sessão aberta (não reinicia nada)
    for k in sleep-inactive-ac-type sleep-inactive-battery-type lid-close-ac-action lid-close-battery-action; do
      runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" dconf write "$P/$k" "'nothing'" 2>/dev/null || true
    done
  fi
  ok "Cinnamon: suspender por inatividade = nunca (travado no dconf; apagar a tela continua igual)"
fi
for XPM in /etc/xdg/xdg-xfce/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml; do
if [[ -f "$XPM" ]]; then
  python3 -I - "$XPM" <<'PY'
import sys, xml.etree.ElementTree as ET
p = sys.argv[1]
t = ET.parse(p); root = t.getroot()
base = [e for e in root.iter('property') if e.get('name') == 'xfce4-power-manager'][0]
want = {'power-button-action': '0', 'inactivity-on-ac': '14', 'inactivity-on-battery': '14', 'lid-action-on-ac': '0',
        'lid-action-on-battery': '0', 'sleep-button-action': '0', 'hibernate-button-action': '0'}
for k, v in want.items():
    e = [x for x in base.findall('property') if x.get('name') == k]
    if e: e[0].set('type', 'uint'); e[0].set('value', v)
    else: ET.SubElement(base, 'property', {'name': k, 'type': 'uint', 'value': v})
ET.indent(t, space='  ')
t.write(p, encoding='UTF-8', xml_declaration=True)
PY
  if [[ -S "/run/user/$UID_ALUNO/bus" ]] && command -v xfconf-query >/dev/null; then
    for k in inactivity-on-ac inactivity-on-battery; do
      runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" xfconf-query -c xfce4-power-manager -n -t uint -p "/xfce4-power-manager/$k" -s 14 2>/dev/null || true
    done
    for k in power-button-action sleep-button-action hibernate-button-action lid-action-on-ac lid-action-on-battery; do
      runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" xfconf-query -c xfce4-power-manager -n -t uint -p "/xfce4-power-manager/$k" -s 0 2>/dev/null || true
    done
  fi
  ok "XFCE: 'colocar o sistema para dormir' = nunca e botão de ligar sem ação (padrão do sistema e sessão aberta)"
fi
done

# ------------------------------------------- 1c. sem protetor de tela e sem tela de bloqueio
info "1c) Sem protetor de tela nem bloqueio (fica aberto onde deixou)"
install -d -m 755 "$LIB"
unlock "$LIB/sem-protetor-xorg" 2>/dev/null || true
cat > "$LIB/sem-protetor-xorg" <<'EOF'
#!/bin/sh
# Desliga o protetor de tela e o apagar-por-X (xset s) na sessão. (O apagar da tela por energia é outro ajuste.)
xset s off s noblank 2>/dev/null
exit 0
EOF
chmod 755 "$LIB/sem-protetor-xorg"
cat > /etc/xdg/autostart/lab-sem-protetor.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Sem protetor de tela (lab)
Exec=$LIB/sem-protetor-xorg
NoDisplay=true
EOF
if (( $(id -u "$ALUNO" >/dev/null 2>&1; echo $?) == 0 )) && [[ -S "/run/user/$UID_ALUNO/bus" ]]; then
  runuser -u "$ALUNO" -- env DISPLAY=:0 XAUTHORITY="/home/$ALUNO/.Xauthority" "$LIB/sem-protetor-xorg" || true
fi
if command -v cinnamon >/dev/null 2>&1; then
  install -d -m 755 /etc/dconf/db/local.d /etc/dconf/db/local.d/locks
  cat > /etc/dconf/db/local.d/11-lab-sem-protetor <<'EOF'
[org/cinnamon/desktop/session]
idle-delay=uint32 0

[org/cinnamon/desktop/screensaver]
idle-activation-enabled=false
lock-enabled=false
lock-delay=uint32 0

[org/cinnamon/desktop/lockdown]
disable-lock-screen=true
EOF
  printf '%s\n' /org/cinnamon/desktop/session/idle-delay /org/cinnamon/desktop/screensaver/idle-activation-enabled \
    /org/cinnamon/desktop/screensaver/lock-enabled /org/cinnamon/desktop/screensaver/lock-delay \
    /org/cinnamon/desktop/lockdown/disable-lock-screen > /etc/dconf/db/local.d/locks/11-lab-sem-protetor
  dconf update
  if [[ -S "/run/user/$UID_ALUNO/bus" ]]; then   # vale já na sessão aberta
    D=/org/cinnamon/desktop
    bus_dc() { runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" dconf write "$@" 2>/dev/null || true; }
    bus_dc $D/session/idle-delay "uint32 0"; bus_dc $D/screensaver/idle-activation-enabled false
    bus_dc $D/screensaver/lock-enabled false; bus_dc $D/screensaver/lock-delay "uint32 0"; bus_dc $D/lockdown/disable-lock-screen true
  fi
  ok "Cinnamon: protetor de tela desligado (idle-delay 0), sem bloqueio automático nem manual (travado no dconf)"
fi
if command -v light-locker >/dev/null 2>&1 || command -v xflock4 >/dev/null 2>&1; then   # XFCE usa o light-locker
  for b in /usr/bin/light-locker /usr/bin/light-locker-command /usr/bin/light-locker-settings /usr/bin/xflock4; do
    [[ -x "$b" ]] || continue
    dpkg-statoverride --list "$b" >/dev/null 2>&1 || dpkg-statoverride --update --add root sudo 750 "$b"
  done
  pkill -u "$ALUNO" -x light-locker 2>/dev/null || true
  ok "XFCE: tela de bloqueio (light-locker/xflock4) só para admins; o aluno não bloqueia nem cai em tela de bloqueio"
fi

# ---- 1d. o aluno não consegue desligar, reiniciar nem suspender o PC (nem por menu, comando ou botão)
info "1d) Ninguém desliga o PC por engano: aluno sem permissão de desligar/reiniciar/suspender"
install -d -m 755 /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/21-lab-sem-desligar.rules <<'EOF'
// Gerado por lab-sistema-mint.sh: a conta aluno não desliga, reinicia, suspende nem hiberna o PC.
// (Admins e o Veyon do professor continuam podendo; ordens do tipo "lab desligar" rodam como root.)
polkit.addRule(function(action, subject) {
  if (subject.user == "aluno" &&
      /^org\.freedesktop\.login1\.(power-off|reboot|halt|suspend|hibernate|hybrid-sleep|suspend-then-hibernate)/.test(action.id)) {
    return polkit.Result.NO;
  }
});
EOF
chmod 644 /etc/polkit-1/rules.d/21-lab-sem-desligar.rules
install -d -m 755 /etc/apt/apt.conf.d
printf '// Gerado por lab-sistema-mint.sh: atualizações automáticas nunca reiniciam nem desligam o PC sozinhas\nUnattended-Upgrade::Automatic-Reboot "false";\n' > /etc/apt/apt.conf.d/99-lab-sem-reiniciar
shutdown -c >/dev/null 2>&1 || true      # cancela qualquer desligamento agendado que tenha ficado pendente
ok "polkit: aluno sem permissão de desligar/reiniciar/suspender; atualizações sem reinício automático; botão de ligar sem ação"

# ------------------------------------------------------------ 2. veyon prioridade
info "2) Veyon: prioridade máxima (CPU, disco, memória e rede), imutável"
install -d -m 755 /etc/systemd/system/veyon.service.d "$LIB"
DROP="/etc/systemd/system/veyon.service.d/10-lab-prioridade.conf"
unlock "$DROP" "$LIB/rede-prioridade-veyon"
cat > "$DROP" <<'EOF'
# Gerado por lab-sistema-mint.sh: Veyon sempre com prioridade máxima
[Service]
Nice=-20
CPUWeight=10000
IOWeight=10000
IOSchedulingClass=best-effort
IOSchedulingPriority=0
OOMScoreAdjust=-900
Restart=always
RestartSec=3
# x11vnc órfão (sobra quando o veyon-server cai) segura a porta 11200 e impede o Veyon de subir
ExecStartPre=-/usr/bin/pkill -9 -x x11vnc
ExecStopPost=-/usr/bin/pkill -9 -x x11vnc
EOF
chmod 644 "$DROP"
systemctl daemon-reload
if systemctl is-active --quiet veyon; then   # aplica ao vivo, sem reiniciar o Veyon
  systemctl set-property --runtime veyon.service CPUWeight=10000 IOWeight=10000 >/dev/null 2>&1 || true
  CG="/sys/fs/cgroup$(systemctl show -p ControlGroup --value veyon)"
  if [[ -r "$CG/cgroup.procs" ]]; then
    while read -r p; do renice -n -20 -p "$p" >/dev/null 2>&1 || true; ionice -c2 -n0 -p "$p" 2>/dev/null || true; done < "$CG/cgroup.procs"
  fi
fi
lock "$DROP"
ok "veyon.service: Nice -20, CPU/IO peso máximo, protegido contra falta de memória, reinício automático (arquivo imutável)"

cat > "$LIB/rede-prioridade-veyon" <<'EOF'
#!/usr/bin/env bash
# Tráfego do Veyon (porta 11100) sai primeiro na fila da placa de rede.
DEV="$(ip route show default | awk '/default/{print $5; exit}')"
[[ -n "$DEV" ]] || exit 0
tc qdisc del dev "$DEV" root 2>/dev/null || true
tc qdisc add dev "$DEV" root handle 1: prio bands 3 priomap 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
for b in 1 2 3; do tc qdisc add dev "$DEV" parent 1:$b handle 1$b: fq_codel; done
for f in "ip sport" "ip dport"; do
  tc filter add dev "$DEV" parent 1: protocol ip prio 1 u32 match $f 11100 0xffff flowid 1:1
done
for f in "ip6 sport" "ip6 dport"; do
  tc filter add dev "$DEV" parent 1: protocol ipv6 prio 2 u32 match $f 11100 0xffff flowid 1:1
done
EOF
chmod 755 "$LIB/rede-prioridade-veyon"
cat > /etc/systemd/system/lab-veyon-rede.service <<EOF
[Unit]
Description=Prioridade de rede do Veyon (lab)
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$LIB/rede-prioridade-veyon
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/NetworkManager/dispatcher.d/90-lab-veyon-rede <<EOF
#!/bin/sh
[ "\$2" = "up" ] && $LIB/rede-prioridade-veyon
exit 0
EOF
chmod 755 /etc/NetworkManager/dispatcher.d/90-lab-veyon-rede
systemctl daemon-reload
systemctl enable lab-veyon-rede.service >/dev/null 2>&1
"$LIB/rede-prioridade-veyon"
lock "$LIB/rede-prioridade-veyon"
ok "rede: porta 11100 (Veyon) com prioridade na fila de saída (reaplica a cada conexão de rede)"

# -------------------------------------------------------------------- 3. vigia
info "3) Vigia do Veyon e do login do aluno (a cada 1 min)"
unlock "$LIB/vigia"
cat > "$LIB/vigia" <<'EOF'
#!/usr/bin/env bash
# lab vigia: 1) Veyon sem escutar com sessão do aluno ativa -> reinicia o Veyon
#            2) tela de login parada > 5 min, sem ninguém logado -> reinicia o login (volta o aluno)
ST=/run/lab-vigia; mkdir -p "$ST"
log() { echo "$(date '+%F %T') $*" >> /var/log/lab-vigia.log; logger -t lab-vigia "$*"; }
SESS="$(loginctl list-sessions --no-legend 2>/dev/null)"
GUI="$(echo "$SESS" | awk '$4=="seat0" && $3!="lightdm" && ($6=="active" || $6=="online")')"     # alguém logado (ativo ou com a tela travada)
ALUNO_ATIVO="$(echo "$SESS" | awk '$4=="seat0" && $3=="aluno" && $6=="active"')"
inc() { n=$(( $(cat "$ST/$1" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$ST/$1"; echo "$n"; }
zero() { echo 0 > "$ST/$1"; }

# 1) Veyon
if [[ -n "$ALUNO_ATIVO" ]]; then
  if ss -ltn 'sport = :11100' 2>/dev/null | grep -q LISTEN; then zero veyon
  else
    n=$(inc veyon)
    if (( n >= 2 )); then log "Veyon sem escutar na porta 11100 há ${n} min com o aluno logado: reiniciando o veyon"
      systemctl restart veyon; zero veyon; fi
  fi
else zero veyon; fi

# 1b) Pasta pública: se o automount morreu (o a1 ainda não estava no ar na hora do boot), religa
AUTO='mnt-trabalhos\x2dalunos.automount'
if grep -q lab-trabalhos /etc/fstab && ! systemctl is-active --quiet "$AUTO"; then
  systemctl reset-failed "$AUTO" 'mnt-trabalhos\x2dalunos.mount' 2>/dev/null
  systemctl start "$AUTO" 2>/dev/null && log "automount da pasta pública estava parado: religado"
fi

# 1c) Nome mDNS: o Veyon do professor acha os PCs por Info-XX.local. Se o avahi ficou com sufixo (-2, -3) por
#     conflito no boot, o PC "some" do Veyon. A cada 5 min confere e, se o nome não resolver, reinicia o avahi.
n=$(inc mdns)
if (( n % 5 == 0 )) && systemctl is-active --quiet avahi-daemon; then
  H="$(hostname).local"
  r="$(timeout 8 avahi-resolve -4 -n "$H" 2>/dev/null | awk '{print $2}')"
  if [[ -z "$r" ]] || ! hostname -I | tr ' ' '\n' | grep -qx "$r"; then
    log "nome mDNS $H não resolve para este PC (resolveu: '${r:-nada}'): reiniciando o avahi"
    systemctl restart avahi-daemon
  fi
fi

# 2) Tela de login parada
SAIU=/run/lab-vigia/sem-autologin   # criado por "sair": não religa o aluno por 60 min
if [[ -f "$SAIU" ]] && (( $(date +%s) - $(stat -c %Y "$SAIU") < 3600 )); then zero login
elif [[ -z "$GUI" ]] && systemctl is-active --quiet lightdm; then
  n=$(inc login)
  if (( n >= 5 )); then log "tela de login parada há ${n} min sem sessão: reiniciando o lightdm (volta o aluno)"
    zero login; systemctl restart lightdm; fi
else zero login; fi
EOF
chmod 755 "$LIB/vigia"
cat > /etc/systemd/system/lab-vigia.service <<EOF
[Unit]
Description=Vigia do laboratório (Veyon e login do aluno)
[Service]
Type=oneshot
Nice=19
ExecStart=$LIB/vigia
EOF
cat > /etc/systemd/system/lab-vigia.timer <<'EOF'
[Unit]
Description=Roda o vigia do laboratório a cada minuto
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=10s
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now lab-vigia.timer >/dev/null 2>&1
lock "$LIB/vigia"
ok "vigia ativo (log em /var/log/lab-vigia.log)"

# ----------------------------------------------------------- 4. libreoffice autosave
info "4) LibreOffice: salvar automaticamente a cada 1 min"
unlock "$LIB/libreoffice-autosave"
cat > "$LIB/libreoffice-autosave" <<'EOF'
#!/usr/bin/env bash
# Liga o salvamento automático do LibreOffice no perfil de quem chamou (roda a cada login).
# Não mexe se o LibreOffice estiver aberto (ele regravaria o arquivo ao fechar).
XCU="${1:-$HOME/.config/libreoffice/4/user/registrymodifications.xcu}"
pgrep -u "$(id -u)" -x soffice.bin >/dev/null 2>&1 && exit 0
mkdir -p "$(dirname "$XCU")"
python3 -I - "$XCU" <<'PY'
import sys, re, os
p = sys.argv[1]
if os.path.exists(p): t = open(p, encoding='utf-8').read()
else: t = '<?xml version="1.0" encoding="UTF-8"?>\n<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n</oor:items>\n'
want = [("/org.openoffice.Office.Recovery/AutoSave", "Enabled", "true"),
        ("/org.openoffice.Office.Recovery/AutoSave", "TimeIntervall", "1"),
        ("/org.openoffice.Office.Recovery/AutoSave", "UserAutoSaveEnabled", "true"),
        ("/org.openoffice.Office.Common/Save/Document", "CreateBackup", "true")]
changed = False
for path, name, val in want:
    item = '<item oor:path="%s"><prop oor:name="%s" oor:op="fuse"><value>%s</value></prop></item>' % (path, name, val)
    pat = re.compile(r'<item oor:path="%s"><prop oor:name="%s" oor:op="fuse"><value>[^<]*</value></prop></item>' % (re.escape(path), name))
    if item in t: continue
    t = pat.sub('', t); t = t.replace('</oor:items>', item + '\n</oor:items>'); changed = True
if changed: open(p, 'w', encoding='utf-8').write(t)
PY
EOF
chmod 755 "$LIB/libreoffice-autosave"
cat > /etc/xdg/autostart/lab-libreoffice-autosave.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Autosave do LibreOffice (lab)
Exec=$LIB/libreoffice-autosave
NoDisplay=true
EOF
lock "$LIB/libreoffice-autosave"
if pgrep -u "$UID_ALUNO" -x soffice.bin >/dev/null 2>&1; then
  ok "autosave será ligado no próximo login (o LibreOffice do aluno está aberto agora)"
else
  runuser -u "$ALUNO" -- env HOME="/home/$ALUNO" "$LIB/libreoffice-autosave" && ok "autosave ligado no perfil do $ALUNO (a cada 1 min, com cópia de segurança)"
fi

# ---------------- 4b. LibreOffice: pasta padrão = pasta pública do lab, fixa (aluno não troca)
info "4b) LibreOffice: pasta padrão = trabalhos-alunos (fixa)"
LOXCD="/etc/libreoffice/registry/lab-paths.xcd"
if [[ -d /etc/libreoffice/registry ]]; then
  chattr -i "$LOXCD" 2>/dev/null || true
  cat > "$LOXCD" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- Gerado por lab-sistema-mint.sh: pasta padrão ("Meus documentos") do LibreOffice = pasta pública do lab, finalizada (o aluno não troca). -->
<oor:data xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <oor:component-data oor:name="Paths" oor:package="org.openoffice.Office">
    <node oor:name="Variables">
      <prop oor:name="Work" oor:finalized="true"><value>file:///mnt/trabalhos-alunos</value></prop>
    </node>
    <node oor:name="Paths">
      <node oor:name="Work" oor:op="fuse">
        <prop oor:name="WritePath" oor:finalized="true"><value>file:///mnt/trabalhos-alunos</value></prop>
      </node>
    </node>
  </oor:component-data>
</oor:data>
EOF
  chmod 644 "$LOXCD"; chown root:root "$LOXCD"; chattr +i "$LOXCD"
  ok "LibreOffice (Writer, Calc, Impress, Draw, Math, Base): Abrir/Salvar começam em /mnt/trabalhos-alunos, travado (vale ao abrir o programa de novo)"
else
  aviso "LibreOffice não encontrado em /etc/libreoffice/registry"
fi

# ----------------------------------------------------------------------- 5. backup
info "5) Backup: leitura das pastas de trabalho liberada para $ADMIN"
setfacl -m "u:$ADMIN:rx" "/home/$ALUNO"
for d in Documentos Documents Imagens Downloads Desktop "Área de trabalho" Músicas Vídeos Modelos Público; do
  [[ -d "/home/$ALUNO/$d" ]] || continue
  setfacl -R -m "u:$ADMIN:rX" "/home/$ALUNO/$d"
  find "/home/$ALUNO/$d" -type d -exec setfacl -d -m "u:$ADMIN:rX" {} +
done
if [[ -d /srv/trabalhos-alunos/dados ]]; then
  setfacl -R -m "u:$ADMIN:rX" /srv/trabalhos-alunos/dados
  find /srv/trabalhos-alunos/dados -type d -exec setfacl -d -m "u:$ADMIN:rX" {} +
  ok "servidor: pasta compartilhada legível pelo admin ($ADMIN)"
fi
ok "pastas do $ALUNO legíveis só para leitura pelo admin (rsync do Bazzite)"

echo
echo "Pronto. Nada foi reiniciado; a maior parte vale já. Energia nova vale também nos próximos logins."
