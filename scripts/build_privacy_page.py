#!/usr/bin/env python3
"""Turns assets/legal/privacy_policy.md (the text the app shows) into
hosting/privacy.html for Firebase Hosting, so the store listings can link to
the same words. Run from the repo root after editing the policy, then
`firebase deploy --only hosting`."""
import html
import re

SRC = 'assets/legal/privacy_policy.md'
OUT = 'hosting/privacy.html'


def inline(text):
    text = html.escape(text)
    return re.sub(r'(https://[^\s<]+)', r'<a href="\1">\1</a>', text)


def main():
    body, para, items = [], [], []

    def flush():
        if para:
            body.append(f'<p>{inline(" ".join(para))}</p>')
            para.clear()
        if items:
            body.append('<ul>' + ''.join(f'<li>{inline(i)}</li>' for i in items) + '</ul>')
            items.clear()

    for raw in open(SRC, encoding='utf-8').read().splitlines():
        line = raw.rstrip()
        if line.startswith('# '):
            flush()
            body.append(f'<h1>{inline(line[2:])}</h1>')
        elif line.startswith('## '):
            flush()
            body.append(f'<h2>{inline(line[3:])}</h2>')
        elif line.startswith('- '):
            if para:
                flush()
            items.append(line[2:])
        elif not line:
            flush()
        elif items:
            items[-1] += ' ' + line.strip()
        else:
            para.append(line.strip())
    flush()
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Chuchula privacy policy</title>
<style>
  body {{ font: 16px/1.55 system-ui, sans-serif; max-width: 720px; margin: 0 auto;
         padding: 24px 16px; color: #1d2a22; background: #faf6ea; }}
  h1 {{ color: #0f5a3a; }} h2 {{ color: #0f5a3a; margin-top: 1.6em; }}
  a {{ color: #0f5a3a; }}
</style>
</head>
<body>
{chr(10).join(body)}
</body>
</html>
"""
    open(OUT, 'w', encoding='utf-8').write(page)


if __name__ == '__main__':
    main()
