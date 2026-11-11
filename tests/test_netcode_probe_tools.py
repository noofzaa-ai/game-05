import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('compare_native',Path(__file__).resolve().parents[1]/'tools/netcode/compare_native.py')
probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class ProbeTools(unittest.TestCase):
    def text(self):
        return '\n'.join('NETCODE_HASH %s %d %s'%(name,tick,'a'*64) for name,tick in sorted(probe.EXPECTED))
    def test_exact_complete_set(self):
        self.assertEqual(len(probe.parse(self.text())),80)
    def test_missing_or_duplicate_rejected(self):
        text=self.text()
        for bad in (text.split('\n',1)[1],text+'\n'+text.splitlines()[0]):
            with self.assertRaises(ValueError):probe.parse(bad)
    def test_web_requires_completion_and_reports_mismatch(self):
        native=probe.parse(self.text())
        with self.assertRaises(ValueError):probe.compare_web(native,self.text())
        self.assertEqual(probe.compare_web(native,self.text()+'\nPROBE_COMPLETE 80'),[])
        altered=self.text().replace('a'*64,'b'*64,1)+'\nPROBE_COMPLETE 80'
        self.assertEqual(len(probe.compare_web(native,altered)),1)

if __name__=='__main__':unittest.main()
