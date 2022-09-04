module TypeChecker(typecheck, ValType (TypeBool, TypeInt, TypeStr), typeFromBNFC) where
import AbsGrammar ( Type(..), Ident, FunDecl' (DFun), Main' (DMain), Program(..), ArgDecl' (DArgDecl, DConstArgDecl),
  Block' (IBlock), Instr' (IRet, IIf, ITryBlock, IBlockInstr, IAss, IWhile, IPrStr, IBreak, IContinue, IRaise, IExp),
  Else' (IElseEmpty, IElse), Decl' (DFunDecl, DVarDecl, DConstVarDecl), Exp' (EAnd, EOr, EEq, ENeq,
  ELeq, EGeq, ELess, EGrt, EPlus, EMinus, EConcat, ETimes, EDiv, ENot, ENeg, EInt, EBool, EStr, EIdent,
  EFuncall), Type' (TBool, TInt, TStr), Arg' (AVal, ARef), ArgDecl, Program' (Prog), Main, Block, Decl, Instr,
  Exp, Arg, FunDecl, HasPosition (hasPosition), BNFC'Position )
import Data.Map ( empty, insert, lookup, Map )
type Constness = Prelude.Bool

data ValType = TypeBool | TypeInt | TypeStr
instance Eq ValType where
  TypeBool == TypeBool = True
  TypeInt == TypeInt = True
  TypeStr == TypeStr = True
  _ == _ = False

type FullType = (ValType, Constness)

newtype FunctionType = FunType (ValType, [FullType])
newtype FunctionBindings = FunBind (Map Ident FunctionType)
newtype TypeBindings = TypeBind (Map Ident FullType)
data ExpectedReturnType = ReturnType ValType | NoneType

newtype BindingsEnvironment = BindEnv (TypeBindings, FunctionBindings, ExpectedReturnType)

emptyEnv :: BindingsEnvironment
emptyEnv = BindEnv (TypeBind Data.Map.empty, FunBind Data.Map.empty, NoneType)

typeFromBNFC :: Type -> ValType
typeFromBNFC (TInt _) = TypeInt
typeFromBNFC (TBool _) = TypeBool
typeFromBNFC (TStr _) = TypeStr

type Err = Either String

getArgType :: ArgDecl -> FullType
getArgType (DArgDecl p t id) = (typeFromBNFC t, False)
getArgType (DConstArgDecl p t id) = (typeFromBNFC t, True)

getArgIdent :: ArgDecl -> Ident
getArgIdent (DArgDecl p t id) = id
getArgIdent (DConstArgDecl p t id) = id

addFunToFunEnv :: FunDecl -> FunctionBindings -> FunctionBindings
addFunToFunEnv (DFun p t ident args block) (FunBind fenv) = FunBind (insert ident (FunType (typeFromBNFC t, Prelude.map getArgType args)) fenv)

addArgsToTypeEnv :: [ArgDecl] -> TypeBindings -> TypeBindings
addArgsToTypeEnv [] tenv = tenv
addArgsToTypeEnv (arg:args) (TypeBind tmap) = addArgsToTypeEnv args (TypeBind (insert (getArgIdent arg) (getArgType arg) tmap))

addFunToEnv :: FunDecl -> BindingsEnvironment -> BindingsEnvironment
addFunToEnv decl (BindEnv (types, funs, ret)) = BindEnv (types, addFunToFunEnv decl funs, ret)

addVarToTypeEnv :: Ident -> ValType -> Bool -> TypeBindings -> TypeBindings
addVarToTypeEnv ident t constness (TypeBind tenv) = TypeBind (insert ident (t, constness) tenv)

addVarToEnv :: Ident -> ValType -> Bool -> BindingsEnvironment -> BindingsEnvironment
addVarToEnv ident t constness (BindEnv (types, funs, ret)) = BindEnv (addVarToTypeEnv ident t constness types, funs, ret)

addDeclToEnv :: Decl -> BindingsEnvironment -> BindingsEnvironment
addDeclToEnv (DFunDecl p fundecl) env = addFunToEnv fundecl env
addDeclToEnv (DVarDecl p t id exp) env = addVarToEnv id (typeFromBNFC t) False env
addDeclToEnv (DConstVarDecl p t id exp) env = addVarToEnv id (typeFromBNFC t) True env

checkOkay :: Err ValType
checkOkay = Right TypeInt -- arbitrary - this is to denote correct instructions and declarations,
                          -- which don't have types themselves

addFunAndArgsToEnv :: FunDecl -> BindingsEnvironment -> BindingsEnvironment
addFunAndArgsToEnv fundecl (BindEnv (types, funs, ret)) =
    BindEnv (addArgsToTypeEnv args types, addFunToFunEnv fundecl funs, ReturnType $ typeFromBNFC t)
  where (DFun p t ident args block) = fundecl

-- checks if an instruction will always execute the 'return' statement if no exception is raised
isAlwaysReturn :: Instr -> Bool
isAlwaysReturn (IRet p e) = True
isAlwaysReturn (IRaise p ident) = True
isAlwaysReturn (IIf p exp if_instr (IElse q else_instr)) = isAlwaysReturn if_instr && isAlwaysReturn else_instr
isAlwaysReturn (ITryBlock p (IBlock q try_decls try_ins) ident idents (IBlock r exc_decls exc_ins)) =
  any isAlwaysReturn try_ins && any isAlwaysReturn exc_ins
isAlwaysReturn (IBlockInstr p (IBlock q decls ins)) = any isAlwaysReturn ins
isAlwaysReturn _ = False

getError :: HasPosition a => String -> a -> Err ValType
getError s e = Left $ s ++ " at line " ++ show i ++ ", col " ++ show j
  where Just (i, j) = hasPosition e

getErrorForPosition :: String -> BNFC'Position  -> Err ValType
getErrorForPosition s p = Left $ s ++ " at line " ++ show i ++ ", col " ++ show j
  where Just (i, j) = p

verifyHasReturn :: [Instr] -> BNFC'Position -> Err ValType
verifyHasReturn ins p = if any isAlwaysReturn ins then checkOkay else getErrorForPosition "no return statement" p

typecheckFunDecl ::  FunDecl -> BindingsEnvironment -> Err ValType
typecheckFunDecl fundecl env = do
    blockCheck <- typecheckBlock block (addFunAndArgsToEnv fundecl env)
    verifyHasReturn ins p
  where (DFun p t id args block) = fundecl
        (IBlock q decls ins) = block

typecheckLogic :: Exp -> Exp -> BindingsEnvironment -> Err ValType
typecheckLogic exp1 exp2 env = do
    type1 <- typecheckExp exp1 env
    type2 <- typecheckExp exp2 env
    if TypeBool /= type1
      then getError "non-boolean expression in logic operation" exp1
      else
        if TypeBool /=  type2
        then getError "non-boolean expression in logic operation" exp2
        else Right TypeBool

typecheckEquality :: Exp -> Exp -> BindingsEnvironment -> Err ValType
typecheckEquality exp1 exp2 env = do
    type1 <- typecheckExp exp1 env
    type2 <- typecheckExp exp2 env
    if type1 == type2 then Right TypeBool else getError "invalid comparison of different types" exp1

typecheckArthComparison :: Exp -> Exp -> BindingsEnvironment -> Err ValType
typecheckArthComparison exp1 exp2 env = do
  type1 <- typecheckExp exp1 env
  type2 <- typecheckExp exp2 env
  if TypeInt /= type1
    then getError "non-arithmetic expression in comparison operation" exp1
    else
      if TypeInt /= type2
        then getError "non-arithmetic expression in comparison operation" exp2
        else Right TypeBool

typecheckArthOp :: Exp -> Exp -> BindingsEnvironment -> Err ValType
typecheckArthOp exp1 exp2 env = do
  type1 <- typecheckExp exp1 env
  type2 <- typecheckExp exp2 env
  if TypeInt /=  type1
    then getError "non-arithmetic expression in arithmetic operation" exp1
    else
      if TypeInt /=  type2
        then getError "non-arithmetic expression in arithmetic operation" exp2
        else Right TypeInt

typecheckStrOp :: Exp -> Exp -> BindingsEnvironment -> Err ValType
typecheckStrOp exp1 exp2 env = do
  type1 <- typecheckExp exp1 env
  type2 <- typecheckExp exp2 env
  if TypeStr /= type1
    then getError "non-string expression in string operation" exp1
    else
      if TypeStr /= type2
        then getError "non-string expression in string operation" exp2
        else Right TypeStr

typecheckArgs :: BNFC'Position  -> ValType -> [Arg] -> [FullType] -> BindingsEnvironment -> Err ValType
typecheckArgs p t [] [] env = Right t
typecheckArgs p t args [] env = getError "too many arguments passed" (head args)
typecheckArgs p t [] expexted_args env = getErrorForPosition "too few arguments passed" p
typecheckArgs p t (arg:args) ((expected_type, expected_const):expected_args) env = do
  case arg of
    AVal p e -> do
      arg_type <- typecheckExp e env
      if arg_type == expected_type
        then typecheckArgs p t args expected_args env
        else getError "wrong type of argument passed to function" arg
    ARef p ident -> do
      case Data.Map.lookup ident tmap of
        Nothing -> getError "identifier passed as function argument out of scope" arg
        Just (t, const) -> do
          if t /= expected_type
            then getError "wrong type of argument passed to function" arg
            else if const && not expected_const
              then getError "const reference passed as non-const argument" arg
              else typecheckArgs p t args expected_args env
    where (BindEnv (TypeBind tmap, _, _)) = env

typecheckFuncall :: BNFC'Position  -> Ident -> [Arg] -> BindingsEnvironment -> Err ValType
typecheckFuncall p ident args env = do
  case Data.Map.lookup ident funs of
    Nothing -> getErrorForPosition "function identifier not in scope" p
    Just (FunType (t, expected_args))-> typecheckArgs p t args expected_args env
  where (BindEnv (_, FunBind funs, _)) = env

typecheckExp :: Exp -> BindingsEnvironment -> Err ValType
typecheckExp (EAnd p exp1 exp2) env = typecheckLogic exp1 exp2 env
typecheckExp (EOr p exp1 exp2) env = typecheckLogic exp1 exp2 env
typecheckExp (EEq p exp1 exp2) env = typecheckEquality exp1 exp2 env
typecheckExp (ENeq p exp1 exp2) env = typecheckEquality exp1 exp2 env
typecheckExp (ELeq p exp1 exp2) env = typecheckArthComparison exp1 exp2 env
typecheckExp (EGeq p exp1 exp2) env = typecheckArthComparison exp1 exp2 env
typecheckExp (ELess p exp1 exp2) env = typecheckArthComparison exp1 exp2 env
typecheckExp (EGrt p exp1 exp2) env = typecheckArthComparison exp1 exp2 env
typecheckExp (EPlus p exp1 exp2) env = typecheckArthOp exp1 exp2 env
typecheckExp (EMinus p exp1 exp2) env = typecheckArthOp exp1 exp2 env
typecheckExp (EConcat p exp1 exp2) env = typecheckStrOp exp1 exp2 env
typecheckExp (ETimes p exp1 exp2) env = typecheckArthOp exp1 exp2 env
typecheckExp (EDiv p exp1 exp2) env = typecheckArthOp exp1 exp2 env
typecheckExp (ENot p exp) env = do
  exp_type <- typecheckExp exp env
  if TypeBool == exp_type then Right TypeBool else getError "non-boolean expression in logic negation" exp
typecheckExp (ENeg p int) env = Right TypeInt
typecheckExp (EInt p int) env = Right TypeInt
typecheckExp (EBool p b) env = Right TypeBool
typecheckExp (EStr p s) env = Right TypeStr
typecheckExp (EIdent p ident) env = do
  case  Data.Map.lookup ident types of
    Nothing -> getErrorForPosition "identifier not in scope" p
    Just (t, c) -> Right t
  where (BindEnv (TypeBind types, _, _)) = env
typecheckExp (EFuncall p ident args) env = typecheckFuncall p ident args env

typecheckDecl :: Decl -> BindingsEnvironment -> Err ValType
typecheckDecl (DFunDecl p fundecl) env = typecheckFunDecl fundecl env
typecheckDecl (DVarDecl p t id exp) env = do
    assigned_type <- typecheckExp exp env
    if assigned_type == typeFromBNFC t then checkOkay else getError "wrong type of assigned value in variable declaration" exp
typecheckDecl (DConstVarDecl p t id exp) env = do
    assigned_type <- typecheckExp exp env
    if assigned_type == typeFromBNFC t then checkOkay else getError "wrong type of assigned value in variable declaration" exp

typecheckInstr :: Instr -> BindingsEnvironment -> Err ValType
typecheckInstr (IAss p ident exp) env = do
    expression_type <- typecheckExp exp env
    case Data.Map.lookup ident types of
        Nothing -> getErrorForPosition "assignment to undeclared variable" p
        Just (_, True ) -> getErrorForPosition "assignment to const variable" p
        Just (t, False) -> if t == expression_type then checkOkay else getErrorForPosition "assignment with wrong type" p
    where (BindEnv (TypeBind types, FunBind funs, _)) = env
typecheckInstr (IIf p exp ins (IElseEmpty q)) env = do
    expression_type <- typecheckExp exp env
    if TypeBool /= expression_type
      then getError "non-boolean expression in if condition" exp
      else typecheckInstr ins env
typecheckInstr (IIf p exp if_ins (IElse q else_ins)) env = do
    expression_type <- typecheckExp exp env
    if TypeBool /=  expression_type
      then getError "non-boolean expression in if condition" exp
      else do
        typecheckInstr if_ins env
        if_type <- typecheckInstr if_ins env
        typecheckInstr else_ins env
typecheckInstr (IWhile p exp ins) env = do
    expression_type <- typecheckExp exp env
    if TypeBool == expression_type then typecheckInstr ins env else getError "non-boolean expression in while condition" exp
typecheckInstr (IPrStr q exp) env = do
    typecheckExp exp env
typecheckInstr (IRet p exp) (BindEnv (TypeBind types, FunBind funs, ReturnType ret)) = do
    expression_type <- typecheckExp exp (BindEnv (TypeBind types, FunBind funs, ReturnType ret))
    if expression_type == ret then checkOkay else getError "wrong return type" exp
typecheckInstr (IRet p exp) (BindEnv  (TypeBind types, FunBind funs, NoneType)) = getError "unexpected return statement in main" exp
typecheckInstr (IBreak p) env = checkOkay
typecheckInstr (IContinue p) env = checkOkay
typecheckInstr (IRaise p ident) env = checkOkay
typecheckInstr (ITryBlock p try_ins ident idents catch_ins) env = do
    try_ins_type <- typecheckBlock try_ins env
    typecheckBlock catch_ins env
typecheckInstr (IBlockInstr p block) env = typecheckBlock block env
typecheckInstr (IExp p exp) env = typecheckExp exp env

typecheckBlock :: Block -> BindingsEnvironment -> Err ValType
typecheckBlock (IBlock p (decl:decls) inss) env = do
    decltype <- typecheckDecl decl env
    typecheckBlock (IBlock p decls inss) (addDeclToEnv decl env)
typecheckBlock (IBlock p [] (ins:inss)) env = do
    instype <- typecheckInstr ins env
    typecheckBlock (IBlock p [] inss) env
typecheckBlock (IBlock p [] []) env = checkOkay

typecheckMain ::  Main -> BindingsEnvironment -> Err ValType
typecheckMain maindecl env = do
    typecheckBlock block env
  where (DMain p block) = maindecl
        (IBlock q decls ins) = block

typecheckProgram :: BindingsEnvironment -> Program -> Err ValType
typecheckProgram env (Prog p [] main) = typecheckMain main env
typecheckProgram env (Prog p (fun:funs) main) = do
  funtype <- typecheckFunDecl fun env
  typecheckProgram (addFunToEnv fun env) (Prog p funs main)

typecheck :: Program -> Maybe String
typecheck p = case typecheckProgram emptyEnv p of
  Left e -> Just e
  Right okay -> Nothing
