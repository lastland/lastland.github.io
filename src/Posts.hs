--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
-- | The Posts module owns every blog-post semantic: front-matter validation
-- (title, date, description, draft, and the Alectryon opt-in plus its
-- required cache), the date parse (exactly "YYYY-MM-DD") and display
-- ("August 12, 2026"), the index ordering key (date descending, title
-- ascending breaks ties), and the markdown-to-HTML pipeline decisions —
-- rocq fences normalized to coq, coq/rocq fences rewritten to alectryon on
-- Alectryon-enabled posts, numbered cross-references, bold as <b>, KaTeX
-- math, and the vendored Coq syntax definition. Its interface is
-- 'parsePostMeta': a JSON 'KeyMap' of front matter in (so a scalar
-- @alectryon:@ is distinguished from a list and rejected), a display-ready
-- 'PostMeta' out, every failure as a 'Left'.
module Posts
    ( -- * Interface
      PostMeta
    , postTitle
    , postDate
    , postDescription
    , postDraft
    , postAlectryon
    , AlectryonConfig
    , alectryonArgs
    , alectryonCache
    , parsePostMeta
    , parsePostDate
    , formatPostDate
    , postSortKey
    , postHasMath
    , postHasAlectryon
    , normalizeRocq
    , normalizeAlectryon
    , applyCrossRef
    , postTransform
    , alectryonTransform
    , parseCoqSyntax
    , coqSyntaxMap
    , postWriterOptions
    , katexVersion
      -- * Internals exposed for the test suite
    , stringify
    ) where

import           Data.Char (isDigit)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AKey
import qualified Data.Aeson.KeyMap as KeyMap
import           Data.List (isInfixOf)
import qualified Data.Map.Strict as M
import           Data.Ord (Down (..))
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import           Data.Time.Calendar (Day, fromGregorianValid)
import           Data.Time.Format (defaultTimeLocale, formatTime)
import qualified Data.Vector as V
import           Prose (boldToB)
import           Skylighting (Syntax (..), SyntaxMap, defaultSyntaxMap)
import           Skylighting.Parser (parseSyntaxDefinitionFromText)
import           Text.Pandoc.CrossRef (defaultCrossRefAction, runCrossRef)
import           Text.Pandoc.Definition (Block (..), Format (..), Pandoc (..))
import           Text.Pandoc.Options (HTMLMathMethod (..), WriterOptions (..))
import qualified Text.Pandoc.Shared as PandocShared (stringify)
import           Text.Pandoc.Walk (walk)

-- | A validated Alectryon configuration: the arguments forwarded to the
-- Alectryon executable and the committed cache directory holding the
-- proof-state HTML. Required on every post that opts in via an @alectryon:@
-- front-matter field.
data AlectryonConfig = AlectryonConfig
    { alectryonArgs  :: [String]
    , alectryonCache :: FilePath
    } deriving (Eq, Show)

-- A validated post front matter: the required fields, parsed.
data PostMeta = PostMeta
    { postTitle       :: String
    , postDate        :: Day
    , postDescription :: String
    , postDraft       :: Bool
    , postAlectryon   :: Maybe AlectryonConfig
    } deriving (Eq, Show)

-- | Parse the post front matter. title, date, and description are required
-- and non-empty; date must parse as 'parsePostDate'. draft is optional:
-- absent or false means published, true means draft — a YAML boolean or a
-- "true"/"false" string, since front matter arrives YAML-typed — and
-- anything else is an error naming the value. alectryon is optional: absent
-- means a standard
-- post; a list (possibly empty) of string arguments opts the post into
-- Alectryon and requires a non-empty 'alectryon-cache' field; any other
-- shape (e.g. a scalar) fails the build.
parsePostMeta :: KeyMap.KeyMap Aeson.Value -> Either String PostMeta
parsePostMeta meta = do
    title <- required "title"
    date <- parsePostDate =<< required "date"
    description <- required "description"
    draft <- parseDraft (KeyMap.lookup (AKey.fromString "draft") meta)
    alectryon <- parseAlectryonField
    Right PostMeta
        { postTitle = title
        , postDate = date
        , postDescription = description
        , postDraft = draft
        , postAlectryon = alectryon
        }
  where
    lookupStr key = case KeyMap.lookup (AKey.fromString key) meta of
        Just (Aeson.String s) -> Just (T.unpack s)
        _                     -> Nothing
    required key = case lookupStr key of
        Just value | not (null value) -> Right value
        _ -> Left ("missing required field " ++ show key)
    -- Site boolean convention: absent means unset, a YAML boolean or a
    -- "true"/"false" string sets or unsets, anything else fails naming the
    -- value. The boolean cases matter because YAML parses `draft: true` as
    -- Bool, not String — a string-only read silently treats it as absent.
    parseDraft Nothing               = Right False
    parseDraft (Just (Aeson.Bool b)) = Right b
    parseDraft (Just (Aeson.String s))
        | s `elem` ["true", "false"] = Right (s == "true")
        | otherwise                  = Left
            ("unrecognized draft value " ++ show (T.unpack s)
             ++ " (expected \"true\" or \"false\")")
    parseDraft (Just other) = Left
        ("unrecognized draft value " ++ show other
         ++ " (expected \"true\" or \"false\")")
    parseAlectryonField =
        case KeyMap.lookup (AKey.fromString "alectryon") meta of
            Nothing -> Right Nothing
            Just (Aeson.Array xs) -> do
                args <- arrayStrings xs
                cache <- case lookupStr "alectryon-cache" of
                    Just c | not (null c) -> Right c
                    _ -> Left "an alectryon-enabled post requires a non-empty 'alectryon-cache' field"
                Right (Just AlectryonConfig
                    { alectryonArgs  = args
                    , alectryonCache = cache
                    })
            Just _ -> Left "alectryon must be a list of arguments (e.g. alectryon: [])"

-- | Extract all-string elements from a JSON array; fail if any element is
-- not a string.
arrayStrings :: V.Vector Aeson.Value -> Either String [String]
arrayStrings xs
    | all isString (V.toList xs) = Right [T.unpack s | Aeson.String s <- V.toList xs]
    | otherwise = Left "alectryon list elements must be strings"
  where
    isString (Aeson.String _) = True
    isString _ = False

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
formatPostDate = formatTime defaultTimeLocale "%B %-e, %Y"

-- | The index sort key: date descending, title ascending breaks ties.
postSortKey :: PostMeta -> (Down Day, String)
postSortKey meta = (Down (postDate meta), postTitle meta)

-- | Whether the rendered HTML carries math, detected by pandoc's
-- KaTeX-method output spans. Decides whether the page loads KaTeX at all.
postHasMath :: String -> Bool
postHasMath html =
    isInfixOf "class=\"math inline\"" html
    || isInfixOf "class=\"math display\"" html

-- | Whether the rendered HTML carries an Alectryon proof-state block. Decides
-- whether the page loads the Alectryon stylesheet.
postHasAlectryon :: String -> Bool
postHasAlectryon = isInfixOf "alectryon-io"

-- | Rewrite the language classes of code blocks by a per-class mapping. Both
-- 'normalizeRocq' and 'normalizeAlectryon' are instances of this; only the
-- class mapping differs. Identifier, key-values, and extra classes survive.
renameClasses :: (T.Text -> T.Text) -> Pandoc -> Pandoc
renameClasses f = walk rename
  where
    rename (CodeBlock (ident, classes, kvs) code) =
        CodeBlock (ident, map f classes, kvs) code
    rename block = block

-- | Rename rocq code fences to coq: the vendored syntax definition is keyed
-- under its historical name, while authors write ```rocq.
normalizeRocq :: Pandoc -> Pandoc
normalizeRocq = renameClasses rocqToCoq
  where
    rocqToCoq "rocq" = "coq"
    rocqToCoq c      = c

-- | Rewrite coq and rocq code fences to alectryon: on Alectryon-enabled
-- posts every Coq/Rocq block is executed and annotated with proof states, so
-- all of them are handed to the Alectryon transform (keyed under the
-- "alectryon" class). Identifier, key-values, and extra classes are preserved.
normalizeAlectryon :: Pandoc -> Pandoc
normalizeAlectryon = renameClasses toAlectryon
  where
    toAlectryon c | c `elem` ["coq", "rocq"] = "alectryon"
    toAlectryon c = c

-- | Resolve numbered cross-references (figures, equations, tables) in
-- process, purely: pandoc-crossref with its default action, HTML format.
applyCrossRef :: Pandoc -> Pandoc
applyCrossRef doc@(Pandoc meta _) =
    runCrossRef meta (Just (Format "html")) defaultCrossRefAction doc

-- | The whole AST pipeline, in order: rocq fences normalized so the syntax
-- definition matches, cross-references numbered, bold rendered as <b>.
postTransform :: Pandoc -> Pandoc
postTransform = boldToB . applyCrossRef . normalizeRocq

-- | The whole AST pipeline, in order, for Alectryon-enabled posts: coq/rocq
-- fences rewritten to alectryon (so the Alectryon transform claims them),
-- cross-references numbered, bold rendered as <b>. Alectryon's own transform —
-- which turns alectryon blocks into proof-state HTML — runs afterwards in the
-- Compiler monad in site.hs.
alectryonTransform :: Pandoc -> Pandoc
alectryonTransform = boldToB . applyCrossRef . normalizeAlectryon

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

-- | The pinned KaTeX release. Single source of the version: the writer
-- options below consume it (pandoc's fragment output ignores the URL, but
-- the method selection matters), and templates/default.html interpolates it
-- into the CDN <link>/<script> via the katexversion context field.
katexVersion :: String
katexVersion = "0.18.4"

katexBaseUrl :: T.Text
katexBaseUrl = "https://cdn.jsdelivr.net/npm/katex@"
    <> T.pack katexVersion <> "/dist/"

-- | Flatten a document to plain text, for assertions. pandoc-types 1.23
-- removed 'stringify' from "Text.Pandoc.Generic"; pandoc's lives in
-- "Text.Pandoc.Shared" and returns 'T.Text', so unpack to 'String'.
stringify :: Pandoc -> String
stringify = T.unpack . PandocShared.stringify
