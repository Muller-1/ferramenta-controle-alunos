#!/usr/bin/env bash
# lab-chaveiro-mint.sh — chaveiro (keyring) do aluno sem senha: com login automático, um chaveiro com senha faz
# o Brave pedir "Autenticação necessária / Default Keyring" toda vez que abre. Vale para a sessão atual e para o perfil limpo.
# Uso: sudo bash lab-chaveiro-mint.sh   (o chaveiro antigo fica guardado em /var/lib/lab/chaveiro-antigo)
for base in /home/aluno /var/lib/lab/perfil-base; do
  d="$base/.local/share/keyrings"; [ -d "$d" ] || continue
  f="$d/Default_Keyring.keyring"
  if [ -f "$f" ] && ! head -c 9 "$f" | grep -q '^\[keyring'; then mkdir -p /var/lib/lab/chaveiro-antigo; cp -a "$f" "/var/lib/lab/chaveiro-antigo/$(echo $base | tr / _).keyring"; fi
  printf '[keyring]\ndisplay-name=Default_Keyring\nctime=0\nmtime=0\nlock-on-idle=false\nlock-after=false\n' > "$f"
  printf 'Default_Keyring' > "$d/default"; chown aluno:aluno "$f" "$d/default"; chmod 600 "$f"
done
pkill -u aluno -x gcr-prompter 2>/dev/null; pkill -u aluno -f gcr-prompter 2>/dev/null
pkill -u aluno -x gnome-keyring-d 2>/dev/null     # o chaveiro relê o arquivo novo na próxima vez que algum app pedir
echo "$(hostname): chaveiro sem senha (antigo guardado em /var/lib/lab/chaveiro-antigo)"
