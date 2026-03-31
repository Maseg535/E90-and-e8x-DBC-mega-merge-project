#!/usr/bin/env python3
"""
BMW E90 Dashboard Icon Library Builder
Downloads SVGs from Wikimedia Commons and generates HTML + MD reference tables.
"""

import os
import re
import time
import urllib.request
import urllib.error
import urllib.parse
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SVG_DIR = os.path.join(SCRIPT_DIR, "svg")
os.makedirs(SVG_DIR, exist_ok=True)

# -----------------------------------------------------------------------
# Icon catalogue — (wikimedia_filename, local_name, description, color, bmw_context)
# color: red | amber | green | blue | white
# -----------------------------------------------------------------------
ICONS = [
    # Engine / Drivetrain
    ("Motorkontrollleuchte.svg",               "engine_mil.svg",            "Engine Management Light (MIL / EML)",    "amber",  "Check engine / EML fault — emissions or engine management system"),
    ("Kontrollleuchte Oeldruck.svg",            "oil_pressure.svg",          "Engine Oil Pressure Warning",            "red",    "Oil pressure critically low — stop engine immediately"),
    ("Kontrollleuchte Generator.svg",           "battery_charge.svg",        "Battery / Alternator Charging Fault",    "red",    "Alternator not charging — drive to workshop"),
    ("Electrical fault.svg",                   "electrical_fault.svg",      "General Electrical Fault",               "amber",  "Electrical system fault — various modules"),
    ("Immobiliser.svg",                        "immobiliser.svg",           "Immobiliser / EWS Active",               "red",    "EWS 3.3/4.0 immobiliser indicator — stays on if armed"),
    ("Kontrollleuchte Wegfahrsperre.svg",       "ewslock.svg",               "Anti-Theft / Immobiliser Warning",       "red",    "EWS immobiliser triggered or fault"),

    # Braking
    ("B01 Brake failure.svg",                  "brake_warning.svg",         "Brake System Warning (Critical)",        "red",    "Brake circuit failure — stop safely immediately"),
    ("B02 Parking brake indication.svg",        "parking_brake.svg",         "Parking Brake / Handbrake",              "red",    "Handbrake applied or EPB fault"),
    ("B05 Anti-lock brake system failure.svg",  "abs_warning.svg",           "ABS Warning",                            "amber",  "ABS malfunction — normal braking retained"),
    ("B10 Worn brake linings.svg",              "brake_wear.svg",            "Brake Pad Wear Indicator",               "amber",  "CBS brake service due — pads worn"),
    ("B13 Brake fluid level low.svg",           "brake_fluid.svg",           "Brake Fluid Level Low",                  "amber",  "Brake fluid reservoir below minimum"),
    ("Braking system alert.svg",               "brake_alert.svg",           "Braking System Alert",                   "red",    "General braking system alert"),

    # Safety
    ("Kontrollleuchte Airbag.svg",              "airbag_srs.svg",            "Airbag / SRS Warning",                   "red",    "Airbag or seatbelt pretensioner system fault"),
    ("Kontrollleuchte Gurtwarnung.svg",         "seatbelt.svg",              "Seatbelt Reminder",                      "red",    "Driver or passenger seatbelt not fastened"),

    # Stability / Traction
    ("Kontrollleuchte ESP.svg",                 "dsc_esp.svg",               "DSC / ESP Stability Control",            "amber",  "DSC off, DTC mode, or stability system fault"),
    ("Kontrollleuchte ESP 2.svg",               "dsc_esp2.svg",              "DSC / ESP (variant 2)",                  "amber",  "Alternative DSC symbol variant"),
    ("Kontrollleuchte TC.svg",                  "traction_control.svg",      "Traction Control (ASC/TC)",              "amber",  "ASC/TC active (flashing) or disabled/fault (steady)"),

    # Diesel specific
    ("Kontrollleuchte Vorgluehen.svg",          "glow_plug.svg",             "Glow Plug / Preheat Indicator",          "amber",  "Diesel preheat in progress (steady) or fault (flashing)"),
    ("Kontrollleuchte DPF.svg",                 "dpf.svg",                   "Diesel Particulate Filter (DPF)",        "amber",  "DPF regeneration required — take for motorway run"),

    # Tyres / Steering
    ("Warnlampe Druckverlust.svg",              "tyre_pressure.svg",         "Tyre Pressure Warning (iTPMS)",          "amber",  "Tyre pressure loss detected — check all tyres"),
    ("Kontrollleuchte Lenkhilfe.svg",           "power_steering.svg",        "Power Steering (EPS/EPAS) Fault",        "amber",  "Electric power steering system fault"),

    # Fuel / Fluids
    ("Kontrollleuchte Tanken.svg",              "fuel_low.svg",              "Fuel Level Low",                         "amber",  "Reserve fuel warning — approx. 8–12 L remaining"),
    ("Kontrollleuchte Waschwasserstand.svg",    "washer_fluid.svg",          "Washer Fluid Level Low",                 "amber",  "Screen wash reservoir low"),

    # Doors / Access — generic
    ("Kontrollleuchte Tuer offen.svg",          "door_open.svg",             "Any Door / Boot / Bonnet Open",          "red",    "Any door, boot or bonnet not fully closed (generic)"),
    # Doors / Access — individual (custom SVGs, no Wikimedia source)
    (None,                                      "door_front_left.svg",       "Front Left Door Open",                   "red",    "Front left (driver LHD / passenger RHD) door open"),
    (None,                                      "door_front_right.svg",      "Front Right Door Open",                  "red",    "Front right (passenger LHD / driver RHD) door open"),
    (None,                                      "door_rear_left.svg",        "Rear Left Door Open",                    "red",    "Rear left door open"),
    (None,                                      "door_rear_right.svg",       "Rear Right Door Open",                   "red",    "Rear right door open"),
    (None,                                      "trunk_open.svg",            "Trunk / Boot Open",                      "red",    "Boot/trunk lid not fully latched"),

    # Lighting indicators
    ("A01 High Beam Indicator.svg",             "high_beam.svg",             "High Beam (Main Beam) On",               "blue",   "Main beam headlights active"),
    ("A02 Low Beam Indicator.svg",              "low_beam.svg",              "Low Beam (Dipped Headlights) On",        "green",  "Dipped headlights active"),
    ("Kontrollleuchte Fahrlicht.svg",           "driving_lights.svg",        "Driving / Running Lights On",            "green",  "Driving lights indicator (alternate symbol variant)"),
    ("A05 Front fog light.svg",                 "fog_front.svg",             "Front Fog Light Active",                 "green",  "Front fog lights switched on"),
    ("A06 Rear fog light.svg",                  "fog_rear.svg",              "Rear Fog Light Active",                  "amber",  "Rear fog light switched on"),
    ("A08 Parking lights.svg",                  "parking_lights.svg",        "Parking / Sidelights On",                "green",  "Parking/side lights active"),
    ("Kontrollleuchte Standlicht.svg",          "sidelights_markers.svg",    "Sidelights / Marker Lights On",          "green",  "Position/marker/sidelights only — no driving lights"),
    ("A16L Left turn signal.svg",               "indicator_left.svg",        "Left Turn Signal",                       "green",  "Left indicator / turn signal flashing"),
    ("A16R Right turn signal.svg",              "indicator_right.svg",       "Right Turn Signal",                      "green",  "Right indicator / turn signal flashing"),
    ("A19 Hazard warning.svg",                  "hazard.svg",                "Hazard Warning Lights",                  "red",    "Hazard / emergency flashers active"),
    ("A27 Daytime running lights.svg",          "drl.svg",                   "Daytime Running Lights (DRL)",           "green",  "Automatic DRL active (LA light package or retrofit)"),
    ("A14 Exterior bulb failure.svg",           "bulb_failure.svg",          "Exterior Bulb Failure",                  "amber",  "One or more exterior lamps failed — CBS light check"),
    ("Leuchtweitenregulierung.svg",             "headlamp_levelling.svg",    "Headlamp Levelling / Range Control",     "amber",  "Automatic or manual headlamp levelling system fault"),

    # Driver assistance
    ("Cruise Control.svg",                     "cruise_control.svg",        "Cruise Control / Speed Limiter",         "green",  "Cruise control or speed limiter active"),
    ("A32 Bend lighting malfunction.svg",       "bend_lighting.svg",         "Adaptive Headlight Malfunction",         "amber",  "Adaptive/cornering headlight system fault"),
]

WIKIMEDIA_API = "https://commons.wikimedia.org/w/api.php"
HEADERS = {"User-Agent": "BMW-E90-IconLib/1.0 (internal; non-commercial)"}


def get_direct_urls(filenames: list) -> dict:
    """Use Wikimedia API to resolve File: titles → direct CDN URLs (up to 50 at a time)."""
    result = {}
    chunk_size = 50
    for i in range(0, len(filenames), chunk_size):
        chunk = filenames[i:i+chunk_size]
        titles = "|".join(f"File:{n}" for n in chunk)
        params = urllib.parse.urlencode({
            "action": "query",
            "titles": titles,
            "prop": "imageinfo",
            "iiprop": "url",
            "format": "json",
        })
        url = f"{WIKIMEDIA_API}?{params}"
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = json.loads(resp.read())
            pages = data.get("query", {}).get("pages", {})
            for page in pages.values():
                title = page.get("title", "").removeprefix("File:")
                ii = page.get("imageinfo", [{}])
                if ii and ii[0].get("url"):
                    result[title] = ii[0]["url"]
                    print(f"  [url]  {title}")
                else:
                    print(f"  [miss] {title} — no URL in API response")
        except Exception as e:
            print(f"  [API FAIL] chunk {i}: {e}")
        time.sleep(1.0)
    return result


def download_svg(url: str, local_path: str, label: str, retries: int = 4) -> bool:
    if os.path.exists(local_path):
        print(f"  [skip] {label} (already exists)")
        return True
    delay = 5
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            if b"<svg" not in data[:1024].lower() and b"<?xml" not in data[:64]:
                print(f"  [WARN] {label} — may not be SVG ({len(data)} bytes)")
            with open(local_path, "wb") as f:
                f.write(data)
            print(f"  [ok]   {label}")
            return True
        except urllib.error.HTTPError as e:
            if e.code == 429:
                retry_after = int(e.headers.get("Retry-After", delay))
                wait = max(retry_after, delay)
                print(f"  [429]  {label} — waiting {wait}s (attempt {attempt+1}/{retries})")
                time.sleep(wait)
                delay *= 2
            else:
                print(f"  [FAIL] {label}: HTTP {e.code}")
                return False
        except Exception as e:
            print(f"  [FAIL] {label}: {e}")
            return False
    print(f"  [GIVE UP] {label}")
    return False


def generate_html(icons, rel_svg="svg/") -> str:
    rows = ""
    for _wiki, local, desc, color, context in icons:
        badge_color = {
            "red": "#e74c3c", "amber": "#e67e22",
            "green": "#27ae60", "blue": "#2980b9", "white": "#95a5a6"
        }.get(color, "#888")
        rows += f"""
        <tr>
          <td class="icon-cell">
            <img src="{rel_svg}{local}" alt="{desc}" onerror="this.style.opacity='0.2'">
          </td>
          <td><a href="{rel_svg}{local}" target="_blank"><code>{local}</code></a></td>
          <td>{desc}</td>
          <td><span class="badge" style="background:{badge_color}">{color}</span></td>
          <td>{context}</td>
        </tr>"""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>BMW E90 Dashboard Icon Library</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font-family: system-ui, sans-serif; background: #111; color: #ddd; margin: 0; padding: 1rem 2rem; }}
  h1 {{ color: #fff; margin-bottom: .25rem; }}
  p.sub {{ color: #888; margin-top: 0; font-size: .9rem; }}
  table {{ border-collapse: collapse; width: 100%; font-size: .85rem; }}
  th {{ background: #1e1e1e; color: #aaa; text-transform: uppercase; font-size: .75rem;
        letter-spacing: .06em; padding: .6rem .8rem; text-align: left; border-bottom: 2px solid #333; }}
  tr:nth-child(even) {{ background: #181818; }}
  td {{ padding: .5rem .8rem; vertical-align: middle; border-bottom: 1px solid #222; }}
  td.icon-cell {{ width: 64px; text-align: center; }}
  td.icon-cell img {{ height: 40px; width: auto; max-width: 56px; filter: invert(1) brightness(.85); }}
  a {{ color: #5b9cf6; text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
  code {{ background: #2a2a2a; padding: .1rem .35rem; border-radius: 3px; font-size: .8rem; }}
  .badge {{ display: inline-block; padding: .15rem .5rem; border-radius: 3px;
             font-size: .72rem; font-weight: 700; color: #fff; letter-spacing: .04em; }}
  @media (prefers-color-scheme: light) {{
    body {{ background: #f5f5f5; color: #222; }}
    th {{ background: #e0e0e0; color: #555; }}
    tr:nth-child(even) {{ background: #ebebeb; }}
    td.icon-cell img {{ filter: none; }}
    code {{ background: #e8e8e8; }}
  }}
</style>
</head>
<body>
<h1>BMW E90 Dashboard Icon Library</h1>
<p class="sub">
  {len(icons)} icons &bull; SVGs sourced from
  <a href="https://commons.wikimedia.org/wiki/Category:Dashboard_SVG_icons" target="_blank">Wikimedia Commons</a>
  (public domain / CC0) &bull; Target: E90 LCI N47D20O1 diesel, ZF 6HP19
</p>
<table>
  <thead>
    <tr><th>Icon</th><th>File</th><th>Description</th><th>Indicator colour</th><th>BMW E90 context</th></tr>
  </thead>
  <tbody>{rows}
  </tbody>
</table>
</body>
</html>
"""


def generate_md(icons, rel_svg="svg/") -> str:
    header = (
        "# BMW E90 Dashboard Icon Library\n\n"
        f"{len(icons)} icons — Wikimedia-sourced SVGs: "
        "[Category:Dashboard SVG icons](https://commons.wikimedia.org/wiki/Category:Dashboard_SVG_icons) "
        "(public domain / CC0); door/trunk icons: custom SVG.  \n"
        "Target vehicle: E90 LCI N47D20O1 diesel, ZF 6HP19.\n\n"
        "| Icon | File | Description | Colour | BMW E90 Context |\n"
        "|------|------|-------------|--------|-----------------|\n"
    )
    rows = ""
    for _wiki, local, desc, color, context in icons:
        img = f"![{desc}]({rel_svg}{local})"
        link = f"[`{local}`]({rel_svg}{local})"
        rows += f"| {img} | {link} | {desc} | {color} | {context} |\n"
    return header + rows


def main():
    # Resolve CDN URLs only for Wikimedia-sourced icons (wiki_name != None)
    wiki_icons = [(w, l) for w, l, *_ in ICONS if w is not None]
    print(f"Resolving CDN URLs for {len(wiki_icons)} Wikimedia icons …\n")
    url_map = get_direct_urls([w for w, _ in wiki_icons])

    print(f"\nDownloading SVG icons to {SVG_DIR} …\n")
    failed = []
    for wiki_name, local_name, *_ in ICONS:
        local_path = os.path.join(SVG_DIR, local_name)
        if wiki_name is None:
            # Custom SVG — must already exist
            if os.path.exists(local_path):
                print(f"  [custom] {local_name}")
            else:
                print(f"  [MISSING custom] {local_name}")
                failed.append(local_name)
            continue
        cdn_url = url_map.get(wiki_name)
        if not cdn_url:
            print(f"  [SKIP] {wiki_name} — no CDN URL resolved")
            failed.append(wiki_name)
            continue
        ok = download_svg(cdn_url, local_path, local_name)
        if not ok:
            failed.append(wiki_name)
        time.sleep(2.0)   # be polite to Wikimedia CDN

    print(f"\nDownload complete — {len(ICONS)-len(failed)}/{len(ICONS)} succeeded.")
    if failed:
        print("Failed:", failed)

    html_path = os.path.join(SCRIPT_DIR, "index.html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(generate_html(ICONS))
    print(f"Generated: {html_path}")

    md_path = os.path.join(SCRIPT_DIR, "README.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(generate_md(ICONS))
    print(f"Generated: {md_path}")


if __name__ == "__main__":
    main()
