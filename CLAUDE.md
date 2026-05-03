# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal academic website for Yao Li (Assistant Professor at Portland State). Built with **Hakyll 4.16** (Haskell static site generator), deployed to **GitHub Pages from `/docs`** on the `master` branch. There is no JS framework, no CSS framework — vanilla CSS + ~150 lines of inline JS.

## Commands

```bash
stack build                  # recompile site.hs (only needed after editing site.hs)
stack exec site rebuild      # full rebuild → writes to /docs (commit /docs to publish)
stack exec site watch        # autocompile + local dev server on :8000
stack exec site clean        # nuke _cache and /docs
```

For browser verification (headless Chrome Beta is installed):

```bash
cd docs && python3 -m http.server 8765 &
CHROME='/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta'
"$CHROME" --headless --disable-gpu --hide-scrollbars --no-sandbox \
  --window-size=1280,7000 --virtual-time-budget=6000 \
  --screenshot=/tmp/page.png http://localhost:8765/index.html
# then Read /tmp/page.png to inspect
pkill -f 'http.server 8765'
```

`--virtual-time-budget` is essential: without it Chrome screenshots before fonts and the IntersectionObserver fire.

## Architecture

**`site.hs`** is the entire build pipeline (~140 lines). It defines per-route `match` rules:

- `papers/*.markdown` → applied through `templates/post.html` then `templates/default.html`
- `courses/*.markdown` → through `templates/course.html` then `templates/default.html`
- `index.html` and `publication.html` are templates themselves; their compiler loads all papers + courses via `recentFirst =<< loadAll "papers/*"` and exposes them as a `listField "papers"` / `listField "courses"`.
- `images/*`, `pdfs/*`, `css/*`, `js/*` are copied wholesale to `/docs/`.

**Per-paper context** (`paperCtx` inside `site.hs`) augments the default Hakyll context with `dateField "year" "%Y"` extracted from the `YYYY-MM-DD-slug.markdown` filename. So `$year$` is available in templates; do **not** add a `year:` field to paper frontmatter — it comes from the filename.

**`customPandocCompiler`** in `site.hs` replaces `<strong>` with `<span class="fw-bold">` in the rendered HTML. Don't be surprised that markdown bold doesn't produce `<strong>` in the output.

**Templates** use Pandoc-style `$field$` interpolation. `$partial("templates/X.html")$` works only when X.html is registered under `match "templates/*"` (it already is). `$for(papers)$ … $endfor$` iterates list fields. `$if(field)$` tests presence/truthiness.

## Adding content

**A new paper:** drop `papers/YYYY-MM-DD-slug.markdown` with frontmatter:

```yaml
---
title: ...
authors: A, B, C
venue: Proceedings of ..., YEAR
link: https://doi.org/...      # canonical published URL
openaccess: true               # optional; if true, the Pre-print button is hidden
preprint: https://...          # optional
artifact: https://doi.org/...  # optional
talk: https://youtu.be/...     # optional
award: Distinguished Paper     # optional; renders as accent chip
featured: true                 # optional; appears on homepage Featured Publications
draft: true                    # optional; appears in Drafts section of /publication.html
---
```

Body becomes the abstract on the paper detail page. Year auto-extracted from filename.

**A new course:** drop `courses/YYYY-MM-DD-slug.markdown` with at minimum `title`, `term`, `show: true` (omit `show` to suppress the "click to view detail" link).

## CSS / JS conventions

- **No Bootstrap, no icon font.** A minimal utility-shim layer in `css/custom.css` covers the small set of legacy utility classes still in markup (`.d-flex`, `.row/.col`, `.card`, `.btn`, `.badge`, etc.) — it is not a Bootstrap reimplementation. Add to it only if you need a class that's already used 3+ times.
- **Design tokens** live at the top of `css/custom.css` as CSS custom properties: `--primary` (PSU green), `--accent` (terracotta), `--accent-cool` (slate blue), `--font-display` (Instrument Serif), `--font-body` (Inter Tight), `--fs-xs … --fs-display`, `--space-1 … --space-6`, `--shadow-soft`, `--shadow-elevated`. Always use the tokens; never hardcode colors or sizes.
- **Icons** are an inline SVG sprite at `images/icons.svg`. Reference: `<svg class="icon"><use href="/images/icons.svg#name"/></svg>`. Each `<symbol>` must declare its `fill` / `stroke` / `stroke-width` as **presentation attributes** — internal `<style>` blocks do not propagate through external `<use>` reliably across browsers.
- **Path-self-closing inside the sprite is critical**: `<path .../>`, never `<path ...></path>`. A stray `</path>` breaks XML parsing of every subsequent symbol.
- **Motion is additive, never gating.** Sections default to visible. Only when JS confirms motion is permitted AND the section is below the fold does it get a `.js-fx` class that hides it; the IntersectionObserver then adds `.is-visible` to reveal. If JS / IO fails, content is still visible. Pattern is in `templates/default.html` inline script + `css/custom.css` `.js-fx` rules.
- **Hakyll re-copies `/css/*` and `/images/*` from source on every rebuild.** Deleting a file from `/docs/css/` alone won't stick — also delete the source under `/css/` (and likewise for `/images/`).

## Pitfalls that have bitten

- The `$partial("…")$` directive errors silently if the referenced template isn't registered via `match "templates/*"`.
- `git add -A` will sweep `.claude/settings.local.json` (Claude Code session settings) into commits. `.gitignore` includes `.claude/`; stage explicit paths instead of `-A`.
- When restructuring/redesigning templates, treat the visible text, aria-labels, and content-shape choices (abbreviation vs spelled-out, icon-only vs labeled, ordering) as read-only. Restructure markup, not strings.
- `/docs/` is committed for GitHub Pages — every Hakyll-touching commit must include both source and rebuilt `/docs/` output, or the deployed site goes stale.
