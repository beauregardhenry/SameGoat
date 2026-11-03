"""Writes the Same Goat icon SVGs (light, dark, tinted, macOS) into docs/brand.

The artwork is drawn on a 180-unit tile and scaled up, so every variant shares one drawing.
Render them to PNGs with scripts/render-icons.sh.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

PALETTES = {
    "light":  dict(bg1="#5CC4D3", bg2="#2C8CA0", face="#FFFFFF", horn="#8C5A1E", cheek="#F8C1B6",
                   muzzle="#F6D9CF", nose="#8A3B2E", eye="#2B2B2B", hull="#E8604C", rim="#C9483A",
                   stripe="#FFFFFF", wave="#FFFFFF"),
    "dark":   dict(bg1="#173E4A", bg2="#0A1F26", face="#F4F1EA", horn="#C08A4A", cheek="#E9A99C",
                   muzzle="#E8CFC4", nose="#7A3328", eye="#1B1B1B", hull="#E8604C", rim="#B9473A",
                   stripe="#F4F1EA", wave="#5CC4D3"),
    "tinted": dict(bg1="#000000", bg2="#000000", face="#FFFFFF", horn="#8A8A8A", cheek="#D6D6D6",
                   muzzle="#E4E4E4", nose="#4A4A4A", eye="#202020", hull="#A8A8A8", rim="#8A8A8A",
                   stripe="#FFFFFF", wave="#C8C8C8"),
}


def art(p):
    """The goat peeking out of its boat, on a 180x180 tile."""
    return f"""
  <g transform="translate(90,76) scale(0.82)">
    <path d="M-20 -36 Q-30 -60 -46 -62" stroke="{p['horn']}" stroke-width="9" fill="none" stroke-linecap="round"/>
    <path d="M20 -36 Q30 -60 46 -62" stroke="{p['horn']}" stroke-width="9" fill="none" stroke-linecap="round"/>
    <ellipse cx="-40" cy="-10" rx="21" ry="10" transform="rotate(34 -40 -10)" fill="{p['face']}"/>
    <ellipse cx="41" cy="-16" rx="21" ry="10" transform="rotate(-8 41 -16)" fill="{p['face']}"/>
    <ellipse cx="-41" cy="-9" rx="12" ry="4.5" transform="rotate(34 -41 -9)" fill="{p['cheek']}"/>
    <ellipse cx="42" cy="-16" rx="12" ry="4.5" transform="rotate(-8 42 -16)" fill="{p['cheek']}"/>
    <path d="M-30 -20 Q-32 -42 0 -42 Q32 -42 30 -20 L24 22 Q18 40 0 40 Q-18 40 -24 22 Z" fill="{p['face']}"/>
    <path d="M-10 -40 Q-6 -50 0 -42 Q6 -51 10 -40 Z" fill="{p['face']}"/>
    <circle cx="-20" cy="9" r="5.5" fill="{p['cheek']}"/><circle cx="20" cy="9" r="5.5" fill="{p['cheek']}"/>
    <ellipse cx="0" cy="24" rx="18" ry="12" fill="{p['muzzle']}"/>
    <circle cx="-6" cy="21" r="2.5" fill="{p['nose']}"/><circle cx="6" cy="21" r="2.5" fill="{p['nose']}"/>
    <path d="M-19 -5 Q-13 -11 -7 -5" stroke="{p['eye']}" stroke-width="3.5" fill="none" stroke-linecap="round"/>
    <circle cx="13" cy="-5" r="6" fill="{p['eye']}"/><circle cx="15" cy="-7" r="2" fill="#FFFFFF"/>
  </g>
  <path d="M26 97 Q90 111 154 97 L136 134 Q90 142 44 134 Z" fill="{p['hull']}" stroke="{p['hull']}" stroke-width="4" stroke-linejoin="round"/>
  <path d="M24 96 Q90 111 156 96" stroke="{p['rim']}" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M38 114 Q90 126 142 114" stroke="{p['stripe']}" stroke-width="5" fill="none" stroke-linecap="round"/>
  <path d="M30 154 q10 -7 20 0 t20 0 t20 0 t20 0 t20 0 t20 0" stroke="{p['wave']}" stroke-width="4.5" fill="none" stroke-linecap="round"/>
"""


def tile(p, name):
    return f"""<linearGradient id="{name}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{p['bg1']}"/><stop offset="1" stop-color="{p['bg2']}"/>
    </linearGradient>"""


def ios(variant):
    p = PALETTES[variant]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 180 180">
  <defs>{tile(p, 'bg')}</defs>
  <rect width="180" height="180" fill="url(#bg)"/>{art(p)}</svg>
"""


def mac():
    # macOS icons sit on a rounded tile inside the canvas, with room for a soft shadow.
    p = PALETTES["light"]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>{tile(p, 'bg')}
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.28"/>
    </filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)" filter="url(#shadow)"/>
  <g transform="translate(100,100) scale({824/180:.5f})">{art(p)}</g>
</svg>
"""


def wordmark(dark=False):
    """The icon beside the name and tagline, for the website, App Store art and printouts."""
    p = PALETTES["light"]
    ink, soft = ("#FFFFFF", "#A9DCE4") if dark else ("#17414C", "#3E7F8C")
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="480" viewBox="0 0 1600 480">
  <defs>{tile(p, 'bg')}
    <clipPath id="tile"><rect x="40" y="40" width="400" height="400" rx="90"/></clipPath>
  </defs>
  <g clip-path="url(#tile)">
    <rect x="40" y="40" width="400" height="400" fill="url(#bg)"/>
    <g transform="translate(40,40) scale({400/180:.5f})">{art(p)}</g>
  </g>
  <text x="510" y="262" font-family="Arial Rounded MT Bold, ui-rounded, sans-serif"
        font-size="160" fill="{ink}" letter-spacing="-2">Same Goat</text>
  <text x="516" y="352" font-family="Arial Rounded MT Bold, ui-rounded, sans-serif"
        font-size="54" fill="{soft}">We\u2019re all in the same goat.</text>
</svg>
"""


POSES = ("cheer", "party", "sleep", "curious")


def mascot(pose):
    """The goat in its boat on a transparent background, for moments inside the app.

    A thin outline keeps the white face visible on light screens.
    """
    ink, face, horn, cheek, muzzle, nose, hull, rim = (
        "#5A3A1A", "#FFFFFF", "#8C5A1E", "#F8C1B6", "#F6D9CF", "#8A3B2E", "#E8604C", "#C9483A")
    line = f'stroke="{ink}" stroke-width="2.5" stroke-linejoin="round"'
    left_ear, right_ear = (34, -8) if pose != "sleep" else (48, 30)
    if pose == "cheer":
        left_ear, right_ear = (14, -24)
    eyes = {
        "cheer": f'''<path d="M-19 -4 Q-13 -12 -7 -4" stroke="{ink}" stroke-width="3.5" fill="none" stroke-linecap="round"/>
    <path d="M7 -4 Q13 -12 19 -4" stroke="{ink}" stroke-width="3.5" fill="none" stroke-linecap="round"/>''',
        "sleep": f'''<path d="M-19 -6 Q-13 0 -7 -6" stroke="{ink}" stroke-width="3.5" fill="none" stroke-linecap="round"/>
    <path d="M7 -6 Q13 0 19 -6" stroke="{ink}" stroke-width="3.5" fill="none" stroke-linecap="round"/>''',
    }.get(pose, f'''<circle cx="-13" cy="-5" r="6" fill="#2B2B2B"/><circle cx="13" cy="-5" r="6" fill="#2B2B2B"/>
    <circle cx="-11" cy="-7" r="2" fill="#FFFFFF"/><circle cx="15" cy="-7" r="2" fill="#FFFFFF"/>''')
    mouth = {
        "cheer": f'<path d="M-8 24 Q0 36 8 24 Z" fill="{nose}"/>',
        "party": f'<path d="M-8 24 Q0 36 8 24 Z" fill="{nose}"/>',
        "curious": f'<circle cx="0" cy="28" r="3" fill="{nose}"/>',
        "sleep": f'<path d="M-5 27 Q0 30 5 27" stroke="{nose}" stroke-width="2.5" fill="none" stroke-linecap="round"/>',
    }[pose]
    extra_head = ""
    if pose == "curious":
        extra_head = f'<path d="M6 -17 Q13 -24 21 -18" stroke="{ink}" stroke-width="3" fill="none" stroke-linecap="round"/>'
    if pose == "party":
        extra_head = f'''<g transform="rotate(-14 0 -40)">
      <path d="M-16 -40 L0 -84 L16 -40 Z" fill="#F5B82E" {line}/>
      <path d="M-11 -54 L11 -54 M-6 -68 L6 -68" stroke="#E8604C" stroke-width="4" stroke-linecap="round"/>
      <circle cx="0" cy="-86" r="6" fill="#4FB3A9" {line}/>
    </g>'''
    around = {
        "cheer": '''<path d="M30 30 l3 8 8 3 -8 3 -3 8 -3 -8 -8 -3 8 -3 Z" fill="#F5B82E"/>
  <path d="M148 22 l2.5 6 6 2.5 -6 2.5 -2.5 6 -2.5 -6 -6 -2.5 6 -2.5 Z" fill="#F5B82E"/>
  <path d="M154 64 l2 5 5 2 -5 2 -2 5 -2 -5 -5 -2 5 -2 Z" fill="#4FB3A9"/>''',
        "party": '''<rect x="26" y="34" width="7" height="7" rx="1.5" fill="#E8604C" transform="rotate(20 29 37)"/>
  <rect x="148" y="30" width="7" height="7" rx="1.5" fill="#4FB3A9" transform="rotate(-25 151 33)"/>
  <circle cx="40" cy="70" r="4" fill="#F5B82E"/><circle cx="146" cy="70" r="4" fill="#E8604C"/>
  <rect x="134" y="12" width="6" height="6" rx="1.5" fill="#F5B82E" transform="rotate(40 137 15)"/>''',
        "sleep": f'''<path d="M128 28 h12 l-12 13 h12" stroke="#4FB3A9" stroke-width="3.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M146 10 h8 l-8 9 h8" stroke="#4FB3A9" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>''',
        "curious": '''<path d="M134 22 Q134 10 145 10 Q156 10 156 20 Q156 28 146 31 L146 37" stroke="#4FB3A9" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="146" cy="47" r="3.5" fill="#4FB3A9"/>''',
    }[pose]
    tilt = {"curious": -8, "sleep": 6}.get(pose, 0)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="360" height="364" viewBox="0 -12 180 182">
  {around}
  <g transform="translate(90,74) scale(0.82) rotate({tilt})">
    <path d="M-20 -36 Q-30 -60 -46 -62" stroke="{horn}" stroke-width="9" fill="none" stroke-linecap="round"/>
    <path d="M20 -36 Q30 -60 46 -62" stroke="{horn}" stroke-width="9" fill="none" stroke-linecap="round"/>
    <ellipse cx="-40" cy="-10" rx="21" ry="10" transform="rotate({left_ear} -40 -10)" fill="{face}" {line}/>
    <ellipse cx="40" cy="-10" rx="21" ry="10" transform="rotate({-right_ear} 40 -10)" fill="{face}" {line}/>
    <path d="M-30 -20 Q-32 -42 0 -42 Q32 -42 30 -20 L24 22 Q18 40 0 40 Q-18 40 -24 22 Z" fill="{face}" {line}/>
    <circle cx="-21" cy="6" r="5.5" fill="{cheek}"/><circle cx="21" cy="6" r="5.5" fill="{cheek}"/>
    <ellipse cx="0" cy="16" rx="17" ry="10" fill="{muzzle}"/>
    <circle cx="-6" cy="13" r="2.5" fill="{nose}"/><circle cx="6" cy="13" r="2.5" fill="{nose}"/>
    {mouth}
    {eyes}
    {extra_head}
  </g>
  <path d="M26 101 Q90 115 154 101 L136 138 Q90 146 44 138 Z" fill="{hull}" {line.replace(ink, rim)}/>
  <path d="M24 100 Q90 115 156 100" stroke="{rim}" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M38 118 Q90 130 142 118" stroke="#FFFFFF" stroke-width="5" fill="none" stroke-linecap="round"/>
  <path d="M30 158 q10 -7 20 0 t20 0 t20 0 t20 0 t20 0 t20 0" stroke="#4FB3A9" stroke-width="4.5" fill="none" stroke-linecap="round"/>
</svg>
"""


if __name__ == "__main__":
    for v in PALETTES:
        open(os.path.join(HERE, f"icon-{v}.svg"), "w").write(ios(v))
    open(os.path.join(HERE, "icon-mac.svg"), "w").write(mac())
    open(os.path.join(HERE, "wordmark.svg"), "w").write(wordmark())
    open(os.path.join(HERE, "wordmark-dark.svg"), "w").write(wordmark(dark=True))
    for pose in POSES:
        open(os.path.join(HERE, f"goat-{pose}.svg"), "w").write(mascot(pose))
    print("Wrote", ", ".join(f"icon-{v}.svg" for v in [*PALETTES, "mac"]), "and the wordmarks")
