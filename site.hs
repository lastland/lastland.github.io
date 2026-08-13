--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Control.Monad (filterM)
import           Courses
import           Data.List (sortOn)
import           Data.Ord (Down (..))
import           Data.String (fromString)
import           Hakyll
import           Posts
import           Publications
import           Prose
import           Talks


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
    either (error . named) return (parsePostMeta (`lookupString` metadata))
  where
    named msg = "post " ++ toFilePath ident ++ ": " ++ msg

-- A field per template key. date/isodate/description come from the validated
-- front matter; hasmath is presence-based ($if(hasmath)$ gates the KaTeX
-- assets in default.html), mirroring paperContext's field + noResult style.
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
    ]

-- Blog order: date descending, title ascending breaks ties (postSortKey).
sortPosts :: [Item a] -> Compiler [Item a]
sortPosts = sortItemsBy (fmap postSortKey . loadPostMeta . itemIdentifier)

-- Drafts stay buildable (their pages exist) but are kept off blog.html and
-- the feed, mirroring the published/draft partition in Publications.
publishedPosts :: [Item a] -> Compiler [Item a]
publishedPosts = filterM (fmap (not . postDraft) . loadPostMeta . itemIdentifier)

feedConfiguration :: FeedConfiguration
feedConfiguration = FeedConfiguration
    { feedTitle       = "Yao Li - Blog"
    , feedDescription = "Posts by Yao Li"
    , feedAuthorName  = "Yao Li"
    , feedAuthorEmail = "liyao@pdx.edu"
    , feedRoot        = "https://lastland.github.io"
    }

-- Context a post page is rendered with (post.html and the default.html
-- wrap). katexversion is the Posts module's pin, interpolated by
-- default.html into the KaTeX CDN tags so the version lives in one place.
postCtx :: Context String
postCtx = postContext
    <> constField "katexversion" katexVersion
    <> defaultContext

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
    hakyllWith config $ do
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
            -- as <b>, KaTeX math, Coq highlighting) is the Posts module's.
            compile $
                pandocCompilerWithTransform
                    defaultHakyllReaderOptions
                    (postWriterOptions defaultHakyllWriterOptions postSyntaxes)
                    postTransform
                >>= saveSnapshot "content"
                >>= loadAndApplyTemplate "templates/post.html" postCtx
                >>= loadAndApplyTemplate "templates/default.html" (postCtx <> navLinkPrefix)
                >>= relativizeUrls

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
