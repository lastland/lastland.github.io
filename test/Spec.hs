-- Tests exercise the Publications, Talks, Courses, Posts, and Prose modules
-- through their interfaces: bib/YAML/AST/front matter in, display-ready
-- values out. No Hakyll, no rebuild, no browser.
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import           Test.Tasty
import           Test.Tasty.HUnit
import           Data.Either (isRight, isLeft)
import           Data.List (isInfixOf, sortOn)
import           Data.Time.Calendar (fromGregorian)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Vector as V
import qualified Data.Text as T
import qualified Text.BibTeX.Entry as BibEntry
import           Text.Pandoc.Definition
                   (Pandoc(..), Block(..), Inline(..), Format(..)
                   , Caption(..), Citation(..), CitationMode(..), nullMeta)
import           Courses
import           Posts
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
    , testGroup "Courses"
        [ courseTermTests, courseOrderTests, courseDisplayTests ]
    , testGroup "Posts"
        [ postDateTests, postMetaTests, postSortTests, postMathTests
        , postAlectryonDetectTests, postAlectryonConfigTests
        , postRocqTests, postAlectryonTests, postCrossRefTests, postSyntaxTests ]
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
-- Courses

courseTermTests :: TestTree
courseTermTests = testGroup "term parsing"
    [ testCase "all four seasons parse" $
        traverse parseTerm ["Winter, 2023", "Spring, 2024", "Summer, 2025", "Fall, 2026"]
          @?= Right [ Term 2023 Winter, Term 2024 Spring
                    , Term 2025 Summer, Term 2026 Fall ]
    , testCase "bad season fails naming the string" $
        case parseTerm "Sprang, 2025" of
            Left msg -> assertBool "message names the term" ("Sprang, 2025" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    , testCase "bad year fails" $
        assertBool "expected Left" (isLeft (parseTerm "Spring, soon"))
    , testCase "missing comma fails" $
        assertBool "expected Left" (isLeft (parseTerm "Spring 2025"))
    ]

courseOrderTests :: TestTree
courseOrderTests = testGroup "term ordering"
    [ testCase "later year wins" $
        assertBool "2026 Winter after 2025 Fall" (Term 2026 Winter > Term 2025 Fall)
    , testCase "within a year: Winter < Spring < Summer < Fall" $
        assertBool "season order"
            (  Term 2025 Winter < Term 2025 Spring
            && Term 2025 Spring < Term 2025 Summer
            && Term 2025 Summer < Term 2025 Fall )
    , testCase "latestTerm is the maximum regardless of authored order" $
        case parseTerms ["Fall, 2024", "Winter, 2023", "Fall, 2025", "Winter, 2024"] of
            Left err -> assertFailure err
            Right ts -> latestTerm ts @?= Term 2025 Fall
    ]

courseDisplayTests :: TestTree
courseDisplayTests = testGroup "terms display and validation"
    [ testCase "a single term displays as authored" $
        fmap displayTerms (parseTerms ["Spring, 2024"]) @?= Right "Spring, 2024"
    , testCase "multiple terms joined with a middle dot, latest first" $
        fmap displayTerms (parseTerms ["Winter, 2023", "Fall, 2025"])
          @?= Right "Fall, 2025 · Winter, 2023"
    , testCase "display sorts by the parsed term, not merely reversing input" $
        fmap displayTerms (parseTerms ["Fall, 2024", "Winter, 2023", "Fall, 2025"])
          @?= Right "Fall, 2025 · Fall, 2024 · Winter, 2023"
    , testCase "empty terms list fails" $
        assertBool "expected Left" (isLeft (parseTerms []))
    , testCase "one bad term fails the whole list naming it" $
        case parseTerms ["Spring, 2025", "Sprong, 2026"] of
            Left msg -> assertBool "message names the bad term" ("Sprong, 2026" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
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

--------------------------------------------------------------------------------
-- Posts

-- Front matter as an assoc list, queried the way site.hs queries Hakyll
-- metadata.
postMeta :: [(String, String)] -> Either String PostMeta
postMeta = parsePostMeta . stringMeta

-- | Build metadata from string fields.
stringMeta :: [(String, String)] -> KeyMap.KeyMap Aeson.Value
stringMeta fs = KeyMap.fromList [(AKey.fromString k, Aeson.String (T.pack v)) | (k, v) <- fs]

-- | Add fields (any value type) to a metadata object.
withFields :: [(String, Aeson.Value)] -> KeyMap.KeyMap Aeson.Value -> KeyMap.KeyMap Aeson.Value
withFields extra meta = foldr (\(k, v) m -> KeyMap.insert (AKey.fromString k) v m) meta extra

validMeta :: [(String, String)]
validMeta = [("title", "T"), ("date", "2026-08-12"), ("description", "D")]

postDateTests :: TestTree
postDateTests = testGroup "date parsing and formatting"
    [ testCase "ISO date parses" $
        parsePostDate "2026-08-12" @?= Right (fromGregorian 2026 8 12)
    , testCase "single-digit month rejected" $
        assertBool "expected Left" (isLeft (parsePostDate "2026-8-12"))
    , testCase "invalid calendar day rejected" $
        assertBool "expected Left" (isLeft (parsePostDate "2026-02-30"))
    , testCase "non-ISO rejected naming the string" $
        case parsePostDate "Aug 12 2026" of
            Left msg -> assertBool "message names the date" ("Aug 12 2026" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    , testCase "formats as Month Day, Year" $
        formatPostDate (fromGregorian 2026 8 12) @?= "August 12, 2026"
    , testCase "day of month not zero-padded" $
        formatPostDate (fromGregorian 2026 8 1) @?= "August 1, 2026"
    ]

postMetaTests :: TestTree
postMetaTests = testGroup "front-matter validation"
    [ testCase "title, date, description parse" $
        case postMeta validMeta of
            Left err -> assertFailure err
            Right pm -> do
                postTitle pm       @?= "T"
                postDate pm        @?= fromGregorian 2026 8 12
                postDescription pm @?= "D"
                postDraft pm       @?= False
    , testCase "missing title fails naming the field" $
        case postMeta [("date", "2026-08-12"), ("description", "D")] of
            Left msg -> assertBool "message names title" ("title" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    , testCase "missing date fails naming the field" $
        case postMeta [("title", "T"), ("description", "D")] of
            Left msg -> assertBool "message names date" ("date" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    , testCase "missing description fails naming the field" $
        case postMeta [("title", "T"), ("date", "2026-08-12")] of
            Left msg -> assertBool "message names description" ("description" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    , testCase "empty required field fails" $
        assertBool "expected Left"
            (isLeft (postMeta [("title", "T"), ("date", "2026-08-12"), ("description", "")]))
    , testCase "malformed date fails" $
        assertBool "expected Left"
            (isLeft (postMeta [("title", "T"), ("date", "soon"), ("description", "D")]))
    , testCase "draft: true marks a draft" $
        fmap postDraft (postMeta (validMeta ++ [("draft", "true")])) @?= Right True
    , testCase "draft: false counts as unset" $
        fmap postDraft (postMeta (validMeta ++ [("draft", "false")])) @?= Right False
    , testCase "unrecognized draft value fails naming it" $
        case postMeta (validMeta ++ [("draft", "banana")]) of
            Left msg -> assertBool "message names the value" ("banana" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    ]

postSortTests :: TestTree
postSortTests = testGroup "ordering"
    [ testCase "date descending, title ascending breaks ties" $ do
        let Right old  = postMeta [("title", "B"), ("date", "2025-01-01"), ("description", "D")]
            Right new  = postMeta [("title", "A"), ("date", "2026-01-01"), ("description", "D")]
            Right tie1 = postMeta [("title", "A"), ("date", "2025-01-01"), ("description", "D")]
            Right tie2 = postMeta [("title", "C"), ("date", "2025-01-01"), ("description", "D")]
        map postTitle (sortOn postSortKey [old, new, tie2, tie1])
            @?= ["A", "A", "B", "C"]
    ]

postMathTests :: TestTree
postMathTests = testGroup "math detection in rendered HTML"
    [ testCase "inline math span" $
        postHasMath "<p><span class=\"math inline\">x^2</span></p>" @?= True
    , testCase "display math span" $
        postHasMath "<span class=\"math display\">x</span>" @?= True
    , testCase "no math" $
        postHasMath "<p>nothing to see</p>" @?= False
    ]

postAlectryonDetectTests :: TestTree
postAlectryonDetectTests = testGroup "alectryon detection in rendered HTML"
    [ testCase "alectryon-io block present" $
        postHasAlectryon "<pre class=\"alectryon-io highlight\">code</pre>" @?= True
    , testCase "no alectryon" $
        postHasAlectryon "<pre class=\"sourceCode coq\">code</pre>" @?= False
    ]

postAlectryonConfigTests :: TestTree
postAlectryonConfigTests = testGroup "alectryon front-matter validation"
    [ testCase "absent alectryon field yields Nothing" $
        case postMeta validMeta of
            Left err -> assertFailure err
            Right pm -> postAlectryon pm @?= Nothing
    , testCase "non-empty args list + cache validated" $
        case parsePostMeta (withFields
            [ ("alectryon", Aeson.Array (V.fromList
                [Aeson.String (T.pack "-Q"), Aeson.String (T.pack "dir,Lib")]))
            , ("alectryon-cache", Aeson.String (T.pack "cache/demo"))
            ] (stringMeta validMeta)) of
            Left err -> assertFailure err
            Right pm -> case postAlectryon pm of
                Nothing -> assertFailure "expected Alectryon config"
                Just cfg -> do
                    alectryonArgs cfg  @?= ["-Q", "dir,Lib"]
                    alectryonCache cfg @?= "cache/demo"
    , testCase "empty args list + cache validated" $
        case parsePostMeta (withFields
            [ ("alectryon", Aeson.Array V.empty)
            , ("alectryon-cache", Aeson.String (T.pack "cache/demo"))
            ] (stringMeta validMeta)) of
            Left err -> assertFailure err
            Right pm -> case postAlectryon pm of
                Nothing -> assertFailure "expected Alectryon config"
                Just cfg -> alectryonArgs cfg @?= []
    , testCase "malformed scalar alectryon fails naming the field" $
        case parsePostMeta (withFields
            [ ("alectryon", Aeson.Bool True) ] (stringMeta validMeta)) of
            Left msg -> assertBool "message names alectryon" ("alectryon" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    , testCase "missing cache fails naming the field" $
        case parsePostMeta (withFields
            [ ("alectryon", Aeson.Array V.empty) ] (stringMeta validMeta)) of
            Left msg -> assertBool "message names alectryon-cache" ("alectryon-cache" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    , testCase "non-string array elements fail mentioning strings" $
        case parsePostMeta (withFields
            [ ("alectryon", Aeson.Array (V.fromList [Aeson.Number 1]))
            , ("alectryon-cache", Aeson.String (T.pack "cache/demo"))
            ] (stringMeta validMeta)) of
            Left msg -> assertBool "message mentions strings" ("strings" `isInfixOf` msg)
            Right _  -> assertFailure "expected Left"
    ]

postRocqTests :: TestTree
postRocqTests = testGroup "rocq fence normalization"
    [ testCase "rocq block becomes coq" $
        normalizeRocq (Pandoc nullMeta [CodeBlock ("", ["rocq"], []) "Theorem t."])
          @?= Pandoc nullMeta [CodeBlock ("", ["coq"], []) "Theorem t."]
    , testCase "other languages untouched" $
        normalizeRocq (Pandoc nullMeta [CodeBlock ("", ["haskell"], []) "main"])
          @?= Pandoc nullMeta [CodeBlock ("", ["haskell"], []) "main"]
    ]

postAlectryonTests :: TestTree
postAlectryonTests = testGroup "alectryon fence normalization"
    [ testCase "coq block becomes alectryon" $
        normalizeAlectryon (Pandoc nullMeta [CodeBlock ("", ["coq"], []) "Theorem t."])
          @?= Pandoc nullMeta [CodeBlock ("", ["alectryon"], []) "Theorem t."]
    , testCase "rocq block becomes alectryon" $
        normalizeAlectryon (Pandoc nullMeta [CodeBlock ("", ["rocq"], []) "Theorem t."])
          @?= Pandoc nullMeta [CodeBlock ("", ["alectryon"], []) "Theorem t."]
    , testCase "other languages untouched" $
        normalizeAlectryon (Pandoc nullMeta [CodeBlock ("", ["haskell"], []) "main"])
          @?= Pandoc nullMeta [CodeBlock ("", ["haskell"], []) "main"]
    , testCase "identifier, key-values, extra classes preserved" $
        normalizeAlectryon (Pandoc nullMeta [CodeBlock ("cb1", ["coq","numberLines"], [("foo","bar")]) "x."])
          @?= Pandoc nullMeta [CodeBlock ("cb1", ["alectryon","numberLines"], [("foo","bar")]) "x."]
    ]

postCrossRefTests :: TestTree
postCrossRefTests = testGroup "numbered cross-references"
    [ testCase "figure numbered and @fig: reference resolved" $ do
        -- pandoc 3 reads a standalone image paragraph as a Figure block;
        -- pandoc-crossref numbers Figure blocks, not bare image paragraphs.
        let doc = Pandoc nullMeta
                [ Figure ("fig:hello", [], [])
                    (Caption Nothing [Plain [Str "A caption"]])
                    [Plain [Image ("", [], []) [Str "A caption"] ("images/hello.png", "")]]
                , Para [Cite [Citation "fig:hello" [] [] NormalCitation 0 0] [Str "@fig:hello"]]
                ]
            out = stringify (applyCrossRef doc)
        assertBool ("expected \"Figure 1\" in: " ++ out) ("Figure 1" `isInfixOf` out)
    ]

postSyntaxTests :: TestTree
postSyntaxTests = testGroup "vendored Coq syntax definition"
    [ testCase "syntax/coq.xml parses" $ do
        raw <- readFile "syntax/coq.xml"
        assertBool "expected Right" (isRight (parseCoqSyntax (T.pack raw)))
    ]
