--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
-- | The Posts module owns every blog-post semantic: front-matter validation
-- (title, date, description, draft), the date parse (exactly "YYYY-MM-DD")
-- and display ("August 12, 2026"), the index ordering key (date descending,
-- title ascending breaks ties), and the markdown-to-HTML pipeline decisions —
-- rocq fences normalized to coq, numbered cross-references, bold as <b>,
-- KaTeX math, and the vendored Coq syntax definition. Its interface is
-- 'parsePostMeta': front-matter lookups in, a display-ready 'PostMeta' out,
-- every failure as a 'Left'.
module Posts
    ( -- * Interface
      PostMeta
    , postTitle
    , postDate
    , postDescription
    , postDraft
    , parsePostMeta
    , parsePostDate
    , formatPostDate
    , postSortKey
    , postHasMath
    , normalizeRocq
    , applyCrossRef
    , postTransform
    , parseCoqSyntax
    , coqSyntaxMap
    , postWriterOptions
      -- * Internals exposed for the test suite
    , stringify
    ) where

import           Data.Char (isDigit)
import           Data.List (isInfixOf)
import qualified Data.Map.Strict as M
import           Data.Ord (Down (..))
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import           Data.Time.Calendar (Day, fromGregorianValid, toGregorian)
import           Prose (boldToB)
import           Skylighting (Syntax (..), SyntaxMap, defaultSyntaxMap)
import           Skylighting.Parser (parseSyntaxDefinitionFromText)
import           Text.Pandoc.CrossRef (defaultCrossRefAction, runCrossRef)
import           Text.Pandoc.Definition (Block (..), Format (..), Pandoc (..))
import           Text.Pandoc.Options (HTMLMathMethod (..), WriterOptions (..))
import qualified Text.Pandoc.Shared as PandocShared (stringify)
import           Text.Pandoc.Walk (walk)

-- A validated post front matter: the required fields, parsed.
data PostMeta = PostMeta
    { postTitle       :: String
    , postDate        :: Day
    , postDescription :: String
    , postDraft       :: Bool
    } deriving (Eq, Show)

-- | Parse the post front matter. title, date, and description are required
-- and non-empty; date must parse as 'parsePostDate'. draft is optional:
-- absent or "false" means published, "true" means draft, anything else is an
-- error naming the value.
parsePostMeta :: (String -> Maybe String) -> Either String PostMeta
parsePostMeta lookupField = do
    title <- required "title"
    date <- parsePostDate =<< required "date"
    description <- required "description"
    draft <- parseDraft (lookupField "draft")
    Right PostMeta
        { postTitle = title
        , postDate = date
        , postDescription = description
        , postDraft = draft
        }
  where
    required key = case lookupField key of
        Just value | not (null value) -> Right value
        _ -> Left ("missing required field " ++ show key)
    parseDraft Nothing        = Right False
    parseDraft (Just "true")  = Right True
    parseDraft (Just "false") = Right False
    parseDraft (Just other)   = Left
        ("unrecognized draft value " ++ show other
         ++ " (expected \"true\" or \"false\")")

-- | Parse a post date, exactly zero-padded "YYYY-MM-DD" and a valid calendar
-- day. Anything else fails naming the offending string.
parsePostDate :: String -> Either String Day
parsePostDate str = case splitOn '-' str of
    [ys, ms, ds]
        | digits 4 ys, digits 2 ms, digits 2 ds
        , Just day <- fromGregorianValid (read ys) (read ms) (read ds)
        -> Right day
    _ -> Left ("unrecognized date " ++ show str
               ++ " (expected \"YYYY-MM-DD\")")
  where
    digits n s = length s == n && all isDigit s
    splitOn c s = case break (== c) s of
        (pre, _ : rest) -> pre : splitOn c rest
        (pre, [])       -> [pre]

-- | Display a date as "August 12, 2026": full month name, day of month
-- without zero-padding, year.
formatPostDate :: Day -> String
formatPostDate day =
    monthNames !! (m - 1) ++ " " ++ show d ++ ", " ++ show y
  where
    (y, m, d) = toGregorian day
    monthNames = [ "January", "February", "March", "April", "May", "June"
                 , "July", "August", "September", "October", "November"
                 , "December" ]

-- | The index sort key: date descending, title ascending breaks ties.
postSortKey :: PostMeta -> (Down Day, String)
postSortKey meta = (Down (postDate meta), postTitle meta)

-- | Whether the rendered HTML carries math, detected by pandoc's
-- KaTeX-method output spans. Decides whether the page loads KaTeX at all.
postHasMath :: String -> Bool
postHasMath html =
    isInfixOf "class=\"math inline\"" html
    || isInfixOf "class=\"math display\"" html

-- | Rename rocq code fences to coq: the vendored syntax definition is keyed
-- under its historical name, while authors write ```rocq.
normalizeRocq :: Pandoc -> Pandoc
normalizeRocq = walk rename
  where
    rename (CodeBlock (ident, classes, kvs) code) =
        CodeBlock (ident, map rocqToCoq classes, kvs) code
    rename block = block
    rocqToCoq "rocq" = "coq"
    rocqToCoq c      = c

-- | Resolve numbered cross-references (figures, equations, tables) in
-- process, purely: pandoc-crossref with its default action, HTML format.
applyCrossRef :: Pandoc -> Pandoc
applyCrossRef doc@(Pandoc meta _) =
    runCrossRef meta (Just (Format "html")) defaultCrossRefAction doc

-- | The whole AST pipeline, in order: rocq fences normalized so the syntax
-- definition matches, cross-references numbered, bold rendered as <b>.
postTransform :: Pandoc -> Pandoc
postTransform = boldToB . applyCrossRef . normalizeRocq

-- | Parse the vendored Kate XML syntax definition from its text. The
-- file name stands in for the one the definition ships in; skylighting
-- derives the syntax's short name from it.
parseCoqSyntax :: T.Text -> Either String Syntax
parseCoqSyntax = parseSyntaxDefinitionFromText "coq.xml" . TL.fromStrict

-- | Extend the default syntax map with the vendored Coq definition, keyed by
-- its exact syntax name ("Coq"): skylighting resolves internal context
-- switches by exact name, so a lowercase key would break them.
coqSyntaxMap :: Syntax -> SyntaxMap
coqSyntaxMap coq = M.insert (sName coq) coq defaultSyntaxMap

-- | The writer options a post is rendered with: KaTeX for math (so math
-- renders without relying on client-side typesetting) and the extended
-- syntax map (so rocq blocks highlight).
postWriterOptions :: WriterOptions -> SyntaxMap -> WriterOptions
postWriterOptions opts sm = opts
    { writerHTMLMathMethod = KaTeX katexBaseUrl
    , writerSyntaxMap = sm
    }

-- Pinned KaTeX release. Pandoc's fragment output ignores this URL (it only
-- matters in standalone mode, which Hakyll never uses); the <link>/<script>
-- the browser actually loads live in templates/default.html. Keep the two
-- pins in sync when upgrading KaTeX.
katexBaseUrl :: T.Text
katexBaseUrl = "https://cdn.jsdelivr.net/npm/katex@0.18.4/dist/"

-- | Flatten a document to plain text, for assertions. pandoc-types 1.23
-- removed 'stringify' from "Text.Pandoc.Generic"; pandoc's lives in
-- "Text.Pandoc.Shared" and returns 'T.Text', so unpack to 'String'.
stringify :: Pandoc -> String
stringify = T.unpack . PandocShared.stringify
