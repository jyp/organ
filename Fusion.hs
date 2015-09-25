{-# LANGUAGE RankNTypes, TypeOperators, GADTs, LambdaCase #-}

import System.IO

data a + b = Inl a | Inr b
type a ⊗ b = (a,b)

type Eff = IO ()
type Zero = IO ()
type N a = a -> Eff
type NN a = N (N a)

data One = TT
newtype Mu f = Mu {fromMu :: forall x. (NN (f x) -> x) -> x}
data Nu f where
  Nu :: x -> (x -> NN (f x)) -> Nu f -- Normally the NN should be in
                                     -- the functor definition, but
                                     -- Haskell makes that quite
                                     -- annoying to implement. So I
                                     -- just stick it in here.
data SrcF a x = Nil | Cons a x
mapF :: (a -> b) -> SrcF a x -> SrcF b x
mapF f Nil = Nil
mapF f (Cons a b) = Cons (f a) b
type Source a = Nu (SrcF a)
type Sink a = Snk a -- It may work to have Mu here. Test.
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

empty :: Src a
empty k = k $ Nu () (\_ -> \k -> k Nil)

fwd :: Src a -> Snk a -> Eff
fwd src k = src k

flipSnk :: (Snk a -> Snk b) -> Src b -> Src a
flipSnk f s = shiftSrc s . onSink f

flipSrc :: (Src a -> Src b) -> Snk b -> Snk a
flipSrc f t = shiftSnk t . onSource f


mapSrc  :: (a -> b) -> Src  a -> Src  b


mapSrc f = flipSnk (mapSnk f)


mapSnk  :: (b -> a) -> Snk  a -> Snk b
mapSnk f t (Nu s0 psi) = t (Nu s0  (\s -> mapNN (mapF f) (psi s)))


nnIntro :: Src a -> Src (NN a)
nnIntro = mapSrc shift

nnElim' :: Snk (NN a) -> Snk a
nnElim' = mapSnk shift

hFileSnk :: Handle -> Snk String
hFileSnk h (Nu s0 psi) = psi s0 $ \case 
  Nil -> hClose h
  Cons c as -> do
    hPutStrLn h c
    hFileSnk h (Nu as psi)

hFileSrc :: Handle -> Src String
hFileSrc h c = c $ Nu () $ \ () k -> do
  e <- hIsEOF h
  if e then do hClose h
               k Nil
       else do x <- hGetLine h
               k (Cons x ())


main = do
  i <- openFile "Fusion.hs" ReadMode
  fwd (hFileSrc i) (hFileSnk stdout)
  print "arostn"
