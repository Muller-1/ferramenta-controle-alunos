#!/usr/bin/env bash
# Gera dist/lab-painel_<versao>_all.deb (Linux Mint / Ubuntu / Debian). Rode na raiz do repositório.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSAO="$(python3 -c "import re;print(re.search(r'\"(.+?)\"', open('labpainel/__init__.py').read()).group(1))")"
RAIZ="$(mktemp -d)"; trap 'rm -rf "$RAIZ"' EXIT
PKG="$RAIZ/lab-painel_${VERSAO}_all"

install -d "$PKG/DEBIAN" "$PKG/usr/lib/lab-painel" "$PKG/usr/bin" "$PKG/usr/share/applications" "$PKG/usr/share/doc/lab-painel"
cp -r labpainel "$PKG/usr/lib/lab-painel/"
find "$PKG/usr/lib/lab-painel" -name '__pycache__' -prune -exec rm -rf {} +
chmod 755 "$PKG/usr/lib/lab-painel/labpainel/pcs/lab-ferramentas-mint.sh"
cp LICENSE README.md "$PKG/usr/share/doc/lab-painel/"

cat > "$PKG/usr/bin/lab-painel" <<'EOF'
#!/bin/sh
PYTHONPATH=/usr/lib/lab-painel exec python3 -m labpainel "$@"
EOF
cat > "$PKG/usr/bin/lab" <<'EOF'
#!/bin/sh
# Atalho: lab <acao> [todos|a1 b2 ...]  (mesmos comandos do painel, pelo terminal)
PYTHONPATH=/usr/lib/lab-painel exec python3 -m labpainel lab "$@"
EOF
chmod 755 "$PKG/usr/bin/lab-painel" "$PKG/usr/bin/lab"

cat > "$PKG/usr/share/applications/lab-painel.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Controle dos Alunos
Comment=Painel para controlar os computadores do laboratório
Exec=lab-painel
Icon=computer
Terminal=false
Categories=Education;Utility;
EOF

cat > "$PKG/DEBIAN/control" <<EOF
Package: lab-painel
Version: ${VERSAO}
Section: education
Priority: optional
Architecture: all
Depends: python3 (>= 3.8), python3-tk, openssh-client
Maintainer: Muller <noreply@users.noreply.github.com>
Homepage: https://github.com/Muller-1/ferramenta-controle-alunos
Description: Ferramenta de controle dos alunos
 Painel (e comandos de terminal) para o professor controlar os computadores
 de um laboratório de informática pelo SSH: fechar programas, bloquear teclado
 e mouse, travar a tela, reiniciar, desligar e ligar (Wake-on-LAN).
EOF

mkdir -p dist
dpkg-deb --root-owner-group --build "$PKG" "dist/lab-painel_${VERSAO}_all.deb"
echo "gerado: dist/lab-painel_${VERSAO}_all.deb"
