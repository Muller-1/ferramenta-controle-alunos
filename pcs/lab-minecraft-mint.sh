#!/usr/bin/env bash
# =============================================================================
# lab-minecraft-mint.sh — Minecraft leve para os alunos (Linux Mint, XFCE ou Cinnamon)
#   1. Jogo em /opt/lab-minecraft (só leitura): Minecraft + Fabric + mods de desempenho
#      (Sodium, Lithium, FerriteCore, ImmediatelyFast, EntityCulling), Java oficial. Sem launcher.
#   2. Mundos/opções em /var/lib/lab-minecraft/jogo (fora do /home: o perfil limpo não apaga).
#   3. Atalho SÓ no menu (Jogos > Minecraft). Nada na área de trabalho, nada abre sozinho.
#   4. Modo offline (sem conta): o aluno escolhe um apelido. Mesma versão em todos os PCs => "Abrir para LAN".
#   5. Firewall: libera o LAN do Minecraft SÓ para a rede do lab (TCP 1024-65535 e UDP 4445).
#   6. Ferramenta do professor: sudo /usr/local/lib/lab/minecraft fechar|bloquear|liberar|status
#      (do Bazzite: lab minecraft bloquear todos).
# O jogo roda limitado (máx. ~3,6 GB de RAM, CPU com prioridade menor): não trava o PC nem o Veyon.
# Não fecha nem abre nada do aluno.
# Uso:   sudo bash lab-minecraft-mint.sh [PASTA_DO_PACOTE]   (padrão: ~/lab-minecraft-pacote do admin)
#        sudo bash lab-minecraft-mint.sh --desfazer [--apagar-mundos]
# Seguro para rodar de novo (atualiza só o que mudou).
# =============================================================================
set -euo pipefail
ALUNO=aluno
OPT=/opt/lab-minecraft
VAR=/var/lib/lab-minecraft
DESK=/usr/share/applications/lab-minecraft.desktop
LIB=/usr/local/lib/lab
FER=$LIB/minecraft
SUDOERS=/etc/sudoers.d/lab-minecraft
BLOQ=/etc/lab/minecraft-bloqueado
REDE=192.168.0.0/24
ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

regras_ufw() {  # $1 = allow | delete allow
  command -v ufw >/dev/null || return 0
  ufw $1 from $REDE to any port 1024:65535 proto tcp comment 'lab-minecraft LAN' >/dev/null 2>&1 || true
  ufw $1 from $REDE to any port 4445 proto udp comment 'lab-minecraft descoberta' >/dev/null 2>&1 || true
}

if [[ "${1:-}" == "--desfazer" ]]; then
  [[ -n "$(pgrep -u $ALUNO -f "$OPT/runtime/" || true)" ]] && { echo "  O Minecraft está aberto: feche antes (sudo $FER fechar)"; exit 1; }
  chattr -i "$FER" 2>/dev/null || true
  rm -rf "$OPT" "$DESK" "$FER" "$SUDOERS"
  regras_ufw "delete allow"
  if [[ "${2:-}" == "--apagar-mundos" ]]; then rm -rf "$VAR"; ok "mundos apagados"; else ok "mundos guardados em $VAR (apague com --apagar-mundos)"; fi
  rm -f "$BLOQ"
  ok "Minecraft removido"; exit 0
fi

ADM_HOME="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
SRC="${1:-$ADM_HOME/lab-minecraft-pacote}"
[[ -f "$SRC/versao.json" && -x "$SRC/jogar" ]] || { echo "ERRO: pacote não encontrado em $SRC (falta versao.json/jogar)" >&2; exit 1; }

info "1) Jogo em $OPT (só leitura)"
if pgrep -u $ALUNO -f "$OPT/runtime/" >/dev/null; then
  echo "  O Minecraft está aberto agora: não atualizo os arquivos do jogo (rode de novo depois)."
else
  install -d -m 755 "$OPT"
  nice -n 19 ionice -c3 rsync -a --delete --chown=root:root --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r "$SRC/" "$OPT/"
  chmod 755 "$OPT/jogar"
  find "$OPT/runtime" -type f -path '*/bin/*' -exec chmod 755 {} +
  find "$OPT/runtime" -type f -name 'jspawnhelper' -exec chmod 755 {} + 2>/dev/null || true
fi
ok "$(python3 -c "import json;d=json.load(open('$OPT/versao.json'));print('Minecraft',d['minecraft'],'|',d['fabric'],'|',len(d['mods']),'mods')") | $(du -sh "$OPT" | cut -f1)"

info "2) Pasta dos mundos (fora do /home)"
install -d -m 755 -o root -g root "$VAR"
install -d -m 755 -o $ALUNO -g $ALUNO "$VAR/jogo"
ok "$VAR/jogo (do aluno)"

info "3) Atalho só no menu (Jogos)"
cat > "$DESK" <<EOF
[Desktop Entry]
Type=Application
Name=Minecraft
GenericName=Jogo
Comment=Minecraft (offline, jogue com os colegas em "Abrir para LAN")
Exec=$OPT/jogar
Icon=$OPT/icone.png
Terminal=false
Categories=Game;
Keywords=minecraft;jogo;blocos;
StartupNotify=true
EOF
chmod 644 "$DESK"
update-desktop-database -q /usr/share/applications 2>/dev/null || true
# garante que não há atalho na área de trabalho (tela atual e foto do perfil limpo)
for d in /home/$ALUNO/Desktop "/home/$ALUNO/Área de trabalho" /var/lib/lab/perfil-base/Desktop "/var/lib/lab/perfil-base/Área de trabalho"; do
  rm -f "$d/lab-minecraft.desktop" "$d/minecraft.desktop" 2>/dev/null || true
done
ok "$DESK (sem atalho na área de trabalho)"

info "4) Firewall: LAN do Minecraft só na rede do lab"
if command -v ufw >/dev/null; then   # grava sempre: se o ufw for ligado um dia, o LAN continua funcionando
  regras_ufw allow; ok "ufw: TCP 1024-65535 e UDP 4445 de $REDE ($(ufw status | head -1))"
else ok "sem ufw (nada a fazer)"; fi

info "5) Ferramenta do professor: $FER"
install -d -m 755 "$LIB" /etc/lab
chattr -i "$FER" 2>/dev/null || true
cat > "$FER" <<'EOF'
#!/usr/bin/env bash
# minecraft fechar|bloquear|liberar|status — controle do Minecraft dos alunos (roda como root pelo sudo).
#   fechar    fecha o jogo do jeito normal (salva o mundo); se não fechar em 20 s, força
#   bloquear  fecha e impede de abrir de novo (o aluno vê um aviso)
#   liberar   permite abrir de novo
#   status    aberto/fechado, apelido, bloqueado
ALUNO=aluno; BLOQ=/etc/lab/minecraft-bloqueado; OPT=/opt/lab-minecraft
U="$(id -u $ALUNO)"; H="$(hostname)"
pids() { pgrep -u "$U" -f "$OPT/runtime/" || true; }
fechar() {
  local p; p="$(pids)"; [[ -n "$p" ]] || { echo "fechado"; return 0; }
  # fecha a janela (o jogo salva e sai sozinho)
  export DISPLAY=:0 XAUTHORITY=/home/$ALUNO/.Xauthority
  wmctrl -lp 2>/dev/null | while read -r w _ pid _; do grep -qx "$pid" <<<"$p" && wmctrl -ic "$w"; done || true
  for i in $(seq 20); do [[ -z "$(pids)" ]] && { echo "fechado (salvo)"; return 0; }; sleep 1; done
  kill -TERM $(pids) 2>/dev/null; sleep 5
  [[ -n "$(pids)" ]] && kill -KILL $(pids) 2>/dev/null
  echo "fechado (forçado)"
}
case "${1:-status}" in
  fechar)   echo "$H: Minecraft $(fechar)" ;;
  bloquear) touch "$BLOQ"; echo "$H: Minecraft bloqueado, $(fechar)" ;;
  liberar)  rm -f "$BLOQ"; echo "$H: Minecraft liberado" ;;
  status)   a="fechado"; [[ -n "$(pids)" ]] && a="ABERTO ($(cat /var/lib/lab-minecraft/jogo/apelido.txt 2>/dev/null))"
            b="liberado"; [[ -e "$BLOQ" ]] && b="BLOQUEADO"
            echo "$H: Minecraft $a, $b" ;;
  *) echo "uso: minecraft fechar|bloquear|liberar|status"; exit 2 ;;
esac
EOF
chown root:root "$FER"; chmod 755 "$FER"; chattr +i "$FER"
{
  echo "# Gerado por lab-minecraft-mint.sh: admins controlam o Minecraft sem senha (só estes argumentos)."
  for a in fechar bloquear liberar status; do echo "%sudo ALL=(root) NOPASSWD: $FER $a"; done
} > "$SUDOERS"
chmod 440 "$SUDOERS"; visudo -cf "$SUDOERS" >/dev/null
ok "sudo $FER fechar|bloquear|liberar|status"

echo "Pronto. Desfazer: sudo bash $0 --desfazer"
