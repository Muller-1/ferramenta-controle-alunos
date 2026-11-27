"""Janela do painel (Tkinter: vem com o Python no Windows e no Linux Mint)."""
import concurrent.futures, os, queue, random, sys, threading, time
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk
from tkinter.scrolledtext import ScrolledText

from . import __version__, config, core

# (id, texto, pede confirmação, descrição)
BASICOS = [
    ("iniciar", "Iniciar", False, "Liga os PCs desligados (Wake-on-LAN)"),
    ("reiniciar", "Reiniciar", True, "Reinicia o computador"),
    ("entrar", "Entrar", False, "Faz o aluno entrar (login automático)"),
    ("sair", "Sair", True, "Encerra a sessão do aluno (fecha tudo)"),
    ("desligar", "Desligar", True, "Desliga o computador"),
]
CUSTOM = [
    ("fechar-roblox", "Fechar Roblox", False, "Fecha o Roblox"),
    ("tirar-conta-roblox", "Tirar conta do Roblox", True, "Fecha o Roblox e apaga o login"),
    ("fechar-apps", "Fechar todos os apps", True, "Fecha tudo e mostra a área de trabalho"),
    ("bloquear-input", "Bloquear teclado e mouse", True, "Desliga teclado e mouse dos alunos"),
    ("liberar-input", "Liberar teclado e mouse", False, "Religa teclado e mouse"),
    ("travar-tela", "Travar tela", True, "Cobre a tela com uma mensagem e bloqueia teclado e mouse (não fecha nem minimiza nada)"),
    ("liberar-tela", "Liberar tela", False, "Tira o aviso e libera teclado e mouse"),
    ("reiniciar-veyon", "Reiniciar Veyon", False, "Reinicia só o Veyon para as telas voltarem a aparecer"),
    ("abrir-app", "Abrir app…", False, "Abre um aplicativo pelo nome (primeiro resultado da busca) na tela dos alunos"),
]
TODOS = {c[0]: c for c in BASICOS + CUSTOM}

# Barra de cima e menu do botão direito: ações agrupadas (None = separador)
GRUPOS = [
    ("Computador", ["iniciar", "reiniciar", "desligar", None, "entrar", "sair", None, "reiniciar-veyon"]),
    ("Tela e teclado", ["travar-tela", "liberar-tela", None, "bloquear-input", "liberar-input"]),
    ("Programas", ["abrir-app", "fechar-apps", None, "fechar-roblox", "tirar-conta-roblox"]),
]

COR = {"aluno": "#bfe8c9", "login": "#ffe3a3", "saiu": "#ffd2a8", "sem": "#d6ecf8", "travada": "#f5b5b5",
       "off": "#d9dce1", "nossh": "#eceef1"}
TX, TX_OFF = "#2b2f36", "#7a808a"
LARG, ALT, GAP, MARGEM, CORREDOR, CAB = 128, 80, 10, 16, 84, 30


class Painel:
    def __init__(self, cfg, demo=False):
        self.demo = demo
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=24)
        self.fila = queue.Queue()
        self.sel, self.ocupados = set(), set()
        self.itens = {}
        self.root = tk.Tk()
        self.root.geometry("1120x760")
        self.root.configure(bg="#eef1f5")
        self._montar_janela()
        self.aplicar_config(cfg)
        self.root.bind_all("<Escape>", lambda e: self._limpar_sel())
        self.root.bind_all("<Control-a>", lambda e: self._sel_grupo(lambda p: True))
        self.root.bind_all("<Control-A>", lambda e: self._sel_grupo(lambda p: True))
        self.root.after(100, self._processar_fila)
        self.root.after(1000, self._tick)
        threading.Thread(target=self._laco_estado, daemon=True).start()
        if cfg.get("_primeira_vez") or not cfg["pcs"]:
            self.root.after(300, self.abrir_config)

    # ----------------------------------------------------------------- config
    def aplicar_config(self, cfg):
        self.cfg = cfg
        self.pcs = sorted((core.PC(d) for d in cfg["pcs"]), key=lambda p: (p.col, p.lin))
        self.por_nome = {p.nome: p for p in self.pcs}
        self.sel &= set(self.por_nome)
        self.root.title(cfg["titulo"])
        if self.demo:
            self._demo()
        self._desenhar_grade()
        self._pintar_todos()

    def abrir_config(self):
        DialogoConfig(self)

    # ----------------------------------------------------------------- janela
    def _montar_janela(self):
        barra_menu = tk.Menu(self.root)
        m = tk.Menu(barra_menu, tearoff=0)
        m.add_command(label="Configurar…", command=self.abrir_config)
        m.add_command(label="Implantar ferramentas nos PCs…", command=self.implantar)
        m.add_separator()
        m.add_command(label="Sair", command=self.root.destroy)
        barra_menu.add_cascade(label="Arquivo", menu=m)
        a = tk.Menu(barra_menu, tearoff=0)
        a.add_command(label="Sobre", command=lambda: messagebox.showinfo(
            "Ferramenta de controle dos alunos", f"Versão {__version__}\nConfiguração: {config.caminho_config()}"))
        barra_menu.add_cascade(label="Ajuda", menu=a)
        self.root.config(menu=barra_menu)

        self.barra = tk.Frame(self.root, bg="#ffffff", padx=6, pady=4)
        self.barra.pack(fill="x")
        for titulo, ids in GRUPOS:
            mb = ttk.Menubutton(self.barra, text=titulo)
            mb["menu"] = self._menu_grupo(mb, ids, lambda: self._alvos_sel() or self.pcs, True)
            mb.pack(side="left", padx=2)
        self.l_alvo = tk.Label(self.barra, bg="#ffffff", fg=TX_OFF, font=("TkDefaultFont", 9))
        self.l_alvo.pack(side="left", padx=10)

        rodape = tk.Frame(self.root, bg="#ffffff")
        rodape.pack(side="bottom", fill="x")
        self.l_status = tk.Label(rodape, anchor="w", bg="#ffffff", fg=TX, font=("TkDefaultFont", 9), padx=10, pady=4)
        self.l_status.pack(fill="x", side="bottom")
        self.log = ScrolledText(rodape, height=4, state="disabled", font=("TkFixedFont", 9), bg="#ffffff", fg=TX, wrap="word")
        self.log.pack(fill="x", side="bottom")

        self.canvas = tk.Canvas(self.root, bg="#eef1f5", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<ButtonPress-1>", self._press)
        self.canvas.bind("<B1-Motion>", self._arrasta)
        self.canvas.bind("<ButtonRelease-1>", self._solta)
        self.canvas.bind("<Button-3>", self._direito)
        self.canvas.bind("<Configure>", lambda e: self._desenhar_grade())
        self.banda = self.inicio = None

    def _menu_grupo(self, pai, ids, alvos, todos):
        """Menu com as ações `ids`; `alvos()` diz em quais PCs rodar no momento do clique."""
        m = tk.Menu(pai, tearoff=0)
        for cid in ids:
            if cid is None:
                m.add_separator()
            else:
                m.add_command(label=TODOS[cid][1], command=lambda c=cid: self.executar(c, alvos(), todos))
        return m

    # ------------------------------------------------------------------ grade
    def _geometria(self):
        letras = sorted({p.col for p in self.pcs})
        linhas = sorted({p.lin for p in self.pcs}, reverse=True)       # fileira 1 embaixo
        apos = (self.cfg.get("corredor_apos") or "").upper()
        x, xs = MARGEM + CAB, {}
        for L in letras:
            xs[L] = x
            x += LARG + GAP
            if L == apos and L != letras[-1]:
                x += CORREDOR - GAP + GAP
        ys = {n: MARGEM + CAB + i * (ALT + GAP) for i, n in enumerate(linhas)}
        return letras, linhas, xs, ys, x, MARGEM + CAB + len(linhas) * (ALT + GAP)

    def _desenhar_grade(self):
        c = self.canvas
        c.delete("all")
        self.itens = {}
        if not self.pcs:
            c.create_text(40, 40, anchor="nw", fill=TX, font=("TkDefaultFont", 12),
                          text="Nenhum computador cadastrado.\nUse Arquivo > Configurar… para adicionar os PCs do laboratório.")
            return
        letras, linhas, xs, ys, larg_total, alt_total = self._geometria()
        self.cab_col = {}
        self.cab_lin = {}
        dx = max((c.winfo_width() - larg_total) // 2, 0)
        dy = max((c.winfo_height() - alt_total) // 2, 0)
        self.off = (dx, dy)
        apos = (self.cfg.get("corredor_apos") or "").upper()
        for L in letras:
            x = xs[L] + dx
            t = c.create_text(x + LARG // 2, MARGEM + dy + CAB // 2, text=L, fill="#44546a", font=("TkDefaultFont", 13, "bold"))
            self.cab_col[L] = (x, MARGEM + dy, x + LARG, MARGEM + dy + CAB)
            if L == apos and L != letras[-1]:
                cx = x + LARG + GAP // 2
                c.create_rectangle(cx, MARGEM + CAB + dy, cx + CORREDOR - GAP, alt_total - GAP + dy, fill="#fff1c2", outline="#d99a00", dash=(4, 3))
                c.create_text(cx + (CORREDOR - GAP) // 2, (MARGEM + CAB + alt_total) // 2 + dy, text="\n".join("CORREDOR"),
                              fill="#8a5d00", font=("TkDefaultFont", 11, "bold"), justify="center")
        for n in linhas:
            y = ys[n] + dy
            c.create_text(MARGEM + dx + CAB // 2, y + ALT // 2, text=str(n), fill="#44546a", font=("TkDefaultFont", 13, "bold"))
            self.cab_lin[n] = (MARGEM + dx, y, MARGEM + dx + CAB, y + ALT)
        for p in self.pcs:
            x, y = xs[p.col] + dx, ys[p.lin] + dy
            r = c.create_rectangle(x, y, x + LARG, y + ALT, width=2)
            t1 = c.create_text(x + 10, y + 8, anchor="nw", text=p.nome.upper(), font=("TkDefaultFont", 16, "bold"))
            t2 = c.create_text(x + 10, y + 40, anchor="nw", font=("TkDefaultFont", 9))
            t3 = c.create_text(x + 10, y + 58, anchor="nw", font=("TkDefaultFont", 8))
            self.itens[p.nome] = (r, t1, t2, t3, (x, y, x + LARG, y + ALT))
        self._pintar_todos()

    # ------------------------------------------------------------------ seleção
    def _achar(self, x, y):
        for nome, it in self.itens.items():
            x0, y0, x1, y1 = it[4]
            if x0 <= x <= x1 and y0 <= y <= y1:
                return nome
        return None

    def _achar_cab(self, x, y):
        for L, (x0, y0, x1, y1) in getattr(self, "cab_col", {}).items():
            if x0 <= x <= x1 and y0 <= y <= y1:
                return ("col", L)
        for n, (x0, y0, x1, y1) in getattr(self, "cab_lin", {}).items():
            if x0 <= x <= x1 and y0 <= y <= y1:
                return ("lin", n)
        return None

    def _press(self, e):
        self.inicio = (e.x, e.y)
        self.press_ctrl = bool(e.state & 0x4)
        self.press_pc = self._achar(e.x, e.y)
        self.arrastou = False

    def _arrasta(self, e):
        if not self.inicio:
            return
        if not self.arrastou and abs(e.x - self.inicio[0]) + abs(e.y - self.inicio[1]) < 6:
            return
        self.arrastou = True
        if self.banda:
            self.canvas.delete(self.banda)
        self.banda = self.canvas.create_rectangle(*self.inicio, e.x, e.y, outline="#1c6dd0", fill="#cfe0f5", stipple="gray25")

    def _solta(self, e):
        if not self.inicio:
            return
        if self.arrastou:
            x0, x1 = sorted((self.inicio[0], e.x)); y0, y1 = sorted((self.inicio[1], e.y))
            dentro = {n for n, it in self.itens.items()
                      if not (it[4][2] < x0 or it[4][0] > x1 or it[4][3] < y0 or it[4][1] > y1)}
            self.sel = (self.sel | dentro) if self.press_ctrl else dentro
        else:
            cab = self._achar_cab(e.x, e.y)
            if cab:
                tipo, v = cab
                novo = {p.nome for p in self.pcs if (p.col == v if tipo == "col" else p.lin == v)}
                self.sel = (self.sel | novo) if self.press_ctrl else novo
            elif self.press_pc:
                self.sel = (self.sel ^ {self.press_pc}) if self.press_ctrl else {self.press_pc}
            elif not self.press_ctrl:
                self.sel = set()
        if self.banda:
            self.canvas.delete(self.banda)
        self.banda = self.inicio = None
        self._repintar_sel()

    def _sel_grupo(self, filtro):
        self.sel = {p.nome for p in self.pcs if filtro(p)}
        self._repintar_sel()

    def _limpar_sel(self):
        self.sel = set()
        self._repintar_sel()

    def _alvos_sel(self):
        return [self.por_nome[n] for n in sorted(self.sel)]

    def _repintar_sel(self):
        self._pintar_todos()

    # -------------------------------------------------------------- menu direito
    def _direito(self, e):
        nome = self._achar(e.x, e.y)
        if not nome:
            return
        if nome not in self.sel:
            self.sel = {nome}
            self._repintar_sel()
        alvos = self._alvos_sel()
        m = tk.Menu(self.root, tearoff=0)
        m.add_command(label="Selecionados: " + ", ".join(p.nome.upper() for p in alvos), state="disabled")
        m.add_separator()
        for titulo, ids in GRUPOS:
            m.add_cascade(label=titulo, menu=self._menu_grupo(m, ids, lambda: alvos, False))
        if len(alvos) == 1 and alvos[0].ip:
            m.add_separator()
            m.add_command(label="Abrir terminal (SSH)", command=lambda: self._terminal(alvos[0]))
        try:
            m.tk_popup(e.x_root, e.y_root)
        finally:
            m.grab_release()

    def _terminal(self, pc):
        if not core.abrir_terminal(self.cfg, pc):
            self._status("Nenhum programa de terminal encontrado.")

    # ------------------------------------------------------------------ executar
    def executar(self, cid, alvos, todos):
        if not alvos:
            self._status("Selecione pelo menos um computador (clique) ou use a barra de cima.")
            return
        if cid == "iniciar":
            return self._iniciar(alvos)
        alvos_on = [p for p in alvos if p.ip and p.online]
        pulados = [p.nome for p in alvos if p not in alvos_on]
        if not alvos_on:
            self._status("Nenhum dos PCs escolhidos está ligado.")
            return
        _i, texto, confirma, dica = TODOS[cid]
        escopo = (f"TODOS os {len(alvos_on)} computadores ligados" if todos and not self.sel
                  else f"{len(alvos_on)} computador(es): " + ", ".join(p.nome.upper() for p in alvos_on))
        if cid == "abrir-app":
            return DialogoTexto(self.root, "Abrir aplicativo",
                                f"Nome do aplicativo para abrir em {escopo}\n(ex.: writer, calc, firefox; abre o primeiro resultado da busca):",
                                False, "Abrir", lambda nome: nome and self._rodar(cid, texto, alvos_on, pulados, nome))
        if cid == "travar-tela":
            return DialogoTexto(self.root, "Travar tela",
                                f"Vai travar a tela de {escopo}.\nNada é fechado nem minimizado: a tela só fica coberta pela mensagem "
                                "e teclado e mouse são bloqueados.\n\nMensagem para os alunos (em branco = mensagem padrão):",
                                True, "Travar tela", lambda msg: self._rodar(cid, texto, alvos_on, pulados, msg))
        if confirma and not messagebox.askokcancel(f"{texto}?", f"{dica}\n\nVai rodar em {escopo}.", parent=self.root):
            return
        self._rodar(cid, texto, alvos_on, pulados)

    def _rodar(self, cid, texto, alvos, pulados, extra=""):
        self._log(f"▶ {texto}: {len(alvos)} PC(s)" + (f"  (ignorados, desligados: {', '.join(pulados)})" if pulados else ""))
        for p in alvos:
            self.ocupados.add(p.nome)
            self.pool.submit(self._tarefa, cid, p, extra)
        self._pintar_todos()

    def _tarefa(self, cid, p, extra=""):
        if self.demo:
            time.sleep(0.4)
            linha, ok = "(demonstração: nada foi enviado)", True
        else:
            linha, ok = core.ssh_exec(self.cfg, p, core.comando_remoto(self.cfg, cid, extra))
        p.t_estado = 0.0
        self.fila.put(("fim", p, linha, ok))

    def implantar(self):
        alvos = [p for p in (self._alvos_sel() or self.pcs) if p.ip and p.online]
        if not alvos:
            messagebox.showinfo("Implantar", "Nenhum PC ligado para receber as ferramentas.", parent=self.root)
            return
        nomes = ", ".join(p.nome.upper() for p in alvos)
        senha = simpledialog.askstring(
            "Implantar ferramentas",
            f"Vai instalar os comandos do professor em {len(alvos)} PC(s):\n{nomes}\n\n"
            "Senha do sudo do administrador dos PCs (não é gravada):", show="*", parent=self.root)
        if not senha:
            return
        self._log(f"▶ Implantar ferramentas: {len(alvos)} PC(s)")

        def tarefa(p):
            linha, ok = core.implantar(self.cfg, p, senha)
            self.fila.put(("fim", p, linha, ok))
        for p in alvos:
            self.ocupados.add(p.nome)
            self.pool.submit(tarefa, p)
        self._pintar_todos()

    def _iniciar(self, alvos):
        sem_mac, enviados = [], []
        for p in alvos:
            if p.online:
                continue
            if not p.mac:
                sem_mac.append(p.nome)
                continue
            try:
                core.enviar_wol(p.mac, self.cfg["broadcast"])
                enviados.append(p.nome)
            except OSError as e:
                self._log(f"  ✘ {p.nome.upper()}: {e}")
        msg = f"▶ Iniciar: Wake-on-LAN enviado para {', '.join(n.upper() for n in enviados) or 'nenhum PC'}."
        msg += " Só liga se o Wake-on-LAN estiver ativo na BIOS e na placa de rede."
        if sem_mac:
            msg += f"  Sem MAC cadastrado (Configurar…): {', '.join(sem_mac)}."
        self._log(msg)

    def _processar_fila(self):
        try:
            while True:
                _t, p, linha, ok = self.fila.get_nowait()
                self.ocupados.discard(p.nome)
                self._log(f"  {'✔' if ok else '✘'} {p.nome.upper()}: {linha}")
                self._pintar_todos()
        except queue.Empty:
            pass
        self.root.after(100, self._processar_fila)

    # --------------------------------------------------------------- estado/pintura
    def _laco_estado(self):
        while True:
            if not self.demo:
                try:
                    list(self.pool.map(self._sonda, [p for p in list(self.pcs) if p.ip]))
                except Exception:
                    pass
            time.sleep(4)

    def _sonda(self, p):
        p.online = core.tcp_ok(p.ip, self.cfg["porta_ssh"])
        if not p.online:
            p.estado, p.travada, p.input = "?", False, False
            return
        if time.time() - p.t_estado > 12:
            linha, ok = core.ssh_exec(self.cfg, p, f"sudo -n {self.cfg['pasta_ferramentas']}/estado", timeout=10)
            p.t_estado = time.time()
            if ok and linha.startswith("estado="):
                d = dict(x.split("=", 1) for x in linha.split() if "=" in x)
                p.estado, p.travada, p.input = d.get("estado", "?"), d.get("travada") == "1", d.get("input") == "1"
            else:
                p.estado = "?"

    def _tick(self):
        self._pintar_todos()
        self.root.after(1000, self._tick)

    def _pintar_todos(self):
        c = self.canvas
        for p in self.pcs:
            it = self.itens.get(p.nome)
            if not it:
                continue
            r, t1, t2, t3, _b = it
            if p.ip is None:
                chave, texto = "nossh", "sem endereço"
            elif not p.online:
                chave, texto = "off", "desligado"
            elif p.travada:
                chave, texto = "travada", "tela travada"
            elif p.estado == "aluno":
                chave, texto = "aluno", "aluno logado"
            elif p.estado == "login":
                chave, texto = "login", "tela de login"
            elif p.estado == "saiu":
                chave, texto = "saiu", "aluno saiu"
            else:
                chave, texto = "sem", "ligado"
            if p.nome in self.ocupados:
                texto = "executando…"
            fg = TX_OFF if chave in ("off", "nossh") else TX
            sel = p.nome in self.sel
            c.itemconfigure(r, fill=COR[chave], outline="#1c6dd0" if sel else ("#b9bec6" if chave == "nossh" else COR[chave]),
                            width=3 if sel else 2, dash=(4, 3) if chave == "nossh" and not sel else ())
            c.itemconfigure(t1, fill=fg)
            c.itemconfigure(t2, text=texto, fill=fg)
            c.itemconfigure(t3, text="⌨ bloqueado" if (p.online and p.input and not p.travada) else "", fill=fg)
        n = len(self.sel)
        alvo = f"Ações em: {n} selecionado(s)" if n else "Ações em: todos os PCs"
        if self.l_alvo.cget("text") != alvo:
            self.l_alvo.config(text=alvo)
        if n:
            self._status(f"{n} selecionado(s): " + ", ".join(sorted(self.sel)))
        else:
            on = sum(1 for p in self.pcs if p.online)
            self._status(f"{on} de {sum(1 for p in self.pcs if p.ip)} computadores ligados.  "
                         "Clique num PC (Ctrl soma, arraste para selecionar vários); botão direito = comandos.")

    def _demo(self):
        random.seed(3)
        for p in self.pcs:
            if not p.ip:
                continue
            p.online = random.random() > 0.2
            p.estado = random.choice(["aluno", "aluno", "aluno", "login", "saiu"]) if p.online else "?"
            p.travada = p.online and random.random() < 0.15
            p.input = p.online and random.random() < 0.2

    # ------------------------------------------------------------------------ util
    def _status(self, txt):
        if self.l_status.cget("text") != txt:
            self.l_status.config(text=txt)

    def _log(self, txt):
        self.log.config(state="normal")
        self.log.insert("end", f"[{time.strftime('%H:%M:%S')}] {txt}\n")
        self.log.see("end")
        self.log.config(state="disabled")

    def rodar(self):
        self.root.mainloop()


class DialogoTexto:
    """Pede um texto (nome do app ou mensagem da tela travada) e chama `ok(texto)` ao confirmar."""

    def __init__(self, pai, titulo, pergunta, multilinha, rotulo_ok, ok):
        self.ok = ok
        self.multi = multilinha
        self.w = tk.Toplevel(pai)
        self.w.title(titulo)
        self.w.transient(pai)
        quadro = ttk.Frame(self.w, padding=12)
        quadro.pack(fill="both", expand=True)
        ttk.Label(quadro, text=pergunta, justify="left", wraplength=440).pack(anchor="w", pady=(0, 8))
        if multilinha:
            self.campo = tk.Text(quadro, width=52, height=6, wrap="word")
        else:
            self.campo = ttk.Entry(quadro, width=52)
            self.campo.bind("<Return>", lambda e: self._confirmar())
        self.campo.pack(fill="both", expand=True)
        rod = ttk.Frame(quadro)
        rod.pack(fill="x", pady=(10, 0))
        ttk.Button(rod, text=rotulo_ok, command=self._confirmar).pack(side="right")
        ttk.Button(rod, text="Cancelar", command=self.w.destroy).pack(side="right", padx=6)
        self.w.bind("<Escape>", lambda e: self.w.destroy())
        self.w.grab_set()
        self.campo.focus_set()

    def _confirmar(self):
        texto = (self.campo.get("1.0", "end") if self.multi else self.campo.get()).strip()
        self.w.destroy()
        self.ok(texto)


class DialogoConfig:
    CAMPOS = [("titulo", "Título da janela"), ("chave_ssh", "Chave SSH (arquivo)"), ("porta_ssh", "Porta SSH"),
              ("usuario_padrao", "Usuário nos PCs (vazio = igual ao nome do PC)"), ("broadcast", "Broadcast da rede (Wake-on-LAN)"),
              ("pasta_ferramentas", "Pasta das ferramentas nos PCs"), ("corredor_apos", "Corredor depois da coluna (ex.: D)")]

    def __init__(self, painel):
        self.p = painel
        self.w = tk.Toplevel(painel.root)
        self.w.title("Configurar")
        self.w.transient(painel.root)
        self.w.geometry("640x640")
        cfg = painel.cfg
        self.vars = {}
        quadro = ttk.Frame(self.w, padding=12)
        quadro.pack(fill="both", expand=True)
        quadro.columnconfigure(1, weight=1)
        for i, (k, rotulo) in enumerate(self.CAMPOS):
            ttk.Label(quadro, text=rotulo).grid(row=i, column=0, sticky="w", pady=3, padx=(0, 8))
            v = tk.StringVar(value=str(cfg.get(k, "")))
            self.vars[k] = v
            ttk.Entry(quadro, textvariable=v).grid(row=i, column=1, sticky="ew", pady=3)
            if k == "chave_ssh":
                ttk.Button(quadro, text="Procurar…", command=self._procurar_chave).grid(row=i, column=2, padx=(6, 0))
        n = len(self.CAMPOS)
        ttk.Label(quadro, text="Computadores — uma linha por PC:  nome  endereço(IP)  [MAC]  [usuário]\n"
                               "Nome = letra da coluna + número da fileira (a1, b2…). Use - se ainda não houver endereço.",
                  justify="left").grid(row=n, column=0, columnspan=3, sticky="w", pady=(12, 4))
        self.texto = ScrolledText(quadro, height=14, font=("TkFixedFont", 10))
        self.texto.grid(row=n + 1, column=0, columnspan=3, sticky="nsew")
        quadro.rowconfigure(n + 1, weight=1)
        self.texto.insert("1.0", config.pcs_para_texto(cfg["pcs"]))
        rod = ttk.Frame(quadro)
        rod.grid(row=n + 2, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        ttk.Button(rod, text="Importar lista (.txt)…", command=self._importar).pack(side="left")
        ttk.Button(rod, text="Salvar", command=self._salvar).pack(side="right")
        ttk.Button(rod, text="Cancelar", command=self.w.destroy).pack(side="right", padx=6)
        self.w.grab_set()

    def _procurar_chave(self):
        f = filedialog.askopenfilename(parent=self.w, title="Chave SSH privada", initialdir=os.path.expanduser("~/.ssh"))
        if f:
            self.vars["chave_ssh"].set(f)

    def _importar(self):
        f = filedialog.askopenfilename(parent=self.w, title="Lista de PCs", filetypes=[("Texto", "*.txt"), ("Todos", "*")])
        if f:
            with open(f, encoding="utf-8", errors="replace") as fh:
                self.texto.insert("end", ("\n" if self.texto.get("1.0", "end").strip() else "") + fh.read())

    def _salvar(self):
        pcs, erros = config.texto_para_pcs(self.texto.get("1.0", "end"))
        try:
            porta = int(self.vars["porta_ssh"].get())
            assert 0 < porta < 65536
        except (ValueError, AssertionError):
            erros.append("a porta SSH deve ser um número entre 1 e 65535")
        corr = self.vars["corredor_apos"].get().strip().upper()
        if corr and not (len(corr) == 1 and corr.isalpha()):
            erros.append("o corredor deve ser uma letra de coluna (ex.: D) ou ficar vazio")
        if erros:
            messagebox.showerror("Confira os dados", "\n".join(erros), parent=self.w)
            return
        cfg = {k: v for k, v in self.p.cfg.items() if not k.startswith("_")}
        for k, _r in self.CAMPOS:
            cfg[k] = self.vars[k].get().strip()
        cfg["porta_ssh"], cfg["corredor_apos"], cfg["pcs"] = porta, corr, pcs
        try:
            config.salvar(cfg)
        except OSError as e:
            messagebox.showerror("Não foi possível salvar", str(e), parent=self.w)
            return
        self.w.destroy()
        self.p.aplicar_config(cfg)


def main():
    cfg = config.carregar()
    if cfg.get("_erro"):
        print("Aviso: config.json ilegível; usando padrões.", file=sys.stderr)
    Painel(cfg, demo=bool(os.environ.get("LAB_PAINEL_DEMO"))).rodar()
