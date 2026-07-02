--------------------------------------------------------------------------------
{-# LANGUAGE TupleSections #-}
-- | The Publications module owns every bib semantic: parsing, LaTeX decoding,
-- author formatting, venue derivation, the published/draft partition, ordering,
-- and button visibility. Its interface is 'parsePublications': bib text in,
-- display-ready 'Paper's out, every failure as a 'Left'. Templates downstream
-- only test key presence; they never decide anything.
module Publications
    ( -- * Interface
      Paper
    , Publications(..)
    , parsePublications
      -- * Internals exposed for the test suite
    , PaperClass(..)
    , classify
    , toPaper
    , sortPapers
    , deriveVenue
    , metaYear
    , composeJournal
    , extractAcronym
    , formatAuthors
    , decodeLaTeX
    , monthNum
    ) where

import           Data.List   (intercalate, sortOn, isInfixOf)
import           Data.Char   (toLower, isDigit, isUpper, isAlphaNum, isSpace)
import           Data.Maybe  (fromMaybe)
import           Data.Ord    (Down(..))
import           Control.Applicative ((<|>))
import           Text.Read   (readMaybe)
import qualified Data.Text   as T
import           Text.Parsec (parse)
import qualified Text.BibTeX.Parse  as BibParse
import qualified Text.BibTeX.Entry  as BibEntry
import           Text.Pandoc (runPure, readLaTeX, writePlain, def)
import           Text.Pandoc.Options (WrapOption(WrapNone), writerWrapText, writerExtensions, readerExtensions)
import           Text.Pandoc.Extensions (disableExtension, Extension(Ext_smart))

-- A paper is a normalized, decoded assoc-list of fields ready for templates.
type Paper = [(String, String)]

-- Every paper is exactly one of these; 'classify' rejects anything else.
data Publications = Publications
    { published :: [Paper]
    , drafts    :: [Paper]
    }

-- | The whole pipeline: parse, classify every entry, partition, sort.
parsePublications :: String -> Either String Publications
parsePublications s = do
    entries <- either (Left . ("publications.bib parse error: " ++) . show) Right
                      (parse (BibParse.skippingLeadingSpace BibParse.file) "publications.bib" s)
    classified <- mapM ((\e -> (, e) <$> classify e) . BibEntry.lowerCaseFieldNames)
                       entries
    let papersOf c = sortPapers [ toPaper e | (c', e) <- classified, c' == c ]
    return (Publications (papersOf Published) (papersOf Draft))

--------------------------------------------------------------------------------
-- Partition

data PaperClass = Published | Draft
    deriving (Eq, Show)

-- | A paper with a derivable venue is published; one with draft = {true} is a
-- draft. Anything else (neither, or a half-finished promotion with both) is a
-- build error naming the entry.
classify :: BibEntry.T -> Either String PaperClass
classify e = case (deriveVenue e, flagSet "draft" e) of
    (Just _,  False) -> Right Published
    (Nothing, True)  -> Right Draft
    (Just _,  True)  -> Left (ctx ++ "has both a derivable venue and draft = {true}; \
                              \finish the promotion by dropping draft, or remove the venue fields")
    (Nothing, False) -> Left (ctx ++ "has neither a derivable venue nor draft = {true}; \
                              \add booktitle/journal/venue, or mark it draft")
  where ctx = "publications.bib entry '" ++ BibEntry.identifier e ++ "' "

-- Presence-based boolean field: set unless absent or literally "false".
flagSet :: String -> BibEntry.T -> Bool
flagSet k e = case trim <$> lookup k (BibEntry.fields e) of
    Nothing -> False
    Just v  -> map toLower v /= "false"

--------------------------------------------------------------------------------
-- Field derivation

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

-- Title link target: link else preprint else absent. Stored raw (never
-- decoded). Falls back to preprint even when openaccess hides its button.
primaryUrl :: BibEntry.T -> Maybe String
primaryUrl e = (trim <$> lookup "link" (BibEntry.fields e))
           <|> (trim <$> lookup "preprint" (BibEntry.fields e))

monthNum :: String -> Int
monthNum m = case map toLower (take 3 (trim m)) of
  "jan"->1; "feb"->2; "mar"->3; "apr"->4; "may"->5; "jun"->6
  "jul"->7; "aug"->8; "sep"->9; "oct"->10; "nov"->11; "dec"->12
  _ -> fromMaybe 0 (readMaybe (trim m))

--------------------------------------------------------------------------------
-- Normalization

toPaper :: BibEntry.T -> Paper
toPaper e = concat
    [ [("title",   decodeLaTeX (get "title"))]
    , [("authors", formatAuthors (get "author"))]
    , [("year",    trim (get "year"))]
    , kv     "venue"      (deriveVenue e)
    , kv     "metayear"   (metaYear e)
    , kv     "link"       (f "link")
    -- openaccess hides the Pre-print button entirely; primaryurl may still
    -- fall back to the preprint URL for the title link.
    , kv     "preprint"   (if flagSet "openaccess" e then Nothing else f "preprint")
    , kv     "artifact"   (f "artifact")
    , kv     "talk"       (f "talk")
    , kvText "award"      (f "award")
    , kvText "submitted"  (f "submitted")
    , bool   "openaccess", bool "draft"
    , kv     "primaryurl" (primaryUrl e)
    , kv     "_month"     (show . monthNum <$> f "month")
    ]
  where
    f k      = trim <$> lookup k (BibEntry.fields e)
    get k    = fromMaybe "" (f k)
    kv  k    = maybe [] (\v -> [(k, v)])
    kvText k = maybe [] (\v -> [(k, decodeLaTeX v)])
    bool k   = [(k, "true") | flagSet k e]

sortPapers :: [Paper] -> [Paper]
sortPapers = sortOn (Down . key)
  where key p = ( readDef 0 (lookup "year"   p)
                , readDef 0 (lookup "_month" p) )
        readDef d = maybe d (fromMaybe d . readMaybe . trim)
