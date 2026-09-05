--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Control.Monad (filterM, (>=>))
import           Courses
import           Data.List (sortOn)
import           Data.Ord (Down (..))
import           Data.String (fromString)
import           Hakyll
import qualified Hakyll.Alectryon as Alectryon
import           Posts
import           Publications
import           Prose
import           Skylighting (SyntaxMap)
import           System.FilePath ((</>))
import           Talks
import           Text.Pandoc.Definition (Pandoc)
import           Text.Pandoc.Options (WriterOptions)


--------------------------------------------------------------------------------

-- Helper function to determine if we're on the index page
isIndexPage :: Item a -> Compiler Bool
isIndexPage item = do
    route <- getRoute $ itemIdentifier item
    return $ case route of
        Just r -> r == "index.html"
        Nothing -> False

-- Context field for navigation link prefix
navLinkPrefix :: Context String
navLinkPrefix = field "navLinkPrefix" $ \item -> do
    isIndex <- isIndexPage item
    return $ if isIndex then "" else "/index.html"

--------------------------------------------------------------------------------
-- Publications: all bib semantics (parsing, decoding, venue derivation, the
-- published/draft partition, ordering, button visibility) live in the
-- Publications module; here we only adapt its display-ready Papers to Hakyll.

-- Load the raw publications.bib (stored as a String, so it is loadable) and
-- run the whole pipeline. A Left (parse error, unclassifiable entry) fails
-- the build with the module's message.
loadPublications :: Compiler Publications
loadPublications = do
    raw <- loadBody "publications.bib" :: Compiler String
    either error return (parsePublications raw)

loadPublished, loadDrafts :: Compiler [Item Paper]
loadPublished = mapM makeItem . published =<< loadPublications
loadDrafts    = mapM makeItem . drafts    =<< loadPublications

-- A field per template key. Using field + noResult means $if(k)$ tests field
-- PRESENCE: optional/boolean keys are simply absent from the assoc-list when
-- they don't apply, so the existing $if(...)$ gating works unchanged.
paperContext :: Context Paper
paperContext = mconcat [ lookupField k | k <- paperKeys ]
  where
    paperKeys =
      [ "title", "authors", "venue", "metayear", "year"
      , "link", "preprint", "artifact", "talk", "award"
      , "openaccess", "draft", "submitted", "primaryurl" ]
    lookupField k = field k $ \item ->
        maybe (noResult ("Paper has no field " ++ k)) return
              (lookup k (itemBody item))


--------------------------------------------------------------------------------
-- Talks: all talks.yaml semantics (decoding, year grouping, ordering, the
-- multi-venue display decision) live in the Talks module; here we only adapt
-- its display-ready TalkYears to Hakyll.

-- Load the raw talks.yaml and run the whole pipeline. A Left fails the build
-- with the module's message. Mirrors loadPublications.
loadTalkYears :: Compiler [Item TalkYear]
loadTalkYears = do
    raw <- loadBody "talks.yaml" :: Compiler String
    either error (mapM makeItem) (parseTalks raw)

venueContext :: Context TalkVenue
venueContext = mconcat
    [ field "text" (return . venueText . itemBody)
    , field "url"  $ \i ->
        maybe (noResult "Talk venue has no url") return (venueUrl (itemBody i))
    ]

talkContext :: Context Talk
talkContext = mconcat
    [ field "title" (return . talkTitle . itemBody)
    , field "note"  $ \i ->
        maybe (noResult "Talk has no note") return (talkNote (itemBody i))
    -- Presence-based flag: $if(multivenue)$ picks <ul> vs <p> markup; the
    -- decision itself is the Talks module's multiVenue.
    , field "multivenue" $ \i ->
        if multiVenue (itemBody i)
            then return "true"
            else noResult "Talk has a single venue"
    , listFieldWith "venues" venueContext (mapM makeItem . talkVenues . itemBody)
    ]

talkYearContext :: Context TalkYear
talkYearContext = mconcat
    [ field "year" (return . show . fst . itemBody)
    , listFieldWith "talks" talkContext (mapM makeItem . snd . itemBody)
    ]


--------------------------------------------------------------------------------
-- Courses: term semantics (parsing, validation, ordering, the joined display
-- string) live in the Courses module; here we only adapt front matter to
-- Hakyll. One course file covers every term it was taught (a terms: list).

-- Read and validate a course's terms list. A Left (missing list, bad term)
-- fails the build naming the course file.
loadCourseTerms :: Identifier -> Compiler CourseTerms
loadCourseTerms ident = do
    metadata <- getMetadata ident
    let terms = maybe (Left "no terms list in front matter") parseTerms
                      (lookupStringList "terms" metadata)
    either (error . named) return terms
  where
    named msg = "course " ++ toFilePath ident ++ ": " ++ msg

-- The template field stays named "term": one string, all terms joined, so
-- course.html and the index card markup are unchanged.
courseContext :: Context String
courseContext = field "term" $ \item ->
    displayTerms <$> loadCourseTerms (itemIdentifier item)

-- Order items by a per-item key computed in the Compiler (a Down inside the
-- key makes that field descending); shared by the course and post listings.
sortItemsBy :: Ord k => (Item a -> Compiler k) -> [Item a] -> Compiler [Item a]
sortItemsBy keyOf items = map snd . sortOn fst <$> mapM keyed items
  where
    keyed item = do
        key <- keyOf item
        return (key, item)

-- Homepage order: by the most recent term taught, descending (replaces
-- recentFirst, which needed date-prefixed filenames); title breaks ties.
sortCourses :: [Item a] -> Compiler [Item a]
sortCourses = sortItemsBy $ \item -> do
    let ident = itemIdentifier item
    terms <- loadCourseTerms ident
    title <- getMetadataField' ident "title"
    return (Down (latestTerm terms), title)


--------------------------------------------------------------------------------
-- Posts: all blog-post semantics (front-matter validation, date parsing and
-- display, ordering, the pandoc pipeline — rocq fences, cross-references,
-- bold as <b>, KaTeX math, Coq highlighting) live in the Posts module; here
-- we only adapt its display-ready posts to Hakyll.

-- Read and validate a post's front matter. A Left (missing title/date/
-- description, bad date, bad draft value) fails the build naming the post.
loadPostMeta :: Identifier -> Compiler PostMeta
loadPostMeta ident = do
    metadata <- getMetadata ident
    either (error . named) return (parsePostMeta metadata)
  where
    named msg = "post " ++ toFilePath ident ++ ": " ++ msg

-- A field per template key. date/isodate/description come from the validated
-- front matter; hasmath is presence-based ($if(hasmath)$ gates the KaTeX
-- assets in default.html), and hasalectryon likewise gates the Alectryon
-- stylesheet — both mirroring paperContext's field + noResult style.
postContext :: Context String
postContext = mconcat
    [ field "date" $ \item ->
        formatPostDate . postDate <$> loadPostMeta (itemIdentifier item)
    , field "isodate" $ \item ->
        show . postDate <$> loadPostMeta (itemIdentifier item)
    , field "description" $ \item ->
        postDescription <$> loadPostMeta (itemIdentifier item)
    , field "hasmath" $ \item ->
        if postHasMath (itemBody item)
            then return "true"
            else noResult "post has no math"
    , field "hasalectryon" $ \item ->
        if postHasAlectryon (itemBody item)
            then return "true"
            else noResult "post has no alectryon blocks"
    -- Presence-based noindex: a draft's page compiles but asks crawlers not
    -- to index it (gates the robots meta in default.html). Parsed leniently
    -- because non-post pages share postContext via blog.html: anything
    -- without a valid draft flag is simply not a draft.
    , field "noindex" $ \item -> do
        metadata <- getMetadata (itemIdentifier item)
        case parsePostMeta metadata of
            Right meta | postDraft meta -> return "true"
            _                           -> noResult "not a draft post"
    ]

-- Blog order: date descending, title ascending breaks ties (postSortKey).
sortPosts :: [Item a] -> Compiler [Item a]
sortPosts = sortItemsBy (fmap postSortKey . loadPostMeta . itemIdentifier)

-- Drafts stay buildable (their pages exist) but are kept off blog.html and
-- the feed, mirroring the published/draft partition in Publications.
publishedPosts :: [Item a] -> Compiler [Item a]
publishedPosts = filterM (fmap (not . postDraft) . loadPostMeta . itemIdentifier)

-- | The site's canonical origin. The Atom feed and the sitemap build their
-- absolute URLs on it.
siteRoot :: String
siteRoot = "https://lastland.github.io"

feedConfiguration :: FeedConfiguration
feedConfiguration = FeedConfiguration
    { feedTitle       = "Yao Li - Blog"
    , feedDescription = "Posts by Yao Li"
    , feedAuthorName  = "Yao Li"
    , feedAuthorEmail = "liyao@pdx.edu"
    , feedRoot        = siteRoot
    }

-- Context a post page is rendered with (post.html and the default.html
-- wrap). katexversion is the Posts module's pin, interpolated by
-- default.html into the KaTeX CDN tags so the version lives in one place.
postCtx :: Context String
postCtx = postContext
    <> constField "katexversion" katexVersion
    <> defaultContext

--------------------------------------------------------------------------------

-- The pure AST pipeline for Alectryon-enabled posts lives in the Posts
-- module alongside the standard 'postTransform' (coq/rocq fences rewritten to
-- alectryon, cross-references numbered, bold as <b>). Alectryon's own transform
-- — which turns alectryon blocks into proof-state HTML — runs afterwards in
-- the Compiler monad (it shells out to the alectryon executable).

-- Wrap a rendered post body in the post and default templates and relativize
-- URLs. Shared by the standard and Alectryon post-page compilers.
wrapPostPage :: Item String -> Compiler (Item String)
wrapPostPage =
    loadAndApplyTemplate "templates/post.html" postCtx
    >=> loadAndApplyTemplate "templates/default.html" (postCtx <> navLinkPrefix)
    >=> relativizeUrls

-- A post page compiler. Posts without an "alectryon" front-matter field follow
-- the standard pipeline (skylighting Coq highlighting). Posts WITH the field —
-- a list of Alectryon arguments, possibly empty — are Alectryon-enabled: their
-- Coq/Rocq blocks are executed and annotated with proof states for the web
-- page, while the Atom feed snapshot keeps the plain Coq-highlighted version.
-- Proof states are a web enhancement that degrades poorly in feed readers (the
-- goals are present in the HTML and shown expanded without the stylesheet), so
-- the feed carries source only.
--
-- "alectryon-cache" (required on Alectryon-enabled posts, validated by
-- parsePostMeta) names a directory holding a committed alectryon.html cache;
-- builds without --run-alectryon read it so the site builds without a Coq
-- toolchain. Pass --run-alectryon to regenerate it.
postPageCompiler :: SyntaxMap -> Alectryon.Options -> Compiler (Item String)
postPageCompiler syntaxes alectryonOpts = do
    raw    <- getResourceBody
    pandoc <- readPandocWith defaultHakyllReaderOptions raw
    pm     <- loadPostMeta (itemIdentifier pandoc)
    let wopt = postWriterOptions defaultHakyllWriterOptions syntaxes
    case postAlectryon pm of
        Nothing        -> standardPostPage wopt pandoc
        Just alectryon ->
            alectryonPostPage wopt alectryonOpts
                (alectryonCache alectryon </> "alectryon.html")
                (alectryonArgs alectryon) pandoc

-- | Write the plain Coq-highlighted post HTML and snapshot it for the Atom
-- feed. Both post-page paths call this before any web-only enhancement
-- (Alectryon proof states), so the feed always carries source-only HTML.
snapshotPlainPost :: WriterOptions -> Item Pandoc -> Compiler (Item String)
snapshotPlainPost wopt pandoc =
    saveSnapshot "content" (writePandocWith wopt (postTransform <$> pandoc))

standardPostPage :: WriterOptions -> Item Pandoc -> Compiler (Item String)
standardPostPage wopt pandoc = snapshotPlainPost wopt pandoc >>= wrapPostPage

alectryonPostPage :: WriterOptions -> Alectryon.Options -> FilePath -> [String]
                 -> Item Pandoc -> Compiler (Item String)
alectryonPostPage wopt alectryonOpts cacheFile args pandoc = do
    -- Feed snapshot: plain Coq-highlighted HTML (no proof states).
    _ <- snapshotPlainPost wopt pandoc
    -- Web page: rewrite Coq/Rocq blocks to Alectryon, number cross-refs and
    -- bold, then run Alectryon (recording proof states) on the alectryon blocks.
    let pre = alectryonTransform (itemBody pandoc)
    annotated <- Alectryon.transformAlectryon alectryonOpts (Just cacheFile) args
                     Alectryon.rawHTML pre
    let webHtml = writePandocWith wopt (pandoc { itemBody = annotated })
    wrapPostPage webHtml

--------------------------------------------------------------------------------

config :: Configuration
config = defaultConfiguration
  { destinationDirectory = "docs"
  }

main :: IO ()
main = do
    -- text is a dependency of the site library only, so it stays hidden from
    -- this executable; read the file as a String and let the IsString
    -- instance produce the Text parseCoqSyntax expects.
    coqXml <- fromString <$> readFile "syntax/coq.xml"
    coq    <- either (error . ("syntax/coq.xml: " ++)) return (parseCoqSyntax coqXml)
    let postSyntaxes = coqSyntaxMap coq
    Alectryon.hakyllWith config $ \alectryonOpts -> do
        match "images/**" $ do
            route   idRoute
            compile copyFileCompiler

        match "pdfs/*" $ do
            route   idRoute
            compile copyFileCompiler

        match "css/*" $ do
            route   idRoute
            compile copyFileCompiler

        match "mysteries/arith/*" $ do
            route   idRoute
            compile copyFileCompiler

        match "mysteries/cond/*" $ do
            route   idRoute
            compile copyFileCompiler

        match "mysteries/func/*" $ do
            route   idRoute
            compile copyFileCompiler

        match "mysteries/array/*" $ do
            route   idRoute
            compile copyFileCompiler

        -- Publications source of truth. Stored as a raw string (not routed, so no
        -- output file); loadPublications parses it. Editing it rebuilds the listing pages.
        match "publications.bib" $ compile getResourceString

        -- Talks source of truth. Same pattern as publications.bib: stored raw,
        -- not routed; loadTalkYears parses it. Editing it rebuilds index.html.
        match "talks.yaml" $ compile getResourceString

        match "courses/*" $ do
            route $ setExtension "html"
            -- boldToB: this site's prose bold means attention, not importance.
            compile $ pandocCompilerWithTransform
                          defaultHakyllReaderOptions defaultHakyllWriterOptions boldToB
                >>= loadAndApplyTemplate "templates/course.html"  (courseContext <> defaultContext)
                >>= loadAndApplyTemplate "templates/default.html" (navLinkPrefix <> defaultContext)
                >>= relativizeUrls

        match "posts/*" $ do
            route $ setExtension "html"
            -- The whole pandoc pipeline (rocq fences, cross-references, bold
            -- as <b>, KaTeX math, Coq highlighting, and Alectryon proof states
            -- on posts that opt in via an "alectryon" front-matter field) is
            -- the Posts module's; postPageCompiler adapts it to Hakyll.
            compile $ postPageCompiler postSyntaxes alectryonOpts

        match "index.html" $ do
            route idRoute
            compile $ do
                courses <- sortCourses =<< loadAll "courses/*"
                renderPage $
                    listField "courses" (courseContext <> defaultContext) (return courses)
                    <> listField "talkyears" talkYearContext loadTalkYears
                    <> pubsContext

        match "publication.html" $ do
            route idRoute
            compile $ renderPage pubsContext

        match "blog.html" $ do
            route idRoute
            compile $ do
                posts <- sortPosts =<< publishedPosts =<< loadAll "posts/*"
                renderPage $
                    listField "posts" postCtx (return posts)
                    <> navLinkPrefix
                    <> postCtx

        -- create, not match: feed.xml has no source file on disk.
        create ["feed.xml"] $ do
            route idRoute
            compile $ do
                posts <- sortPosts =<< publishedPosts =<< loadAllSnapshots "posts/*" "content"
                renderAtom feedConfiguration postCtx posts

        -- Sitemap and robots.txt, created like the feed: the sitemap lists
        -- the canonical public pages only — home, blog, publications, every
        -- course page, published posts — mirroring the order of the pages
        -- that list them. Drafts (unlisted and noindex), the feed, the
        -- copied assets, and the deliberately unlinked mysteries apps stay
        -- out; robots.txt allows all crawlers and points at the sitemap.
        create ["sitemap.xml"] $ do
            route idRoute
            compile $ do
                courses <- sortCourses =<< loadAllStrings "courses/*"
                posts   <- sortPosts =<< publishedPosts =<< loadAllStrings "posts/*"
                urls    <- mapM routeUrl $
                    [ "index.html", "blog.html", "publication.html" ]
                        ++ map itemIdentifier courses
                        ++ map itemIdentifier posts
                makeItem (sitemapXml urls)

        create ["robots.txt"] $ do
            route idRoute
            compile $ makeItem $ unlines
                [ "User-agent: *"
                , "Allow: /"
                , ""
                , "Sitemap: " ++ siteRoot ++ "/sitemap.xml"
                ]

        match "templates/*" $ compile templateBodyCompiler

-- Shared by index.html and publication.html: both render the published and
-- drafts lists (via templates/pub-sections.html) plus the base page fields.
pubsContext :: Context String
pubsContext =
    listField "published" paperContext loadPublished
    <> listField "drafts" paperContext loadDrafts
    <> navLinkPrefix
    <> defaultContext

-- Compile a top-level page: the page body is itself a template, then it is
-- wrapped in default.html.
renderPage :: Context String -> Compiler (Item String)
renderPage ctx =
    getResourceBody
        >>= applyAsTemplate ctx
        >>= loadAndApplyTemplate "templates/default.html" ctx
        >>= relativizeUrls

--------------------------------------------------------------------------------

-- Sitemap and robots.txt: created like the feed (no source file on disk).

-- | 'loadAll' at the String body type. Its polymorphism needs a concrete
-- body when the items are used only by identifier, as the sitemap does.
loadAllStrings :: Pattern -> Compiler [Item String]
loadAllStrings = loadAll

-- | The absolute site URL of a routed identifier's output file. The
-- homepage maps to the site root; every other page, to its route.
routeUrl :: Identifier -> Compiler String
routeUrl ident = do
    route <- getRoute ident
    return . (siteRoot ++) $ case route of
        Nothing           -> error ("no route for " ++ show ident)
        Just "index.html" -> "/"
        Just path         -> toUrl path

-- | The sitemap document: one @<url>@ element per page, in the order the
-- caller chose (the pages that list them).
sitemapXml :: [String] -> String
sitemapXml urls = unlines $
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    , "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"
    ]
    ++ [ "  <url><loc>" ++ url ++ "</loc></url>" | url <- urls ]
    ++ [ "</urlset>" ]
