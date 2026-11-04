#!/usr/bin/env python3
"""Builds the small public site (a landing page and the privacy policy) from docs/.

    python3 scripts/build-site.py <output-dir>

The output is what the gh-pages branch serves, so only these pages are public; the rest of
docs/ stays out of it. The policy page is rendered from docs/app-store/privacy-policy.md, so
edit that file and rebuild rather than editing the HTML.
"""
import html
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]).resolve()

STYLE = """
:root{--bg:#fff;--fg:#17313a;--muted:#4f6a73;--accent:#1f7d90;--card:#f1f7f9}
@media (prefers-color-scheme:dark){:root{--bg:#10262d;--fg:#e8f3f6;--muted:#a9c3cb;--accent:#5cc4d3;--card:#173640}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:17px/1.65 ui-rounded,"SF Pro Rounded",system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:42rem;margin:0 auto;padding:2rem 1.25rem 4rem}
h1{font-size:2rem;line-height:1.2;margin:.2rem 0 .4rem}
h2{font-size:1.25rem;margin:2rem 0 .4rem}
p,li{color:var(--fg)}
a{color:var(--accent)}
.muted{color:var(--muted)}
.brand{display:flex;align-items:center;gap:.75rem;margin-bottom:1.5rem}
.brand img{width:56px;height:56px;border-radius:13px}
.brand a{font-weight:700;text-decoration:none;color:var(--fg);font-size:1.15rem}
.card{background:var(--card);border-radius:16px;padding:1.25rem 1.4rem;margin:1.5rem 0}
footer{margin-top:3rem;color:var(--muted);font-size:.9rem}
"""


def page(title, body, description, depth=0):
    root = "../" * depth
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(description)}">
<link rel="icon" href="{root}icon.png">
<style>{STYLE}</style></head>
<body><main>
<div class="brand"><img src="{root}icon.png" alt=""><a href="{root}">Same Goat</a></div>
{body}
<footer>We're all in the same goat.</footer>
</main></body></html>
"""


def inline(text):
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\w)_(.+?)_(?!\w)", r"<em>\1</em>", text)
    text = re.sub(r"\[(.+?)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', text)
    return re.sub(r"(?<![\"'>=])(https?://[^\s<)]+[^\s<).,])", r'<a href="\1">\1</a>', text)


def markdown(source):
    out, items, para = [], [], []

    def flush():
        nonlocal items, para
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items = []
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para = []

    for line in source.splitlines():
        if line.startswith("# "):
            flush(); out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("## "):
            flush(); out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("- "):
            if para: flush()
            items.append(line[2:])
        elif not line.strip():
            flush()
        elif items and line.startswith("  "):
            items[-1] += " " + line.strip()
        else:
            if items: flush()
            para.append(line.strip())
    flush()
    return "\n".join(out)


policy = (ROOT / "docs/app-store/privacy-policy.md").read_text()
if OUT.exists():
    for child in OUT.iterdir():
        if child.name != ".git":
            shutil.rmtree(child) if child.is_dir() else child.unlink()
(OUT / "privacy").mkdir(parents=True, exist_ok=True)
shutil.copy(ROOT / "docs/brand/icon.png", OUT / "icon.png")
(OUT / ".nojekyll").write_text("")

(OUT / "privacy/index.html").write_text(page(
    "Same Goat privacy policy", markdown(policy),
    "What Same Goat stores, where it lives, and what it never does. Short version: your family's data stays with your family.",
    depth=1))

landing = """
<h1>We're all in the same goat.</h1>
<p class="muted">Same Goat is a chore chart for families. Kids finish chores and earn points, parents confirm,
and everyone pitches in. It works on iPhone, iPad and Mac.</p>
<div class="card">
<p><strong>Private by design.</strong> Your family's chores, points, photos and moods live in your own iCloud account.
There are no ads, no tracking, no AI services and no accounts to create.</p>
<p><a href="privacy/">Read the privacy policy</a></p>
</div>
<p>Questions or ideas? <a href="https://github.com/beauregardhenry/SameGoat/issues">Open an issue</a>.</p>
"""
(OUT / "index.html").write_text(page("Same Goat: Family Chores", landing,
    "Same Goat is a private chore chart for families. Kids earn points, parents confirm, and everyone pitches in."))
print("Built", OUT)
