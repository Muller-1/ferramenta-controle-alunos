#!/usr/bin/env bash
# =============================================================================
# lab-trabalhos-alunos.sh — pasta pública "trabalhos-alunos" do laboratório
#
# O PC a1 (192.168.0.101) guarda a pasta (Samba). Todos os PCs (inclusive o a1)
# montam essa pasta sozinhos em /mnt/trabalhos-alunos, com atalho na Área de
# trabalho e na barra lateral do Thunar. Assim a criança abre o trabalho dela em
# qualquer lugar da sala.
#
# Uso (como admin, com sudo):
#   sudo bash lab-trabalhos-alunos.sh servidor  --cred ARQUIVO   # só no a1
#   sudo bash lab-trabalhos-alunos.sh guarda                      # só a guarda da raiz (arquivo solto -> quarentena), no a1
#   sudo bash lab-trabalhos-alunos.sh cliente   --cred ARQUIVO   # em todos (a1 também)
#   sudo bash lab-trabalhos-alunos.sh desfazer-cliente
#   sudo bash lab-trabalhos-alunos.sh desfazer-servidor
# ARQUIVO = linhas "username=trabalhos" e "password=...". Fica guardado só em
# /etc/lab-trabalhos.cred (root, modo 600); as crianças não têm acesso.
# Seguro para rodar de novo.
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR

SERVER_IP="192.168.0.101"
SHARE="trabalhos-alunos"
USUARIO_SMB="trabalhos"
BASE_SRV="/srv/trabalhos-alunos"          # pai imutável (protege a pasta de exclusão)
DADOS_SRV="$BASE_SRV/dados"               # o que é compartilhado de fato
MNT="/mnt/trabalhos-alunos"
CRED_DEST="/etc/lab-trabalhos.cred"
ALUNO="aluno"
# IPs que podem acessar o servidor (PCs do lab + professor)
PERMITIDOS="127.0.0.1 192.168.0.27 192.168.0.101 192.168.0.102 192.168.0.103 192.168.0.104 192.168.0.106 192.168.0.108 192.168.0.109 192.168.0.110 192.168.0.111 192.168.0.112 192.168.0.113 192.168.0.114 192.168.0.115 192.168.0.116 192.168.0.117 192.168.0.118 192.168.0.119 192.168.0.120"
MARC_I="# >>> lab-trabalhos (gerado por lab-trabalhos-alunos.sh)"
MARC_F="# <<< lab-trabalhos"

ok()    { echo "  [ok] $*"; }
info()  { echo "==> $*"; }
aviso() { echo "  [aviso] $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0 ..." >&2; exit 1; }

MODO="${1:-}"; shift || true
CRED_SRC=""
while [[ $# -gt 0 ]]; do
  case "$1" in --cred) CRED_SRC="${2:-}"; shift 2 ;; *) echo "argumento desconhecido: $1" >&2; exit 1 ;; esac
done
echo "Máquina: $(hostname) | modo: ${MODO:-?}"

AUTO_UNIT="$(systemd-escape -p --suffix=automount "$MNT")"
MOUNT_UNIT="$(systemd-escape -p --suffix=mount "$MNT")"

le_senha() { grep -m1 '^password=' "$1" | cut -d= -f2-; }
precisa_cred() {
  [[ -n "$CRED_SRC" && -f "$CRED_SRC" ]] || { echo "Informe --cred ARQUIVO (username=/password=)" >&2; exit 1; }
  [[ -n "$(le_senha "$CRED_SRC")" ]] || { echo "Arquivo de credencial sem password=" >&2; exit 1; }
}
para_montagem() {
  systemctl stop "$AUTO_UNIT" "$MOUNT_UNIT" >/dev/null 2>&1 || true
  umount -l "$MNT" >/dev/null 2>&1 || true
}

guarda_pasta() {
  info "Raiz da pasta pública: só pastas (arquivo solto vai para a quarentena)"
  if ! command -v inotifywait >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive; apt-get install -y inotify-tools >/dev/null 2>&1 || aviso "não consegui instalar inotify-tools"
  fi
  install -d -m 755 -o root -g root "$DADOS_SRV/Material"        # material do professor: o aluno só lê
  install -d -m 700 -o root -g root /srv/trabalhos-alunos-soltos   # quarentena (fora da pasta compartilhada)
  install -d -m 755 /usr/local/lib/lab
  chattr -i /usr/local/lib/lab/pasta-guarda 2>/dev/null || true
  cat > /usr/local/lib/lab/pasta-guarda <<'EOF'
#!/usr/bin/env bash
# Mantém a raiz de trabalhos-alunos só com PASTAS: todo ARQUIVO solto que aparecer é movido na hora para a
# quarentena /srv/trabalhos-alunos-soltos (o aluno cria a pasta dele e salva lá dentro).
DIR=/srv/trabalhos-alunos/dados; Q=/srv/trabalhos-alunos-soltos
mover() {
  local f="$1"
  [[ -f "$DIR/$f" && ! -L "$DIR/$f" ]] || return 0
  mv -f -- "$DIR/$f" "$Q/$(date +%F_%H%M%S)_${f//\//_}" 2>/dev/null && logger -t lab-pasta "arquivo solto movido para a quarentena: $f"
}
varre() { local x; for x in "$DIR"/* "$DIR"/.[!.]*; do [[ -e "$x" ]] && mover "$(basename "$x")"; done; }
varre
inotifywait -m -q -e create -e moved_to -e close_write --format '%f' "$DIR" | while read -r f; do mover "$f"; done
EOF
  chmod 755 /usr/local/lib/lab/pasta-guarda; chattr +i /usr/local/lib/lab/pasta-guarda
  cat > /etc/systemd/system/lab-pasta-guarda.service <<'EOF'
[Unit]
Description=Guarda da pasta pública (só pastas na raiz)
After=smbd.service
[Service]
ExecStart=/usr/local/lib/lab/pasta-guarda
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now lab-pasta-guarda.service >/dev/null 2>&1; systemctl restart lab-pasta-guarda.service
  ok "guarda ativo: arquivos soltos na raiz vão para /srv/trabalhos-alunos-soltos; 'Material' é só leitura"
}

# =============================================================== SERVIDOR =====
servidor() {
  precisa_cred
  [[ "$(hostname)" == "Info-A1" ]] || aviso "este PC não é o Info-A1; o servidor deveria ser o a1 ($SERVER_IP)"
  info "Samba"
  if dpkg-query -W -f='${Status}' samba 2>/dev/null | grep -q "install ok installed"; then
    ok "já instalado"
  else
    export DEBIAN_FRONTEND=noninteractive
    timeout 180 apt-get update || aviso "apt update teve problemas; tentando instalar mesmo assim"
    apt-get install -y samba
    ok "instalado"
  fi

  info "Usuário do compartilhamento ($USUARIO_SMB)"
  id "$USUARIO_SMB" &>/dev/null || useradd -r -M -s /usr/sbin/nologin "$USUARIO_SMB"
  SENHA="$(le_senha "$CRED_SRC")"
  printf '%s\n%s\n' "$SENHA" "$SENHA" | smbpasswd -a -s "$USUARIO_SMB" >/dev/null
  smbpasswd -e "$USUARIO_SMB" >/dev/null
  ok "usuário $USUARIO_SMB com a senha do arquivo"

  info "Pasta $DADOS_SRV (a pasta não pode ser excluída)"
  chattr -i "$BASE_SRV" 2>/dev/null || true
  install -d -m 755 -o root -g root "$BASE_SRV"
  install -d -m 2770 -o "$USUARIO_SMB" -g "$USUARIO_SMB" "$DADOS_SRV"
  chattr +i "$BASE_SRV"
  ok "$BASE_SRV imutável (ninguém, nem root, apaga/renomeia 'dados' sem chattr -i)"

  guarda_pasta

  info "Configuração do Samba"
  [[ -f /etc/samba/smb.conf.orig-lab ]] || cp -a /etc/samba/smb.conf /etc/samba/smb.conf.orig-lab
  cat > /etc/samba/smb.conf <<EOF
# Gerado por lab-trabalhos-alunos.sh (original em smb.conf.orig-lab)
[global]
   workgroup = WORKGROUP
   server string = Trabalhos dos alunos
   server role = standalone server
   security = user
   map to guest = Never
   server min protocol = SMB3_00
   disable netbios = yes
   smb ports = 445
   hosts allow = $PERMITIDOS
   hosts deny = ALL
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
   log file = /var/log/samba/log.%m
   max log size = 1000

[$SHARE]
   path = $DADOS_SRV
   comment = Trabalhos dos alunos
   browseable = yes
   read only = no
   valid users = $USUARIO_SMB
   force user = $USUARIO_SMB
   force group = $USUARIO_SMB
   create mask = 0664
   directory mask = 0775
   # arquivos apagados vão para .lixeira (escondida) e podem ser recuperados pelo admin
   vfs objects = recycle
   recycle:repository = .lixeira
   recycle:keeptree = yes
   recycle:versions = yes
   recycle:touch = yes
   recycle:directory_mode = 0770
   hide files = /.lixeira/
EOF
  testparm -s >/dev/null 2>&1 || { testparm -s; echo "smb.conf inválido" >&2; exit 1; }
  systemctl disable --now nmbd >/dev/null 2>&1 || true
  systemctl enable smbd >/dev/null 2>&1 || true
  systemctl restart smbd
  ok "smbd ativo (só os PCs do lab + professor, porta 445)"

  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    for ip in $PERMITIDOS; do ufw allow from "$ip" to any port 445 proto tcp >/dev/null; done
    ok "ufw: porta 445 liberada só para os IPs do lab"
  fi
  echo "Servidor pronto. Lixeira (admin): $DADOS_SRV/.lixeira"
}

# =============================================================== CLIENTE ======
cliente() {
  precisa_cred
  info "cifs-utils"
  if dpkg-query -W -f='${Status}' cifs-utils 2>/dev/null | grep -q "install ok installed"; then
    ok "já instalado"
  else
    export DEBIAN_FRONTEND=noninteractive
    timeout 180 apt-get update || aviso "apt update teve problemas; tentando instalar mesmo assim"
    apt-get install -y cifs-utils
    ok "instalado"
  fi

  info "Credencial em $CRED_DEST"
  install -m 600 -o root -g root "$CRED_SRC" "$CRED_DEST"
  ok "guardada (root, 600)"

  info "Ponto de montagem $MNT (a pasta no PC não pode ser excluída)"
  para_montagem
  chattr -i "$MNT" 2>/dev/null || true
  install -d -m 755 -o root -g root "$MNT"
  chattr +i "$MNT"
  ok "$MNT criado, dono root, imutável"

  info "Montagem automática (fstab)"
  cp --update=none /etc/fstab /etc/fstab.orig-lab
  sed -i "\|$MARC_I|,\|$MARC_F|d" /etc/fstab
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' /etc/fstab
  {
    echo
    echo "$MARC_I"
    echo "//$SERVER_IP/$SHARE $MNT cifs credentials=$CRED_DEST,uid=$ALUNO,gid=$ALUNO,file_mode=0664,dir_mode=0775,vers=3.0,iocharset=utf8,nosuid,nodev,noexec,_netdev,nofail,noauto,x-systemd.automount,x-systemd.requires=network-online.target,x-systemd.mount-timeout=15,x-systemd.idle-timeout=0 0 0"
    echo "$MARC_F"
  } >> /etc/fstab
  systemctl daemon-reload
  systemctl restart "$AUTO_UNIT"
  ok "fstab atualizado; monta sozinho no primeiro acesso"

  info "Atalho na Área de trabalho e no Thunar (recriado a cada login)"
  cat > /usr/local/bin/lab-trabalhos-link <<'EOF'
#!/bin/sh
# Recria o atalho da pasta pública na Área de trabalho e na barra lateral do Thunar.
DESK="$(xdg-user-dir DESKTOP 2>/dev/null)"
[ -d "$DESK" ] && ln -sfn /mnt/trabalhos-alunos "$DESK/trabalhos-alunos"
B="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$B")"
grep -q 'file:///mnt/trabalhos-alunos' "$B" 2>/dev/null || echo "file:///mnt/trabalhos-alunos trabalhos-alunos" >> "$B"
exit 0
EOF
  chmod 755 /usr/local/bin/lab-trabalhos-link
  cat > /etc/xdg/autostart/lab-trabalhos-link.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Atalho trabalhos-alunos
Exec=/usr/local/bin/lab-trabalhos-link
OnlyShowIn=XFCE;
NoDisplay=true
EOF
  if id "$ALUNO" &>/dev/null; then
    runuser -u "$ALUNO" -- env HOME="/home/$ALUNO" /usr/local/bin/lab-trabalhos-link || aviso "não consegui criar o atalho agora (será criado no próximo login)"
  fi
  ok "atalho 'trabalhos-alunos' na Área de trabalho"

  info "Teste de montagem e escrita"
  if timeout 25 ls "$MNT" >/dev/null 2>&1 && mountpoint -q "$MNT"; then
    T=".teste-$(hostname)-$$"
    if runuser -u "$ALUNO" -- touch "$MNT/$T" 2>/dev/null && runuser -u "$ALUNO" -- rm -f "$MNT/$T"; then
      ok "montou e o usuário $ALUNO consegue criar/apagar arquivos"
    else
      aviso "montou, mas $ALUNO não conseguiu escrever"
    fi
  else
    aviso "não montou agora (servidor $SERVER_IP ligado? rode: sudo bash $0 servidor no a1)"
  fi
}

desfazer_cliente() {
  info "Desfazendo cliente"
  para_montagem
  sed -i "\|$MARC_I|,\|$MARC_F|d" /etc/fstab
  systemctl daemon-reload
  chattr -i "$MNT" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
  rm -f "$CRED_DEST" /usr/local/bin/lab-trabalhos-link /etc/xdg/autostart/lab-trabalhos-link.desktop
  rm -f "/home/$ALUNO/"*/trabalhos-alunos "/home/$ALUNO/Área de trabalho/trabalhos-alunos" 2>/dev/null || true
  ok "cliente removido (atalho e credencial apagados)"
}

desfazer_servidor() {
  info "Desfazendo servidor (os dados em $DADOS_SRV NÃO são apagados)"
  systemctl disable --now lab-pasta-guarda.service >/dev/null 2>&1 || true
  [[ -f /etc/samba/smb.conf.orig-lab ]] && cp -a /etc/samba/smb.conf.orig-lab /etc/samba/smb.conf
  systemctl restart smbd || true
  chattr -i "$BASE_SRV" 2>/dev/null || true
  ok "configuração original do Samba restaurada; $BASE_SRV destravada"
}

case "$MODO" in
  servidor) servidor ;;
  guarda) guarda_pasta ;;
  cliente) cliente ;;
  desfazer-cliente) desfazer_cliente ;;
  desfazer-servidor) desfazer_servidor ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
