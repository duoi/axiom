"""Check every relative Markdown link and #anchor in a repo.

  python3 check_links.py REPO [--skip DIR ...]

Reports links to files that do not exist and #anchors that match no heading (GitHub's slug rules: lowercase, drop
punctuation except - and _, spaces to -, duplicates get -1, -2, ...). External links (http, mailto) are not checked.
Exits 1 when anything is broken.
"""
import argparse, os, re, sys

LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
FENCE = re.compile(r"^\s*(```|~~~)")
SKIP = {".git", "node_modules", ".venv", "venv", "__pycache__", "site-packages", "dist", "build"}


def slug(text):
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)      # a link in a heading keeps its text
    text = text.strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path):
    seen, out, fenced = {}, set(), False
    for line in open(path, encoding="utf-8", errors="replace"):
        if FENCE.match(line):
            fenced = not fenced
            continue
        m = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if m and not fenced:
            s = slug(m.group(2))
            n = seen.get(s, 0)
            out.add(s if n == 0 else f"{s}-{n}")
            seen[s] = n + 1
        for a in re.findall(r'<a\s+(?:name|id)="([^"]+)"', line):
            out.add(a)
    return out


def links(path):
    fenced = False
    for i, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if FENCE.match(line):
            fenced = not fenced
            continue
        if not fenced:
            for target in LINK.findall(re.sub(r"`[^`]*`", "", line)):
                yield i, target


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo"); ap.add_argument("--skip", nargs="*", default=[])
    a = ap.parse_args()
    skip, cache, bad, n = SKIP | set(a.skip), {}, [], 0
    for root, dirs, files in os.walk(a.repo):
        dirs[:] = [d for d in dirs if d not in skip]
        for f in files:
            if not f.endswith(".md"):
                continue
            src = os.path.join(root, f)
            for line, target in links(src):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target):     # http:, https:, mailto:, ...
                    continue
                n += 1
                path, _, frag = target.partition("#")
                dst = os.path.normpath(os.path.join(root, path)) if path else src
                where = f"{os.path.relpath(src, a.repo)}:{line}"
                if not os.path.exists(dst):
                    bad.append(f"{where}: missing file {target}")
                elif frag and dst.endswith(".md"):
                    if dst not in cache:
                        cache[dst] = anchors(dst)
                    if frag not in cache[dst]:
                        bad.append(f"{where}: no heading for #{frag} in {os.path.relpath(dst, a.repo)}")
    print("\n".join(bad))
    print(f"{n} relative links checked, {len(bad)} broken")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
