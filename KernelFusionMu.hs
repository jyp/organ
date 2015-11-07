{-# LANGUAGE RankNTypes, TypeOperators, GADTs, LambdaCase,TypeSynonymInstances, FlexibleInstances #-}

import System.IO
import Data.Monoid
data a + b = Inl a | Inr b
type a ⊗ b = (a,b)

data One = TT

type Eff = IO ()
type Zero = IO ()
type N a = a -> Eff
type NN a = N (N a)

-- newtype Mu f = Mu {fromMu :: forall x. ((f (IO x)) -> IO x) -> IO x}

data Step a s = Nil
              | Cons a s
data Choke s = Full | More s

newtype CoSource a = Source {fromSource :: forall x. ((Step a Eff) -> Eff) -> Eff}
type CoSrc a = CoSource a
type CoSnk a = N (CoSource a)
type Snk a = CoSrc (N a)
type Src a = CoSnk (N a)

instance Monoid Eff where
   mempty = return ()
   mappend = (>>)

hFileSnk :: Handle -> Snk String
hFileSnk h = Source $ \feed ->
  let loop = do
        feed (Cons (hPutStrLn h) loop)
  in loop

hFileSrc :: Handle -> Src String
hFileSrc h (Source f) = f $ \case
  Nil -> hClose h
  Cons x xs -> do
    x' <- hGetLine h
    x x'
    xs


-- "Loops"
type Schedule a = Src a -> Src (N a) -> Eff

sequentially :: Schedule a
sequentially s1 s2 = do
  s1 $ Source $ \k -> k $ Cons _ _
  s2 $ Source $ \k -> k $ _

main = print "aw"
