-- Tests exercise the Publications, Talks, and Prose modules through their
-- interfaces: bib/YAML/AST in, display-ready values out. No Hakyll, no
-- rebuild, no browser.
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import           Test.Tasty
import           Test.Tasty.HUnit
import           Data.Either (isRight, isLeft)
import           Data.List (isInfixOf)
import qualified Text.BibTeX.Entry as BibEntry
import           Text.Pandoc.Definition
                   (Pandoc(..), Block(..), Inline(..), Format(..), nullMeta)
import           Publications
import           Prose
import           Talks

entry :: String -> [(String, String)] -> BibEntry.T
entry key fs = BibEntry.Cons
    { BibEntry.entryType  = "inproceedings"
    , BibEntry.identifier = key
    , BibEntry.fields     = fs
    }

main :: IO ()
main = defaultMain $ testGroup "site"
    [ testGroup "Publications"
        [ venueTests, authorTests, decodeTests, monthTests
        , classifyTests, buttonTests, sortTests, pipelineTests
        ]
    , testGroup "Talks"
        [ talkGroupingTests, talkDisplayTests, talkPipelineTests ]
    , testGroup "Prose" [ proseTests ]
    ]

venueTests :: TestTree
venueTests = testGroup "venue derivation"
    [ testCase "acronym+year extracted from DBLP booktitle" $
        extractAcronym "Programming Languages and Systems - 35th European Symposium on Programming, ESOP 2026, Held as Part of ETAPS 2026"
          @?= "ESOP 2026"
    , testCase "booktitle without acronym+year falls back whole" $
        extractAcronym "Workshop on Interesting Things" @?= "Workshop on Interesting Things"
    , testCase "journal with volume and number" $
        composeJournal "J. Funct. Program." (Just "34") (Just "2") @?= "J. Funct. Program., 34(2)"
    , testCase "journal with volume only" $
        composeJournal "J. Funct. Program." (Just "34") Nothing @?= "J. Funct. Program., 34"
    , testCase "journal alone" $
        composeJournal "J. Funct. Program." Nothing Nothing @?= "J. Funct. Program."
    , testCase "explicit venue override wins over booktitle" $
        deriveVenue (entry "k" [("venue", "ICFP 2025"), ("booktitle", "Something ESOP 2026")])
          @?= Just "ICFP 2025"
    , testCase "journal composition used when no override" $
        deriveVenue (entry "k" [("journal", "PACMPL"), ("volume", "9"), ("number", "ICFP")])
          @?= Just "PACMPL, 9(ICFP)"
    , testCase "metayear suppressed when venue embeds the year" $
        metaYear (entry "k" [("booktitle", "Blah, ESOP 2026, Blah"), ("year", "2026")])
          @?= Nothing
    , testCase "metayear shown for journal venues" $
        metaYear (entry "k" [("journal", "PACMPL"), ("volume", "9"), ("year", "2025")])
          @?= Just "2025"
    , testCase "metayear shown for drafts (no venue)" $
        metaYear (entry "k" [("draft", "true"), ("year", "2026")]) @?= Just "2026"
    ]

authorTests :: TestTree
authorTests = testGroup "author formatting"
    [ testCase "Last, First flipped" $
        formatAuthors "Li, Yao and Weirich, Stephanie" @?= "Yao Li, Stephanie Weirich"
    , testCase "First Last passes through" $
        formatAuthors "Yao Li and Stephanie Weirich" @?= "Yao Li, Stephanie Weirich"
    , testCase "DBLP disambiguation digits stripped" $
        formatAuthors "Yao Li 0004" @?= "Yao Li"
    ]

decodeTests :: TestTree
decodeTests = testGroup "LaTeX decoding"
    [ testCase "clean string passes through untouched" $
        decodeLaTeX "Don't Sweat Interaction Trees" @?= "Don't Sweat Interaction Trees"
    , testCase "protective braces removed" $
        decodeLaTeX "The {ESOP} Paper" @?= "The ESOP Paper"
    ]

monthTests :: TestTree
monthTests = testGroup "month parsing"
    [ testCase "named month" $ monthNum "may" @?= 5
    , testCase "capitalized"  $ monthNum "May" @?= 5
    , testCase "numeric"      $ monthNum "5"   @?= 5
    , testCase "garbage is 0" $ monthNum "soon" @?= 0
    ]

classifyTests :: TestTree
classifyTests = testGroup "published/draft partition"
    [ testCase "derivable venue means published" $
        classify (entry "k" [("booktitle", "Blah ESOP 2026")]) @?= Right Published
    , testCase "draft flag means draft" $
        classify (entry "k" [("draft", "true")]) @?= Right Draft
    , testCase "neither venue nor draft fails, naming the entry" $
        case classify (entry "lost2026" []) of
            Left msg -> assertBool "message names the entry" ("lost2026" `elem` words' msg)
            Right _  -> assertFailure "expected Left"
    , testCase "both venue and draft fails (half-finished promotion)" $
        assertBool "expected Left" (isLeft (classify (entry "k" [("booktitle", "Blah ESOP 2026"), ("draft", "true")])))
    , testCase "draft = {false} counts as unset" $
        assertBool "expected Left" (isLeft (classify (entry "k" [("draft", "false")])))
    ]
  where words' = words . map (\c -> if c == '\'' then ' ' else c)

buttonTests :: TestTree
buttonTests = testGroup "button visibility"
    [ testCase "openaccess drops the preprint key" $
        lookup "preprint" (toPaper (entry "k" [("openaccess", "true"), ("preprint", "https://x")]))
          @?= Nothing
    , testCase "preprint key kept without openaccess" $
        lookup "preprint" (toPaper (entry "k" [("preprint", "https://x")]))
          @?= Just "https://x"
    , testCase "primaryurl prefers link over preprint" $
        lookup "primaryurl" (toPaper (entry "k" [("link", "https://l"), ("preprint", "https://p")]))
          @?= Just "https://l"
    , testCase "primaryurl falls back to preprint even when openaccess" $
        lookup "primaryurl" (toPaper (entry "k" [("openaccess", "true"), ("preprint", "https://p")]))
          @?= Just "https://p"
    ]

sortTests :: TestTree
sortTests = testGroup "ordering"
    [ testCase "year desc, then month desc" $
        map (lookup "t") (sortPapers
            [ [("t", "a"), ("year", "2020"), ("_month", "3")]
            , [("t", "b"), ("year", "2024")]
            , [("t", "c"), ("year", "2020"), ("_month", "11")]
            ])
          @?= [Just "b", Just "c", Just "a"]
    ]

pipelineTests :: TestTree
pipelineTests = testGroup "parsePublications"
    [ testCase "partitions a small bib into published and drafts" $ do
        let bib = unlines
              [ "@inproceedings{pub1,"
              , "  author = {Doe, Jane},"
              , "  title = {A Title},"
              , "  year = {2026},"
              , "  booktitle = {Proceedings of Stuff, ESOP 2026, Somewhere},"
              , "}"
              , "@unpublished{dr1,"
              , "  author = {Doe, Jane},"
              , "  title = {A Draft},"
              , "  year = {2025},"
              , "  draft = {true},"
              , "}"
              ]
        case parsePublications bib of
            Left err -> assertFailure err
            Right ps -> do
                map (lookup "venue") (published ps) @?= [Just "ESOP 2026"]
                map (lookup "draft") (drafts ps)    @?= [Just "true"]
    , testCase "unclassifiable entry fails with its key" $ do
        let bib = "@misc{orphan2026,\n  title = {No Venue No Draft},\n  year = {2026},\n}\n"
        case parsePublications bib of
            Left msg -> assertBool "names orphan2026" ("orphan2026" `elem` words (map unquote msg))
            Right _  -> assertFailure "expected Left"
    , testCase "the real publications.bib parses, both lists non-empty, years sorted" $ do
        raw <- readFile "publications.bib"
        case parsePublications raw of
            Left err -> assertFailure err
            Right ps -> do
                assertBool "has published papers" (not (null (published ps)))
                assertBool "has drafts"           (not (null (drafts ps)))
                let years = map (maybe (0 :: Int) read . lookup "year") (published ps)
                assertBool "published years non-increasing" (and (zipWith (>=) years (drop 1 years)))
    ]
  where unquote c = if c == '\'' then ' ' else c

--------------------------------------------------------------------------------
-- Talks

talkYaml :: [String] -> String
talkYaml = unlines

talkGroupingTests :: TestTree
talkGroupingTests = testGroup "year grouping"
    [ testCase "years descending, file order preserved within a year" $ do
        let yaml = talkYaml
              [ "- title: Old A"
              , "  year: 2022"
              , "  venues: [{text: \"X\"}]"
              , "- title: New"
              , "  year: 2026"
              , "  venues: [{text: \"Y\"}]"   -- quoted: bare Y is YAML for true
              , "- title: Old B"
              , "  year: 2022"
              , "  venues: [{text: \"Z\"}]"
              ]
        case parseTalks yaml of
            Left err -> assertFailure err
            Right ys -> map (fmap (map talkTitle)) ys
                @?= [(2026, ["New"]), (2022, ["Old A", "Old B"])]
    , testCase "malformed YAML fails naming talks.yaml" $
        case parseTalks "- title: Broken\n  venues: notalist\n" of
            Left msg -> assertBool "message names talks.yaml" ("talks.yaml" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    ]

talkDisplayTests :: TestTree
talkDisplayTests = testGroup "display decisions"
    [ testCase "two venues render as a list" $
        multiVenue (Talk "t" 2026 Nothing [TalkVenue "a" Nothing, TalkVenue "b" Nothing])
          @?= True
    , testCase "a single venue renders inline" $
        multiVenue (Talk "t" 2026 Nothing [TalkVenue "a" Nothing]) @?= False
    , testCase "venue url and talk note are optional" $ do
        let yaml = talkYaml
              [ "- title: T"
              , "  note: Discussion"
              , "  year: 2026"
              , "  venues:"
              , "    - text: Linked"
              , "      url: https://x"
              , "    - text: Plain"
              ]
        case parseTalks yaml of
            Left err -> assertFailure err
            Right ys -> do
                let [(_, [t])] = ys
                talkNote t @?= Just "Discussion"
                map venueUrl (talkVenues t) @?= [Just "https://x", Nothing]
    ]

--------------------------------------------------------------------------------
-- Prose

proseTests :: TestTree
proseTests = testGroup "bold renders as <b>"
    [ testCase "Strong becomes raw <b>…</b>" $
        boldToB (Pandoc nullMeta [Para [Strong [Str "Instructor:"], Space, Str "Yao"]])
          @?= Pandoc nullMeta
                [ Para [ RawInline (Format "html") "<b>"
                       , Str "Instructor:"
                       , RawInline (Format "html") "</b>"
                       , Space, Str "Yao" ] ]
    , testCase "markup nested inside the bold span survives" $
        boldToB (Pandoc nullMeta [Para [Strong [Emph [Str "hi"]]]])
          @?= Pandoc nullMeta
                [ Para [ RawInline (Format "html") "<b>"
                       , Emph [Str "hi"]
                       , RawInline (Format "html") "</b>" ] ]
    ]

talkPipelineTests :: TestTree
talkPipelineTests = testGroup "parseTalks on the real talks.yaml"
    [ testCase "parses, non-empty, years strictly descending" $ do
        raw <- readFile "talks.yaml"
        case parseTalks raw of
            Left err -> assertFailure err
            Right ys -> do
                assertBool "has talks" (not (null ys))
                let years = map fst ys
                assertBool "years strictly descending" (and (zipWith (>) years (drop 1 years)))
    ]
