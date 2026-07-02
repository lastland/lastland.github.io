--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Data.List   (sortBy, nub)
import           Data.Ord    (Down(..), comparing)
import qualified Data.Text   as T
import qualified Data.Text.Encoding as TE
import qualified Data.Yaml   as Yaml
import           Data.Yaml   (FromJSON(..), (.:), (.:?))
import           Data.Aeson  (withObject)
import           Hakyll
import           Publications


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
-- Talks: parsed from talks.yaml at build time.

data Venue = Venue
    { venueText :: String
    , venueUrl  :: Maybe String
    }

data Talk = Talk
    { talkTitle  :: String
    , talkYear   :: Int
    , talkNote   :: Maybe String
    , talkVenues :: [Venue]
    }

instance FromJSON Venue where
    parseJSON = withObject "venue" $ \o ->
        Venue <$> o .: "text" <*> o .:? "url"

instance FromJSON Talk where
    parseJSON = withObject "talk" $ \o ->
        Talk <$> o .: "title" <*> o .: "year"
             <*> o .:? "note" <*> o .: "venues"

parseTalks :: String -> [Talk]
parseTalks s = case Yaml.decodeEither' (TE.encodeUtf8 (T.pack s)) of
    Left err    -> error ("talks.yaml parse error: "
                          ++ Yaml.prettyPrintParseException err)
    Right talks -> talks

-- Years descending; file order preserved within a year (filter is stable).
groupTalksByYear :: [Talk] -> [(Int, [Talk])]
groupTalksByYear ts =
    [ (y, filter ((== y) . talkYear) ts) | y <- years ]
  where
    years = sortBy (comparing Down) (nub (map talkYear ts))

-- Load the raw talks.yaml, parse it, and lift each year group to an Item
-- for listField. Mirrors loadPublications.
loadTalkYears :: Compiler [Item (Int, [Talk])]
loadTalkYears = do
    raw <- loadBody "talks.yaml" :: Compiler String
    mapM makeItem (groupTalksByYear (parseTalks raw))

venueContext :: Context Venue
venueContext = mconcat
    [ field "text" (return . venueText . itemBody)
    , field "url"  $ \i ->
        maybe (noResult "Venue has no url") return (venueUrl (itemBody i))
    ]

talkContext :: Context Talk
talkContext = mconcat
    [ field "title" (return . talkTitle . itemBody)
    , field "note"  $ \i ->
        maybe (noResult "Talk has no note") return (talkNote (itemBody i))
    -- Presence-based flag: $if(multivenue)$ picks <ul> vs <p> markup.
    , field "multivenue" $ \i ->
        if length (talkVenues (itemBody i)) > 1
            then return "true"
            else noResult "Talk has a single venue"
    , listFieldWith "venues" venueContext (mapM makeItem . talkVenues . itemBody)
    ]

talkYearContext :: Context (Int, [Talk])
talkYearContext = mconcat
    [ field "year" (return . show . fst . itemBody)
    , listFieldWith "talks" talkContext (mapM makeItem . snd . itemBody)
    ]


--------------------------------------------------------------------------------

config :: Configuration
config = defaultConfiguration
  { destinationDirectory = "docs"
  }

main :: IO ()
main = hakyllWith config $ do
    match "images/*" $ do
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
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/course.html"  defaultContext
            >>= loadAndApplyTemplate "templates/default.html" (navLinkPrefix `mappend` defaultContext)
            >>= relativizeUrls

    match "index.html" $ do
        route idRoute
        compile $ do
            courses <- recentFirst =<< loadAll "courses/*"
            let ctx =
                    listField "courses" defaultContext (return courses)
                    `mappend` listField "published" paperContext loadPublished
                    `mappend` listField "drafts" paperContext loadDrafts
                    `mappend` listField "talkyears" talkYearContext loadTalkYears
                    `mappend` navLinkPrefix
                    `mappend` defaultContext
            getResourceBody
                >>= applyAsTemplate ctx
                >>= loadAndApplyTemplate "templates/default.html" ctx
                >>= relativizeUrls

    match "publication.html" $ do
        route idRoute
        compile $ do
            let pubCtx =
                    listField "published" paperContext loadPublished
                    `mappend` listField "drafts" paperContext loadDrafts
                    `mappend` navLinkPrefix
                    `mappend` defaultContext
            getResourceBody
                >>= applyAsTemplate pubCtx
                >>= loadAndApplyTemplate "templates/default.html" pubCtx
                >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler
