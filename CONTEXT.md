# Academic Website

Domain language for Yao Li's personal academic site: a Hakyll build that turns
`publications.bib`, `talks.yaml`, and `courses/*.markdown` into static pages.

## Language

**Paper**:
One entry in `publications.bib`, normalized into a display-ready assoc-list by
the Publications module. Every field a template sees is already decoded and
decided — templates only test presence.
_Avoid_: post, article, entry

**Published / Draft partition**:
Every Paper is exactly one of **published** (has a derivable Venue) or a
**draft** (`draft = {true}`). A Paper that is neither, or both, fails the
build with its cite key.
_Avoid_: filtering in templates

**Venue**:
The displayed publication venue, derived in the Publications module: explicit
`venue` override → composed journal string → acronym+year extracted from
`booktitle`. Its presence is what makes a Paper published.

**Promotion**:
Moving a draft to published: remove `draft`, ensure a Venue derives (and drop
`submitted`). Mid-promotion states (both or neither) are build errors.

**Pub entry**:
The rendered `<li>` for one Paper — title, authors, meta line, resource
buttons. One template (`templates/pub-entry.html`) renders every Pub entry,
published or draft.

**Publications module**:
The deep module (`src/Publications.hs`) owning all bib semantics: parsing,
LaTeX decoding, author formatting, Venue derivation, the partition, ordering,
and button visibility. Its interface — display-ready Papers — is the test
surface.

**Talk venue**:
A place a talk was given: display text plus an optional link; a talk may have
several. Not a Venue — that word is reserved for a Paper's publication venue.
_Avoid_: bare "venue" when talking about talks

**Talks module**:
The deep module (`src/Talks.hs`) owning all talks.yaml semantics: decoding,
year grouping, ordering, and the single/multi-venue display decision. Its
interface — display-ready TalkYears — is the test surface, mirroring the
Publications module.

## Example dialogue

> **Dev:** ESOP 2026 shows no year chip but the TOPLAS paper does — where do I look?
> **Domain expert:** The Publications module. The Venue for a conference embeds
> the year, so the meta-year is suppressed; a journal Venue doesn't, so the year
> renders. Templates never decide this — they just test presence.
> **Dev:** And to promote the Parkour draft once it's accepted?
> **Domain expert:** Edit its bib entry: drop `draft` and `submitted`, add the
> fields a Venue derives from. If you leave it half-promoted, the build fails
> and names the entry.
