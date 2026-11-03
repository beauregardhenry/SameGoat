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


if __name__ == "__main__":
    for v in PALETTES:
        open(os.path.join(HERE, f"icon-{v}.svg"), "w").write(ios(v))
    open(os.path.join(HERE, "icon-mac.svg"), "w").write(mac())
    open(os.path.join(HERE, "wordmark.svg"), "w").write(wordmark())
    open(os.path.join(HERE, "wordmark-dark.svg"), "w").write(wordmark(dark=True))
    print("Wrote", ", ".join(f"icon-{v}.svg" for v in [*PALETTES, "mac"]), "and the wordmarks")
