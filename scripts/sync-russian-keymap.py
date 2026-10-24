"""Add Russian physical-key equivalents to the effective Yazi keymaps."""
import argparse
import itertools
import json
from pathlib import Path
import re
import tomllib

LOWER = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
RUSSIAN = "йцукенгшщзхъфывапролджэячсмитьбюё"
UPPER = 'QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>~'
KEYS = dict(zip(LOWER + UPPER, RUSSIAN + RUSSIAN.upper(), strict=True))
MARKER = "[RU alias] "


def russian(key):
    if len(key) == 1:
        return KEYS.get(key, key)
    match = re.fullmatch(r"<((?:[SCAD]-)*)(.)>", key)
    return f"<{match[1]}{KEYS.get(match[2], match[2])}>" if match else key


def sequence(on):
    return tuple(on if isinstance(on, list) else [on])


def generate(config, defaults):
    config = {layer: {key: [item for item in value if not item.get('desc', '').startswith(MARKER)]
                       for key, value in section.items()} for layer, section in config.items()}
    for layer, preset in defaults.items():
        section = config.setdefault(layer, {})
        effective = section.get('prepend_keymap', []) + section.get('keymap', preset['keymap']) + section.get('append_keymap', [])
        # Keep the first binding, matching Yazi's custom-before-default precedence.
        bindings = {}
        for item in effective:
            if item.get('for', 'windows') in ('windows',):
                bindings.setdefault(sequence(item['on']), item)
        aliases = {}
        for keys, item in bindings.items():
            variants = itertools.product(*(dict.fromkeys((key, russian(key))) for key in keys))
            for variant in variants:
                if variant == keys or variant in bindings or variant in aliases:
                    continue
                aliases[variant] = {**item, 'on': variant[0] if len(variant) == 1 else list(variant),
                                    'desc': MARKER + item.get('desc', ' '.join(keys))}
        section['prepend_keymap'] = section.get('prepend_keymap', []) + list(aliases.values())
    return config


def toml_value(value):
    if isinstance(value, dict):
        return '{ ' + ', '.join(f'{json.dumps(key)} = {toml_value(item)}' for key, item in value.items()) + ' }'
    if isinstance(value, list):
        return '[\n' + ''.join('  ' + toml_value(item) + ',\n' for item in value) + ']'
    return json.dumps(value, ensure_ascii=False)


def dump(config):
    return '# English and Russian physical-key bindings. Regenerate with sync-russian-keymap.py.\n' + '\n'.join(
        f'\n[{layer}]\n' + '\n'.join(f'{key} = {toml_value(value)}' for key, value in section.items()) + '\n'
        for layer, section in config.items())


def self_test():
    assert russian('t') == 'е' and russian('N') == 'Т' and russian('<C-o>') == '<C-щ>'
    assert russian('<S-Enter>') == '<S-Enter>' and russian('[') == 'х'
    defaults = {'mgr': {'keymap': [{'on': 'n', 'run': 'find_arrow'}, {'on': ['g', 'h'], 'run': 'cd ~'}]}}
    custom = {'mgr': {'prepend_keymap': [{'on': 'n', 'run': 'create'}]}}
    result = generate(custom, defaults)
    rows = {sequence(row['on']): row['run'] for row in result['mgr']['prepend_keymap']}
    assert rows[('т',)] == 'create' and rows[('п', 'р')] == rows[('g', 'р')] == 'cd ~'
    assert generate(result, defaults) == result
    assert tomllib.loads(dump(result)) == result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('defaults', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    self_test()
    source = tomllib.loads(args.config.read_text(encoding='utf-8-sig'))
    defaults = tomllib.loads(args.defaults.read_text(encoding='utf-8-sig'))
    result = generate(source, defaults)
    if args.check:
        assert result == source, 'Russian key aliases are missing or stale; regenerate them'
    else:
        output = args.output or args.config
        output.write_text(dump(result), encoding='utf-8')
    print(json.dumps({layer: sum(item.get('desc', '').startswith(MARKER) for item in section['prepend_keymap'])
                      for layer, section in result.items()}))
