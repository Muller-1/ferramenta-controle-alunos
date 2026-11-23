# Comandos do professor (Bazzite)

Instalar tudo de novo: `bash instalar-no-bazzite.sh` (esta pasta).

| Comando | O que faz |
|---|---|
| `lab-painel` | **janela com os PCs em grade (colunas = letras, fileira 1 embaixo)**: clique seleciona, Ctrl+clique soma, botão direito = comandos nos selecionados, barra de cima = comandos em todos |
| `lab status` | PCs no ar e quem está logado |
| `lab fechar-roblox [todos\|a1 b2 ...]` | fecha o Roblox |
| `lab tirar-conta-roblox [...]` | fecha o Roblox e apaga o login |
| `lab fechar-apps [...]` | fecha todos os programas e mostra a área de trabalho |
| `lab bloquear-input` / `lab liberar-input [...]` | bloqueia/libera teclado e mouse |
| `lab travar-tela [-m "mensagem"] [...]` | cobre a tela com uma mensagem (padrão: "Tela bloqueada pelo professor") e bloqueia teclado e mouse; não fecha nem minimiza nada; solta sozinho em 90 min |
| `lab reiniciar-veyon [...]` | reinicia só o Veyon (limpa x11vnc preso) para as telas voltarem a aparecer |
| `lab liberar-tela [...]` | tira o aviso e libera |
| `lab-backup` | copia os trabalhos dos alunos para `~/Backups-Lab` (também roda sozinho a cada 2 h na tomada) |
| `lab-gui <ação>` | igual ao `lab`, com confirmação (usado pelos atalhos "Lab: ..." do menu) |

Arquivos: `bin/` (comandos), `menu/` (atalhos do menu Personalizado), `systemd/` (timer do backup), `ssh/` (bloco do ssh config e mapa de PCs).
As chaves NÃO estão aqui (`~/.ssh/lab_nopass_ed25519` e `~/.ssh/lab-trabalhos.cred`): guarde uma cópia no cofre de senhas.


## Painel (lab-painel)
Código em `painel/lab_painel.py` (GTK4 + Python, sem instalar nada). Cores: verde = aluno logado, amarelo = tela de login, laranja = aluno saiu, vermelho = tela travada, cinza = desligado, tracejado = sem SSH. Botão **Iniciar** usa Wake-on-LAN (MACs em `ssh/macs.json` → `~/.config/lab-painel/macs.json`); o ícone amarelo avisa que só liga se o Wake-on-LAN estiver ativo na BIOS.
Comandos novos nos PCs (reiniciar, desligar, sair, entrar, estado): `bash implantar-nos-pcs.sh` (pede a senha do sudo).
Teste visual sem os PCs: `LAB_PAINEL_DEMO=1 lab-painel --captura imagem.png`.
