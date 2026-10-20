#!/usr/bin/env python3
"""Fetch core sources from jsDelivr CDN (GitHub mirror) with pinned refs.

Usage: python3 fetch_cores.py <core_name> <repo> <ref> <dest_dir>
Skips: .github/, tests/, files > 20MB (jsDelivr limit), binary junk.
"""
import json
import sys
import os
import time
import random
import urllib.request
import urllib.parse
import urllib.error
from concurrent.futures import ThreadPoolExecutor

MAX_SIZE = 20 * 1024 * 1024  # jsDelivr hard limit per file
SKIP_DIRS = (".github/", "tests/", "test/", ".gitlab/")
SKIP_EXT = (".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".zip", ".gz", ".bz2", ".xz", ".7z")
CDN_DOMAINS = [
    "https://gcore.jsdelivr.net",
    "https://cdn.jsdelivr.net",
    "https://fastly.jsdelivr.net",
]


def fetch_tree(repo: str, ref: str):
    url = f"https://data.jsdelivr.com/v1/packages/gh/{repo}@{ref}?structure=flat"
    with urllib.request.urlopen(url, timeout=60) as r:
        data = json.load(r)
    files = []
    for f in data.get("files", []):
        name = f.get("name", "")
        if not name or name.endswith("/"):
            continue
        if f.get("size", 0) > MAX_SIZE:
            continue
        if any(name.startswith("/" + d) for d in SKIP_DIRS):
            continue
        if name.lower().endswith(SKIP_EXT):
            continue
        files.append(name)
    return files


def fetch_tree_gh(repo: str, ref: str):
    """GitHub git/trees API fallback for repos >50MB that jsDelivr refuses to index."""
    url = f"https://api.github.com/repos/{repo}/git/trees/{ref}?recursive=1"
    with urllib.request.urlopen(url, timeout=60) as r:
        data = json.load(r)
    files = []
    for t in data.get("tree", []):
        if t.get("type") != "blob":
            continue
        path = t.get("path", "")
        if t.get("size", 0) > MAX_SIZE:
            continue
        if any(path.startswith(d) for d in SKIP_DIRS):
            continue
        if path.lower().endswith(SKIP_EXT):
            continue
        files.append("/" + path)
    return files


def download_one(repo, ref, path, dest_root, retries=6):
    local = os.path.join(dest_root, path.lstrip("/"))
    os.makedirs(os.path.dirname(local), exist_ok=True)
    last_err = None
    for attempt in range(retries):
        domain = CDN_DOMAINS[attempt % len(CDN_DOMAINS)]
        url = f"{domain}/gh/{repo}@{ref}{urllib.parse.quote(path)}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "miniretro-fetch/1.0"})
            with urllib.request.urlopen(req, timeout=90) as r:
                content = r.read()
            if len(content) < 64 and b"404" in content[:16]:
                last_err = "404 not found"
                continue
            with open(local, "wb") as fh:
                fh.write(content)
            return (path, len(content), None)
        except Exception as e:  # noqa: BLE001
            last_err = str(e)
            time.sleep(0.5 + random.random())
    return (path, 0, str(last_err))


def main():
    core, repo, ref, dest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    use_gh_tree = len(sys.argv) > 5 and sys.argv[5] == "--gh-tree"
    list_file = None
    if "--list" in sys.argv:
        list_file = sys.argv[sys.argv.index("--list") + 1]
    if list_file:
        with open(list_file) as fh:
            files = [ln.strip() for ln in fh if ln.strip()]
    elif use_gh_tree:
        print(f"[{core}] fetching file tree for {repo}@{ref} (gh_tree=True) ...", flush=True)
        files = fetch_tree_gh(repo, ref)
    else:
        print(f"[{core}] fetching file tree for {repo}@{ref} ...", flush=True)
        files = fetch_tree(repo, ref)
    print(f"[{core}] {len(files)} files to download", flush=True)
    # 本地代理对高并发敏感：限制在 6 并发
    ok, fail = 0, []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = [pool.submit(download_one, repo, ref, p, dest) for p in files]
        for i, fut in enumerate(futures):
            path, size, err = fut.result()
            if err:
                fail.append((path, err))
            else:
                ok += 1
            if (i + 1) % 500 == 0:
                print(f"[{core}] {i + 1}/{len(files)} done (ok={ok} fail={len(fail)})", flush=True)
    print(f"[{core}] DONE ok={ok} fail={len(fail)}", flush=True)
    for p, e in fail[:20]:
        print(f"  FAIL {p}: {e}", flush=True)
    if fail:
        sys.exit(2)


if __name__ == "__main__":
    main()
