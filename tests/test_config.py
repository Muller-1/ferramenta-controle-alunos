import os, sys, unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from labpainel import config, core


class TestParser(unittest.TestCase):
    def test_formatos(self):
        pcs, erros = config.texto_para_pcs(
            "a1: 192.168.0.101  (Info-A1)\nb2 10.0.0.5 aa:bb:cc:dd:ee:ff prof\n# comentario\n\nc3 -\n")
        self.assertEqual(erros, [])
        self.assertEqual(pcs[0], {"nome": "a1", "ip": "192.168.0.101", "mac": "", "usuario": ""})
        self.assertEqual(pcs[1], {"nome": "b2", "ip": "10.0.0.5", "mac": "aa:bb:cc:dd:ee:ff", "usuario": "prof"})
        self.assertEqual(pcs[2]["ip"], "")

    def test_erros(self):
        pcs, erros = config.texto_para_pcs("zz 1.1.1.1\na1 1.1.1.1\na1 2.2.2.2\nb1 ip;rm")
        self.assertEqual([p["nome"] for p in pcs], ["a1"])
        self.assertEqual(len(erros), 3)

    def test_ida_e_volta(self):
        orig = [{"nome": "a1", "ip": "1.2.3.4", "mac": "aa:bb:cc:dd:ee:ff", "usuario": "x"}, {"nome": "b2", "ip": "", "mac": "", "usuario": ""}]
        self.assertEqual(config.texto_para_pcs(config.pcs_para_texto(orig))[0], orig)

    def test_salvar_carregar(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.environ["LAB_PAINEL_CONFIG"] = os.path.join(d, "sub", "c.json")
            cfg = config.carregar()
            self.assertTrue(cfg["_primeira_vez"])
            cfg["pcs"] = [{"nome": "a1", "ip": "1.1.1.1", "mac": "", "usuario": ""}]
            config.salvar(cfg)
            self.assertEqual(config.carregar()["pcs"][0]["nome"], "a1")
            del os.environ["LAB_PAINEL_CONFIG"]


class TestSsh(unittest.TestCase):
    def test_destino_e_args(self):
        cfg = config.carregar() | {"usuario_padrao": ""}
        pc = core.PC({"nome": "b2", "ip": "10.0.0.5"})
        self.assertEqual(core.destino(cfg, pc), "b2@10.0.0.5")
        self.assertEqual(core.destino(cfg | {"usuario_padrao": "adm"}, pc), "adm@10.0.0.5")
        self.assertIn("BatchMode=yes", core.ssh_base(cfg))
        self.assertNotIn("BatchMode=yes", core.ssh_base(cfg, automatico=False))


if __name__ == "__main__":
    unittest.main()
