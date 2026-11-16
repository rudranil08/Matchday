#!/usr/bin/env python3
"""Builds the web versions of Matchday's legal pages from the same text the app shows
(Matchday/Legal/LegalInfo.swift). Run after changing that file:  python3 legal/build.py
Host the resulting folder anywhere (GitHub Pages, Firebase Hosting...) and put the URLs in LegalInfo.
Fonts are self-hosted from legal/fonts: no Google Fonts or other font CDN."""
import html, pathlib, re

root = pathlib.Path(__file__).resolve().parent
src = (root.parent / "Matchday/Legal/LegalInfo.swift").read_text()

def const(name):
    return re.search(rf'static let {name} = "(.*?)"', src).group(1)

operator, contact, effective = const("operatorName"), const("contactEmail"), const("effectiveDate")
values = {
    r"\(LegalInfo.who)": operator or "the Matchday team",
    r"\(LegalInfo.contact)": contact or "the support link on Matchday’s App Store page",
    r"\(LegalInfo.effectiveDate)": effective,
}

def clean(text):
    for k, v in values.items():
        text = text.replace(k, v)
    text = re.sub(r"\\\n\s*", "", text)          # Swift line continuations
    return "\n".join(line.strip() for line in text.strip().splitlines())

def paragraphs(text):
    out, bullets = [], []
    for line in clean(text).splitlines():
        if line.startswith("• "):
            bullets.append(f"<li>{html.escape(line[2:])}</li>")
            continue
        if bullets:
            out.append("<ul>" + "".join(bullets) + "</ul>"); bullets = []
        if line:
            out.append(f"<p>{html.escape(line)}</p>")
    if bullets:
        out.append("<ul>" + "".join(bullets) + "</ul>")
    return "\n".join(out)

docs = re.findall(r'static let (\w+) = LegalDoc\(id: "(\w+)", title: "(.*?)", intro: """(.*?)""", sections: \[(.*?)\n    \]\)', src, re.S)
nav = " · ".join(f'<a href="{d[1]}.html">{html.escape(d[2])}</a>' for d in docs)
style = """
@font-face { font-family: "DM Sans"; src: url(fonts/DMSans_400Regular.ttf); font-weight: 400; }
@font-face { font-family: "DM Sans"; src: url(fonts/DMSans_600SemiBold.ttf); font-weight: 600; }
@font-face { font-family: "DM Sans"; src: url(fonts/DMSans_700Bold.ttf); font-weight: 700; }
@font-face { font-family: "Archivo Expanded"; src: url(fonts/ArchivoExpanded-800.ttf); font-weight: 800; }
:root { --bg: #eef1f5; --surface: #fff; --ink: #121726; --muted: #5b6272; --line: rgba(18,23,38,.12); --accent: #2747d6; }
@media (prefers-color-scheme: dark) { :root { --bg: #0f1320; --surface: #181d2c; --ink: #eef0f6; --muted: #9ba2b4; --line: rgba(238,240,246,.14); --accent: #8ea2ff; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 400 16px/1.55 "DM Sans", system-ui, sans-serif; }
header { background: #2747d6; color: #fff; padding: 40px 20px 64px; }
header .wrap, main { max-width: 720px; margin: 0 auto; }
.mark { font: 800 13px "Archivo Expanded", sans-serif; letter-spacing: .1em; opacity: .85; }
h1 { font: 800 30px/1.15 "Archivo Expanded", sans-serif; text-transform: uppercase; margin: 10px 0 0; }
main { padding: 0 20px 48px; margin-top: -40px; }
.intro, section { background: var(--surface); border: 1px solid var(--line); border-radius: 16px; padding: 18px 20px; margin-bottom: 14px; }
.intro { color: var(--muted); }
h2 { font: 600 12px "DM Sans", sans-serif; letter-spacing: .1em; text-transform: uppercase; color: var(--muted); margin: 0 0 8px; }
p { margin: 0 0 8px; } p:last-child { margin: 0; }
ul { margin: 0; padding-left: 20px; } li { margin-bottom: 6px; }
nav { color: var(--muted); font-size: 14px; margin-top: 24px; }
a { color: var(--accent); }
"""
for var, slug, title, intro, body in docs:
    sections = re.findall(r'\("(.*?)", """(.*?)"""\)', body, re.S)
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · Matchday</title><style>{style}</style></head>
<body><header><div class="wrap"><div class="mark">MATCHDAY</div><h1>{html.escape(title)}</h1></div></header>
<main><div class="intro">{paragraphs(intro)}</div>
{"".join(f'<section><h2>{html.escape(h)}</h2>{paragraphs(b)}</section>' for h, b in sections)}
<nav>{nav}</nav></main></body></html>
"""
    (root / f"{slug}.html").write_text(page)
    print("wrote", f"legal/{slug}.html", f"({len(sections)} sections)")
