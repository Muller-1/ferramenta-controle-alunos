#!/usr/bin/env bash
# Espalha lab-sistema-mint.sh, lab-ferramentas-mint.sh e lab-aparencia-mint.sh (esta pasta, ../) para os PCs do lab pelo SSH.
# Uso: bash implantar-nos-pcs.sh [a1 b2 ...]     (sem argumentos = todos). Pede a senha do sudo dos admins (não grava).
# Precisa estar na rede do lab (cabo) e com ~/.ssh/lab_nopass_ed25519.
cd "$(dirname "$0")/pcs"
LISTA="$HOME/.ssh/ips-lab-testados.txt"; CHAVE="$HOME/.ssh/lab_nopass_ed25519"
read -rsp "Senha do sudo dos admins dos PCs: " PW; echo
SSH=(-F /dev/null -i "$CHAVE" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
mapfile -t ALV < <(grep -E '^[a-f][0-9]+: +[0-9.]+' "$LISTA" | sed -E 's/^([a-f][0-9]+): +([0-9.]+).*/\1 \2/')
for l in "${ALV[@]}"; do
  u="${l%% *}"; ip="${l##* }"; H="/home/$u"
  if [[ $# -gt 0 && " $* " != *" $u "* ]]; then continue; fi
  timeout 40 scp -q "${SSH[@]}" lab-sistema-mint.sh lab-ferramentas-mint.sh lab-aparencia-mint.sh "$u@$ip:~/" || { echo "$u: sem acesso"; continue; }
  out="$(printf '%s\n' "$PW" | timeout 150 ssh "${SSH[@]}" "$u@$ip" "sudo -S -p '' bash -c 'bash $H/lab-sistema-mint.sh && bash $H/lab-ferramentas-mint.sh && bash $H/lab-aparencia-mint.sh'" 2>&1)"
  echo "$u: $(echo "$out" | grep -c '\[ok\]') ok, $(echo "$out" | grep -c ERRO) erros"
done
