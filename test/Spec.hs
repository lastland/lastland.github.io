-- Tests exercise the Publications module through its interface: bib entries
-- in, display-ready Papers out. No Hakyll, no rebuild, no browser.
module Main (main) where

import           Test.Tasty
import           Test.Tasty.HUnit
import           Data.Either (isRight, isLeft)
import qualified Text.BibTeX.Entry as BibEntry
import           Publications

entry :: String -> [(String, String)] -> BibEntry.T
entry key fs = BibEntry.Cons
    { BibEntry.entryType  = "inproceedings"
    , BibEntry.identifier = key
    , BibEntry.fields     = fs
    }

main :: IO ()
main = defaultMain $ testGroup "Publications"
    [ venueTests, authorTests, decodeTests, monthTests
    , classifyTests, buttonTests, sortTests, pipelineTests
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
