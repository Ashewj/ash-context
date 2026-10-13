from pathlib import Path
import sys
import tempfile
import tomllib
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from manage_profiles import manage, prepare_config, replace_with_backup


class ProfileTests(unittest.TestCase):
    def test_preserves_nested_values_comments_and_encoding(self):
        original = b'\xef\xbb\xbf# settings\r\nmodel = "example"\r\nmodel_context_window = 500000 # old\r\n[profiles.other]\r\nmodel_context_window = 100000\r\n'
        updated = prepare_config(original, {'model_context_window': 256000, 'model_post_turn_compact_threshold_percent': 0})
        parsed = tomllib.loads(updated.decode('utf-8-sig'))
        self.assertEqual(parsed['model_context_window'], 256000)
        self.assertEqual(parsed['profiles']['other']['model_context_window'], 100000)
        self.assertEqual(parsed['model'], 'example')
        self.assertIn(b'# old', updated)
        self.assertTrue(updated.startswith(b'\xef\xbb\xbf'))
        self.assertNotIn(b'\n', updated.replace(b'\r\n', b''))

    def test_dry_run_does_not_create_home(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / 'profile'
            manage(home, {'model_context_window': 256000}, True, True)
            self.assertFalse(home.exists())

    def test_backup_idempotence_and_skill_install(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / 'config.toml'
            original = b'model = "example"\n'
            config.write_bytes(original)
            manage(home, {'model_context_window': 256000}, True, False)
            backups = list(home.glob('config.toml.bak-*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            self.assertTrue((home / 'skills/rolling-context/SKILL.md').exists())
            manage(home, {'model_context_window': 256000}, True, False)
            self.assertEqual(len(list(home.glob('config.toml.bak-*'))), 1)

    def test_detected_concurrent_edit_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.toml'
            path.write_bytes(b'model = "newer"\n')
            with self.assertRaises(RuntimeError):
                replace_with_backup(path, b'model = "ours"\n', b'model = "older"\n')
            self.assertEqual(path.read_bytes(), b'model = "newer"\n')

    def test_invalid_toml_is_not_overwritten(self):
        with self.assertRaises(tomllib.TOMLDecodeError):
            prepare_config(b'[broken', {'model_context_window': 256000})

    def test_ambiguous_multiline_layout_is_refused(self):
        original = b'note = """\n[not-a-table]\n"""\nmodel_context_window = 500000\n'
        with self.assertRaises((ValueError, tomllib.TOMLDecodeError)):
            prepare_config(original, {'model_context_window': 256000})


if __name__ == '__main__':
    unittest.main()
