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

- `publications.bib` (repo root) is the **single source of truth for all publications**. `site.hs` parses it with the `bibtex` library, decodes LaTeX via pandoc, and exposes the papers as a `listField "papers"` consumed by both `index.html` and `publication.html`. There are no per-paper markdown files or detail pages.
- `courses/*.markdown` → through `templates/course.html` then `templates/default.html`
- `index.html` and `publication.html` are templates themselves; their compilers build `listField "papers"` via `loadPapers` (parses `publications.bib`) and, for the homepage, `listField "courses"` via `recentFirst =<< loadAll "courses/*"`.
- `images/*`, `pdfs/*`, `css/*` are copied wholesale to `/docs/`.

**Per-paper context** (`paperContext` inside `site.hs`) exposes each bib entry's fields to templates. Every optional/boolean field is implemented with `field` + `noResult`, so `$if(field)$` tests **presence** — a key is in the assoc-list only when it applies. `$year$` comes from the bib `year` field; ordering is `(year, month)` descending (see `sortPapers`). The displayed `venue` is **auto-derived** (`deriveVenue`): a `venue = {…}` field wins if present, else a journal string is composed from `journal`/`volume`/`number`, else the conference acronym+year is extracted from `booktitle`. The title links to `primaryurl` (`link`, else `preprint`, else plain text). Author names are reordered to "First Last" and DBLP disambiguation digits (`Yao Li 0004`) are stripped.

**`customPandocCompiler`** in `site.hs` replaces `<strong>` with `<span class="fw-bold">` in the rendered HTML. Don't be surprised that markdown bold doesn't produce `<strong>` in the output.

**Templates** use Pandoc-style `$field$` interpolation. `$partial("templates/X.html")$` works only when X.html is registered under `match "templates/*"` (it already is). `$for(papers)$ … $endfor$` iterates list fields. `$if(field)$` tests presence/truthiness.

## Adding content

**A new paper:** add one entry to `publications.bib`. Easiest path: copy the entry from DBLP (`https://dblp.org/rec/<KEY>.bib`), strip the `DBLP:` key prefix, then add the website-only fields. Standard bib fields used: `author`, `title`, `year`, `month` (for ordering), and `journal`/`volume`/`number` or `booktitle` (the venue is derived from these — add a `venue = {…}` field to override when the derived string is wrong/ugly).

Website-only custom fields (all optional):

```bibtex
@inproceedings{slug,
  author    = {Last, First and First Last},   % either ordering works
  title     = {...},
  booktitle = {... ACRONYM YEAR ...},          % or journal/volume/number
  year      = {2026},
  month     = {5},                             % numeric or "may"; for sort order only
  venue     = {ACRONYM YEAR},                  % optional override of derived venue
  link      = {https://doi.org/...},           % canonical published URL → Paper button + title link
  openaccess= {true},                          % optional; if set, the Pre-print button is hidden
  preprint  = {https://...},                   % optional
  artifact  = {https://doi.org/...},           % optional
  talk      = {https://youtu.be/...},          % optional
  award     = {Distinguished Paper}            % optional; renders as accent chip
}
```

**A draft** (not yet peer-reviewed): same, but add `draft = {true}` and omit the venue (`@unpublished` is conventional). It appears in the Drafts section of `/publication.html`. An optional `submitted = {ACM TOPLAS ...}` field renders as "Submitted to …" on the draft's meta line (draft entries only — the published-list template ignores it). **Promotion**: remove `draft`, add the venue (and drop `submitted`). Booleans (`openaccess`/`draft`) are presence-based — write `{true}`; omit the field to turn it off. There are no abstracts.

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
