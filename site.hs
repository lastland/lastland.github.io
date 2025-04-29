--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Hakyll


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

    match (fromList ["about.rst", "contact.markdown"]) $ do
        route   $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

    match "papers/*" $ do
        route $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/post.html"    defaultContext
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

    match "courses/*" $ do
        route $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/course.html"  defaultContext
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

    match "index.html" $ do
        route idRoute
        compile pubCompiler
        compile courseCompiler

    match "publication.html" $ do
        route idRoute
        compile pubCompiler

    match "templates/*" $ compile templateBodyCompiler

pubCompiler :: Compiler (Item String)
pubCompiler = do
  papers <- recentFirst =<< loadAll "papers/*"
  let pubCtx =
        listField "papers" defaultContext (return papers)
        `mappend` defaultContext
  getResourceBody
    >>= applyAsTemplate pubCtx
    >>= loadAndApplyTemplate "templates/default.html" pubCtx
    >>= relativizeUrls

courseCompiler :: Compiler (Item String)
courseCompiler = do
  courses <- recentFirst =<< loadAll "courses/*"
  papers  <- recentFirst =<< loadAll "papers/*"
  let ctx =
        listField "courses" defaultContext (return courses)
        `mappend` listField "papers" defaultContext (return papers)
        `mappend` defaultContext
  getResourceBody
    >>= applyAsTemplate ctx
    >>= loadAndApplyTemplate "templates/default.html" ctx
    >>= relativizeUrls
