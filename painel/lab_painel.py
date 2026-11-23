#!/usr/bin/env python3
# =============================================================================
# Painel do laboratório — controla os PCs do laboratório de informática (parecido com o Veyon)
#
#   * Colunas = letras (A..F); linhas = números, com a fileira 1 EMBAIXO.
#   * Clique seleciona um PC; Ctrl+clique soma/tira da seleção; CLIQUE E ARRASTE desenha
#     um retângulo e seleciona os PCs dentro dele (com Ctrl soma); clique na letra ou no
#     número seleciona a coluna/fileira; Ctrl+A seleciona todos; Esc limpa.
#   * Entre as colunas D e E fica o CORREDOR, bem visível.
#   * Botão direito num PC: comandos só para os selecionados.
#   * Barra de cima: comandos que rodam em TODOS os PCs (pede confirmação nos mais fortes).
#   * Básicos (Iniciar, Reiniciar, Entrar, Sair, Desligar) | scripts do professor.
#
# Fala com os PCs por SSH (chave ~/.ssh/lab_nopass_ed25519) e roda as ferramentas
# instaladas em /usr/local/lib/lab (sudo sem senha só para elas).
# Uso:  lab-painel                 abre a janela
#       lab-painel --captura X.png salva uma imagem da janela e fecha (teste)
# =============================================================================
import json, os, re, shlex, socket, subprocess, sys, threading, time, concurrent.futures
import gi
gi.require_version("Gtk", "4.0"); gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Gio

HOME = os.path.expanduser("~")
LISTA = f"{HOME}/.ssh/ips-lab-testados.txt"
CHAVE = f"{HOME}/.ssh/lab_nopass_ed25519"
MACS = f"{HOME}/.config/lab-painel/macs.json"
LIB = "/usr/local/lib/lab"
BROADCAST = "192.168.0.255"

SSH = ["ssh", "-F", "/dev/null", "-i", CHAVE, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
       "-o", "ConnectTimeout=6", "-o", "StrictHostKeyChecking=accept-new",
       "-o", "ControlMaster=auto", "-o", "ControlPath=/tmp/labpainel-%r@%h", "-o", "ControlPersist=120"]

# (id, texto, ícone, pede confirmação, descrição)
BASICOS = [
    ("iniciar", "Iniciar", "system-run-symbolic", False, "Liga os PCs desligados (Wake-on-LAN)"),
    ("reiniciar", "Reiniciar", "system-reboot-symbolic", True, "Reinicia o computador"),
    ("entrar", "Entrar", "go-next-symbolic", False, "Faz o aluno entrar (login automático)"),
    ("sair", "Sair", "system-log-out-symbolic", True, "Encerra a sessão do aluno (fecha tudo)"),
    ("desligar", "Desligar", "system-shutdown-symbolic", True, "Desliga o computador"),
]
CUSTOM = [
    ("fechar-roblox", "Fechar Roblox", "process-stop-symbolic", False, "Fecha o Roblox"),
    ("tirar-conta-roblox", "Tirar conta do Roblox", "user-trash-symbolic", True, "Fecha o Roblox e apaga o login"),
    ("fechar-apps", "Fechar todos os apps", "window-close-symbolic", True, "Fecha tudo e mostra a área de trabalho"),
    ("bloquear-input", "Bloquear teclado e mouse", "input-keyboard-symbolic", True, "Desliga teclado e mouse dos alunos"),
    ("liberar-input", "Liberar teclado e mouse", "input-mouse-symbolic", False, "Religa teclado e mouse"),
    ("travar-tela", "Travar tela", "changes-prevent-symbolic", True, "Cobre a tela com uma mensagem e bloqueia teclado e mouse (não fecha nem minimiza nada)"),
    ("liberar-tela", "Liberar tela", "changes-allow-symbolic", False, "Tira o aviso e libera teclado e mouse"),
    ("reiniciar-veyon", "Reiniciar Veyon", "view-refresh-symbolic", False, "Reinicia só o Veyon para as telas voltarem a aparecer no programa"),
]
TODOS = {c[0]: c for c in BASICOS + CUSTOM}

CSS = b"""
window { background: #eef1f5; color: #2b2f36; }
window label { color: #2b2f36; }
textview, textview text { background: #ffffff; color: #2b2f36; }
expander title { color: #2b2f36; }
.barra button label, .barra button image { color: #2b2f36; }
.barra { background: #ffffff; border-bottom: 1px solid #c9d1dc; padding: 6px 8px; }
.barra button { padding: 6px 10px; }
.titulo-col, .titulo-lin { font-weight: bold; color: #44546a; font-size: 15px; padding: 4px 10px; border-radius: 6px; }
.titulo-col:hover, .titulo-lin:hover { background: #dbe4f0; }
.tile { border-radius: 10px; border: 2px solid transparent; padding: 8px; min-width: 120px; min-height: 78px;
        background: #cfd6df; color: #2b2f36; }
.tile .nome { font-weight: bold; font-size: 20px; }
.tile .info { font-size: 12px; }
.tile.on-aluno { background: #bfe8c9; }
.tile.on-login { background: #ffe3a3; }
.tile.on-saiu { background: #ffd2a8; }
.tile.on-sem { background: #d6ecf8; }
.tile.travada { background: #f5b5b5; }
.tile.off { background: #d9dce1; color: #7a808a; }
.tile.nossh { background: #eceef1; color: #9aa0a8; border: 2px dashed #b9bec6; }
.tile.sel { border: 2px solid #1c6dd0; box-shadow: 0 0 0 2px #9cc3f3; }
.vazio { min-width: 150px; min-height: 78px; }
.corredor { background: #fff1c2; border-left: 3px dashed #d99a00; border-right: 3px dashed #d99a00;
            min-width: 84px; border-radius: 4px; }
.corredor label { color: #8a5d00; font-weight: bold; font-size: 15px; }
.elastico { background: rgba(28,109,208,0.18); border: 1px solid #1c6dd0; }
.aviso { color: #e0a800; }
.rodape { background: #ffffff; border-top: 1px solid #c9d1dc; padding: 4px 10px; font-size: 12px; }
.menu-cab { font-weight: bold; padding: 4px 10px; color: #44546a; }
"""


class PC:
    def __init__(self, nome, ip):
        self.nome, self.ip = nome, ip
        self.col, self.lin = nome[0].upper(), int(nome[1:])
        self.online = False
        self.estado = "?"          # aluno | login | saiu | ?
        self.travada = False
        self.input = False
        self.t_estado = 0.0
        self.widget = self.l_nome = self.l_info = self.l_extra = None


def carregar_pcs():
    pcs = {}
    if os.path.exists(LISTA):
        for linha in open(LISTA, encoding="utf-8"):
            m = re.match(r"^([a-f]\d+):\s+(\d+\.\d+\.\d+\.\d+)", linha.strip())
            if m:
                pcs[m.group(1)] = PC(m.group(1), m.group(2))
    for extra in ("e4", "f4"):          # ainda sem SSH instalado
        pcs.setdefault(extra, PC(extra, None))
    return sorted(pcs.values(), key=lambda p: (p.col, p.lin))


def ssh_exec(pc, remoto, timeout=40):
    try:
        r = subprocess.run(SSH + [f"{pc.nome}@{pc.ip}", remoto], capture_output=True, text=True, timeout=timeout)
        saida = (r.stdout + r.stderr).strip()
        return (saida.splitlines() or ["(sem resposta)"])[-1], r.returncode == 0
    except subprocess.TimeoutExpired:
        return "tempo esgotado", False
    except Exception as e:  # noqa
        return f"erro: {e}", False


def tcp_ok(ip, porta=22, t=1.5):
    try:
        with socket.create_connection((ip, porta), timeout=t):
            return True
    except OSError:
        return False


def enviar_wol(mac):
    b = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    pacote = b"\xff" * 6 + b * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for porta in (9, 7):
            s.sendto(pacote, (BROADCAST, porta))


class Painel(Gtk.Application):
    def __init__(self, captura=None):
        super().__init__(application_id="br.lab.painel" + (".teste" if captura else ""))
        self.captura = captura
        self.pcs = carregar_pcs()
        self.por_nome = {p.nome: p for p in self.pcs}
        self.sel = set()
        self.ocupados = set()
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=24)
        self.macs = {}
        try:
            self.macs = json.load(open(MACS))
        except Exception:
            pass

    # ------------------------------------------------------------------ janela
    def do_activate(self):
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", False)
        prov = Gtk.CssProvider(); prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.win = Gtk.ApplicationWindow(application=self, title="Laboratório de Informática")
        self.win.set_default_size(1120, 760)
        raiz = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        raiz.append(self._barra())
        raiz.append(self._grade())
        raiz.append(self._rodape())
        self.win.set_child(raiz)
        kc = Gtk.EventControllerKey(); kc.connect("key-pressed", self._tecla); self.win.add_controller(kc)
        self.win.present()
        if os.environ.get("LAB_PAINEL_DEMO"):
            self._demo()
        threading.Thread(target=self._laco_estado, daemon=True).start()
        if self.captura:
            GLib.timeout_add_seconds(7, self._capturar)

    def _demo(self):
        import random
        random.seed(3)
        for p in self.pcs:
            if not p.ip: continue
            p.online = random.random() > 0.2
            p.estado = random.choice(["aluno", "aluno", "aluno", "login", "saiu"]) if p.online else "?"
            p.travada = p.online and random.random() < 0.15
            p.input = p.online and random.random() < 0.2
            p.t_estado = time.time() + 9999
        self.sel = {"b2", "c2", "d3"}
        self.demo = True
        self._pintar_todos(); self._repintar_sel()
        if os.environ.get("LAB_PAINEL_DEMO") == "2":
            GLib.timeout_add(500, lambda: (self._elastico(70, 360, 540, 150), False)[1])
        if os.environ.get("LAB_PAINEL_DEMO") == "3":
            try:
                self._dialogo_mensagem("TODOS os 18 computadores", lambda m: print("MSG:", repr(m)))
                print("DEMO3: diálogo abriu sem erro")
            except Exception as e:
                print("DEMO3 ERRO:", repr(e))
        try:
            self._menu(self.por_nome["b2"], 20, 20); self.executar("fechar-roblox", [self.por_nome["d3"]], False)
            print("DEMO: menu e execução sem erro")
        except Exception as e:
            print("DEMO ERRO:", repr(e))
        self._log("▶ Fechar todos os apps: 14 PC(s)"); self._log("  ✔ A1: Info-A1: programas fechados (janelas restantes: 0), área de trabalho à mostra"); self._log("  ✘ D2: tempo esgotado")

    def _capturar(self):
        p = Gtk.WidgetPaintable.new(self.win)
        w, h = self.win.get_width(), self.win.get_height()
        snap = Gtk.Snapshot(); p.snapshot(snap, w, h)
        tex = self.win.get_native().get_renderer().render_texture(snap.to_node(), None)
        tex.save_to_png(self.captura)
        self.quit()
        return False

    # ---------------------------------------------------------------- barra de cima
    def _botao(self, cid, texto, icone, dica, aviso=False):
        b = Gtk.Button(); b.set_tooltip_text(dica)
        caixa = Gtk.Box(spacing=6)
        caixa.append(Gtk.Image.new_from_icon_name(icone))
        caixa.append(Gtk.Label(label=texto))
        if aviso:  # ícone amarelo pequeno: função ainda limitada
            ic = Gtk.Image.new_from_icon_name("dialog-warning-symbolic"); ic.set_pixel_size(12); ic.add_css_class("aviso")
            caixa.append(ic)
        b.set_child(caixa)
        b.connect("clicked", lambda _b: self.executar(cid, [p for p in self.pcs if p.ip], todos=True))
        return b

    def _barra(self):
        fb = Gtk.FlowBox(); fb.set_selection_mode(Gtk.SelectionMode.NONE); fb.set_max_children_per_line(30)
        fb.set_column_spacing(4); fb.set_row_spacing(4); fb.set_homogeneous(False); fb.add_css_class("barra")
        for cid, texto, icone, _c, dica in BASICOS:
            fb.append(self._botao(cid, texto, icone, dica + " (em todos)", aviso=(cid == "iniciar")))
        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL); sep.set_margin_start(6); sep.set_margin_end(6)
        sep.set_size_request(1, 28); sep.set_halign(Gtk.Align.CENTER); sep.set_valign(Gtk.Align.CENTER)
        fb.append(sep)
        for cid, texto, icone, _c, dica in CUSTOM:
            fb.append(self._botao(cid, texto, icone, dica + " (em todos)"))
        return fb

    # ---------------------------------------------------------------------- grade
    def _grade(self):
        letras = sorted({p.col for p in self.pcs})
        maxlin = max(p.lin for p in self.pcs)
        g = Gtk.Grid(column_spacing=10, row_spacing=10, margin_top=16, margin_bottom=16, margin_start=16, margin_end=16)
        g.set_column_homogeneous(False)
        g.set_halign(Gtk.Align.CENTER); g.set_valign(Gtk.Align.CENTER)
        # posição de cada letra; entre D e E fica o corredor (coluna extra bem visível)
        pos, x, col_corredor = {}, 1, None
        for letra in letras:
            if letra == "E":
                col_corredor = x; x += 1
            pos[letra] = x; x += 1
        for letra in letras:
            l = Gtk.Label(label=letra); l.add_css_class("titulo-col")
            gc = Gtk.GestureClick(); gc.connect("pressed", lambda *_a, L=letra: self._sel_grupo(lambda p: p.col == L)); l.add_controller(gc)
            g.attach(l, pos[letra], 0, 1, 1)
        if col_corredor:
            corr = Gtk.Box(orientation=Gtk.Orientation.VERTICAL); corr.add_css_class("corredor")
            lab = Gtk.Label(label="\n".join("CORREDOR")); lab.set_vexpand(True); lab.set_valign(Gtk.Align.CENTER); lab.set_justify(Gtk.Justification.CENTER)
            corr.append(lab)
            g.attach(corr, col_corredor, 0, 1, maxlin + 1)
        for lin in range(1, maxlin + 1):
            linha_grade = maxlin - lin + 1          # fileira 1 fica embaixo
            l = Gtk.Label(label=str(lin)); l.add_css_class("titulo-lin")
            gc = Gtk.GestureClick(); gc.connect("pressed", lambda *_a, N=lin: self._sel_grupo(lambda p: p.lin == N)); l.add_controller(gc)
            g.attach(l, 0, linha_grade, 1, 1)
            for letra in letras:
                pc = self.por_nome.get(f"{letra.lower()}{lin}")
                if pc is None:
                    v = Gtk.Box(); v.add_css_class("vazio"); g.attach(v, pos[letra], linha_grade, 1, 1); continue
                g.attach(self._tile(pc), pos[letra], linha_grade, 1, 1)
        fundo = Gtk.GestureClick(); fundo.connect("pressed", self._clique_fundo)
        cont = Gtk.Box(); cont.set_hexpand(True); cont.set_vexpand(True); cont.append(g); g.set_hexpand(True)
        cont.add_controller(fundo)
        # seleção por arrasto (retângulo elástico por cima de tudo)
        self.area = Gtk.Overlay(); self.area.set_child(cont); self.area.set_hexpand(True); self.area.set_vexpand(True)
        self.elastico = Gtk.Box(); self.elastico.add_css_class("elastico"); self.elastico.set_can_target(False)
        self.elastico.set_halign(Gtk.Align.START); self.elastico.set_valign(Gtk.Align.START); self.elastico.set_visible(False)
        self.area.add_overlay(self.elastico)
        arr = Gtk.GestureDrag(); arr.set_button(1); arr.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        arr.connect("drag-begin", self._arr_ini); arr.connect("drag-update", self._arr_mov); arr.connect("drag-end", self._arr_fim)
        self.area.add_controller(arr)
        return self.area

    # ---- seleção por arrasto
    def _arr_ini(self, gesto, x, y):
        ctrl = bool(gesto.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK)
        self._arr = {"x": x, "y": y, "base": set(self.sel) if ctrl else set(), "ativo": False}

    def _retangulo(self, ox, oy):
        a = self._arr
        x0, y0 = min(a["x"], a["x"] + ox), min(a["y"], a["y"] + oy)
        return x0, y0, abs(ox), abs(oy)

    def _arr_mov(self, gesto, ox, oy):
        a = getattr(self, "_arr", None)
        if not a or (not a["ativo"] and abs(ox) + abs(oy) < 6):
            return
        a["ativo"] = True
        x, y, w, h = self._retangulo(ox, oy)
        self._elastico(x, y, w, h)
        novos = set(a["base"])
        for p in self.pcs:
            if p.widget is None:
                continue
            ok, r = p.widget.compute_bounds(self.area)
            if not ok:
                continue
            rx, ry, rw, rh = r.get_x(), r.get_y(), r.get_width(), r.get_height()
            if rx < x + w and rx + rw > x and ry < y + h and ry + rh > y:
                novos.add(p.nome)
        if novos != self.sel:
            self.sel = novos; self._repintar_sel()

    def _arr_fim(self, gesto, ox, oy):
        self.elastico.set_visible(False)
        self._arr = None

    def _elastico(self, x, y, w, h):
        self.elastico.set_margin_start(int(x)); self.elastico.set_margin_top(int(y))
        self.elastico.set_size_request(max(1, int(w)), max(1, int(h))); self.elastico.set_visible(True)

    def _tile(self, pc):
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2); t.add_css_class("tile")
        pc.l_nome = Gtk.Label(label=pc.nome.upper(), xalign=0); pc.l_nome.add_css_class("nome")
        pc.l_info = Gtk.Label(label="…", xalign=0); pc.l_info.add_css_class("info")
        pc.l_info.set_ellipsize(3); pc.l_info.set_max_width_chars(16)
        pc.l_extra = Gtk.Label(label="", xalign=0); pc.l_extra.add_css_class("info")
        t.set_size_request(150, -1)
        t.append(pc.l_nome); t.append(pc.l_info); t.append(pc.l_extra)
        gc = Gtk.GestureClick(); gc.set_button(0)
        gc.connect("pressed", self._clique_pc, pc)
        t.add_controller(gc)
        pc.widget = t
        self._pintar(pc)
        return t

    def _rodape(self):
        caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.l_status = Gtk.Label(label="Clique num PC para selecionar (Ctrl+clique soma). Botão direito = comandos.", xalign=0)
        self.l_status.add_css_class("rodape")
        self.log = Gtk.TextView(editable=False, monospace=True, cursor_visible=False)
        self.log.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        rol = Gtk.ScrolledWindow(); rol.set_child(self.log); rol.set_min_content_height(130)
        exp = Gtk.Expander(label="Resultados dos comandos"); exp.set_child(rol); exp.set_expanded(True)
        caixa.append(exp); caixa.append(self.l_status)
        return caixa

    # ------------------------------------------------------------------- seleção
    def _clique_pc(self, gesto, n, x, y, pc):
        botao = gesto.get_current_button()
        ctrl = bool(gesto.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK)
        if botao == 1:
            if ctrl:
                self.sel ^= {pc.nome}
            else:
                self.sel = {pc.nome}
            self._repintar_sel()
        elif botao == 3:
            if pc.nome not in self.sel:
                self.sel = {pc.nome}; self._repintar_sel()
            self._menu(pc, x, y)

    def _clique_fundo(self, gesto, n, x, y):
        if not bool(gesto.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK):
            self.sel = set(); self._repintar_sel()

    def _sel_grupo(self, filtro):
        self.sel = {p.nome for p in self.pcs if filtro(p)}; self._repintar_sel()

    def _tecla(self, ctl, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.sel = set(); self._repintar_sel(); return True
        if (state & Gdk.ModifierType.CONTROL_MASK) and keyval in (Gdk.KEY_a, Gdk.KEY_A):
            self.sel = {p.nome for p in self.pcs}; self._repintar_sel(); return True
        return False

    def _repintar_sel(self):
        for p in self.pcs:
            self._pintar(p)
        n = len(self.sel)
        self._status("Nenhum PC selecionado." if not n else f"{n} selecionado(s): " + ", ".join(sorted(self.sel)))

    # ---------------------------------------------------------------- menu direito
    def _menu(self, pc, x, y):
        alvos = [self.por_nome[n] for n in sorted(self.sel)]
        pop = Gtk.Popover(); pop.set_parent(pc.widget); pop.set_has_arrow(False)
        r = Gdk.Rectangle(); r.x, r.y, r.width, r.height = int(x), int(y), 1, 1
        pop.set_pointing_to(r)
        caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        cab = Gtk.Label(label=("Selecionados: " + ", ".join(p.nome.upper() for p in alvos)), xalign=0)
        cab.add_css_class("menu-cab"); caixa.append(cab)
        caixa.append(Gtk.Separator())

        def item(cid, texto, icone, dica, aviso=False):
            b = Gtk.Button(); b.add_css_class("flat"); b.set_tooltip_text(dica)
            h = Gtk.Box(spacing=8); h.append(Gtk.Image.new_from_icon_name(icone)); lab = Gtk.Label(label=texto, xalign=0); lab.set_hexpand(True); h.append(lab)
            if aviso:
                ic = Gtk.Image.new_from_icon_name("dialog-warning-symbolic"); ic.set_pixel_size(12); ic.add_css_class("aviso"); h.append(ic)
            b.set_child(h)
            b.connect("clicked", lambda _b: (pop.popdown(), self.executar(cid, alvos, todos=False)))
            caixa.append(b)

        for cid, texto, icone, _c, dica in BASICOS:
            item(cid, texto, icone, dica, aviso=(cid == "iniciar"))
        caixa.append(Gtk.Separator())
        for cid, texto, icone, _c, dica in CUSTOM:
            item(cid, texto, icone, dica)
        if len(alvos) == 1 and alvos[0].ip:
            caixa.append(Gtk.Separator())
            b = Gtk.Button(); b.add_css_class("flat")
            h = Gtk.Box(spacing=8); h.append(Gtk.Image.new_from_icon_name("utilities-terminal-symbolic")); l = Gtk.Label(label="Abrir terminal (SSH)", xalign=0); h.append(l)
            b.set_child(h)
            b.connect("clicked", lambda _b: (pop.popdown(), self._terminal(alvos[0])))
            caixa.append(b)
        pop.set_child(caixa)
        pop.connect("closed", lambda p: GLib.idle_add(p.unparent))
        pop.popup()

    def _terminal(self, pc):
        cmd = ["ssh", "-F", "/dev/null", "-i", CHAVE, "-o", "IdentitiesOnly=yes", f"{pc.nome}@{pc.ip}"]
        for term in (["konsole", "-e"], ["gnome-terminal", "--"], ["xterm", "-e"]):
            try:
                subprocess.Popen(term + cmd); return
            except FileNotFoundError:
                continue
        self._status("Nenhum terminal encontrado (konsole).")

    # ------------------------------------------------------------------ executar
    def executar(self, cid, alvos, todos):
        if not alvos:
            self._status("Selecione pelo menos um computador (clique) ou use a barra de cima."); return
        if cid == "iniciar":
            return self._iniciar(alvos)
        alvos_on = [p for p in alvos if p.ip and p.online]
        pulados = [p.nome for p in alvos if p not in alvos_on]
        if not alvos_on:
            self._status("Nenhum dos PCs escolhidos está ligado."); return
        _id, texto, _i, confirma, dica = TODOS[cid]
        if cid == "travar-tela":
            esc = f"TODOS os {len(alvos_on)} computadores ligados" if todos else f"{len(alvos_on)} computador(es): " + ", ".join(p.nome.upper() for p in alvos_on)
            return self._dialogo_mensagem(esc, lambda msg: self._rodar(cid, texto, alvos_on, pulados, msg))
        escopo = f"TODOS os {len(alvos_on)} computadores ligados" if todos else f"{len(alvos_on)} computador(es): " + ", ".join(p.nome.upper() for p in alvos_on)
        if confirma:
            self._confirmar(f"{texto}?", f"{dica}\n\nVai rodar em {escopo}.", lambda: self._rodar(cid, texto, alvos_on, pulados))
        else:
            self._rodar(cid, texto, alvos_on, pulados)

    def _dialogo_mensagem(self, escopo, ok):
        """Pergunta a mensagem da tela travada. Em branco = mensagem padrão."""
        d = Gtk.Window(title="Travar tela", transient_for=self.win, modal=True)
        d.set_default_size(460, 300)
        caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin_top=14, margin_bottom=14, margin_start=14, margin_end=14)
        caixa.append(Gtk.Label(label=f"Vai travar a tela de {escopo}.\nNada é fechado nem minimizado: a tela só fica coberta pela mensagem e teclado e mouse são bloqueados.", xalign=0, wrap=True))
        caixa.append(Gtk.Label(label="Mensagem que aparece na tela dos alunos:", xalign=0))
        tv = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=6, bottom_margin=6, left_margin=6, right_margin=6)
        rol = Gtk.ScrolledWindow(); rol.set_child(tv); rol.set_vexpand(True); rol.set_min_content_height(110)
        caixa.append(rol)
        caixa.append(Gtk.Label(label="Deixe em branco para a mensagem padrão: \"Tela bloqueada pelo professor — Aguarde, por favor\".", xalign=0, wrap=True))
        botoes = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        cancelar = Gtk.Button(label="Cancelar"); travar = Gtk.Button(label="Travar tela"); travar.add_css_class("suggested-action")
        botoes.append(cancelar); botoes.append(travar); caixa.append(botoes)
        cancelar.connect("clicked", lambda _b: d.close())
        def confirmar(_b):
            b = tv.get_buffer(); msg = b.get_text(b.get_start_iter(), b.get_end_iter(), False).strip()
            d.close(); ok(msg.replace("\n", "\\n"))     # quebras de linha viram \n (o aviso converte de volta)
        travar.connect("clicked", confirmar)
        d.set_child(caixa); d.present()

    def _confirmar(self, titulo, detalhe, ok):
        try:
            d = Gtk.AlertDialog(); d.set_message(titulo); d.set_detail(detalhe)
            d.set_buttons(["Cancelar", "Executar"]); d.set_cancel_button(0); d.set_default_button(0)
            def fim(dlg, res):
                try:
                    if dlg.choose_finish(res) == 1:
                        ok()
                except GLib.Error:
                    pass
            d.choose(self.win, None, fim)
        except AttributeError:
            ok()

    def _rodar(self, cid, texto, alvos, pulados, extra=""):
        self._log(f"▶ {texto}: {len(alvos)} PC(s)" + (f"  (ignorados, desligados: {', '.join(pulados)})" if pulados else ""))
        for p in alvos:
            self.ocupados.add(p.nome); self._pintar(p)
            self.pool.submit(self._tarefa, cid, p, extra)

    def _tarefa(self, cid, p, extra=""):
        linha, ok = ssh_exec(p, f"sudo -n {LIB}/{cid}" + (" " + shlex.quote(extra) if extra else ""))
        p.t_estado = 0.0           # força reler o estado
        GLib.idle_add(self._fim_tarefa, p, linha, ok)

    def _fim_tarefa(self, p, linha, ok):
        self.ocupados.discard(p.nome); self._pintar(p)
        self._log(f"  {'✔' if ok else '✘'} {p.nome.upper()}: {linha}")
        return False

    def _iniciar(self, alvos):
        sem_mac, enviados = [], []
        for p in alvos:
            if p.online:
                continue
            mac = self.macs.get(p.nome)
            if not mac:
                sem_mac.append(p.nome); continue
            try:
                enviar_wol(mac); enviados.append(p.nome)
            except OSError as e:
                self._log(f"  ✘ {p.nome.upper()}: {e}")
        msg = f"▶ Iniciar: pacote Wake-on-LAN enviado para {', '.join(n.upper() for n in enviados) or 'nenhum PC'}."
        msg += " Só liga se o Wake-on-LAN estiver ativo na BIOS e na placa de rede (ainda não configurado: por isso o aviso amarelo)."
        if sem_mac:
            msg += f"  Sem MAC cadastrado: {', '.join(sem_mac)}."
        self._log(msg)

    # --------------------------------------------------------------- estado/pintura
    def _laco_estado(self):
        while True:
            try:
                list(self.pool.map(self._sonda, [p for p in self.pcs if p.ip]))
            except Exception:
                pass
            GLib.idle_add(self._pintar_todos)
            time.sleep(4)

    def _sonda(self, p):
        if getattr(self, "demo", False): return
        p.online = tcp_ok(p.ip)
        if not p.online:
            p.estado, p.travada, p.input = "?", False, False
            return
        if time.time() - p.t_estado > 12:
            linha, ok = ssh_exec(p, f"sudo -n {LIB}/estado", timeout=10)
            p.t_estado = time.time()
            if ok and linha.startswith("estado="):
                d = dict(x.split("=", 1) for x in linha.split())
                p.estado = d.get("estado", "?"); p.travada = d.get("travada") == "1"; p.input = d.get("input") == "1"
            else:
                p.estado = "?"

    def _pintar_todos(self):
        for p in self.pcs:
            self._pintar(p)
        on = sum(1 for p in self.pcs if p.online)
        if not self.sel:
            self._status(f"{on} de {sum(1 for p in self.pcs if p.ip)} computadores ligados.")
        return False

    def _pintar(self, p):
        if p.widget is None:
            return
        for c in ("on-aluno", "on-login", "on-saiu", "on-sem", "off", "nossh", "travada", "sel"):
            p.widget.remove_css_class(c)
        if p.ip is None:
            p.widget.add_css_class("nossh"); texto = "sem SSH"
        elif not p.online:
            p.widget.add_css_class("off"); texto = "desligado"
        elif p.travada:
            p.widget.add_css_class("travada"); texto = "tela travada"
        elif p.estado == "aluno":
            p.widget.add_css_class("on-aluno"); texto = "aluno logado"
        elif p.estado == "login":
            p.widget.add_css_class("on-login"); texto = "tela de login"
        elif p.estado == "saiu":
            p.widget.add_css_class("on-saiu"); texto = "aluno saiu"
        else:
            p.widget.add_css_class("on-sem"); texto = "ligado"
        p.l_extra.set_text("⌨ teclado/mouse bloqueados" if (p.online and p.input and not p.travada) else "")
        if p.nome in self.ocupados:
            texto = "executando…"
        p.l_info.set_text(texto)
        if p.nome in self.sel:
            p.widget.add_css_class("sel")

    # ------------------------------------------------------------------------ util
    def _status(self, txt):
        self.l_status.set_text(txt)

    def _log(self, txt):
        buf = self.log.get_buffer()
        buf.insert(buf.get_end_iter(), f"[{time.strftime('%H:%M:%S')}] {txt}\n")
        GLib.idle_add(lambda: self.log.scroll_to_iter(buf.get_end_iter(), 0, False, 0, 0) and False)


def main():
    captura = None
    if "--captura" in sys.argv:
        captura = sys.argv[sys.argv.index("--captura") + 1]
    app = Painel(captura)
    sys.exit(app.run([sys.argv[0]]))


if __name__ == "__main__":
    main()
