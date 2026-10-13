"""Install rolling-context and edit requested Codex settings, with backups."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import tempfile
import tomllib

SKILL_SOURCE = Path(__file__).resolve().parents[1] / 'skills' / 'rolling-context'


def prepare_config(original: bytes, settings: dict[str, int]) -> bytes:
    text = original.decode('utf-8-sig')
    parsed = tomllib.loads(text)
    if all(parsed.get(key) == value for key, value in settings.items()):
        return original
    newline = '\r\n' if b'\r\n' in original else '\n'
    boundary = re.search(r'^[ \t]*\[', text, re.MULTILINE)
    head, tail = (text[:boundary.start()], text[boundary.start():]) if boundary else (text, '')
    additions = []
    for key, value in settings.items():
        pattern = rf'^([ \t]*{re.escape(key)}[ \t]*=[ \t]*)[^\r\n#]*([^\r\n]*)(\r?)$'
        head, count = re.subn(pattern, lambda m: f'{m[1]}{value}' + (' ' + m[2] if m[2] else '') + m[3], head, flags=re.MULTILINE)
        if not count:
            additions.append(f'{key} = {value}{newline}')
    updated = ''.join(additions) + head + tail
    if tomllib.loads(updated) != dict(parsed, **settings):
        raise ValueError('Cannot safely edit this TOML layout; no changes written')
    encoding = 'utf-8-sig' if original.startswith(b'\xef\xbb\xbf') else 'utf-8'
    return updated.encode(encoding)


def replace_with_backup(path: Path, data: bytes, expected: bytes | None) -> bool:
    current = path.read_bytes() if path.exists() else None
    if current != expected:
        raise RuntimeError(f'File changed concurrently: {path}')
    if current == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    if current is not None:
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = path.with_name(f'{path.name}.bak-{stamp}')
        with backup.open('xb') as stream:
            stream.write(current)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        # Check again after preparation to avoid overwriting a detected external edit.
        if (path.read_bytes() if path.exists() else None) != current:
            raise RuntimeError(f'File changed concurrently: {path}')
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)
    return True


def manage(home: Path, settings: dict[str, int], install: bool, dry_run: bool) -> None:
    home = home.expanduser().resolve()
    operations = []
    if settings:
        config = home / 'config.toml'
        old = config.read_bytes() if config.exists() else None
        operations.append((config, prepare_config(old or b'', settings), old))
    if install:
        for source in sorted(SKILL_SOURCE.rglob('*')):
            if source.is_file():
                target = home / 'skills' / 'rolling-context' / source.relative_to(SKILL_SOURCE)
                old = target.read_bytes() if target.exists() else None
                operations.append((target, source.read_bytes(), old))
    for target, new, old in operations:
        changed = old != new
        if changed and not dry_run:
            replace_with_backup(target, new, old)
        status = 'would update' if dry_run and changed else 'updated' if changed else 'unchanged'
        print(f'{status}: {target}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, action='append', help='Codex home; repeat for multiple profiles')
    parser.add_argument('--install', action='store_true', help='Install/update the skill')
    parser.add_argument('--window', type=int, help='Configured model context window in tokens')
    parser.add_argument('--disable-post-turn', action='store_true', help='Disable turn-end compaction only (Codex 0.162.1)')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if not (args.install or args.window is not None or args.disable_post_turn):
        parser.error('Specify --install, --window, or --disable-post-turn')
    if args.window is not None and args.window <= 0:
        parser.error('--window must be positive')
    settings = {}
    if args.window is not None:
        settings['model_context_window'] = args.window
    if args.disable_post_turn:
        settings['model_post_turn_compact_threshold_percent'] = 0
        print('Turn-end compaction disabled; main native auto-compaction remains enabled.')
    homes = args.home or [Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex')]
    for home in dict.fromkeys(homes):
        manage(home, settings, args.install, args.dry_run)


if __name__ == '__main__':
    main()
