# Como mexer no menu "Personalizado" > "Laboratório" (KDE)

## Onde fica
Botão **Super** (menu de aplicativos) → **Personalizado** → **Laboratório**.
Dentro de Laboratório o **Painel do laboratório** fica sempre no topo; abaixo, uma linha e os outros comandos (ordem alfabética).

## Jeito fácil (com o mouse): Editor de Menu
1. Clique com o botão direito em qualquer item do menu → **Editar aplicativos…** (ou abra o programa **Editor de Menu**, `kmenuedit`).
2. Na árvore da esquerda abra **Personalizado → Laboratório**.
3. Clique num item para ver/alterar **Nome, Comentário, Comando e Ícone** na direita.
4. **Arrastar** um item muda a ordem ou move para outra pasta. Botão direito na pasta → **Novo item / Novo submenu / Nova linha**.
5. **Salvar** (disquete) no alto. Desmarque a caixinha ao lado do item para escondê-lo sem apagar.
Obs.: o Painel é fixado no topo pelo arquivo do menu; se arrastar outro item para cima dele, o menu pode ignorar. Para mudar a ordem fixa, veja "Jeito de arquivo" abaixo.

## Jeito de arquivo (o que eu usei)
- **Cada botão é um arquivo** em `~/.local/share/applications/lab-*.desktop`. Exemplo:
```
[Desktop Entry]
Type=Application
Name=Fechar Roblox em todos
Exec=/var/home/Muller/.local/bin/lab-gui fechar-roblox
Icon=process-stop-symbolic
Terminal=false
Categories=X-Laboratorio;
```
  - `Name` = texto no menu; `Exec` = comando; `Icon` = ícone; **`Categories=X-Laboratorio;` é o que coloca o item dentro da pasta Laboratório**. Com `X-Personalizado;` ele aparece direto em Personalizado (fora da pasta).
- **A estrutura de pastas** está em `~/.config/menus/applications-merged/personalizado.menu` (a pasta Laboratório e a ordem, no bloco `<Layout>`: o que vier em `<Filename>` fica no topo). O nome e o ícone da pasta estão em `~/.local/share/desktop-directories/laboratorio.directory`.
- Depois de mudar qualquer arquivo rode: `kbuildsycoca6` (ou saia e entre no KDE) para o menu atualizar.

## Receitas
- **Adicionar um comando novo na pasta:** crie `~/.local/share/applications/meu-comando.desktop` com `Categories=X-Laboratorio;`, rode `kbuildsycoca6`.
- **Fixar outro item no topo:** no `personalizado.menu`, dentro de `<Layout>`, acrescente `<Filename>meu-comando.desktop</Filename>` antes de `<Merge type="all"/>`.
- **Tirar um item:** apague o `.desktop` (ou use o Editor de Menu e desmarque).
- **Voltar ao menu antigo:** `cp ~/.config/menus/applications-merged/personalizado.menu.bak ~/.config/menus/applications-merged/personalizado.menu` e `kbuildsycoca6`.
- **Reinstalar tudo:** `bash instalar-no-bazzite.sh` (nesta pasta).

## Arquivos do pacote
`menu/` = os atalhos (.desktop); `menu-config/` = arquivos da pasta (personalizado.menu e *.directory).
