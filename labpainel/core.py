"""Rede e SSH, sem interface gráfica (funciona igual no Windows e no Linux)."""
import os, socket, subprocess, sys, tempfile

WINDOWS = sys.platform.startswith("win")
_SEM_JANELA = {"creationflags": 0x08000000} if WINDOWS else {}   # CREATE_NO_WINDOW


class PC:
    def __init__(self, d):
        self.nome = d["nome"].lower()
        self.ip = d.get("ip") or None
        self.mac = d.get("mac", "")
        self.usuario = d.get("usuario", "")
        self.col, self.lin = self.nome[0].upper(), int(self.nome[1:])
        self.online = False
        self.estado = "?"      # aluno | login | saiu | ?
        self.travada = False
        self.input = False
        self.t_estado = 0.0


def ssh_base(cfg, automatico=True):
    """Argumentos do ssh. automatico=True: sem perguntas (BatchMode) e com conexão reaproveitada."""
    cmd = ["ssh", "-F", os.devnull, "-i", os.path.expanduser(cfg["chave_ssh"]), "-p", str(cfg["porta_ssh"]),
           "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=6", "-o", "StrictHostKeyChecking=accept-new"]
    if automatico:
        cmd += ["-o", "BatchMode=yes"]
        if not WINDOWS:   # o OpenSSH do Windows não suporta ControlMaster
            cmd += ["-o", "ControlMaster=auto", "-o", "ControlPersist=120",
                    "-o", "ControlPath=" + os.path.join(tempfile.gettempdir(), "labpainel-%r@%h-%p")]
    return cmd


def destino(cfg, pc):
    return f"{pc.usuario or cfg['usuario_padrao'] or pc.nome}@{pc.ip}"


def ssh_exec(cfg, pc, remoto, timeout=40):
    try:
        r = subprocess.run(ssh_base(cfg) + [destino(cfg, pc), remoto], capture_output=True, text=True,
                           timeout=timeout, **_SEM_JANELA)
        saida = (r.stdout + r.stderr).strip()
        return (saida.splitlines() or ["(sem resposta)"])[-1], r.returncode == 0
    except subprocess.TimeoutExpired:
        return "tempo esgotado", False
    except FileNotFoundError:
        return ("ssh não encontrado (Windows: Configurações > Aplicativos > Recursos opcionais > "
                "Cliente OpenSSH; Mint: sudo apt install openssh-client)"), False
    except Exception as e:  # noqa
        return f"erro: {e}", False


def tcp_ok(ip, porta=22, t=1.5):
    try:
        with socket.create_connection((ip, int(porta)), timeout=t):
            return True
    except OSError:
        return False


def enviar_wol(mac, broadcast):
    b = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    pacote = b"\xff" * 6 + b * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for porta in (9, 7):
            s.sendto(pacote, (broadcast, porta))


SCRIPT_PCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pcs", "lab-ferramentas-mint.sh")


def implantar(cfg, pc, senha_sudo, timeout=150):
    """Copia e roda o instalador das ferramentas no PC. Precisa da senha do sudo do admin do PC
    (enviada pelo SSH e nunca gravada). Retorna (resumo, ok)."""
    dest = destino(cfg, pc)
    base = ssh_base(cfg, automatico=False) + ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8"]
    scp = [("-P" if a == "-p" else a) for a in base]            # o scp usa -P para a porta
    scp = ["scp" if a == "ssh" else a for a in scp]
    try:
        r = subprocess.run(scp + [SCRIPT_PCS, f"{dest}:lab-ferramentas-mint.sh"], capture_output=True, text=True,
                           timeout=40, **_SEM_JANELA)
        if r.returncode:
            return "sem acesso: " + ((r.stderr or r.stdout).strip().splitlines() or ["?"])[-1], False
        r = subprocess.run(base + [dest, "sudo -S -p '' bash lab-ferramentas-mint.sh; rm -f lab-ferramentas-mint.sh"],
                           input=senha_sudo + "\n", capture_output=True, text=True, timeout=timeout, **_SEM_JANELA)
    except subprocess.TimeoutExpired:
        return "tempo esgotado", False
    except FileNotFoundError:
        return "scp/ssh não encontrado (instale o cliente OpenSSH)", False
    saida = r.stdout + r.stderr
    oks, erros = saida.count("[ok]"), saida.count("[ERRO]")
    if r.returncode or erros or not oks:
        ultima = (saida.strip().splitlines() or ["(sem resposta)"])[-1]
        return f"{oks} ok, {erros} erro(s): {ultima}", False
    return f"{oks} etapas concluídas", True


def abrir_terminal(cfg, pc):
    cmd = ssh_base(cfg, automatico=False) + [destino(cfg, pc)]
    if WINDOWS:
        subprocess.Popen(cmd, creationflags=0x00000010)   # CREATE_NEW_CONSOLE
        return True
    for term in (["x-terminal-emulator", "-e"], ["gnome-terminal", "--"], ["xfce4-terminal", "-x"],
                 ["mate-terminal", "-x"], ["konsole", "-e"], ["xterm", "-e"]):
        try:
            subprocess.Popen(term + cmd)
            return True
        except FileNotFoundError:
            continue
    return False
