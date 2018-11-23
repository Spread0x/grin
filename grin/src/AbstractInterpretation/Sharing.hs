{-# LANGUAGE LambdaCase, RecordWildCards #-}
module AbstractInterpretation.Sharing where
    
import Data.Set (Set)
import Data.Map (Map)
import Data.Vector (Vector)
import qualified Data.Set as Set
import qualified Data.Map as Map
import qualified Data.Vector as Vec

import qualified Data.Set.Extra as Set

import Data.Maybe
import Data.Foldable
import Data.Functor.Foldable

import Grin.Syntax
import Grin.TypeEnvDefs
import AbstractInterpretation.Util (converge)

{-
[x] Calc non-linear variables, optionally ignoring updates.
[x] Assumption: all the non-linear variables have registers already.
[x] For all non-linear variables set the locations as shared.
[x] For all the shared locations, look up the pointed locations and set to shared them.

[x] Create a register to maintain sharing information
[x] Add Sharing register as parameter to HPT
[x] Add Sharing register as parameter to Sharing
[x] Remove _shared field from Reduce
[-] Add 'In' to the Condition
[x] Remove GetShared from IR
[x] Remove SetShared from IR
[x] CodeGenMain: depend on optimisation phase, before InLineAfter inline
    [x] CodeGenMain: add an extra parameter
    [x] Pipeline: Set a variable if the codegen is after or before
[-] Add mode as parameter for the eval'' and typecheck
[x] Remove Mode for calcNonLinearVars
-}

type SharingResult = Set Loc

-- | Calc non linear variables, ignores variables that are used in update locations
-- This is an important difference, if a variable would become non-linear due to
-- being subject to an update, that would make the sharing analysis incorrect.
-- One possible improvement is to count the updates in a different set and make a variable
-- linear if it is subject to an update more than once. But that could not happen, thus the only
-- introdcution of new updates comes from inlining eval.
calcNonLinearNonUpdateLocVariables :: Exp -> Set.Set Name
calcNonLinearNonUpdateLocVariables exp = Set.fromList $ Map.keys $ Map.filter (>1) $ cata collect exp
  where
    union = Map.unionsWith (+)
    collect = \case
      ECaseF val alts -> union (seen val : alts)
      SStoreF val -> seen val
      SFetchIF var _ -> seen (Var var)
      SUpdateF var val -> seen val
      SReturnF val -> seen val
      SAppF _ ps -> union $ fmap seen ps
      rest -> Data.Foldable.foldr (Map.unionWith (+)) mempty rest

    seen = \case
      Var v -> Map.singleton v 1
      ConstTagNode _ ps -> union $ fmap seen ps
      VarTagNode v ps -> union $ fmap seen (Var v : ps)
      _ -> Map.empty

calcSharedLocations :: TypeEnv -> Exp -> Set Loc
calcSharedLocations TypeEnv{..} e = converge (==) (Set.concatMap fetchLocs) origShVarLocs where
  nonLinearVars = calcNonLinearNonUpdateLocVariables e
  shVarTypes    = Set.mapMaybe (`Map.lookup` _variable) $ nonLinearVars
  origShVarLocs = onlyLocations . onlySimpleTys $ shVarTypes

  onlySimpleTys :: Set Type -> Set SimpleType
  onlySimpleTys tys = Set.fromList [ sty | T_SimpleType sty <- Set.toList tys ]

  onlyLocations :: Set SimpleType -> Set Loc
  onlyLocations stys = Set.fromList $ concat [ ls | T_Location ls <- Set.toList stys ]

  fetchLocs :: Loc -> Set Loc
  fetchLocs l = onlyLocations . fieldsFromNodeSet . fromMaybe (error msg) . (Vec.!?) _location $ l
    where msg = "Sharing: Invalid heap index: " ++ show l
          
  fieldsFromNodeSet :: NodeSet -> Set SimpleType
  fieldsFromNodeSet = Set.fromList . concatMap Vec.toList . Map.elems
  
