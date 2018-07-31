{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
module Unison.Test.ColorText where

-- import EasyTest
import           Data.Set              (Set, union)
import qualified Data.Set              as Set
import           Text.RawString.QQ
import           Unison.Lexer          (Pos (..))
import           Unison.Util.ColorText

markup :: Ord a => AnnotatedExcerpt a -> Set (Range, a) -> AnnotatedExcerpt a
markup a r = a { annotations = r `union` (annotations a) }

ex2 :: AnnotatedExcerpt Color
ex2 = markup ex (Set.fromList
      [ (Range (Pos 3 1) (Pos 3 5), Color1) -- SCENE
      , (Range (Pos 5 1) (Pos 5 5), Color1) -- Enter
      , (Range (Pos 25 1) (Pos 25 6), Color2) -- ALONSO
      , (Range (Pos 7 1) (Pos 13 44), Color1) -- Master ... bestir.
      ])

ex :: Ord a => AnnotatedExcerpt a
ex = [r|The Tempest | Act 1, Scene 1

SCENE I. On a ship at sea: a tempestuous noise
of thunder and lightning heard.
Enter a Master and a Boatswain

Master
Boatswain!
Boatswain
Here, master: what cheer?
Master
Good, speak to the mariners: fall to't, yarely,
or we run ourselves aground: bestir, bestir.
Exit

Enter Mariners

Boatswain
Heigh, my hearts! cheerly, cheerly, my hearts!
yare, yare! Take in the topsail. Tend to the
master's whistle. Blow, till thou burst thy wind,
if room enough!
Enter ALONSO, SEBASTIAN, ANTONIO, FERDINAND, GONZALO, and others

ALONSO
Good boatswain, have care. Where's the master?
Play the men.
Boatswain
I pray now, keep below.
|]

-- test = scope "colortext.snipWithContext" . expect $
