--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Data.List   (intercalate, sortBy, isInfixOf, nub)
import           Data.Char   (toLower, isDigit, isUpper, isAlphaNum, isSpace)
import           Data.Ord    (Down(..), comparing)
import           Control.Applicative ((<|>))
import           Text.Read   (readMaybe)
import qualified Data.Text   as T
import qualified Data.Text.Encoding as TE
import qualified Data.Yaml   as Yaml
import           Data.Yaml   (FromJSON(..), (.:), (.:?))
import           Data.Aeson  (withObject)
import           Text.Parsec (parse)
import qualified Text.BibTeX.Parse  as BibParse
import qualified Text.BibTeX.Entry  as BibEntry
import           Text.Pandoc (runPure, readLaTeX, writePlain, def)
import           Text.Pandoc.Options (WrapOption(WrapNone), writerWrapText, writerExtensions, readerExtensions)
import           Text.Pandoc.Extensions (disableExtension, Extension(Ext_smart))
import           Hakyll hiding (trim)


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

-- Custom compiler that replaces <strong> with <span class="fw-bold">
customPandocCompiler :: Compiler (Item String)
customPandocCompiler = do
    item <- pandocCompiler
    return $ fmap replaceStrongTags item
  where
    replaceStrongTags :: String -> String
    replaceStrongTags = replaceAll' "</strong>" "</span>" . replaceAll' "<strong>" "<span class=\"fw-bold\">"

    replaceAll' :: String -> String -> String -> String
    replaceAll' old new = go
      where
        go [] = []
        go str@(x:xs)
            | old `isPrefixOf'` str = new ++ go (drop (length old) str)
            | otherwise = x : go xs

    isPrefixOf' :: String -> String -> Bool
    isPrefixOf' [] _ = True
    isPrefixOf' _ [] = False
    isPrefixOf' (x:xs) (y:ys) = x == y && xs `isPrefixOf'` ys


--------------------------------------------------------------------------------
-- Publications: parsed from publications.bib at build time.

-- A paper is a normalized, decoded assoc-list of fields ready for templates.
type Paper = [(String, String)]

trim :: String -> String
trim = f . f where f = reverse . dropWhile isSpace

-- Decode LaTeX escapes/braces to Unicode for display. Only invoke pandoc when
-- the value actually contains LaTeX markup, so clean strings pass through
-- untouched (and URLs are never decoded by callers).
decodeLaTeX :: String -> String
decodeLaTeX s
    | not (any (\c -> c == '\\' || c == '{' || c == '}') s) = s
    | otherwise =
        case runPure (readLaTeX ropts (T.pack s) >>= writePlain wopts) of
            Right t -> T.unpack (T.strip t)
            Left  _ -> s
  where
    -- Disable smart quotes so apostrophes/dashes are preserved verbatim, and
    -- disable text wrapping so long titles never gain stray newlines.
    ropts = def { readerExtensions = disableExtension Ext_smart (readerExtensions def) }
    wopts = def { writerWrapText = WrapNone
                , writerExtensions = disableExtension Ext_smart (writerExtensions def) }

-- "Yao Li 0004" -> "Yao Li": drop DBLP all-digit disambiguation tokens.
stripDisambig :: String -> String
stripDisambig = unwords . filter (not . allDigits) . words
  where allDigits w = not (null w) && all isDigit w

-- "Last, First and First Last and ..." -> "First Last, First Last, ...".
-- flipName is a no-op on names without a comma, so both orderings work.
formatAuthors :: String -> String
formatAuthors raw =
    intercalate ", "
  . map (stripDisambig . trim . decodeLaTeX . BibEntry.flipName)
  $ BibParse.splitAuthorList raw

composeJournal :: String -> Maybe String -> Maybe String -> String
composeJournal j (Just v) (Just n) = j ++ ", " ++ v ++ "(" ++ n ++ ")"
composeJournal j (Just v) Nothing  = j ++ ", " ++ v
composeJournal j Nothing  _        = j

-- DBLP conference booktitles are paragraph-long; pull out the "ACRONYM YEAR"
-- token pair (e.g. "ESOP 2026"). Falls back to the whole string if not found.
extractAcronym :: String -> String
extractAcronym bt = scan (map clean toks)
  where
    toks    = words (map (\c -> if c == ',' then ' ' else c) bt)
    clean   = filter isAlphaNum
    isYear w = length w == 4 && all isDigit w &&
               case w of { (c:_) -> c == '1' || c == '2'; _ -> False }
    isAcr w  = length w >= 2 && all (\c -> isUpper c || isDigit c) w && any isUpper w
    scan (a:b:rest) | isAcr a && isYear b = a ++ " " ++ b
                    | otherwise           = scan (b:rest)
    scan _ = bt

-- Display venue: explicit override -> journal composition -> booktitle acronym.
deriveVenue :: BibEntry.T -> Maybe String
deriveVenue e = case f "venue" of
    Just v  -> Just (decodeLaTeX v)
    Nothing -> case f "journal" of
      Just j  -> Just (composeJournal (decodeLaTeX j) (decodeLaTeX <$> f "volume") (decodeLaTeX <$> f "number"))
      Nothing -> fmap (extractAcronym . decodeLaTeX) (f "booktitle")
  where f k = trim <$> lookup k (BibEntry.fields e)

-- Year for the meta line, present only when the venue doesn't already contain
-- it (conference acronyms embed the year; journals and some venue overrides
-- don't; drafts have no venue at all).
metaYear :: BibEntry.T -> Maybe String
metaYear e
  | null y                                             = Nothing
  | maybe True (not . (y `isInfixOf`)) (deriveVenue e) = Just y
  | otherwise                                          = Nothing
  where y = maybe "" trim (lookup "year" (BibEntry.fields e))

-- Title link target: link else preprint else absent. Stored raw (never decoded).
primaryUrl :: BibEntry.T -> Maybe String
primaryUrl e = (trim <$> lookup "link" (BibEntry.fields e))
           <|> (trim <$> lookup "preprint" (BibEntry.fields e))

monthNum :: String -> Int
monthNum m = case map toLower (take 3 (trim m)) of
  "jan"->1; "feb"->2; "mar"->3; "apr"->4; "may"->5; "jun"->6
  "jul"->7; "aug"->8; "sep"->9; "oct"->10; "nov"->11; "dec"->12
  _ -> maybe 0 id (readMaybe (trim m))

toPaper :: BibEntry.T -> Paper
toPaper e = concat
    [ [("title",   decodeLaTeX (get "title"))]
    , [("authors", formatAuthors (get "author"))]
    , [("year",    trim (get "year"))]
    , kv     "venue"      (deriveVenue e)
    , kv     "metayear"   (metaYear e)
    , kv     "link"       (f "link")
    , kv     "preprint"   (f "preprint")
    , kv     "artifact"   (f "artifact")
    , kv     "talk"       (f "talk")
    , kvText "award"      (f "award")
    , kvText "submitted"  (f "submitted")
    , bool   "openaccess", bool "draft"
    , kv     "primaryurl" (primaryUrl e)
    , kv     "_month"     (show . monthNum <$> f "month")
    ]
  where
    f k         = trim <$> lookup k (BibEntry.fields e)
    get k       = maybe "" id (f k)
    kv  k mv    = maybe [] (\v -> [(k, v)]) mv
    kvText k mv = maybe [] (\v -> [(k, decodeLaTeX v)]) mv
    bool k      = case f k of
        Nothing -> []
        Just v | map toLower v == "false" -> []
               | otherwise                -> [(k, "true")]

sortPapers :: [Paper] -> [Paper]
sortPapers = sortBy (comparing (Down . key))
  where key p = ( readDef 0 (lookup "year"   p)
                , readDef 0 (lookup "_month" p) )
        readDef d = maybe d (\s -> maybe d id (readMaybe (trim s)))

parsePapers :: String -> [Paper]
parsePapers s =
  case parse (BibParse.skippingLeadingSpace BibParse.file) "publications.bib" s of
    Left err      -> error ("publications.bib parse error: " ++ show err)
    Right entries -> sortPapers (map (toPaper . BibEntry.lowerCaseFieldNames) entries)

-- Load the raw publications.bib (stored as a String, so it is Writable/loadable),
-- parse it, and lift each paper to an Item for listField.
loadPapers :: Compiler [Item Paper]
loadPapers = do
    raw <- loadBody "publications.bib" :: Compiler String
    mapM makeItem (parsePapers raw)

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
-- for listField. Mirrors loadPapers.
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
    -- output file); loadPapers parses it. Editing it rebuilds the listing pages.
    match "publications.bib" $ compile getResourceString

    -- Talks source of truth. Same pattern as publications.bib: stored raw,
    -- not routed; loadTalkYears parses it. Editing it rebuilds index.html.
    match "talks.yaml" $ compile getResourceString

    match "courses/*" $ do
        route $ setExtension "html"
        compile $ customPandocCompiler
            >>= loadAndApplyTemplate "templates/course.html"  defaultContext
            >>= loadAndApplyTemplate "templates/default.html" (navLinkPrefix `mappend` defaultContext)
            >>= relativizeUrls

    match "index.html" $ do
        route idRoute
        compile $ do
            courses <- recentFirst =<< loadAll "courses/*"
            let ctx =
                    listField "courses" defaultContext (return courses)
                    `mappend` listField "papers" paperContext loadPapers
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
                    listField "papers" paperContext loadPapers
                    `mappend` navLinkPrefix
                    `mappend` defaultContext
            getResourceBody
                >>= applyAsTemplate pubCtx
                >>= loadAndApplyTemplate "templates/default.html" pubCtx
                >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler
