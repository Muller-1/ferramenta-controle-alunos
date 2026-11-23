# Ferramenta de Controle dos Alunos

Painel e comandos para o professor administrar os computadores de um laboratório de informática (Linux Mint nos PCs, Bazzite/Linux na máquina do professor), via SSH.

- **`lab-painel`**: janela GTK4 (Python) com os PCs em grade; clique para selecionar, botão direito para executar comandos.
- **`lab <ação> [todos|a1 b2 ...]`**: status, fechar apps/Roblox, bloquear teclado e mouse, travar tela com aviso, reiniciar Veyon, ligar (Wake-on-LAN), reiniciar/desligar.
- **`lab-backup`**: copia os trabalhos dos alunos periodicamente.

Documentação detalhada em [LEIA-ME.md](LEIA-ME.md) (português).

## Estrutura
- `bin/`, `painel/`, `menu/`, `menu-config/`, `systemd/`: o que roda na máquina do professor.
- `pcs/`: scripts que rodam nos PCs do laboratório (como admin, com `sudo`): `lab-sistema-mint.sh` (energia, prioridade do Veyon, vigia, autosave, pasta padrão do LibreOffice, backup), `lab-ferramentas-mint.sh` (comandos do professor), `lab-aparencia-mint.sh` (tema escuro e painel travado), `lab-travas-mint.sh` (nome do PC, fundo de tela, pasta segura) e `lab-trabalhos-alunos.sh` (pasta pública em rede via Samba).
- `implantar-nos-pcs.sh`: envia os scripts de `pcs/` para os PCs pelo SSH.
- Os IPs dos exemplos (`192.168.0.x`) são fictícios: ajuste para a sua rede.

## Configuração
1. Edite `ssh/ips-lab-testados.txt` com o nome e IP dos seus PCs e ajuste `BROADCAST` em `painel/lab_painel.py`.
2. Gere uma chave SSH do lab e instale a pública nos PCs. **Nunca** envie chaves ou senhas ao repositório.
3. `bash instalar-no-bazzite.sh` no computador do professor; `bash implantar-nos-pcs.sh` para implantar as ferramentas nos PCs.

## Aviso
Use apenas em equipamentos que você administra e com ciência da instituição.

Licença: MIT.
