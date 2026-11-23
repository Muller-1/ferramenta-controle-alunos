import sys


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] == "lab":
        from .cli import main as cli
        return cli(argv[1:])
    from .app import main as gui
    gui()
    return 0
