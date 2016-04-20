{- |
Module           : $Header$
Description      :
License          : BSD3
Stability        : provisional
Point-of-contact : atomb
-}
module SAWScript.VerificationCheck where

import Control.Monad
import qualified Cryptol.TypeCheck.AST as C
import qualified Cryptol.Eval.Value as CV
import Verifier.SAW.Cryptol (exportValueWithSchema, scCryptolType)
import Verifier.SAW.SharedTerm
import Verifier.SAW.Simulator.Concrete (CValue)
import Text.PrettyPrint.ANSI.Leijen

import Verifier.SAW.Cryptol (scCryptolEq)
import qualified SAWScript.Value as SV (PPOpts(..), cryptolPPOpts)

data VerificationCheck s
  = AssertionCheck String (SharedTerm s)
    -- ^ A predicate to check with a name and term.
  | EqualityCheck String          -- Name of value to compare
                  (SharedTerm s)  -- Value returned by implementation.
                  (SharedTerm s)  -- Expected value in Spec.
    -- ^ Check that equality assertion is true.

vcName :: VerificationCheck s -> String
vcName (AssertionCheck nm _) = nm
vcName (EqualityCheck nm _ _) = nm

-- | Returns goal that one needs to prove.
vcGoal :: SharedContext s -> VerificationCheck s -> IO (SharedTerm s)
vcGoal _ (AssertionCheck _ n) = return n
vcGoal sc (EqualityCheck _ x y) = scCryptolEq sc x y

type CounterexampleFn s = (SharedTerm s -> IO CValue) -> IO Doc

-- | Returns documentation for check that fails.
vcCounterexample :: SharedContext s -> SV.PPOpts -> VerificationCheck s -> CounterexampleFn s
vcCounterexample _ opts (AssertionCheck nm n) _ = do
  let opts' = defaultPPOpts { ppBase = SV.ppOptsBase opts }
  return $ text ("Assertion " ++ nm ++ " is unsatisfied:") <+>
           scPrettyTermDoc opts' n
vcCounterexample sc opts (EqualityCheck nm impNode specNode) evalFn =
  do ln <- evalFn impNode
     sn <- evalFn specNode
     lty <- scTypeOf sc impNode
     lct <- scCryptolType sc lty
     sty <- scTypeOf sc specNode
     sct <- scCryptolType sc sty
     let lschema = (C.Forall [] [] lct)
         sschema = (C.Forall [] [] sct)
     unless (lschema == sschema) $ fail "Mismatched schemas in counterexample"
     let lv = exportValueWithSchema lschema ln
         sv = exportValueWithSchema sschema sn
         opts' = SV.cryptolPPOpts opts
     -- Grr. Different pretty-printers.
     return (text nm <$$>
        nest 2 (text "Encountered: " <+>
                text (show (CV.ppValue opts' lv))) <$$>
        nest 2 (text "Expected:    " <+>
                text (show (CV.ppValue opts' sv))))

ppCheck :: VerificationCheck s -> Doc
ppCheck (AssertionCheck nm tm) =
  hsep [ text (nm ++ ":")
       , scPrettyTermDoc defaultPPOpts tm
       ]
ppCheck (EqualityCheck nm tm tm') =
  hsep [ text (nm ++ ":")
       , scPrettyTermDoc defaultPPOpts tm
       , text ":="
       , scPrettyTermDoc defaultPPOpts tm'
       ]
