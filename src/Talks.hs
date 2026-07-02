--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
-- | The Talks module owns every talks.yaml semantic: decoding, year grouping,
-- ordering, and the single/multi-venue display decision. Its interface is
-- 'parseTalks': YAML text in, display-ready 'TalkYear's out, every failure as
-- a 'Left'. Templates downstream only test key presence; they never decide
-- anything.
module Talks
    ( -- * Interface
      TalkVenue(..)
    , Talk(..)
    , TalkYear
    , parseTalks
    , multiVenue
      -- * Internals exposed for the test suite
    , groupTalksByYear
    ) where

import           Data.List   (sortOn, nub)
import           Data.Ord    (Down(..))
import qualified Data.Text   as T
import qualified Data.Text.Encoding as TE
import qualified Data.Yaml   as Yaml
import           Data.Yaml   ((.:), (.:?))
import           Data.Aeson  (FromJSON(..), withObject)

-- A place a talk was given: display text plus an optional link. Distinct from
-- a Paper's Venue (the derived publication-venue string in Publications).
data TalkVenue = TalkVenue
    { venueText :: String
    , venueUrl  :: Maybe String
    } deriving (Eq, Show)

data Talk = Talk
    { talkTitle  :: String
    , talkYear   :: Int
    , talkNote   :: Maybe String
    , talkVenues :: [TalkVenue]
    } deriving (Eq, Show)

-- One year band of the talks timeline, newest year first.
type TalkYear = (Int, [Talk])

instance FromJSON TalkVenue where
    parseJSON = withObject "venue" $ \o ->
        TalkVenue <$> o .: "text" <*> o .:? "url"

instance FromJSON Talk where
    parseJSON = withObject "talk" $ \o ->
        Talk <$> o .: "title" <*> o .: "year"
             <*> o .:? "note" <*> o .: "venues"

-- | The whole pipeline: decode talks.yaml, group by year, order the years.
parseTalks :: String -> Either String [TalkYear]
parseTalks s = case Yaml.decodeEither' (TE.encodeUtf8 (T.pack s)) of
    Left err    -> Left ("talks.yaml parse error: "
                         ++ Yaml.prettyPrintParseException err)
    Right talks -> Right (groupTalksByYear talks)

-- | A talk given at several venues renders as a list; a single venue renders
-- inline. This is the display decision behind the template's $if(multivenue)$.
multiVenue :: Talk -> Bool
multiVenue = (> 1) . length . talkVenues

-- Years descending; file order preserved within a year (filter is stable).
groupTalksByYear :: [Talk] -> [TalkYear]
groupTalksByYear ts =
    [ (y, filter ((== y) . talkYear) ts) | y <- years ]
  where
    years = sortOn Down (nub (map talkYear ts))
