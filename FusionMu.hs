{-# LANGUAGE RankNTypes, TypeOperators, GADTs, LambdaCase #-}

import System.IO

data a + b = Inl a | Inr b
type a ⊗ b = (a,b)

data One = TT

type Eff = IO ()
type Zero = IO ()
type N a = a -> Eff
type NN a = N (N a)

newtype Mu f = Mu {fromMu :: forall x. ((f (IO x)) -> IO x) -> IO x}

data SrcF a x = Nil | Cons a x
type Source a = Mu (SrcF a)
type Snk a = N (Source a)
type Src a = N (Snk a)

hFileSnk :: Handle -> Snk String
hFileSnk h (Mu fold) = fold $ \case
  Nil -> return ()
  Cons c r -> do
    hPutStrLn h c
    r

hFileSrc :: Handle -> Src String
hFileSrc h k = k $ Mu $ \phi ->
   let loop = do
         e <- hIsEOF h
         if e then do hClose h
                      phi Nil
              else do x <- hGetLine h
                      phi (Cons x loop)
   in loop
      -- this is an initial producer; driver of computation.

main = print "aw"
