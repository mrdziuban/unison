-- Interface to the Unison node
module Unison.Node where

import Dict as M
import Maybe (maybe)
import Either (Either(..))
import Http
import Http (Request, Response)
import Json
import Set as S
import Unison.Action as A
import Unison.Action (Action)
import Unison.Hash as H
import Unison.Hash (Hash)
import Unison.Metadata as MD
import Unison.Metadata (Metadata, Query)
import Unison.Term as E
import Unison.Path as Path
import Unison.Term (Term)
import Unison.Type as T
import Unison.Type (Type)
import Unison.Jsonify as J
import Unison.Jsonify (Jsonify)
import Unison.Parser as P
import Unison.Parser (Parser)
import Unison.Var as V
type Path = Path.Path

type Host = String

-- split a Signal (Response a) into two streams, Signal a
-- which just echos the the previous value
-- and a Signal String of error messages

jsonGet : Jsonify a -> Host -> String -> a -> Request String
jsonGet = jsonRequest "GET"

jsonPost : Jsonify a -> Host -> String -> a -> Request String
jsonPost = jsonRequest "POST"

jsonRequest : String -> Jsonify a -> Host -> String -> a -> Request String
jsonRequest verb ja host path a =
  Http.request verb (host ++ "/" ++ path) (J.render ja a) []

parseResponse : Parser a -> Response String -> Response a
parseResponse p r = case r of
  Http.Success body ->
    let err = Left ("malformed json: " ++ body)
    in case maybe err (P.run p) (Json.fromString body) of
      Left err -> Http.Failure 0 err
      Right a -> Http.Success a
  Http.Waiting -> Http.Waiting
  Http.Failure code body -> Http.Failure code body

admissibleTypeOf : Signal Host -> Signal (Term, Path.Path) -> Signal (Response Type)
admissibleTypeOf host params =
  let body = J.tuple2 E.jsonifyTerm Path.jsonifyPath
      req host params = jsonGet body host "admissible-type-of" params
  in parseResponse T.parseType <~ Http.send (lift2 req host params)

createTerm : Signal Host -> Signal (Term, Metadata) -> Signal (Response Hash)
createTerm host params =
  let body = J.tuple2 E.jsonifyTerm MD.jsonifyMetadata
      req host params = jsonPost body host "create-term" params
  in parseResponse H.parse <~ Http.send (lift2 req host params)

createType : Signal Host -> Signal (Type, Metadata) -> Signal (Response Hash)
createType host params =
  let body = J.tuple2 T.jsonifyType MD.jsonifyMetadata
      req host params = jsonPost body host "create-type" params
  in parseResponse H.parse <~ Http.send (lift2 req host params)

dependencies : Signal Host
            -> Signal (Maybe (S.Set Hash), Hash)
            -> Signal (Response (S.Set Hash))
dependencies host params =
  let body = J.tuple2 (J.optional (J.set H.jsonify)) H.jsonify
      req host params = jsonGet body host "dependencies" params
  in parseResponse (P.set H.parse) <~ Http.send (lift2 req host params)

dependents : Signal Host
          -> Signal (Maybe (S.Set Hash), Hash)
          -> Signal (Response (S.Set Hash))
dependents host params =
  let body = J.tuple2 (J.optional (J.set H.jsonify)) H.jsonify
      req host params = jsonGet body host "dependents" params
  in parseResponse (P.set H.parse) <~ Http.send (lift2 req host params)

editTerm : Signal Host
        -> Signal (Path, Action, Term)
        -> Signal (Response Term)
editTerm host params =
  let body = J.tuple3 Path.jsonifyPath A.jsonify E.jsonifyTerm
      req host params = jsonGet body host "edit-term" params
      parse = parseResponse E.parseTerm
  in parse <~ Http.send (lift2 req host params)

{-
editType : Signal Host
        -> Signal (Path, Action, Type)
        -> Signal (Response Type)
editTerm host params =
  let body = J.tuple3 H.jsonify Path.jsonify A.jsonify
      req host params = jsonGet body host "edit-type" params
      parse = parseResponse (P.tuple2 H.parse E.parseTerm)
  in parse <~ Http.send (lift2 req host params)
-}

metadatas : Signal Host -> Signal [Hash] -> Signal (Response (M.Dict Hash Metadata))
metadatas host params =
  let req host params = jsonGet (J.array H.jsonify) host "metadata" params
  in parseResponse (P.object MD.parseMetadata) <~ Http.send (lift2 req host params)

search : Signal Host
      -> Signal (Maybe Type, Maybe (S.Set Hash), Query)
      -> Signal (Response (M.Dict Hash Metadata))
search host params =
  let body = J.tuple3 (J.optional T.jsonifyType)
                      (J.optional (J.set H.jsonify))
                      MD.jsonifyQuery
      req host params = jsonGet body host "search" params
      parse = parseResponse (P.object MD.parseMetadata)
  in parse <~ Http.send (lift2 req host params)

searchLocal : Signal Host
           -> Signal (Hash, Path.Path, Maybe Type, Query)
           -> Signal (Response (Metadata, [(V.I, Type)]))
searchLocal host params =
  let body = J.tuple4 H.jsonify
                      Path.jsonifyPath
                      (J.optional T.jsonifyType)
                      MD.jsonifyQuery
      req host params = jsonGet body host "search-local" params
      parse = P.tuple2 MD.parseMetadata
                       (P.array (P.tuple2 V.parse T.parseType))
  in parseResponse parse <~ Http.send (lift2 req host params)

terms : Signal Host -> Signal [Hash] -> Signal (Response (M.Dict Hash Term))
terms host params =
  let req host params = jsonGet (J.array H.jsonify) host "terms" params
  in parseResponse (P.object E.parseTerm) <~ Http.send (lift2 req host params)

transitiveDependencies : Signal Host
                      -> Signal (Maybe (S.Set Hash), Hash)
                      -> Signal (Response (S.Set Hash))
transitiveDependencies host params =
  let body = J.tuple2 (J.optional (J.set H.jsonify)) H.jsonify
      req host params = jsonGet body host "transitive-dependencies" params
  in parseResponse (P.set H.parse) <~ Http.send (lift2 req host params)

transitiveDependents : Signal Host
                    -> Signal (Maybe (S.Set Hash), Hash)
                    -> Signal (Response (S.Set Hash))
transitiveDependents host params =
  let body = J.tuple2 (J.optional (J.set H.jsonify)) H.jsonify
      req host params = jsonGet body host "transitive-dependents" params
  in parseResponse (P.set H.parse) <~ Http.send (lift2 req host params)

types : Signal Host -> Signal [Hash] -> Signal (Response (M.Dict Hash Type))
types host params =
  let body = J.array H.jsonify
      req host params = jsonGet body host "types" params
  in parseResponse (P.object T.parseType) <~ Http.send (lift2 req host params)

typeOf : Signal Host
      -> Signal (Term, Path)
      -> Signal (Response Type)
typeOf host params =
  let body = J.tuple2 E.jsonifyTerm Path.jsonifyPath
      req host params = jsonGet body host "type-of" params
      parse = parseResponse T.parseType
  in parse <~ Http.send (lift2 req host params)

updateMetadata : Signal Host
              -> Signal (Hash, Metadata)
              -> Signal (Response ())
updateMetadata host params =
  let body = J.tuple2 H.jsonify MD.jsonifyMetadata
      req host params = jsonPost body host "update-metadata" params
      parse = parseResponse (P.unit ())
  in parse <~ Http.send (lift2 req host params)

undefined : a
undefined = undefined
