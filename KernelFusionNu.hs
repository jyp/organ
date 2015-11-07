{-# LANGUAGE RankNTypes, TypeOperators, GADTs, LambdaCase, TypeSynonymInstances, FlexibleInstances #-}


module KernelFusionNu where

-- There are four choices of representation:

-- Nu for sources. In this case the sources respond to data

import System.IO

type Eff = IO ()
type N a = a -> Eff
type NN a = N (N a)

-- This is the underlying functor; but with a delay monad slapped on
-- it, so we can implement filter and friends without an (explicit)
-- loop.
data Step a s = Nil
              | Delay s
              | Cons a s
data Choke s = Full | More s

data Source a = forall s. Source s (s -> N (Choke (N (Step a s))))

mapF :: (a -> b) -> Step a x -> Step b x
mapF f Nil = Nil
mapF f (Delay x) = Delay x
mapF f (Cons a b) = Cons (f a) b

type Sink a = Snk a
type Snk a = N (Source a)
type Src a = NN (Source a)


shift :: a -> NN a
shift x k = k x

mapNN :: (a -> b) -> NN a -> NN b
mapNN f k1 k2 = k1 $ \ a -> k2 (f a)

unshift :: N (NN a) -> N a
unshift k x = k (shift x)

forward :: Source a -> Sink a -> Eff
forward s s' = s' s

onSource   :: (Src  a -> t) -> Source   a -> t
onSink     :: (Snk  a -> t) -> Sink   a -> t

onSource  f   s = f   (\t -> forward s t)
onSink    f   t = f   (\s -> forward s t)

unshiftSnk :: N (Src a) -> Snk a
unshiftSrc :: N (Snk a) -> Src a
shiftSnk :: Snk a -> N (Src a)
shiftSrc :: Src a -> N (Snk a)

unshiftSnk = onSource
unshiftSrc = onSink
shiftSnk k kk = kk ( k)
shiftSrc k kk = k ( kk)
instance Monoid Eff where
empty :: Src a
-- empty k = k $ Source () (\_ -> \k -> k Nil)
empty k = k $ Source () $ \_ -> \case
  More k -> k Nil
  Full -> mempty

fwd :: Src a -> Snk a -> Eff
fwd src k = src k

flipSnk :: (Snk a -> Snk b) -> Src b -> Src a
flipSnk f s = shiftSrc s . onSink f

flipSrc :: (Src a -> Src b) -> Snk b -> Snk a
flipSrc f t = shiftSnk t . onSource f


mapSrc  :: (a -> b) -> Src  a -> Src  b


mapSrc f = flipSnk (mapSnk f)


mapSnk  :: (b -> a) -> Snk  a -> Snk b
-- mapSnk f t (Source s0 psi) = t (Source s0  (\s -> mapNN (mapF f) (psi s)))
mapSnk f t (Source s0 psi) = t $ Source s0 $ \s -> \case
  Full -> psi s Full
  More u -> psi s $ More $ u . mapF f

nnIntro :: Src a -> Src (NN a)
nnIntro = mapSrc shift

nnElim' :: Snk (NN a) -> Snk a
nnElim' = mapSnk shift



nnElim :: Src (NN a) -> Src a
nnElim = flipSnk nnIntro'

nnIntro' :: Snk a -> Snk (NN a)
nnIntro' k (Source s0 psi) = k $ Source s0 $ \s -> \case
  Full -> psi s Full
  More k' -> psi s $ More $ \case
    Nil -> k' Nil
    Delay xs -> k' (Delay xs)
    Cons x xs -> x $ \x' -> k' (Cons x' xs)


takeSnk  :: Int -> Snk  a -> Snk  a
takeSnk n t (Source s0 psi) = t $ Source (n,s0) $ 
  \(m,s) -> \case
    Full -> psi s Full
    More k -> case m of
      0 -> k Nil
      _ -> psi s $ More $ \case
        Nil -> k Nil
        Delay xs -> k $ Delay (m,xs)
        Cons x xs -> k $ Cons x (m-1,xs)



hFileSnk :: Handle -> Snk String
hFileSnk h (Source s0 psi) = psi s0 $ More $ \case 
  Nil -> hClose h
  Cons c as -> do
    hPutStrLn h c
    hFileSnk h (Source as psi)
      -- this is a final consumer (driver of
      -- computation): it is ok to have a loop
      -- here.

hFileSrc :: Handle -> Src String 
hFileSrc h c = c $ Source () $ \()-> \case
  Full -> hClose h
  More k -> do
    e <- hIsEOF h
    if e then do hClose h
                 k Nil
         else do x <- hGetLine h
                 k (Cons x ())


-- "Loops"
type Schedule a = Source a -> Source (N a) -> Eff

sequentially :: Schedule a
sequentially (Source s1 psi1) (Source s2 psi2) =
  psi1 s1 $ More $ \i1 ->
  psi2 s2 $ More $ \i2 ->
  case (i1,i2) of
   (Cons x1 xs1, Cons x2 xs2) -> do
     x2 x1
     sequentially (Source xs1 psi1) (Source xs2 psi2)

main = do
  i <- openFile "Fusion.hs" ReadMode
  fwd (hFileSrc i) (hFileSnk stdout)
  print "arostn"
