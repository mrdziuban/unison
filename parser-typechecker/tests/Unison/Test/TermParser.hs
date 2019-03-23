{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TypeApplications  #-}

module Unison.Test.TermParser where

import           Control.Applicative
import           Control.Monad (join)
import           EasyTest
import qualified Text.Megaparsec as P
import           Text.RawString.QQ
import           Unison.Parser
import qualified Unison.Parsers as Ps
import           Unison.PrintError (renderParseErrorAsANSI)
import qualified Unison.Reference as R
import qualified Unison.Referent as Referent
import           Unison.Symbol (Symbol)
import qualified Unison.TermParser as TP
import qualified Unison.Names as Names
import Unison.Names (Names)

test1 :: Test ()
test1 = scope "termparser" . tests . map parses $
  [ "1"
  , "1.0"
  , "+1"
  , "-1"
  , "-1.0"
  , "4th"
  , "()"
  , "(0)"
  , "forty"
  , "forty two"
  , "\"forty two\""
  , "( one ; two )"
  , "( one ; two )"
  , "( one ; two ; three )"
  , "( one ; two ; 42 )"
  , "[1,2,3]"
  , "\"abc\""
  , "x + 1"
  , "1 + 1"
  , "1 Nat.+ 1"
  , "( x + 1 )"
  , "foo 42"
  , "1 Nat.== 1"
  , "x Nat.== y"
  , "if 1 Nat.== 1 then 1 else 1"
  , "if 1 Nat.== x then 1 else 1"
  , "if x Nat.== 1 then 1 else 1"
  , "if x == 1 then 1 else 1"
  , "if x Nat.== x then 1 else 1"
  --
  -- Block tests
  , "let x = 1\n" ++
    "    x"
  , "let\n" ++
    " y = 1\n" ++
    " x"
  , unlines [
    "let y = 1  ",
    "    x = 2  ",
    "    x + y"]
  , "(let \n" ++
    "  x = 23 + 42\n" ++
    "  x + 1 \n)"
  --
  -- Handlers
  ,"handle foo in \n" ++
    "  x = 23 + 42\n" ++
    "  x + foo 8 102.0 +4"
  , "handle foo in \n" ++
    "  x = 1\n" ++
    "  x"
  , "handle foo in x"

  -- Patterns
  , "case x of x -> x"
  , "case x of 0 -> 1"
  , "case x of\n" ++
    "  0 -> 1"
  , "case +0 of\n" ++
    "  +0 -> -1"
  , "case x of\n" ++
    "  x -> 1\n" ++
    "  2 -> 7\n" ++
    "  _ -> 3\n" ++
    "  Pair x y -> x + y\n" ++
    "  Pair (Pair x y) _ -> x + y \n"
  , "case x of\n" ++
    "  {Pair x y} -> 1\n" ++
    "  {State.set 42 -> k} -> k 42\n"
  , "case x of\n" ++
    "  0 ->\n" ++
    "    z = 0\n" ++
    "    z"
  , "case x of\n" ++
    " 0 | 1 == 2 -> 123"
  , "case x of\n" ++
    " [] -> 0\n" ++
    " [1] -> 1\n" ++
    " _ -> -1"

  -- Conditionals
  , "if x then y else z"
  , "-- if test 1\n" ++
    "if\n" ++
    "  s = 0\n" ++
    "  s > 0\n" ++
    "then\n" ++
    "  s = 0\n" ++
    "  s + 1\n" ++
    "else\n" ++
    "  s = 0\n" ++
    "  s + 2\n"
  , "-- if test 2\n" ++
    "if\n" ++
    "  s = 0\n" ++
    "  s > 0\n" ++
    "then\n" ++
    "  s: Int\n" ++
    "  s = (0: Int)\n" ++
    "  s + 1\n" ++
    "else\n" ++
    "  s = 0\n" ++
    "  s + 2\n"
  , "-- if test 3\n" ++
    "if\n" ++
    "  s = 0\n" ++
    "  s > 0\n" ++
    "then\n" ++
    "  s: Int\n" ++
    "  s = (0 : Int)\n" ++
    "  s + 1\n" ++
    "else\n" ++
    "  s = 0\n" ++
    "  s + 2\n"
   , "and x y"
   , "or x y"
   , [r|--let r1
   let r1 : Nat
       r1 = case Optional.Some 3 of
         x -> 1
       42 |]
   , [r|let
        increment = (Nat.+) 1

        (|>) : forall a . a -> (a -> b) -> b
        a |> f = f a

        Stream.from-int -3
          |> Stream.take 10
          |> Stream.fold-left 0 increment
       |]
  ]

test2 :: Test ()
test2 = (scope "fiddle" . tests $ unitTests)

test :: Test ()
test = test1 <|> test2

unitTests :: [Test ()]
unitTests =
 [ t w "hi"
 , t s "foo.+"
 , t (w <|> s) "foo.+"
 , t (w *> w) "foo bar"
 , t (P.try (w *> w) <|> (w *> s)) "foo +"
 , t TP.term "x -> x"
 , t (TP.lam TP.term) "x y z -> 1 + 1"
 , t (sepBy s w) ""
 , t (sepBy s w) "uno"
 , t (sepBy s w) "uno + dos"
 , t (sepBy s w) "uno + dos * tres"
 , t (reserved "(" *> sepBy s w <* reserved ")") "(uno + dos + tres)"
 , t TP.term "( 0 )"
 ]
 where
   -- type TermP v = P v (AnnotatedTerm v Ann)
   t :: P Symbol a -> String -> Test ()
   t = parseWith
   w = wordyId
   s = symbolyId

builtins :: Names
builtins = Names.fromTerms
  [("Pair", Referent.Con (R.Builtin "Pair") 0),
   ("State.set", Referent.Con (R.Builtin "State") 0)]

parses :: String -> Test ()
parses = parseWith TP.term

parseWith :: P Symbol a -> String -> Test ()
parseWith p s = scope (join . take 1 $ lines s) $
  case Ps.parse @ Symbol p s builtins of
    Left e -> do
      note $ renderParseErrorAsANSI s e
      crash $ renderParseErrorAsANSI s e
    Right _ -> ok
