--------------------------------------------------------------------------------
-- | The Courses module owns every course-term semantic: parsing a front-matter
-- term string ("Spring, 2025"), validating a course's terms list, the homepage
-- ordering key (a course sorts by the latest term it was taught), and the
-- joined display string. Its interface is 'parseTerms': front-matter strings
-- in, display-ready 'CourseTerms' out, every failure as a 'Left'. One course
-- page covers every term the course was taught; teaching it again is one more
-- string in the terms list.
module Courses
    ( -- * Interface
      Season(..)
    , Term(..)
    , CourseTerms
    , parseTerms
    , latestTerm
    , displayTerms
      -- * Internals exposed for the test suite
    , parseTerm
    ) where

import           Data.Char (isDigit)
import           Data.List (intercalate)

-- PSU quarters, chronological within a calendar year.
data Season = Winter | Spring | Summer | Fall
    deriving (Eq, Ord, Show, Enum, Bounded)

-- Field order gives the derived Ord the sort we want: year, then season.
data Term = Term
    { termYear   :: Int
    , termSeason :: Season
    } deriving (Eq, Ord, Show)

-- A validated, non-empty terms list. The authored strings are kept alongside
-- the parsed terms: display echoes the front matter, ordering uses the parse.
newtype CourseTerms = CourseTerms [(String, Term)]
    deriving (Eq, Show)

-- | Parse one term string, exactly "<Season>, <year>".
parseTerm :: String -> Either String Term
parseTerm str = case break (== ',') str of
    (seasonStr, ',' : ' ' : yearStr)
        | Just season <- lookup seasonStr seasons
        , not (null yearStr) && all isDigit yearStr
        -> Right (Term (read yearStr) season)
    _ -> Left ("unrecognized term " ++ show str
               ++ " (expected \"<Winter|Spring|Summer|Fall>, <year>\")")
  where
    seasons = [ (show season, season) | season <- [minBound .. maxBound] ]

-- | The whole pipeline: every string must parse, and there must be at least
-- one — a course page with no terms is a mistake worth failing the build for.
parseTerms :: [String] -> Either String CourseTerms
parseTerms []      = Left "course has an empty terms list"
parseTerms authored = CourseTerms . zip authored <$> traverse parseTerm authored

-- | The homepage sort key: courses order by the last time they were taught.
latestTerm :: CourseTerms -> Term
latestTerm (CourseTerms ts) = maximum (map snd ts)

-- | Authored order, joined with a middle dot; a single term is just itself.
displayTerms :: CourseTerms -> String
displayTerms (CourseTerms ts) = intercalate " · " (map fst ts)
