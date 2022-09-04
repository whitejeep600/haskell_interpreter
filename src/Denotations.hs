module Denotations (progDenotation) where
import Control.Monad.Except
    ( fix, MonadIO(liftIO), MonadError(throwError), ExceptT )
import Data.Map (Map, lookup, empty, size, insert)
import qualified Data.Maybe
import qualified AbsGrammar (Bool, Bool')
import AbsGrammar (Ident (Ident), Arg, Decl, Decl' (DVarDecl, DConstVarDecl, DFunDecl), FunDecl' (DFun), ArgDecl, Instr,
  Block' (IBlock), Instr' (IBlockInstr, IAss, IIf, IWhile, ITryBlock, IRaise, IRet, IBreak, IContinue, IExp, IPrStr),
  Else' (IElse, IElseEmpty), Exp, Exp' (EFuncall, EIdent, EInt, ENeg, EDiv, ETimes, EMinus, EPlus, EOr, EAnd, EEq,
  ENeq, ELeq, EGeq, ELess, EGrt, EBool, EStr, EConcat, ENot), Program, Program' (Prog), FunDecl, Main' (DMain),
  Arg' (AVal, ARef), ArgDecl' (DArgDecl, DConstArgDecl),
  Bool' (BTrue, BFalse))
import TypeChecker (ValType (TypeBool, TypeInt, TypeStr), typeFromBNFC)

type Loc = Int
type FName = Ident
type EName = Ident

type IntState = (Map Loc Int)
type BoolState = (Map Loc Bool)
type StrState = (Map Loc String)

type State =  (IntState, BoolState, StrState)

type AnsMonad = ExceptT String IO
type Ans = AnsMonad State

type Cont = State -> Ans
data ContRet = ContInt ContE | ContBool ContB | ContStr ContS  -- the continuation expecting the value of return statement
type ContE = Int -> Cont
type ContB = Bool -> Cont
type ContS = String -> Cont
type ContD = Env -> FEnv -> State -> Ans
type ContA = Env -> State -> Ans

type Env = (Map Ident Loc)
newtype FEnv = FEnv (Map Ident (Fun, ValType))
type EEnv = (Map EName Cont)

type Fun = [Arg] -> ContRet -> Env -> FEnv -> EEnv -> Cont

newloc :: State -> Loc
newloc (ints, bools, strs) = Data.Map.size ints + Data.Map.size bools + Data.Map.size strs

mapIntInState :: Loc -> Int -> State -> State
mapIntInState l i (ints, bools, strs) = (Data.Map.insert l i ints, bools, strs)

mapBoolInState :: Loc -> Bool -> State -> State
mapBoolInState l b (ints, bools, strs) = (ints, Data.Map.insert l b bools, strs)

mapStrInState :: Loc -> String -> State -> State
mapStrInState l s (ints, bools, strs) = (ints, bools, Data.Map.insert l s strs)

mapLocInEnv :: Ident -> Loc -> Env -> Env
mapLocInEnv = Data.Map.insert

mapFunInFenv :: ValType -> FName -> Fun -> FEnv -> FEnv
mapFunInFenv t fname fun (FEnv map) = FEnv $ Data.Map.insert fname (fun, t) map

mapExcInEnv :: Ident -> Cont -> EEnv -> EEnv
mapExcInEnv = Data.Map.insert

fakeEmptyFun :: (Fun, ValType)
fakeEmptyFun = (f, TypeInt) where
    f :: Fun
    f _ _ _ _ _ _ = throwError "call to nonexistent function will not happen due to typecheck"

-- due to static typecheck, these lookups will always be successful.
askEnv :: Env -> Ident -> Loc
askEnv map ident = Data.Maybe.fromMaybe 0 (Data.Map.lookup ident map)

askFEnv :: FEnv -> Ident -> Fun
askFEnv (FEnv map) ident = f where
    (f, t) = Data.Maybe.fromMaybe fakeEmptyFun (Data.Map.lookup ident map)

askFEnvForType :: FEnv -> Ident -> ValType
askFEnvForType (FEnv map) ident = t where
    (f, t) = Data.Maybe.fromMaybe fakeEmptyFun (Data.Map.lookup ident map)

askEEnv :: EEnv -> Ident -> Cont
askEEnv map ident = Data.Maybe.fromMaybe (errorContWithIdent ident) (Data.Map.lookup ident map)

askStateInt :: State -> Loc -> Int
askStateInt (i_state, _, _) l = Data.Maybe.fromMaybe 0 (Data.Map.lookup l i_state)

askStateBool :: State -> Loc -> Bool
askStateBool (_, b_state, _) l = Data.Maybe.fromMaybe False (Data.Map.lookup l b_state)

askStateStr :: State -> Loc -> String
askStateStr (_, _, s_state) l = Data.Maybe.fromMaybe "" (Data.Map.lookup l s_state)

getTypeFromState :: Loc -> State -> ValType
getTypeFromState l (ints, bools, strs) = case Data.Map.lookup l ints of
    Just _ -> TypeInt
    Nothing -> case Data.Map.lookup l bools of
        Just _ -> TypeBool
        Nothing -> TypeStr 

getType :: Ident -> Env -> State -> ValType
getType ident rho = getTypeFromState (askEnv rho ident)

-- this is necessary for printing the correct type.
runtimeTypecheck :: Exp -> Env -> FEnv -> State -> ValType
runtimeTypecheck (EAnd p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (EOr p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (EEq p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (ENeq p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (ELeq p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (EGeq p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (ELess p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (EGrt p exp1 exp2) env fenv s = TypeBool
runtimeTypecheck (EPlus p exp1 exp2) env fenv s = TypeInt
runtimeTypecheck (EMinus p exp1 exp2) env fenv s = TypeInt
runtimeTypecheck (EConcat p exp1 exp2) env fenv s = TypeStr
runtimeTypecheck (ETimes p exp1 exp2) env fenv s = TypeInt
runtimeTypecheck (EDiv p exp1 exp2) env fenv s = TypeInt
runtimeTypecheck (ENot p exp) env fenv s = TypeBool
runtimeTypecheck (ENeg p int) env fenv s = TypeInt
runtimeTypecheck (EInt p int) env fenv s = TypeInt
runtimeTypecheck (EBool p b) env fenv s = TypeBool
runtimeTypecheck (EStr p str) env  fenv s = TypeStr
runtimeTypecheck (EIdent p ident) env fenv s = getType ident env s
runtimeTypecheck (EFuncall p ident args) env fenv s = askFEnvForType fenv ident

-- lookup in the exception environment might fail (this is not checked in static typecheck). Thus,
-- if a nonexistent exception identifier is being looked up, an error continuation is returned.
errorContWithIdent :: Ident -> Cont
errorContWithIdent (Ident message) s = throwError $ "uncaught exception: " ++ show message

declDenotation :: Decl -> Env -> FEnv -> EEnv -> ContD -> State -> Ans
declDenotation (DVarDecl p t ident expr) rho rhoF rhoE kappaD s =
    case typeFromBNFC t of
        TypeInt -> arthExpDenotation expr rho rhoF rhoE kappaE s where
            kappaE :: ContE
            kappaE n s' = kappaD (mapLocInEnv ident l rho) rhoF (mapIntInState l n s')
              where l = newloc s'
        TypeBool -> boolExpDenotation expr rho rhoF rhoE kappaB s where
            kappaB :: ContB
            kappaB b s' = kappaD (mapLocInEnv ident l rho) rhoF (mapBoolInState l b s')
              where l = newloc s'
        TypeStr -> strExpDenotation expr rho rhoF rhoE kappaS s where
            kappaS :: ContS
            kappaS str s' = kappaD (mapLocInEnv ident l rho) rhoF (mapStrInState l str s')
              where l = newloc s'
declDenotation (DConstVarDecl p t ident expr) rho rhoF rhoE kappaD s =
    declDenotation (DVarDecl p t ident expr) rho rhoF rhoE kappaD s
declDenotation (DFunDecl p (DFun q t ident argdecls block)) rho rhoF rhoE kappaD s =
    kappaD rho (mapFunInFenv (typeFromBNFC t) ident f rhoF) s where
        f = fix phi where
            phi :: Fun -> Fun
            phi x args kappaRet rho'' rhoF'' rhoE'' s'' = compositeArgDenotation argdecls args rho kappaA rho'' rhoF'' rhoE'' s'' where
                kappaA :: ContA
                kappaA rho' s' = instrDenotation (IBlockInstr q block) rho' (mapFunInFenv (typeFromBNFC t) ident x rhoF) rhoE'' errorCont kappaRet errorCont errorCont s'

compositeDeclDenotation :: [Decl] -> Env -> FEnv -> EEnv -> ContD -> State -> Ans
compositeDeclDenotation (decl:decls) rho rhoF rhoE kappaD s =
    declDenotation decl rho rhoF rhoE kappa_decls s where
        kappa_decls :: ContD
        kappa_decls rho' rhoF' s' = compositeDeclDenotation decls rho' rhoF' rhoE kappaD s'
compositeDeclDenotation [] rho rhoF rhoE kappaD s = kappaD rho rhoF s

argDenotation :: ArgDecl -> Arg -> Env -> ContA -> Env -> FEnv -> EEnv -> State -> Ans
argDenotation (DArgDecl p t v) (AVal q e) rho kappaA rho' rhoF' rhoE' s' =
    case typeFromBNFC t of
        TypeInt -> arthExpDenotation e rho' rhoF' rhoE' kappaE s' where
            kappaE :: ContE
            kappaE n s''' = kappaA (mapLocInEnv v l rho) (mapIntInState l n s''') where
                l = newloc s'''
        TypeBool -> boolExpDenotation e rho' rhoF' rhoE' kappaB s' where
            kappaB :: ContB
            kappaB d s''' = kappaA (mapLocInEnv v l rho) (mapBoolInState l d s''') where
                l = newloc s'''
        TypeStr -> strExpDenotation e rho' rhoF' rhoE' kappaS s' where
            kappaS :: ContS
            kappaS str s''' = kappaA (mapLocInEnv v l rho) (mapStrInState l str s''') where
                l = newloc s'''
argDenotation (DArgDecl p t v) (ARef q x) rho kappaA rho' rhoF' rhoE' s =
    kappaA (mapLocInEnv v (askEnv rho' x) rho) s
argDenotation (DConstArgDecl p t v) (AVal q e) rho kappaA rho' rhoF' rhoE' s =
    argDenotation (DArgDecl p t v) (AVal q e) rho kappaA rho' rhoF' rhoE' s
argDenotation (DConstArgDecl p t v) (ARef q x) rho kappaA rho' rhoF' rhoE' s =
    argDenotation (DArgDecl p t v) (ARef q x) rho kappaA rho' rhoF' rhoE' s

compositeArgDenotation :: [ArgDecl] -> [Arg] -> Env -> ContA -> Env -> FEnv -> EEnv -> State -> Ans
compositeArgDenotation (argdecl:argdecls) (arg:args) rho kappaA rho'' rhoF'' rhoE'' s'' =
    argDenotation argdecl arg rho kappaA' rho'' rhoF'' rhoE'' s'' where
        kappaA' :: ContA
        kappaA' rho' s' = compositeArgDenotation argdecls args rho' kappaA rho'' rhoF'' rhoE'' s'
compositeArgDenotation [] [] rho kappaA rho'' rhoF'' rhoE'' s'' = kappaA rho s''
compositeArgDenotation _ _ rho kappaA rho' rhoF' rhoE' s =  throwError "mismatch in argument list length cannot happen due to static typecheck"

instrDenotation :: Instr -> Env -> FEnv -> EEnv -> Cont -> ContRet -> Cont -> Cont -> State -> Ans
instrDenotation (IBlockInstr p (IBlock q decls instrs)) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    compositeDeclDenotation decls rho rhoF rhoE kappaD s where
        kappaD :: ContD
        kappaD rho' rhoF' s' = compositeInstrDenotation instrs rho' rhoF' rhoE kappaDf kappaRet kappaBr kappaC s'
instrDenotation (IAss p ident exp) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    case getType ident rho s of
        TypeInt -> arthExpDenotation exp rho rhoF rhoE kappaE' s where
            kappaE' :: ContE
            kappaE' n s' = kappaDf (mapIntInState (askEnv rho ident) n s')
        TypeBool -> boolExpDenotation exp rho rhoF rhoE kappaB' s where
            kappaB' :: ContB
            kappaB' d s' = kappaDf (mapBoolInState (askEnv rho ident) d s')
        TypeStr -> strExpDenotation exp rho rhoF rhoE kappaS' s where
            kappaS' :: ContS
            kappaS' str s' = kappaDf (mapStrInState (askEnv rho ident) str s')
instrDenotation (IIf p bexp if_ins (IElse q else_ins)) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    boolExpDenotation bexp rho rhoF rhoE kappaB s where
        kappaB :: ContB
        kappaB d s' = if d then i1 else i2 where
            i1 :: Ans
            i1 = instrDenotation if_ins rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s'
            i2 :: Ans
            i2 = instrDenotation else_ins rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s'
instrDenotation (IIf p bexp if_ins (IElseEmpty q)) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    boolExpDenotation bexp rho rhoF rhoE kappaB s where
        kappaB :: ContB
        kappaB d s' = if d then i1 else kappaDf s' where
            i1 :: Ans
            i1 = instrDenotation if_ins rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s'
instrDenotation (IWhile p bexp ins) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    boolExpDenotation bexp rho rhoF rhoE kappaB s where
        kappaB :: ContB
        kappaB d s' = if d then i1 else kappaDf s' where
            i1 :: Ans
            i1 = compositeInstrDenotation [ins, IWhile p bexp ins] rho rhoF rhoE kappaDf kappaRet kappaDf kappaC' s' where
                kappaC' :: Cont
                kappaC' = instrDenotation (IWhile p bexp ins) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC
instrDenotation (ITryBlock p try_ins ident idents catch_ins) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    instrDenotation (IBlockInstr p try_ins) rho rhoF (mapExcInEnv ident i2 rhoE) kappaDf kappaRet kappaBr kappaC s where
        i2 :: Cont
        i2 = instrDenotation (IBlockInstr p catch_ins) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC
instrDenotation (IRaise p ident) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s = askEEnv rhoE ident s
instrDenotation (IRet p exp) rho rhoF rhoE kappaDf (ContInt kappaE) kappaBr kappaC s =
    arthExpDenotation exp rho rhoF rhoE kappaE s
instrDenotation (IRet p exp) rho rhoF rhoE kappaDf (ContBool kappaB) kappaBr kappaC s =
    boolExpDenotation exp rho rhoF rhoE kappaB s
instrDenotation (IRet p exp) rho rhoF rhoE kappaDf (ContStr kappaS) kappaBr kappaC s =
    strExpDenotation exp rho rhoF rhoE kappaS s
instrDenotation (IBreak p) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s = kappaBr s
instrDenotation (IContinue p) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s = kappaC s
instrDenotation (IExp p exp) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    case runtimeTypecheck exp rho rhoF s of
        TypeInt -> arthExpDenotation exp rho rhoF rhoE kappaE s where
            kappaE :: ContE
            kappaE n s' = kappaDf s'
        TypeBool -> boolExpDenotation exp rho rhoF rhoE kappaB s where
            kappaB :: ContB
            kappaB d s' = kappaDf s'
        TypeStr -> strExpDenotation exp rho rhoF rhoE kappaS s where
            kappaS :: ContS
            kappaS str s' = kappaDf s'
instrDenotation (IPrStr p exp) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    case runtimeTypecheck exp rho rhoF s of
        TypeInt -> arthExpDenotation exp rho rhoF rhoE kappaE s where
            kappaE :: ContE
            kappaE n s' = do
                liftIO $ putStr $ show n
                kappaDf s'
        TypeBool -> boolExpDenotation exp rho rhoF rhoE kappaB s where
            kappaB :: ContB
            kappaB d s' = do
                liftIO $ putStr $ show d
                kappaDf s'
        TypeStr -> strExpDenotation exp rho rhoF rhoE kappaS s where
            kappaS :: ContS
            kappaS str s' = do
                liftIO $ putStr str
                kappaDf s'

compositeInstrDenotation :: [Instr] -> Env -> FEnv -> EEnv -> Cont -> ContRet -> Cont -> Cont -> State -> Ans
compositeInstrDenotation (instr:instrs) rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s =
    instrDenotation instr rho rhoF rhoE kappaDf' kappaRet kappaBr kappaC s where
        kappaDf' :: Cont
        kappaDf' s' = compositeInstrDenotation instrs rho rhoF rhoE kappaDf kappaRet kappaBr kappaC s'
compositeInstrDenotation [] rho rhoF rhoE kappaDf kappaE kappaBr kappaC s = kappaDf s

type ArthOp = Int -> Int -> Int

runArthDenotation :: ArthOp -> Exp -> Exp -> Env -> FEnv -> EEnv -> ContE -> State -> Ans
runArthDenotation op exp1 exp2 rho rhoF rhoE kappaE =
    arthExpDenotation exp1 rho rhoF rhoE kappaE' where
        kappaE' :: ContE
        kappaE' n s' = arthExpDenotation exp2 rho rhoF rhoE kappaE'' s' where
            kappaE'' :: ContE
            kappaE'' m s'' = kappaE (op n m) s''

arthExpDenotation :: Exp -> Env -> FEnv -> EEnv -> ContE -> State -> Ans
arthExpDenotation (EFuncall p ident args) rho rhoF rhoE kappaE s =
    askFEnv rhoF ident args kappaRet rho rhoF rhoE s where
        kappaRet = ContInt kappaE
arthExpDenotation (EIdent p ident) rho rhoF rhoE kappaE s = kappaE n s where
    n = askStateInt s (askEnv rho ident)
arthExpDenotation (EInt p i) rho rhoF rhoE kappaE s = kappaE (fromIntegral i) s
arthExpDenotation (ENeg p i) rho rhoF rhoE kappaE s = kappaE (-1 * fromIntegral i) s
arthExpDenotation (EDiv (Just (line, col)) exp1 exp2) rho rhoF rhoE kappaE s =
    arthExpDenotation exp1 rho rhoF rhoE kappaE' s where
        kappaE' :: ContE
        kappaE' n s' = arthExpDenotation exp2 rho rhoF rhoE kappaE'' s' where
            kappaE'' :: ContE
            kappaE'' m s'' = if m == 0
                then throwError $ "divisionByZero at line" ++ show line ++ ", col " ++ show col
                else kappaE (div n m) s''
arthExpDenotation (ETimes p exp1 exp2) rho rhoF rhoE kappaE s = runArthDenotation (*) exp1 exp2 rho rhoF rhoE kappaE s
arthExpDenotation (EMinus p exp1 exp2) rho rhoF rhoE kappaE s = runArthDenotation (-) exp1 exp2 rho rhoF rhoE kappaE s
arthExpDenotation (EPlus p exp1 exp2) rho rhoF rhoE kappaE s = runArthDenotation (+) exp1 exp2 rho rhoF rhoE kappaE s
arthExpDenotation _ rho rhoF rhoE kappaE s = throwError "a different arth expression impossible here due to static typecheck"

getBoolVal :: AbsGrammar.Bool' a -> Bool
getBoolVal (BTrue a) = True
getBoolVal (BFalse a) = False

type BoolOp = Bool -> Bool -> Bool

runBoolOpDenotation :: BoolOp -> Exp -> Exp -> Env -> FEnv -> EEnv -> ContB -> State -> Ans
runBoolOpDenotation op exp1 exp2 rho rhoF rhoE kappaB =
    boolExpDenotation exp1 rho rhoF rhoE kappaB' where
        kappaB' :: ContB
        kappaB' d1 s' = boolExpDenotation exp2 rho rhoF rhoE kappaB'' s' where
            kappaB'' :: ContB
            kappaB'' d2 s'' = kappaB (op d1 d2) s''

type Comp = Int -> Int -> Bool

runCompDenotation :: Comp -> Exp -> Exp -> Env -> FEnv -> EEnv -> ContB -> State -> Ans
runCompDenotation op exp1 exp2 rho rhoF rhoE kappaB =
    arthExpDenotation exp1 rho rhoF rhoE kappaE' where
        kappaE' :: ContE
        kappaE' n s' = arthExpDenotation exp2 rho rhoF rhoE kappaE'' s' where
            kappaE'' :: ContE
            kappaE'' m s'' = kappaB (op n m) s''

boolExpDenotation :: Exp -> Env -> FEnv -> EEnv -> ContB -> State -> Ans
boolExpDenotation (EFuncall p ident args) rho rhoF rhoE kappaB s =
    askFEnv rhoF ident args kappaRet rho rhoF rhoE s where
        kappaRet = ContBool kappaB
boolExpDenotation (EOr p exp1 exp2) rho rhoF rhoE kappaB s =
    boolExpDenotation exp1 rho rhoF rhoE kappaB' s where
        kappaB' :: ContB
        kappaB' d1 s' = boolExpDenotation exp2 rho rhoF rhoE kappaB'' s' where
            kappaB'' :: ContB
            kappaB'' d2 s'' = kappaB (d1 || d2) s''
boolExpDenotation (EAnd p exp1 exp2) rho rhoF rhoE kappaB s =
    boolExpDenotation exp1 rho rhoF rhoE kappaB' s where
        kappaB' :: ContB
        kappaB' d1 s' = boolExpDenotation exp2 rho rhoF rhoE kappaB'' s' where
            kappaB'' :: ContB
            kappaB'' d2 s'' = kappaB (d1 && d2) s''
boolExpDenotation (EEq p exp1 exp2) rho rhoF rhoE kappaB s = runCompDenotation (==) exp1 exp2 rho rhoF rhoE kappaB s
boolExpDenotation (ENeq p exp1 exp2) rho rhoF rhoE kappaB s = runCompDenotation (/=) exp1 exp2 rho rhoF rhoE kappaB s
boolExpDenotation (ELeq p exp1 exp2) rho rhoF rhoE kappaB s = runCompDenotation (<=) exp1 exp2 rho rhoF rhoE kappaB s
boolExpDenotation (EGeq p exp1 exp2) rho rhoF rhoE kappaB s = runCompDenotation (>=) exp1 exp2 rho rhoF rhoE kappaB s
boolExpDenotation (ELess p exp1 exp2) rho rhoF rhoE kappaB s = runCompDenotation (<) exp1 exp2 rho rhoF rhoE kappaB s
boolExpDenotation (EGrt p exp1 exp2) rho rhoF rhoE kappaB s = runCompDenotation (>) exp1 exp2 rho rhoF rhoE kappaB s
boolExpDenotation (ENot p exp) rho rhoF rhoE kappaB s =
    boolExpDenotation exp rho rhoF rhoE kappaB' s where
        kappaB' :: ContB
        kappaB' d s' = kappaB (not d) s'
boolExpDenotation (EIdent p ident) rho rhoF rhoE kappaB s = kappaB d s where
    d = askStateBool s (askEnv rho ident)
boolExpDenotation (EBool p b) rho rhoF rhoE kappaB s = kappaB (getBoolVal b) s
boolExpDenotation _ rho rhoF rhoE kappaB s = throwError "another bool expression cannot happen due to static typecheck"

strExpDenotation :: Exp -> Env -> FEnv -> EEnv -> ContS -> State -> Ans
strExpDenotation (EFuncall p ident args) rho rhoF rhoE kappaS s =
    askFEnv rhoF ident args kappaRet rho rhoF rhoE s where
        kappaRet = ContStr kappaS
strExpDenotation (EConcat p exp1 exp2) rho rhoF rhoE kappaS s =
    strExpDenotation exp1 rho rhoF rhoE kappaS' s where
        kappaS' :: ContS
        kappaS' str1 s' = strExpDenotation exp2 rho rhoF rhoE kappaS'' s' where
            kappaS'' :: ContS
            kappaS'' str2 s'' = kappaS (str1 ++ str2) s''
strExpDenotation (EIdent p ident) rho rhoF rhoE kappaS s = kappaS str s where
    str = askStateStr s (askEnv rho ident)
strExpDenotation (EStr p str) rho rhoF rhoE kappaS s = kappaS str s
strExpDenotation _ rho rhoF rhoE kappaS s = throwError "another string expression cannot happen due to static typecheck"

emptyEnv :: Env
emptyEnv = Data.Map.empty

emptyFEnv :: FEnv
emptyFEnv = FEnv Data.Map.empty

emptyEEnv :: EEnv
emptyEEnv = Data.Map.empty

emptyState :: State
emptyState = (Data.Map.empty, Data.Map.empty, Data.Map.empty)

emptyCont :: Cont
emptyCont s = do
    return s

declFromFunDecl :: FunDecl -> Decl
declFromFunDecl (DFun p t ident args block) = DFunDecl p (DFun p t ident args block)

errorCont :: Cont
errorCont s = throwError "unexpected break or continue"

errorContE :: ContRet
errorContE  = ContInt kappa where
    kappa :: ContE
    kappa x s = throwError $ show "unexpected return (but this is not used due to static typecheck)"

progDenotation :: Program -> Ans
progDenotation (Prog p decls (DMain q block)) = compositeDeclDenotation fun_decls emptyEnv emptyFEnv emptyEEnv mainDenotation emptyState
  where
      fun_decls = map declFromFunDecl decls
      mainDenotation :: ContD
      mainDenotation rho rhoF s = instrDenotation (IBlockInstr p block) emptyEnv rhoF emptyEEnv emptyCont errorContE errorCont errorCont emptyState
