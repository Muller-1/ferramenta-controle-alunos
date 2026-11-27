# Ferramenta de Controle dos Alunos

Painel para o professor controlar os computadores de um laboratório de informática pelo SSH:
fechar programas, bloquear teclado e mouse, travar a tela com um aviso, reiniciar, desligar e
ligar (Wake-on-LAN). Funciona no **Windows** e no **Linux Mint** (a máquina do professor);
os computadores dos alunos são Linux Mint.

![](https://img.shields.io/badge/Windows-.exe-blue) ![](https://img.shields.io/badge/Linux%20Mint-.deb-green)

## Baixar

Na página de [**Releases**](../../releases/latest):

| Sistema do professor | Arquivo | Como instalar |
|---|---|---|
| **Linux Mint** (Ubuntu/Debian) | `lab-painel_X.Y.Z_all.deb` | `sudo apt install ./lab-painel_*_all.deb` e abra **Controle dos Alunos** no menu (ou `lab-painel`) |
| **Windows 10/11** | `LabPainel-windows.zip` | Descompacte e abra `LabPainel.exe` (o Windows pode avisar "editor desconhecido": *Mais informações → Executar assim mesmo*) |

Requisito: cliente **OpenSSH**. No Mint já vem (`sudo apt install openssh-client` se faltar); no Windows 10/11:
*Configurações → Aplicativos → Recursos opcionais → Cliente OpenSSH*.

## Configurar (primeira vez)

Ao abrir pela primeira vez a janela **Configurar** aparece (depois: *Arquivo → Configurar…*):

| Campo | Para que serve |
|---|---|
| Chave SSH | Arquivo da chave privada que entra nos PCs (sem senha, para o painel não precisar perguntar). Gere com `ssh-keygen -t ed25519 -f ~/.ssh/lab_nopass_ed25519 -N ""` (no Windows: `ssh-keygen` no PowerShell) |
| Usuário nos PCs | Vazio = o usuário administrador de cada PC tem o mesmo nome do PC (`a1`, `b2`…). Preencha se for um só nome para todos |
| Broadcast | Endereço de broadcast da rede, para ligar PCs (ex.: `192.168.0.255`) |
| Corredor depois da coluna | Letra da coluna após a qual o painel desenha um corredor (ex.: `D`); vazio = sem corredor |
| Computadores | Uma linha por PC: `nome  endereço  [MAC]  [usuário]`. **Nome = letra da coluna + número da fileira** (`a1`, `b2`…); a fileira 1 fica embaixo. Aceita importar uma lista `.txt` |

A configuração fica em `~/.config/lab-painel/config.json` (Linux) ou `%APPDATA%\LabPainel\config.json` (Windows).

Cada PC dos alunos precisa de: servidor SSH (`sudo apt install openssh-server`), a **chave pública** em
`~/.ssh/authorized_keys` do administrador, e as ferramentas abaixo.

## Instalar as ferramentas nos PCs dos alunos

Com os PCs ligados, use **Arquivo → Implantar ferramentas nos PCs…** (ou, no terminal do Mint, `lab implantar`).
Será pedida a senha do `sudo` dos administradores; ela é enviada pelo SSH e **não é gravada**. O instalador
(`pcs/lab-ferramentas-mint.sh`) cria os comandos em `/usr/local/lib/lab`, protegidos contra alteração, com
`sudo` sem senha **só** para eles. Pressupõe que a conta dos alunos se chama `aluno` e usa Cinnamon ou XFCE.

## Uso

- Clique seleciona um PC; **Ctrl+clique** soma; **arraste** para selecionar vários; clique na letra/número seleciona a coluna/fileira; `Ctrl+A` todos; `Esc` limpa.
- **Menus de cima** (*Computador*, *Tela e teclado*, *Programas*): agem nos PCs selecionados ou, sem seleção, em todos (o texto ao lado diz qual). **Botão direito** num PC: os mesmos menus, só para os selecionados.
- Cores: verde = aluno logado, amarelo = tela de login, laranja = aluno saiu, vermelho = tela travada, cinza = desligado.
- Terminal (Linux): `lab <ação> [todos | a1 b2 …]`, `lab status`, `lab implantar`.
- Teste sem PCs: `LAB_PAINEL_DEMO=1 lab-painel`.

Comandos: `fechar-roblox`, `tirar-conta-roblox`, `fechar-apps`, `bloquear-input`, `liberar-input`, `travar-tela`
(cobre a tela com uma mensagem à sua escolha, sem fechar nem minimizar nada; solta sozinho em 90 min), `liberar-tela`,
`abrir-app` (abre um aplicativo pelo nome na tela dos alunos), `abrir-site`, `mensagem` (faixa na tela), `internet` (cortar/liberar), `volume`, `enviar` (arquivo para os alunos), `agenda` (ações programadas), `reiniciar`, `desligar`, `sair`, `entrar`, `reiniciar-veyon`.
No terminal: `lab travar-tela -m "Volto em 5 minutos"`, `lab abrir-app -a writer a1 b2`.

## Estrutura do repositório
- `labpainel/`: o painel e a linha de comando (Python + Tkinter).
- `pcs/`: scripts que rodam **nos PCs dos alunos** (energia sem desligar nunca, segurança/bloqueios, perfil limpo a cada boot, Wake-on-LAN, pasta pública), como administrador (`lab-ferramentas-mint.sh` é o que o painel implanta; os demais — energia/Veyon, aparência, travas, pasta pública — são opcionais e específicos de um laboratório Mint).
- `packaging/`, `.github/workflows/`: geração do `.deb` e do `.exe`. `tests/`: testes.
- Os IPs de exemplo (`192.168.0.x`) são fictícios: ajuste para a sua rede.

## Rodar do código-fonte / gerar os pacotes

```bash
python3 -m labpainel              # precisa de Python 3.8+ com Tk (Mint: sudo apt install python3-tk)
python3 -m unittest discover -s tests
bash packaging/build-deb.sh       # gera dist/lab-painel_X.Y.Z_all.deb (precisa de dpkg-deb)
```

O `.exe` do Windows e o `.deb` são gerados pelo GitHub Actions (`.github/workflows/build.yml`);
ao empurrar uma tag `vX.Y.Z` os dois são anexados a uma Release.

## Aviso

Use apenas em equipamentos que você administra e com ciência da instituição. Nunca publique chaves ou senhas.

Licença: MIT.
