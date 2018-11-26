{-# LANGUAGE LambdaCase, RecordWildCards #-}
module AbstractInterpretation.PrettySharing where

import Text.PrettyPrint.ANSI.Leijen

import Data.Set (Set)
import Data.Map (Map)
import qualified Data.Set as Set
import qualified Data.Map as Map

import Data.Vector (Vector)
import qualified Data.Vector as V

import Grin.Pretty
import AbstractInterpretation.PrettyHPT
import AbstractInterpretation.HPTResult
import AbstractInterpretation.SharingResult


instance Pretty SharingResult where 
  pretty = prettySharingResult

prettySharingResult :: SharingResult -> Doc
prettySharingResult shResult = vsep
  [ yellow (text "Heap (* is shared)") <$$> indent 4 (prettyKeyValue . V.toList . V.imap annotateSharedLoc $ _memory) 
  , yellow (text "Env")                <$$> indent 4 (prettyKeyValue $ Map.toList  _register)
  , yellow (text "Function")           <$$> indent 4 (vsep $ map prettyHPTFunction $ Map.toList _function)
  ] where 
  shLocs = _sharedLocs shResult
  HPTResult{..} = _hptResult $ shResult
  annotateSharedLoc loc ty
    | Set.member loc shLocs = (pretty loc <> text "*", ty)  
    | otherwise             = (pretty loc, ty)  

