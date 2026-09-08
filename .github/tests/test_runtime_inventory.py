"""Exercise runtime test discovery with real Nix and changing directories."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class RuntimeInventoryTests(unittest.TestCase):
    def inventory(self, directory, extra="{ }"):
        expression = (
            'builtins.attrNames (import '
            + str(ROOT / 'flake/runtime-tests.nix')
            + ' { lib = (builtins.getFlake '
            + json.dumps(str(ROOT))
            + ').inputs.nixpkgs.lib; root = builtins.toPath '
            + json.dumps(str(directory))
            + '; extra = ' + extra + '; })'
        )
        return json.loads(subprocess.check_output(
            ['nix', 'eval', '--impure', '--json', '--expr', expression], text=True
        ))

    def test_add_rename_remove_and_ignore_fixtures(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'runtime-safety.nix').touch()
            (root / 'scenario.nix').touch()
            (root / 'runtime-directory.nix').mkdir()
            (root / 'runtime-link.nix').symlink_to(root / 'scenario.nix')
            self.assertEqual(self.inventory(root), ['vm-runtime-safety'])
            added = root / 'runtime-new-case.nix'
            added.touch()
            self.assertEqual(self.inventory(root), ['vm-new-case', 'vm-runtime-safety'])
            renamed = root / 'runtime-renamed.nix'
            added.rename(renamed)
            self.assertEqual(self.inventory(root), ['vm-renamed', 'vm-runtime-safety'])
            renamed.unlink()
            self.assertEqual(self.inventory(root), ['vm-runtime-safety'])

    def test_collisions_fail_instead_of_losing_coverage(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'runtime-safety.nix').touch()
            (root / 'runtime-runtime-safety.nix').touch()
            with self.assertRaises(subprocess.CalledProcessError):
                self.inventory(root)
            (root / 'runtime-runtime-safety.nix').unlink()
            (root / 'runtime-baseline-confinement.nix').touch()
            with self.assertRaises(subprocess.CalledProcessError):
                self.inventory(root, '{ vm-baseline-confinement = null; }')


if __name__ == '__main__':
    unittest.main()
