"""
Parse all HIL log files and merge most common byte values per CAN ID into known_values.json.

HIL data takes priority over existing entries from other sources (e.g. loopybunny).
Entries from other sources are preserved if the CAN ID is not seen in HIL logs.

Log format (per line, ignoring # comments):
  timestamp_ms  can_id_hex  dlc  b0  b1  b2 ... (all hex, CAN ID is 3-digit zero-padded hex)

JSON keys are TRUE DECIMAL CAN IDs (e.g. 0x175 -> "373", 0x0A9 -> "169").

Run from repo root:
  python tools/extract_known_values.py
"""

import os
import sys
import json
from collections import defaultdict, Counter

LOG_DIR = r"E:\HIL_LOGS"
JSON_PATH = os.path.join(os.path.dirname(__file__), 'known_values.json')
MIN_OCCURRENCES = 5  # skip IDs seen fewer than this many times

# Accumulate: {can_id_decimal: {byte_pos: Counter}}
byte_counters = defaultdict(lambda: defaultdict(Counter))
id_count = Counter()

for fname in os.listdir(LOG_DIR):
    if fname.endswith('.err.log'):
        continue
    fpath = os.path.join(LOG_DIR, fname)
    try:
        with open(fpath, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split()
                if len(parts) < 3:
                    continue
                try:
                    can_id = int(parts[1], 16)   # log stores hex IDs (e.g. "0A9", "175")
                    dlc = int(parts[2])
                    bytes_data = [int(b, 16) for b in parts[3:3+dlc]]
                except (ValueError, IndexError):
                    continue
                if len(bytes_data) != dlc:
                    continue
                id_count[can_id] += 1
                for pos, val in enumerate(bytes_data):
                    byte_counters[can_id][pos][val] += 1
    except Exception as e:
        print(f"# Warning: {fname}: {e}", file=sys.stderr)

# Load existing JSON to preserve non-HIL entries.
# Re-key any entries whose key looks like a hex-as-decimal value (legacy format):
#   Old keys were hex values stored as decimal strings (e.g. "175" meant 0x175=373).
#   New format: keys are true decimal CAN IDs.
# Heuristic: if the same key reinterpreted as hex differs from itself as decimal,
#   and the hex interpretation produces a plausible CAN ID (<= 0x7FF = 2047), rekey it.
existing_raw = {}
if os.path.exists(JSON_PATH):
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        existing_raw = json.load(f)

meta = existing_raw.get('_meta', {
    "description": "Known typical byte values per CAN ID. Merged from HIL logs and loopybunny reference.",
    "sources": {
        "hil": r"E:\HIL_LOGS\ — captured on E90 LCI N47 bench, most common value per byte position",
        "loopybunny": "https://www.loopybunny.co.uk/CarPC/k_can.html — BMW X1 E84 reference (2012)"
    },
    "format": "TRUE DECIMAL CAN ID -> { bytes: [b0..bN hex], source: str, count: int|null }"
})

def rekey_if_needed(key_str):
    """Convert legacy hex-as-decimal key to true decimal key."""
    try:
        as_dec = int(key_str)       # the stored value treated as decimal
        as_hex = int(key_str, 16)   # the stored value treated as hex
    except ValueError:
        return key_str
    # If the value is a valid 3-digit hex CAN ID and differs when reinterpreted
    if as_hex != as_dec and as_hex <= 0x7FF and len(key_str) == 3:
        return str(as_hex)
    return key_str

existing = {}
for key, val in existing_raw.items():
    if key == '_meta':
        continue
    new_key = rekey_if_needed(key)
    # If two keys map to the same new key, prefer hil source
    if new_key in existing:
        if existing[new_key].get('source') != 'hil' and val.get('source') == 'hil':
            existing[new_key] = val
    else:
        existing[new_key] = val

# Build output: start with existing (rekeyed), overwrite with fresh HIL data
output = {'_meta': meta}
for key, val in existing.items():
    output[key] = val

hil_count = 0
for can_id in sorted(byte_counters.keys()):
    if id_count[can_id] < MIN_OCCURRENCES:
        continue
    byte_dict = byte_counters[can_id]
    max_pos = max(byte_dict.keys())
    vals = []
    for pos in range(max_pos + 1):
        if pos in byte_dict:
            most_common = byte_dict[pos].most_common(1)[0][0]
            vals.append('0x{:02X}'.format(most_common))
        else:
            vals.append('0x00')
    output[str(can_id)] = {
        'bytes': vals,
        'source': 'hil',
        'count': id_count[can_id]
    }
    hil_count += 1

# Write sorted by numeric CAN ID key (_meta first)
sorted_output = {'_meta': output['_meta']}
for key in sorted(output.keys(), key=lambda k: int(k) if k != '_meta' else -1):
    if key != '_meta':
        sorted_output[key] = output[key]

with open(JSON_PATH, 'w', encoding='utf-8') as f:
    json.dump(sorted_output, f, indent=2)

total = len(sorted_output) - 1
print(f"Written {total} entries to {JSON_PATH} ({hil_count} from HIL, {total - hil_count} from other sources)")
