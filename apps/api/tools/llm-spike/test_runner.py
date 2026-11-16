import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent


class BenchmarkCLI(unittest.TestCase):
    def test_fixture_report_never_claims_live_measurements(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(ROOT / 'run.py'), '--fixture',
                                     str(ROOT / 'fixture.json'), '--output',
                                     str(Path(directory) / 'report.json')], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((Path(directory) / 'report.json').read_text())
            self.assertEqual(len(report['queries']), 50)
            self.assertFalse(report['live'])
            self.assertIsNone(report['cost_per_search_usd'])
            self.assertIsNone(report['p90_ms'])


if __name__ == '__main__':
    unittest.main()
