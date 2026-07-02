--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
-- | The Prose module owns the rendering semantics of pandoc-compiled prose
-- (currently the course pages). One decision lives here: bold in this site's
-- prose draws attention ("Instructor:", "Office Hours:") without claiming
-- extra importance, so markdown bold renders as <b>, not <strong>.
module Prose
    ( -- * Interface
      boldToB
    ) where

import Text.Pandoc.Definition (Pandoc, Inline(..), Format(..))
import Text.Pandoc.Walk (walk)

-- | Render markdown bold (Strong) as <b>. Applied to the parsed Pandoc AST,
-- so nested markup inside the bold span survives.
boldToB :: Pandoc -> Pandoc
boldToB = walk go
  where
    go :: [Inline] -> [Inline]
    go = concatMap expand
    expand (Strong is) = RawInline (Format "html") "<b>"
                       : is ++ [RawInline (Format "html") "</b>"]
    expand i           = [i]
