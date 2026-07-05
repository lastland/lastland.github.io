# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal academic website for Yao Li (Assistant Professor at Portland State). Built with **Hakyll 4.16** (Haskell static site generator), deployed to **GitHub Pages from `/docs`** on the `master` branch. There is no JS framework, no CSS framework — vanilla CSS + ~150 lines of inline JS.

## Commands

```bash
stack build                  # recompile (only needed after editing site.hs / src/*.hs)
stack test                   # run the Publications and Talks module tests (fast, no rebuild)
stack exec site rebuild      # full rebuild → writes to /docs (commit /docs to publish)
stack exec site watch        # autocompile + local dev server on :8000
stack exec site clean        # nuke _cache and /docs
hlint site.hs src/ test/     # Haskell style check — keep it at "No hints" (prefer <> over mappend)
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

**`src/Publications.hs`** is the Publications module: it owns every bib semantic (parsing via the `bibtex` library, LaTeX decoding via pandoc, author formatting, venue derivation, the published/draft partition, ordering, button visibility). Its interface is `parsePublications :: String -> Either String Publications` — bib text in, display-ready papers out, every failure as a `Left`. `test/Spec.hs` tests it through this interface (`stack test`), including a check that the real `publications.bib` parses and partitions.

**`src/Talks.hs`** is the Talks module: it owns every `talks.yaml` semantic (YAML decoding, year grouping, ordering, the single/multi-venue display decision). Its interface is `parseTalks :: String -> Either String [TalkYear]` — YAML text in, display-ready year groups out, every failure as a `Left`. The talk-venue type is `TalkVenue` (bare "Venue" means a Paper's publication venue; see CONTEXT.md). Also tested via `test/Spec.hs`.

**`src/Courses.hs`** is the Courses module: it owns every course-term semantic (parsing `"Spring, 2025"`-style strings — PSU quarters, Winter < Spring < Summer < Fall within a year — validating a course's `terms:` list, the homepage sort key, the joined display string). Its interface is `parseTerms :: [String] -> Either String CourseTerms` — front-matter strings in, display-ready terms out, every failure as a `Left`. Also tested via `test/Spec.hs`.

**`site.hs`** defines the Hakyll build: per-route `match` rules plus thin adapters (`loadPublished`/`loadDrafts`, `paperContext`, `loadTalkYears`, `talkContext`, `loadCourseTerms`/`courseContext`/`sortCourses`) from the Publications, Talks, and Courses modules to Hakyll contexts. `index.html` and `publication.html` share `pubsContext` (the `published`/`drafts` listFields) and the `renderPage` helper.

- `publications.bib` (repo root) is the **single source of truth for all publications**. Its papers are exposed as `listField "published"` and `listField "drafts"`, consumed by both `index.html` and `publication.html`. There are no per-paper markdown files or detail pages. **Every entry must be exactly one of published (derivable venue) or draft (`draft = {true}`)** — neither, or both, fails the build naming the entry.
- `courses/*` → through `templates/course.html` then `templates/default.html`. **One file = one course**, slug-named (`courses/fp.markdown`, no date prefix), covering every term it was taught via a front-matter `terms:` list. The `$term$` template field is the joined display string (`"Spring, 2025 · Spring, 2026"`); a missing or malformed `terms` list fails the build naming the file.
- `index.html` and `publication.html` are templates themselves; both render their publications section via `$partial("templates/pub-sections.html")$` with the section heading supplied by a `pubsheading:` front-matter field. The homepage additionally gets `listField "courses"` (sorted by most recent term descending via `sortCourses`, title breaking ties) and `listField "talkyears"` from the Talks module.
- `images/*`, `pdfs/*`, `css/*` are copied wholesale to `/docs/`.

**Per-paper context** (`paperContext` in `site.hs`) exposes each paper's fields to templates. Every optional/boolean field is implemented with `field` + `noResult`, so `$if(field)$` tests **presence** — a key is in the assoc-list only when it applies; all decisions (venue, meta-year, button visibility) are made in the Publications module, never in templates. `$year$` comes from the bib `year` field; ordering is `(year, month)` descending (`sortPapers`). The displayed `venue` is **auto-derived** (`deriveVenue`): a `venue = {…}` field wins if present, else a journal string is composed from `journal`/`volume`/`number`, else the conference acronym+year is extracted from `booktitle`. The title links to `primaryurl` (`link`, else `preprint`, else plain text). Author names are reordered to "First Last" and DBLP disambiguation digits (`Yao Li 0004`) are stripped. `openaccess = {true}` removes the `preprint` key (hiding the Pre-print button) while `primaryurl` may still fall back to the preprint URL.

**Publication templates**: `templates/pub-entry.html` renders one paper (`<li>` with title/authors/meta/buttons); `templates/pub-sections.html` renders the whole section shape (heading, published `<ol>`, Drafts heading, drafts `<ol>`) for both pages.

**`src/Prose.hs`** is the Prose module: it owns the rendering semantics of pandoc-compiled prose (currently the course pages). Site policy: bold in prose draws attention without claiming importance, so `**bold**` renders as `<b>`, not `<strong>` (`boldToB`, applied via `pandocCompilerWithTransform` in the `courses/*` rule; styled by the `b, strong, .fw-bold` rule in `css/custom.css`). Don't be surprised that markdown bold doesn't produce `<strong>` in the output. Tested in `test/Spec.hs`.

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

**A draft** (not yet peer-reviewed): same, but add `draft = {true}` and omit the venue (`@unpublished` is conventional). It appears in the Drafts sections. An optional `submitted = {ACM TOPLAS ...}` field renders as "Submitted to …" on the draft's meta line (published entries never render it). **Promotion**: remove `draft`, add the venue (and drop `submitted`) — do it in one edit; an entry with both `draft` and a venue, or neither, fails the build with its cite key. Booleans (`openaccess`/`draft`) are presence-based — write `{true}`; omit the field to turn it off. There are no abstracts.

**A course taught again (the common case):** append one line to the existing course file's `terms:` list, e.g. `- "Spring, 2026"`, and rebuild. Nothing else changes.

**A new course:** drop `courses/slug.markdown` (no date prefix) with at minimum `title`, a `terms:` list of `"<Winter|Spring|Summer|Fall>, <year>"` strings, and `show: true` (omit `show` to suppress the "click to view detail" link). Content policy: Canvas is the source of truth for logistics, and the website only records what was taught and what the course is — so a course page carries the course description (plus a topics list if useful), **no** Instructor/Office/Office Hours/Syllabus/Credit Hours lines, and no TBA placeholders.

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
