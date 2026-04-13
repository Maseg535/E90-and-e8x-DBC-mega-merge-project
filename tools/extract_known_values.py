"""
Parse all HIL log files and merge most common byte values per CAN ID into known_values.json.

HIL data takes priority over existing entries from other sources (e.g. loopybunny).
Entries from other sources are preserved if the CAN ID is not seen in HIL logs.

Log format (per line, ignoring # comments):
  timestamp_ms  can_id_decimal  dlc  b0  b1  b2 ... (hex bytes)

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

# Accumulate: {can_id: {byte_pos: Counter}}
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
                    can_id = int(parts[1])
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

# Load existing JSON to preserve non-HIL entries
existing = {}
if os.path.exists(JSON_PATH):
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        existing = json.load(f)

meta = existing.get('_meta', {
    "description": "Known typical byte values per CAN ID. Merged from HIL logs and loopybunny reference.",
    "sources": {
        "hil": r"E:\HIL_LOGS\ — captured on E90 LCI N47 bench, most common value per byte position",
        "loopybunny": "https://www.loopybunny.co.uk/CarPC/k_can.html — BMW X1 E84 reference (2012)"
    },
    "format": "decimal CAN ID -> { bytes: [b0..bN hex], source: str, count: int|null }"
})

# Start output with all existing entries (non-HIL preserved as-is)
output = {'_meta': meta}
for key, val in existing.items():
    if key == '_meta':
        continue
    output[key] = val

# Overwrite with HIL data (HIL takes priority)
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

total = len(sorted_output) - 1  # exclude _meta
print(f"Written {total} entries to {JSON_PATH} ({hil_count} from HIL, {total - hil_count} from other sources)")
