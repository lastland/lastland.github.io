--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Data.Maybe (fromMaybe)
import           Hakyll


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

    match "js/*" $ do
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

    match (fromList ["about.rst", "contact.markdown"]) $ do
        route   $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/default.html" (navLinkPrefix `mappend` defaultContext)
            >>= relativizeUrls

    match "papers/*" $ do
        route $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/post.html"    defaultContext
            >>= loadAndApplyTemplate "templates/default.html" (navLinkPrefix `mappend` defaultContext)
            >>= relativizeUrls

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
            papers  <- recentFirst =<< loadAll "papers/*"
            let ctx =
                    listField "courses" defaultContext (return courses)
                    `mappend` listField "papers" defaultContext (return papers)
                    `mappend` navLinkPrefix
                    `mappend` defaultContext
            getResourceBody
                >>= applyAsTemplate ctx
                >>= loadAndApplyTemplate "templates/default.html" ctx
                >>= relativizeUrls

    match "publication.html" $ do
        route idRoute
        compile $ do
            papers <- recentFirst =<< loadAll "papers/*"
            let pubCtx =
                    listField "papers" defaultContext (return papers)
                    `mappend` navLinkPrefix
                    `mappend` defaultContext
            getResourceBody
                >>= applyAsTemplate pubCtx
                >>= loadAndApplyTemplate "templates/default.html" pubCtx
                >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler
