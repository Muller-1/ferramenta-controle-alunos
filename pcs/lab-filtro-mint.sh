#!/usr/bin/env bash
# =============================================================================
# lab-filtro-mint.sh — reforço do filtro de conteúdo + "modo aula" (Linux Mint, XFCE ou Cinnamon)
# O filtro principal já existe (bloquear-sites-mint.sh: DNS de família CleanBrowsing, lista de sites no /etc/hosts,
# busca segura e YouTube restrito no Brave). Este script fecha as brechas para a conta "aluno":
#   1. Qualquer programa que tente usar outro DNS (ex.: 8.8.8.8) é desviado para o DNS de família.
#   2. DNS criptografado (DoT, porta 853, e DoH dos serviços conhecidos) bloqueado: não dá para "furar" o filtro.
#   Admins e o sistema não são afetados.
# Modo aula (comando do professor: lab modo-aula ligar|desligar|status, ou botões no painel):
#   - fecha e bloqueia o Roblox (app e site: toda a faixa de endereços da Roblox) e o Minecraft;
#   - bloqueia sites de jogos no navegador (Poki, Friv, CrazyGames, Click Jogos...);
#   - vale até "desligar" o modo aula ou até o PC reiniciar.
# Uso:  sudo bash lab-filtro-mint.sh   [--desfazer]
# =============================================================================
set -euo pipefail
LIB=/usr/local/lib/lab
NFT=/etc/lab/filtro-dns.nft
DNS1=185.228.168.168
ok() { echo "  [ok] $*"; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo bash $0" >&2; exit 1; }
echo "Máquina: $(hostname)"

if [[ "${1:-}" == "--desfazer" ]]; then
  "$LIB/modo-aula" desligar >/dev/null 2>&1 || true
  systemctl disable --now lab-filtro-dns.service >/dev/null 2>&1 || true
  nft delete table inet lab_dns 2>/dev/null || true
  rm -f /etc/systemd/system/lab-filtro-dns.service /etc/systemd/system/lab-modo-aula.service "$NFT" "$LIB/modo-aula" /etc/sudoers.d/lab-modo-aula
  systemctl daemon-reload; ok "reforço do filtro e modo aula removidos"; exit 0
fi
id aluno >/dev/null 2>&1 || { echo "conta aluno não existe"; exit 1; }
install -d -m 755 /etc/lab "$LIB"

# ------------------------------------------------------------------ 1-2. DNS sempre filtrado para o aluno
cat > "$NFT" <<EOF
# Gerado por lab-filtro-mint.sh: o aluno só usa o DNS de família (CleanBrowsing).
table inet lab_dns
delete table inet lab_dns
table inet lab_dns {
  set doh4 {
    type ipv4_addr; flags interval
    elements = { 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1, 1.1.1.2, 1.0.0.2, 9.9.9.9, 149.112.112.112, 208.67.222.222, 208.67.220.220,
                 94.140.14.14, 94.140.15.15, 76.76.2.0/24, 76.76.10.0/24, 45.90.28.0/24, 45.90.30.0/24, 194.242.2.0/24, 86.54.11.0/24 }
  }
  chain nat_saida {
    type nat hook output priority -100; policy accept;
    meta skuid "aluno" meta nfproto ipv4 udp dport 53 ip daddr != 127.0.0.0/8 dnat ip to $DNS1
    meta skuid "aluno" meta nfproto ipv4 tcp dport 53 ip daddr != 127.0.0.0/8 dnat ip to $DNS1
  }
  chain saida {
    type filter hook output priority 0; policy accept;
    meta skuid "aluno" tcp dport 853 reject
    meta skuid "aluno" udp dport 853 reject
    meta skuid "aluno" meta nfproto ipv6 udp dport 53 ip6 daddr != ::1 reject
    meta skuid "aluno" meta nfproto ipv6 tcp dport 53 ip6 daddr != ::1 reject
    meta skuid "aluno" ip daddr @doh4 reject
  }
}
EOF
nft -c -f "$NFT"
cat > /etc/systemd/system/lab-filtro-dns.service <<EOF
[Unit]
Description=Filtro de conteúdo: DNS sempre filtrado para o aluno
After=network-pre.target
Before=network.target display-manager.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f $NFT
ExecStop=/usr/sbin/nft delete table inet lab_dns
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable lab-filtro-dns.service >/dev/null 2>&1; systemctl restart lab-filtro-dns.service
ok "DNS do aluno sempre filtrado; DNS criptografado bloqueado (tabela nft lab_dns)"

# ------------------------------------------------------------------ 3. modo aula
cat > "$LIB/modo-aula" <<'EOF'
#!/usr/bin/env bash
# modo-aula ligar|desligar|status — sem Roblox, Minecraft e sites de jogos durante a aula
FLAG=/run/lab-modo-aula; POL=/etc/brave/policies/managed/zz-lab-modo-aula.json; LIB=/usr/local/lib/lab; H=$(hostname)
# o Brave usa a lista de sites bloqueados do ÚLTIMO arquivo (ordem alfabética): este junta a lista do filtro + os jogos
ROBLOX="128.116.0.0/17, 209.206.40.0/21, 103.140.28.0/23"      # faixas de endereços da Roblox (site, app e jogos)
SITES='"roblox.com","rbxcdn.com","rbx.com","poki.com","poki.com.br","friv.com","friv.com.br","crazygames.com","crazygames.com.br","jogos360.com.br","clickjogos.com.br","1001jogos.com.br","ojogos.com.br","y8.com","miniclip.com","kizi.com","coolmathgames.com","now.gg","gamejolt.com","itch.io","krunker.io","slither.io","agar.io","silvergames.com","gamesgames.com","jogosdomeninas.com.br"'
case "${1:-status}" in
  ligar)
    nft -f - <<NFT
table inet lab_modo_aula
delete table inet lab_modo_aula
table inet lab_modo_aula {
  chain saida { type filter hook output priority 0; policy accept;
    meta skuid "aluno" ip daddr { $ROBLOX } reject
  }
}
NFT
    install -d -m 755 /etc/brave/policies/managed
    rm -f /etc/brave/policies/managed/96-lab-modo-aula.json
    python3 -I - "$POL" "[$SITES]" <<'PYJ'
import glob, json, sys
destino, jogos = sys.argv[1], json.loads(sys.argv[2]); lista = []
for f in sorted(glob.glob("/etc/brave/policies/managed/*.json")):
    if f == destino: continue
    try: lista += json.load(open(f)).get("URLBlocklist", [])
    except Exception: pass
json.dump({"URLBlocklist": sorted(set(lista + jogos))}, open(destino, "w"), indent=1)
PYJ
    chmod 644 "$POL"
    touch "$FLAG"
    pkill -u aluno -x sober 2>/dev/null; pkill -u aluno -f 'org.vinegarhq.Sober' 2>/dev/null
    [[ -x $LIB/minecraft ]] && "$LIB/minecraft" bloquear >/dev/null 2>&1
    systemctl start lab-modo-aula.service 2>/dev/null
    echo "$H: modo aula LIGADO (sem Roblox, Minecraft e sites de jogos)" ;;
  desligar)
    nft delete table inet lab_modo_aula 2>/dev/null; rm -f "$POL" /etc/brave/policies/managed/96-lab-modo-aula.json "$FLAG"
    systemctl stop lab-modo-aula.service 2>/dev/null
    [[ -x $LIB/minecraft ]] && "$LIB/minecraft" liberar >/dev/null 2>&1
    echo "$H: modo aula desligado (jogos liberados)" ;;
  vigiar)   # usado pelo serviço: fecha o Roblox se alguém abrir durante o modo aula
    while [[ -e "$FLAG" ]]; do pkill -u aluno -x sober 2>/dev/null; pkill -u aluno -f 'org.vinegarhq.Sober' 2>/dev/null; sleep 3; done ;;
  status)   [[ -e "$FLAG" ]] && echo "$H: modo aula LIGADO" || echo "$H: modo aula desligado" ;;
  *) echo "uso: modo-aula ligar|desligar|status"; exit 2 ;;
esac
EOF
chmod 755 "$LIB/modo-aula"
cat > /etc/systemd/system/lab-modo-aula.service <<EOF
[Unit]
Description=Modo aula: fecha o Roblox se for aberto
[Service]
ExecStart=$LIB/modo-aula vigiar
EOF
systemctl daemon-reload
printf '%%sudo ALL=(root) NOPASSWD: %s/modo-aula\n' "$LIB" > /etc/sudoers.d/lab-modo-aula
chmod 440 /etc/sudoers.d/lab-modo-aula; visudo -cf /etc/sudoers.d/lab-modo-aula >/dev/null
ok "modo aula instalado (lab modo-aula ligar|desligar|status); vale até desligar ou reiniciar o PC"
