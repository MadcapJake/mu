{-# OPTIONS_GHC -fglasgow-exts #-}

module Pugs.Compile.Parrot where
import Pugs.Internals
import Pugs.Pretty
import Pugs.AST
import Data.HashTable
import Text.PrettyPrint

-- XXX This compiler needs a totaly rewrite using Parrot AST,
-- XXX and maybe TH-based AST combinators

genPIR :: Env -> IO String
genPIR Env{ envBody = exp } = return . unlines $
    [ "#!/usr/bin/env parrot"
    , ".sub main @MAIN"
    , ""
    , renderStyle (Style LeftMode 0 0) (compile exp)
    , ".end"
    ]

class (Show x) => Compile x where
    compile :: x -> Doc
    compile x = internalError ("Unrecognized construct: " ++ show x)

varText ('$':name)  = text $ "s__" ++ name
varText ('@':name)  = text $ "a__" ++ name
varText ('%':name)  = text $ "h__" ++ name
varText x           = error $ "invalid name: " ++ x

varInit ('$':_) = text $ "PerlUndef"
varInit ('@':_) = text $ "PerlArray"
varInit ('%':_) = text $ "PerlHash"
varInit x       = error $ "invalid name: " ++ x

instance Compile SourcePos where
    compile SourcePos{ sourceName = file, sourceLine = line } = hsep $
        [ text "#line"
        , doubleQuotes $ text file
        , showText line
        ]

declareLabel :: (Show a) => a -> String -> Doc
declareLabel exp str = text $
    "LABEL_" ++ show (hashString (show exp)) ++ "_" ++ str

label doc = doc <> text ":"

compileCond neg exps@[cond, bodyIf, bodyElse] =
    let [alt, end] = map (declareLabel exps) ["else", "endif"] in vcat $
        [ text neg <+> compile cond <+> text "goto" <+> alt
        , compile bodyIf
        , text "goto" <+> end
        , label alt
        , compile bodyElse
        , label end
        ]
compileCond x y = error $ show (x,y)

instance Compile Exp where
    compile (Var name) = varText name
    compile (Syn ";" stmts) = vcat $ map compile stmts
    compile (Syn "=" [var, Syn "[]" [lhs, rhs]]) = vcat $
        [ compile var <+> text "=" <+> compile lhs <> text "[" <> compile rhs <> text"]"
        ]
    compile (Syn "block" blocks) = vcat $ map compile blocks
    compile (Syn "=" [lhs, rhs@(Var _)]) = hsep $
        [ compile lhs, text "=", text "assign", compile rhs ]
    compile (Syn "=" [lhs, rhs]) = hsep $
        [ compile lhs, text "=", compile rhs ]
    compile (Syn "if" exps) = compileCond "unless" exps
    compile (Syn "unless" exps) = compileCond "if" exps
    compile exp@(Syn "loop" [pre, cond, post, body]) = 
        let [start, end, last] = map (declareLabel exp) ["start", "end", "last"] in vcat $
            [ compile pre
            , text "goto" <+> end
            , label start
            , text ".local pmc last"
            , text "last = new Continuation"
            , text "set_addr last," <+> last
            , compile body
            , compile post
            , label end
            -- , text "if" <+> compile cond <+> text "goto" <+> start
            , compile cond
            , text "goto" <+> start
            , label last
            ]
    compile (App "&last" _ _) = text "invoke last"
    compile (App "&substr" [] [str, start, Val (VInt 1)]) = hcat $
        [ compile str
        , text "["
        , compile start
        , text "]"
        ]
    compile (App "&postfix:++" [inv] []) = text "inc" <+> compile inv
    compile (App "&postfix:--" [inv] []) = text "dec" <+> compile inv
    compile (App "&infix:~" [exp, Val (VStr "")] []) = compile exp
    compile (App ('&':'i':'n':'f':'i':'x':':':op) [lhs, rhs] []) =
        compile lhs <+> text op <+> compile rhs
    compile (App "&say" invs args) = 
        compile $ App "&print" invs (args ++ [Val $ VStr "\n"])
    compile (App "&print" invs args) = vcat $
        map ((text "print" <+>) . compile) (invs ++ args)
    compile (Val (VStr x))  = showText $ encodeUTF8 (concatMap quoted x)
    compile (Val (VInt x))  = integer x
    compile (Val (VNum x))  = showText x
    compile (Val (VRat x))  = showText $ ratToNum x
    compile (Val VUndef)    = text "PerlUndef"
    compile Noop            = empty
    compile (Stmts stmts) = vcat $
        [ compile pos $+$ compile stmt $+$ text ""
        | (stmt, pos) <- stmts
        ]
    compile (Pad _ pad) = vcat $ concat
        [ [ text ".local" <+> text "pmc" <+> varText name
          , varText name <+> text "=" <+> text "new" <+> varInit name
          ]
          | (name, _) <- padToList pad
        ]
    compile (Syn "mval" [exp]) = compile exp
    compile (Syn "," things) = vcat $ map compile things
    compile (App "&not" [] []) =
        text "new" <+> compile (Val VUndef)
    compile (Cxt _ exp) = compile exp
    compile x = error $ "Cannot compile: " ++ (show x)

showText :: (Show a) => a -> Doc
showText = text . show

