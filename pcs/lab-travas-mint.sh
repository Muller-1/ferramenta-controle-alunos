#!/usr/bin/env bash
# =============================================================================
# lab-travas-mint.sh — travas do laboratório (Linux Mint 22.x com XFCE)
#   1. Nome do computador: ninguém além dos admins (grupo sudo) consegue mudar.
#   2. Papel de parede da conta "aluno": travado (arquivo de configuração
#      imutável + tela "Configurações do Desktop" restrita aos admins).
#   3. Pasta segura /opt/lab: só admins enxergam, ninguém apaga/renomeia.
#      Para mexer nela: sudo lab-pasta destravar  ...  sudo lab-pasta travar
# Uso:   sudo bash lab-travas-mint.sh              (aplica)
#        sudo bash lab-travas-mint.sh --desfazer   (libera 1 e 2; mantém /opt/lab)
# É seguro rodar de novo: o que já estiver feito só é conferido.
# =============================================================================
set -euo pipefail
trap 'echo "  [ERRO] falhou na linha $LINENO: $BASH_COMMAND (código $?)" >&2' ERR

ALUNO="aluno"
XML="/home/$ALUNO/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
POLKIT_RULE="/etc/polkit-1/rules.d/10-lab-hostname.rules"
SETTINGS_BIN="/usr/bin/xfdesktop-settings"
PASTA="/opt/lab"

ok()   { echo "  [ok] $*"; }
info() { echo "==> $*"; }
aviso(){ echo "  [aviso] $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

# ------------------------------------------------------------------ desfazer --
DESFAZER=0; FUNDO_SRC=""
FUNDO_DEST="/usr/share/backgrounds/lab/fundo-lab.jpg"   # legível pela conta aluno
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desfazer) DESFAZER=1; shift ;;
    --fundo)    FUNDO_SRC="${2:-}"; shift 2 ;;
    *) echo "uso: sudo bash $0 [--fundo IMAGEM.jpg] [--desfazer]" >&2; exit 1 ;;
  esac
done
if [[ $DESFAZER -eq 1 ]]; then
  info "Desfazendo travas 1 e 2"
  rm -f "$POLKIT_RULE" && ok "regra do nome do computador removida"
  if [[ -f "$XML" ]]; then chattr -i "$XML" && ok "papel de parede liberado"; fi
  if [[ -f /etc/dconf/db/local.d/00-lab-fundo ]]; then
    rm -f /etc/dconf/db/local.d/00-lab-fundo /etc/dconf/db/local.d/locks/00-lab-fundo
    dconf update && ok "fundo do Cinnamon liberado"
  fi
  if dpkg-statoverride --list "$SETTINGS_BIN" >/dev/null 2>&1; then
    dpkg-statoverride --remove "$SETTINGS_BIN"
    chmod 755 "$SETTINGS_BIN"
    ok "Configurações do Desktop liberadas para todos"
  fi
  echo "Pasta $PASTA mantida (use: sudo lab-pasta destravar)."
  exit 0
fi

# ------------------------------------------------- 1. nome do computador ------
info "1) Nome do computador"
install -d -m 755 /etc/polkit-1/rules.d
cat > "$POLKIT_RULE" <<'EOF'
// Gerado por lab-travas-mint.sh: só quem é do grupo sudo muda o nome do PC.
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.hostname1.") === 0 &&
      !subject.isInGroup("sudo")) {
    return polkit.Result.NO;
  }
});
EOF
chmod 644 "$POLKIT_RULE"
ok "mudança de nome negada para quem não é admin"

# ------------------------------------------------------ 2. papel de parede ----
info "2) Papel de parede da conta $ALUNO"
if dpkg-statoverride --list "$SETTINGS_BIN" >/dev/null 2>&1; then
  ok "Configurações do Desktop já restritas"
elif [[ -x "$SETTINGS_BIN" ]]; then
  dpkg-statoverride --update --add root sudo 750 "$SETTINGS_BIN"
  ok "$SETTINGS_BIN agora só abre para admins (grupo sudo)"
else
  aviso "$SETTINGS_BIN não encontrado (XFCE diferente?)"
fi
UID_ALUNO="$(id -u "$ALUNO" 2>/dev/null || echo 1001)"
BUS="unix:path=/run/user/$UID_ALUNO/bus"
if [[ -n "$FUNDO_SRC" ]]; then
  [[ -f "$FUNDO_SRC" ]] || { echo "imagem não encontrada: $FUNDO_SRC" >&2; exit 1; }
  install -d -m 755 "$(dirname "$FUNDO_DEST")"
  install -m 644 -o root -g root "$FUNDO_SRC" "$FUNDO_DEST"
  ok "imagem de fundo instalada em $FUNDO_DEST"
fi
if [[ -f "$XML" && -f "$FUNDO_DEST" ]]; then
  # troca o fundo (destrava, aplica ao vivo se a sessão estiver aberta, grava no arquivo, trava de novo)
  chattr -i "$XML" 2>/dev/null || true
  if [[ -S "/run/user/$UID_ALUNO/bus" ]] && command -v xfconf-query >/dev/null; then
    while read -r p; do
      runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" xfconf-query -c xfce4-desktop -p "$p" -s "$FUNDO_DEST" 2>/dev/null || true
    done < <(runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/(last-image|last-single-image)$' || true)
  fi
  TMP="$(mktemp)"
  sed -E "s#(name=\"(last-image|last-single-image)\" type=\"string\" value=\")[^\"]*#\1$FUNDO_DEST#" "$XML" > "$TMP"
  cat "$TMP" > "$XML"; rm -f "$TMP"
  ok "XFCE: fundo = $FUNDO_DEST"
fi
if [[ -f "$XML" ]]; then
  chattr +i "$XML"
  ok "XFCE: configuração do fundo travada (arquivo imutável): $XML"
elif [[ -x "$SETTINGS_BIN" ]]; then
  aviso "XFCE: $XML ainda não existe; faça login como $ALUNO, escolha o fundo e rode de novo"
fi
# Cinnamon: trava as chaves do dconf (o valor atual da conta aluno vira o padrão do sistema)
if command -v cinnamon >/dev/null 2>&1; then
  BG="/org/cinnamon/desktop/background"
  DB_DIR="/etc/dconf/db/local.d"
  install -d -m 755 "$DB_DIR" "$DB_DIR/locks" /etc/dconf/profile
  PROFILE="/etc/dconf/profile/user"
  if ! grep -qs '^system-db:local' "$PROFILE"; then
    printf 'user-db:user\nsystem-db:local\n' > "$PROFILE"
    ok "dconf: perfil user usa o banco local"
  fi
  {
    echo "# Gerado por lab-travas-mint.sh: fundo de tela travado"
    echo "[org/cinnamon/desktop/background]"
    for k in picture-uri picture-options picture-opacity primary-color secondary-color color-shading-type; do
      v="$(runuser -u "$ALUNO" -- dconf read "$BG/$k" 2>/dev/null || true)"
      [[ -n "$v" ]] || v="$(gsettings get org.cinnamon.desktop.background "$k" 2>/dev/null || true)"
      [[ -n "$v" ]] && echo "$k=$v"
    done
    echo "[org/cinnamon/desktop/background/slideshow]"
    echo "slideshow-enabled=false"
  } > "$DB_DIR/00-lab-fundo"
  if [[ -f "$FUNDO_DEST" ]]; then
    sed -i -e "s#^picture-uri=.*#picture-uri='file://$FUNDO_DEST'#" -e "s#^picture-options=.*#picture-options='zoom'#" "$DB_DIR/00-lab-fundo"
    grep -q '^picture-uri=' "$DB_DIR/00-lab-fundo" || sed -i "/^\[org\/cinnamon\/desktop\/background\]/a picture-uri='file://$FUNDO_DEST'\npicture-options='zoom'" "$DB_DIR/00-lab-fundo"
    if [[ -S "/run/user/$UID_ALUNO/bus" ]]; then   # aplica ao vivo na sessão aberta
      runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" dconf write "$BG/picture-uri" "'file://$FUNDO_DEST'" 2>/dev/null || true
      runuser -u "$ALUNO" -- env DBUS_SESSION_BUS_ADDRESS="$BUS" dconf write "$BG/picture-options" "'zoom'" 2>/dev/null || true
    fi
    ok "Cinnamon: fundo = $FUNDO_DEST"
  fi
  cat > "$DB_DIR/locks/00-lab-fundo" <<EOF
$BG/picture-uri
$BG/picture-options
$BG/picture-opacity
$BG/primary-color
$BG/secondary-color
$BG/color-shading-type
$BG/slideshow/slideshow-enabled
EOF
  dconf update
  ok "Cinnamon: fundo travado via dconf (vale no próximo login do $ALUNO)"
fi

# -------------------------------------------------------- 3. pasta segura -----
info "3) Pasta segura $PASTA"
chattr -i "$PASTA" 2>/dev/null || true
install -d -m 750 -o root -g sudo "$PASTA"
if [[ -n "$FUNDO_SRC" ]]; then
  install -m 640 -o root -g sudo "$FUNDO_SRC" "$PASTA/fundo-lab.jpg"
  ok "cópia protegida da imagem em $PASTA/fundo-lab.jpg"
fi
if [[ ! -f "$PASTA/LEIA-ME.txt" ]]; then
  cat > "$PASTA/LEIA-ME.txt" <<EOF
Pasta segura do laboratório (criada por lab-travas-mint.sh).
- Só admins (grupo sudo) enxergam; a conta "aluno" não entra nem apaga.
- A pasta fica imutável: para colocar/tirar arquivos use
      sudo lab-pasta destravar
  e, ao terminar,
      sudo lab-pasta travar
EOF
  chmod 640 "$PASTA/LEIA-ME.txt"; chown root:sudo "$PASTA/LEIA-ME.txt"
fi
cat > /usr/local/sbin/lab-pasta <<'EOF'
#!/usr/bin/env bash
# lab-pasta: destrava/trava a pasta segura /opt/lab (imutável)
P=/opt/lab
[[ $EUID -eq 0 ]] || { echo "Use: sudo lab-pasta destravar|travar|status" >&2; exit 1; }
case "${1:-status}" in
  destravar) chattr -i "$P" && echo "Destravada: pode criar/apagar arquivos em $P. Depois rode: sudo lab-pasta travar" ;;
  travar)    chattr +i "$P" && echo "Travada: $P protegida contra criar/apagar/renomear." ;;
  status)    lsattr -d "$P"; ls -la "$P" ;;
  *) echo "Uso: sudo lab-pasta destravar|travar|status" >&2; exit 1 ;;
esac
EOF
chmod 755 /usr/local/sbin/lab-pasta
chattr +i "$PASTA"
ok "$PASTA (root:sudo, modo 750, imutável). Mexer: sudo lab-pasta destravar"

echo
echo "Pronto neste PC. Papel de parede/nome: valem a partir do próximo login/reinício da sessão."
