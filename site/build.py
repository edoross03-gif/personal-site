#!/usr/bin/env python3
"""Assemble the personal site.  Run: python build.py   (needs Pillow)
out/eddy-site.html  -> preview (no document skeleton)
dist/               -> what deploy.sh copies to the live folder
Everything is built from parts/, assets/, static/ and ledger.json in this folder.
Live ledger.json / corrections.json are written by n8n and are never produced here.
SITEMAP_LASTMOD=YYYY-MM-DD overrides the sitemap date (deploy.sh keeps the live one when index.html is unchanged).
"""
import base64, io, json, os, re
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
P = lambda *a: os.path.join(HERE, *a)

def data_uri(path, mime):
    return f"data:{mime};base64," + base64.b64encode(open(path, "rb").read()).decode()

# campus photo (already compressed: 900px, q68)
campus = data_uri(P("assets", "campus.jpg"), "image/jpeg")

subs = {f"{{{{logo-{k}}}}}": data_uri(P("assets", f"logo-{k}.png"), "image/png")
        for k in ["balderdash", "sangi", "abvision", "kolme", "nova"]}
subs["{{img-campus}}"] = campus
for k in ["edu-nova","edu-cattolica","edu-stpaul","club-canottieri","club-nsa","headshot"]:
    subs["{{img-"+k+"}}"] = data_uri(P("assets", k + ".jpg"), "image/jpeg")
for k in ["nova-hub", "strategy-lab"]:
    subs["{{shot-"+k+"}}"] = data_uri(P("assets", "shot-" + k + ".webp"), "image/webp")
ledger = open(P("ledger.json")).read()
subs["{{LEDGER}}"] = ledger

parts = sorted(f for f in os.listdir(P("parts")) if f.endswith(".html"))
src_html = "".join(open(P("parts", f)).read() for f in parts)
for k, val in subs.items():
    src_html = src_html.replace(k, val)
assert "{{" not in src_html, re.findall(r"\{\{[^}]+\}\}", src_html)[:5]

head = re.search(r"<!--HEAD-->(.*?)<!--/HEAD-->", src_html, re.S).group(1)
body = src_html.replace(re.search(r"<!--HEAD-->.*?<!--/HEAD-->", src_html, re.S).group(0), "")

# ---- artifact version
os.makedirs(P("out"), exist_ok=True)
open(P("out", "eddy-site.html"), "w").write(head + body)

# ---- VPS version
SITE_URL = os.environ.get("SITE_URL", "https://edoardorossetti.eu")
TITLE = "Edoardo Rossetti – Finance, Analytics, Automation | Nova SBE"
desc = ("I'm Edoardo Rossetti: finance, analytics and automation. Master in Management student "
        "at Nova SBE in Lisbon; before that I built finance systems in Milan.")
OG_ALT = "Edoardo Rossetti – Finance × Analytics. Master in Management, Nova SBE, Lisbon"
HEADSHOT_URL = "/edoardo-rossetti.jpg"
# Favicon: the × mark already used inline since v1.0, now served as real files (Google ignores data: icons)
FAVICON_SVG = ("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><rect width='64' height='64' rx='12' fill='#050d1c'/>"
               "<path d='M20 20l24 24M44 20L20 44' stroke='#38bdf8' stroke-width='8' stroke-linecap='round'/></svg>\n")
person = {
    "@context": "https://schema.org", "@type": "Person",
    "name": "Edoardo Rossetti", "alternateName": "Eddy Rossetti",
    "url": f"{SITE_URL}/", "image": f"{SITE_URL}{HEADSHOT_URL}",
    "jobTitle": "Master in Management student",
    "description": desc,
    "address": {"@type": "PostalAddress", "addressLocality": "Lisbon", "addressCountry": "PT"},
    "alumniOf": [
        {"@type": "CollegeOrUniversity", "name": "Nova School of Business and Economics", "alternateName": "Nova SBE", "url": "https://www.novasbe.unl.pt/"},
        {"@type": "CollegeOrUniversity", "name": "Università Cattolica del Sacro Cuore", "alternateName": "Università Cattolica", "url": "https://www.unicatt.it/"},
    ],
    "knowsAbout": ["Corporate finance", "Financial analysis", "Business intelligence", "Finance automation"],
    "sameAs": ["https://www.linkedin.com/in/edoardo-rossetti-96586229a", "https://x.com/EddyR0ss",
               "https://github.com/edoross03-gif"],
}
jsonld = json.dumps(person, ensure_ascii=False, indent=1).replace("</", "<\\/")
vps_head = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="{desc}">
<meta name="theme-color" content="#050d1c">
<link rel="canonical" href="{SITE_URL}/">
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Edoardo Rossetti">
<meta property="og:title" content="{TITLE}">
<meta property="og:description" content="{desc}">
<meta property="og:url" content="{SITE_URL}/">
<meta property="og:image" content="{SITE_URL}/og-hero.jpg">
<meta property="og:image:type" content="image/jpeg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{OG_ALT}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:site" content="@EddyR0ss">
<meta name="twitter:creator" content="@EddyR0ss">
<meta name="twitter:title" content="{TITLE}">
<meta name="twitter:description" content="{desc}">
<meta name="twitter:image" content="{SITE_URL}/og-hero.jpg">
<meta name="twitter:image:alt" content="{OG_ALT}">
<script type="application/ld+json">
{jsonld}
</script>
<style>html,body{{margin:0}} [hidden]{{display:none!important}}</style>
{head}
<script>window.ER_CONFIG={{fixApi:"/api/fix"}};</script>
<script defer src="https://stats.rossettilab.store/insights.js" data-website-id="ea6a536b-06c1-438f-8ee8-a24ef4b79bae"></script>
</head>
<body>
"""
os.makedirs(P("dist"), exist_ok=True)
# On the VPS the headshot is a real file, so Google can index it (data: URIs never show as thumbnails)
hs = data_uri(P("assets", "headshot.jpg"), "image/jpeg")
assert body.count(hs) == 1
body = body.replace(hs, HEADSHOT_URL)
open(P("dist", "index.html"), "w").write(vps_head + body + "\n</body>\n</html>\n")
# static/ (cv PDFs, ...) is copied as is
import shutil
shutil.copytree(P("static"), P("dist"), dirs_exist_ok=True)
open(P("dist", "robots.txt"), "w").write(f"User-agent: *\nAllow: /\nSitemap: {SITE_URL}/sitemap.xml\n")
import datetime
today = os.environ.get("SITEMAP_LASTMOD") or datetime.date.today().isoformat()
open(P("dist", "sitemap.xml"), "w").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">\n'
    f'  <url>\n    <loc>{SITE_URL}/</loc>\n    <lastmod>{today}</lastmod>\n'
    f'    <image:image><image:loc>{SITE_URL}{HEADSHOT_URL}</image:loc></image:image>\n'
    f'    <image:image><image:loc>{SITE_URL}/og-hero.jpg</image:loc></image:image>\n  </url>\n</urlset>\n')

# ---- icons (the × mark), drawn 4x then downsampled
shutil.copyfile(P("assets", "headshot.jpg"), P("dist", HEADSHOT_URL.lstrip("/")))
open(P("dist", "favicon.svg"), "w").write(FAVICON_SVG)
from PIL import ImageDraw
def icon(size, rounded=True):
    S = size * 4; k = S / 64
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    if rounded: d.rounded_rectangle([0, 0, S - 1, S - 1], radius=12 * k, fill=(5, 13, 28, 255))
    else: d.rectangle([0, 0, S, S], fill=(5, 13, 28, 255))
    w, r = 8 * k, 4 * k
    for a, b in [((20, 20), (44, 44)), ((44, 20), (20, 44))]:
        a = (a[0] * k, a[1] * k); b = (b[0] * k, b[1] * k)
        d.line([a, b], fill=(56, 189, 248, 255), width=round(w))
        for x, y in (a, b): d.ellipse([x - r, y - r, x + r, y + r], fill=(56, 189, 248, 255))
    return im.resize((size, size), Image.LANCZOS)
icon(48).save(P("dist", "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])
icon(192).save(P("dist", "icon-192.png"), optimize=True)
icon(512).save(P("dist", "icon-512.png"), optimize=True)
icon(180, rounded=False).convert("RGB").save(P("dist", "apple-touch-icon.png"), optimize=True)  # iOS rounds it itself
open(P("dist", "site.webmanifest"), "w").write(json.dumps({
    "name": "Edoardo Rossetti", "short_name": "E×R", "start_url": "/", "display": "browser",
    "background_color": "#050d1c", "theme_color": "#050d1c",
    "icons": [{"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"},
              {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"}]}, ensure_ascii=False, indent=1) + "\n")

# ---- og-hero.jpg 1200x630 from the branded card (assets/og.png); centre-crop if the source ever changes size
o = Image.open(P("assets", "og.png")).convert("RGB")
s = max(1200 / o.width, 630 / o.height)
o = o.resize((round(o.width * s), round(o.height * s)), Image.LANCZOS)
l, t = (o.width - 1200) // 2, (o.height - 630) // 2
o.crop((l, t, l + 1200, t + 630)).save(P("dist", "og-hero.jpg"), "JPEG", quality=86, optimize=True, progressive=True)

for f in [P("out", "eddy-site.html"), P("dist", "index.html")]:
    print(f, os.path.getsize(f))
