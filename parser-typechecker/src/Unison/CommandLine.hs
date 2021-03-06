{-# LANGUAGE DoAndIfThenElse     #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE ViewPatterns        #-}


module Unison.CommandLine where

-- import Debug.Trace
import           Control.Concurrent              (forkIO, killThread)
import           Control.Concurrent.STM          (atomically)
import           Control.Monad                   (forever, when)
import           Data.List                       (isSuffixOf)
import           Data.ListLike                   (ListLike)
import           Data.Map                        (Map)
import qualified Data.Map                        as Map
import           Data.Maybe                      (fromMaybe)
import           Data.String                     (IsString, fromString)
import           Data.Text                       (Text)
import qualified Data.Text                       as Text
import           Prelude                         hiding (readFile, writeFile)
import qualified System.Console.Haskeline        as Line
import qualified System.Console.Terminal.Size    as Terminal
import           Unison.Codebase                 (Codebase)
import qualified Unison.Codebase                 as Codebase
import           Unison.Codebase.Branch          (Branch, Branch0)
import           Unison.Codebase.Editor          (BranchName, Event (..),
                                                  Input (..))
import qualified Unison.Codebase.Runtime         as Runtime
import qualified Unison.Codebase.SearchResult    as SR
import qualified Unison.Codebase.Watch           as Watch
import           Unison.CommandLine.InputPattern (InputPattern (parse))
import qualified Unison.HashQualified            as HQ
import           Unison.Parser                   (Ann)
import           Unison.Parser                   (startingLine)
import qualified Unison.PrettyPrintEnv           as PPE
import           Unison.Term                     (Term)
import qualified Unison.TermPrinter              as TermPrinter
import qualified Unison.Util.ColorText           as CT
import qualified Unison.Util.Find                as Find
import qualified Unison.Util.Pretty              as P
import           Unison.Util.TQueue              (TQueue)
import qualified Unison.Util.TQueue              as Q
import           Unison.Var                      (Var)

watchPrinter :: Var v => Text -> PPE.PrettyPrintEnv -> Ann
                      -> Term v
                      -> Runtime.IsCacheHit
                      -> P.Pretty P.ColorText
watchPrinter src ppe ann term isHit = P.bracket $ let
  lines = Text.lines src
  lineNum = fromMaybe 1 $ startingLine ann
  lineNumWidth = length (show lineNum)
  extra = "     " -- for the ` | > ` after the line number
  line = lines !! (lineNum - 1)
  in P.lines [
    fromString (show lineNum) <> " | " <> P.text line,
    fromString (replicate lineNumWidth ' ')
      <> fromString extra <> "⧩"
      <> (if isHit then P.bold " (using cache)" else ""),
    P.indentN (lineNumWidth + length extra)
      . P.green $ TermPrinter.prettyTop ppe term
  ]

allow :: FilePath -> Bool
allow = (||) <$> (".u" `isSuffixOf`) <*> (".uu" `isSuffixOf`)

watchFileSystem :: TQueue Event -> FilePath -> IO (IO ())
watchFileSystem q dir = do
  (cancel, watcher) <- Watch.watchDirectory dir allow
  t <- forkIO . forever $ do
    (filePath, text) <- watcher
    atomically . Q.enqueue q $ UnisonFileChanged (Text.pack filePath) text
  pure (cancel >> killThread t)

watchBranchUpdates :: IO (Branch, BranchName) -> TQueue Event -> Codebase IO v a -> IO (IO ())
watchBranchUpdates currentBranch q codebase = do
  (cancelExternalBranchUpdates, externalBranchUpdates) <-
    Codebase.branchUpdates codebase
  thread <- forkIO . forever $ do
    updatedBranches <- externalBranchUpdates
    (b, bname) <- currentBranch
    b' <- Codebase.getBranch codebase bname
    -- We only issue the event if the branch is different than what's already
    -- in memory. This skips over file events triggered by saving to disk what's
    -- already in memory.
    when (b' /= Just b) $
      atomically . Q.enqueue q . UnisonBranchChanged $ updatedBranches
  pure (cancelExternalBranchUpdates >> killThread thread)

warnNote :: String -> String
warnNote s = "⚠️  " <> s

backtick :: IsString s => P.Pretty s -> P.Pretty s
backtick s = P.group ("`" <> s <> "`")

backtickEOS :: IsString s => P.Pretty s -> P.Pretty s
backtickEOS s = P.group ("`" <> s <> "`.")

tip :: P.Pretty CT.ColorText -> P.Pretty CT.ColorText
tip s = P.column2 [("Tip:", P.wrap s)]

warn :: (ListLike s Char, IsString s) => P.Pretty s -> P.Pretty s
warn s = emojiNote "⚠️" s

problem :: (ListLike s Char, IsString s) => P.Pretty s -> P.Pretty s
problem = emojiNote "❗️"

bigproblem :: (ListLike s Char, IsString s) => P.Pretty s -> P.Pretty s
bigproblem = emojiNote "‼️"

emojiNote :: (ListLike s Char, IsString s) => String -> P.Pretty s -> P.Pretty s
emojiNote lead s = P.group (fromString lead) <> "\n" <> P.wrap s

nothingTodo :: (ListLike s Char, IsString s) => P.Pretty s -> P.Pretty s
nothingTodo s = emojiNote "😶" s

completion :: String -> Line.Completion
completion s = Line.Completion s s True

prettyCompletion :: (String, P.Pretty P.ColorText) -> Line.Completion
-- -- discards formatting in favor of better alignment
-- prettyCompletion (s, p) = Line.Completion s (P.toPlainUnbroken p) True
-- preserves formatting, but Haskeline doesn't know how to align
prettyCompletion (s, p) = Line.Completion s (P.toAnsiUnbroken p) True

fuzzyCompleteHashQualified :: Branch0 -> String -> [Line.Completion]
fuzzyCompleteHashQualified b q0@(HQ.fromString -> query) =
    fixupCompletion q0 $
      makeCompletion <$> Find.fuzzyFindInBranch b query
  where
  makeCompletion (sr, p) =
    prettyCompletion (HQ.toString . SR.name $ sr, p)

fuzzyComplete :: String -> [String] -> [Line.Completion]
fuzzyComplete q ss =
  fixupCompletion q (prettyCompletion <$> Find.fuzzyFinder q ss id)

-- workaround for https://github.com/judah/haskeline/issues/100
-- if the common prefix of all the completions is smaller than
-- the query, we make all the replacements equal to the query,
-- which will preserve what the user has typed
fixupCompletion :: String -> [Line.Completion] -> [Line.Completion]
fixupCompletion _q [] = []
fixupCompletion _q [c] = [c]
fixupCompletion q cs@(h:t) = let
  commonPrefix (h1:t1) (h2:t2) | h1 == h2 = h1 : commonPrefix t1 t2
  commonPrefix _ _             = ""
  overallCommonPrefix =
    foldl commonPrefix (Line.replacement h) (Line.replacement <$> t)
  in if length overallCommonPrefix < length q
     then [ c { Line.replacement = q } | c <- cs ]
     else cs

autoCompleteHashQualified :: Branch0 -> String -> [Line.Completion]
autoCompleteHashQualified b (HQ.fromString -> query) =
  makeCompletion <$> Find.prefixFindInBranch b query
  where
  makeCompletion (sr, p) =
    prettyCompletion (HQ.toString . SR.name $ sr, p)

parseInput
  :: Map String InputPattern -> [String] -> Either (P.Pretty CT.ColorText) Input
parseInput patterns ss = case ss of
  []             -> Left ""
  command : args -> case Map.lookup command patterns of
    Just pat -> parse pat args
    Nothing ->
      Left
        .  warn
        .  P.wrap
        $  "I don't know how to "
        <> P.group (fromString command <> ".")
        <> "Type `help` or `?` to get help."

prompt :: String
prompt = "> "

-- like putPrettyLn' but prints a blank line before and after.
putPrettyLn :: P.Pretty CT.ColorText -> IO ()
putPrettyLn p = do
  width <- getAvailableWidth
  putStrLn . P.toANSI width $ P.border 2 p

putPrettyLn' :: P.Pretty CT.ColorText -> IO ()
putPrettyLn' p = do
  width <- getAvailableWidth
  putStrLn . P.toANSI width $ P.indentN 2 p

getAvailableWidth :: IO Int
getAvailableWidth =
  fromMaybe 80 . fmap (\s -> 100 `min` Terminal.width s) <$> Terminal.size
