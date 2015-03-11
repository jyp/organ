{-# LANGUAGE BangPatterns #-}
module DirectStyle where

import Organ
import System.IO
import Control.Concurrent.MVar
import Control.Concurrent (forkIO)

type Src a = N (Sink a)
type Snk a = N (Source a)

-- Source and Sink are true duals:
unshiftSnk :: N (Src a) -> Snk a
unshiftSnk k1 k2 = k1 $ \x -> fwd k2 x

unshiftSrc :: N (Snk a) -> Src a
unshiftSrc k1 k2 = k1 $ \x -> fwd x k2

-- Converting between Source and Src, Sink and Snk

sinkToSnk :: Sink a -> Snk a
sinkToSnk Full Nil = return ()
sinkToSnk Full (Cons a n) = n Full
sinkToSnk (Cont f) s = f s

sourceToSrc :: Source a -> Src a
sourceToSrc Nil Full = return ()
sourceToSrc (Cons a n) Full = n Full
sourceToSrc s (Cont f) = f s

snkToSink :: Snk a -> NN (Sink a)
snkToSink k kk = kk (Cont k)

srcToSource :: Src a -> NN (Source a)
srcToSource k kk = k (Cont kk)

-- Perhaps better name is "forward" (see ax in LL)
compose :: Src a -> Snk a -> Eff
compose = open

shiftSrc :: Src a -> N (Snk a)
shiftSrc = open

shiftSnk :: Snk a -> N (Src a)
shiftSnk = flip open

-- | Discard the source contents; return the length.
lengthSrc :: Src a -> N Int -> Eff
lengthSrc s k = s (Cont (lengthSnk k))

-- | Discard the source contents; return the length.
lengthSnk :: N Int -> Snk a
lengthSnk ni Nil = ni 0
lengthSnk ni (Cons _ s) = lengthSrc s (ni . (+1))

lenSrc :: Src a -> NN Int
lenSrc = lenAcc 0

lenAcc :: Int -> Src a -> NN Int
lenAcc !i s k = s (Cont (lenSnk i k))

lenSnk :: Int -> N Int -> Snk a
lenSnk i ni Nil = ni i
lenSnk i ni (Cons _ s) = lenAcc (i+1) s ni

data Status = Taken | Done

pipe :: NN (Src a, Snk a)
pipe k = do
  r <- newEmptyMVar
  p <- newMVar Taken
  let src Full = putMVar p Done
      src (Cont s) = do putMVar p Taken
                        ma <- takeMVar r
                        case ma of
                          Nothing -> s Nil
                          Just a  -> s (Cons a src)
      snk Nil = takeMVar p >> putMVar r Nothing
      snk (Cons a s) = takeMVar p >>= \st ->
        case st of
          Done  -> {- putMVar r Nothing  >> -} s Full
          Taken -> putMVar r (Just a) >> s (Cont snk)
  k (src,snk)

plug :: Snk a
plug = close

empty :: Src a
empty = done

unzipSnk :: Snk (a,b) -> Source a -> Source b -> Eff
unzipSnk s Nil (Cons _ s') = s' Full >> s Nil
unzipSnk s (Cons _ s') Nil = s' Full >> s Nil
unzipSnk s (Cons a s1) (Cons b s2) = s (Cons (a,b) (zipSrc s1 s2))

zipSrc :: Src a -> Src b -> Src (a,b)
zipSrc s1 s2 Full = s1 Full >> s2 Full
zipSrc s1 s2 (Cont s) = s1 (Cont (\source1 -> s2 (Cont (\source2 -> unzipSnk s source1 source2))))

mapSrc :: (a -> b) -> Src a -> Src b
mapSrc f src Full = src Full
mapSrc f src (Cont s) = src (Cont (mapSnk f s))

mapSnk :: (b -> a) -> Snk a -> Snk b
mapSnk f snk Nil = snk Nil
mapSnk f snk (Cons a s) = snk (Cons (f a) (mapSrc f s))

foldSrc :: (a -> b -> b) -> b -> Src a -> NN b
foldSrc f z s nb = s (Cont (foldSnk f z nb))

foldSnk :: (a -> b -> b) -> b -> N b -> Snk a
foldSnk f z nb Nil = nb z
foldSnk f z nb (Cons a s) = foldSrc f z s (nb . f a)

foldSrc' :: (b -> a -> b) -> b -> Src a -> NN b
foldSrc' f !z s nb = s (Cont (foldSnk' f z nb))

foldSnk' :: (b -> a -> b) -> b -> N b -> Snk a
foldSnk' f z nb Nil = nb z
foldSnk' f z nb (Cons a s) = foldSrc' f (f z a) s nb

takeSrc :: Int -> Src a -> Src a
takeSrc 0 s Full = s Full
takeSrc 0 s (Cont s') = s Full >> s' Nil -- Subtle case
takeSrc i s Full = s Full
takeSrc i s (Cont s') = s (Cont (takeSnk i s'))

takeSnk :: Int -> Snk a -> Snk a
takeSnk 0 s (Cons _ _) = s Nil
takeSnk _ s Nil = s Nil
takeSnk i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))

dropSrc :: Int -> Src a -> Src a
dropSrc _ s Full = s Full
dropSrc 0 s (Cont s') = s (Cont s')
dropSrc i s (Cont s') = s (Cont (dropSnk i s'))

dropSnk :: Int -> Snk a -> Snk a
dropSnk 0 s (Cons a s') = s (Cons a s')
dropSnk 0 s Nil = s Nil
dropSnk i s Nil = s Nil
dropSnk i s (Cons a s') = s' (Cont (dropSnk (i-1) s))


hReadSrc :: Handle -> Src Char
hReadSrc = readF

readSrc :: FilePath -> Src Char
readSrc file sink = do
  h <- openFile file ReadMode
  hReadSrc h sink

enumFromToSrc :: Int -> Int -> Src Int
enumFromToSrc b e Full = return ()
enumFromToSrc b e (Cont s)
  | b > e     = s Nil
  | otherwise = s (Cons b (enumFromToSrc (b+1) e))

enumFromSrc :: Int -> Src Int
enumFromSrc i Full = return ()
enumFromSrc i (Cont s) = s (Cons i (enumFromSrc (i+1)))

replicateSrc :: Int -> a -> Src a
replicateSrc _ _ Full = return ()
replicateSrc 0 _ (Cont s) = s Nil
replicateSrc i a (Cont s) = s (Cons a (replicateSrc (i-1) a))

dnsSink :: Sink (NN a) -> NN (Sink a)
dnsSink Full k = k Full
dnsSink (Cont s) k = help k s

help :: N (Sink a) -> N (Source (NN a)) -> Eff
help k1 k2 = open k1 $ \x -> smap (shift . shift) x k2 -- overkill

srcToSnk :: Src a -> Snk (N a)
srcToSnk k1 s2 = dnsSink (sourceToSink s2) k1

snkToSrc :: Snk a -> Src (N a)
snkToSrc s s' = sinkToSource' s' s

cons :: a -> Src a -> Src a
cons a s s' = yield a s' s

match :: Eff -> (a -> Snk a) -> Snk a
match nil' cons' k = await k nil' cons'

tail :: Src a -> Src a
tail s Full = s Full
tail s (Cont s') = s (Cont (\source -> case source of
  Nil -> s' Nil
  (Cons a s'') -> compose s'' s'))

-- A slightly crazy variant
tail' :: Src a -> Src a
tail' s = unshiftSrc $ \k -> -- instead of producing a source, consume a sink (k)
          shiftSrc s $ -- instead of consuming a source, produce a sink
          match
            (return ())
            (\_ -> k)

writeFileSnk :: FilePath -> Snk Char
writeFileSnk file s = do
  h <- openFile file WriteMode
  hWriteFileSnk h s

hWriteFileSnk :: Handle -> Snk Char
hWriteFileSnk h Nil = hClose h
hWriteFileSnk h (Cons c s) = do
  hPutChar h c
  s (Cont (hWriteFileSnk h))

deadlock :: Eff
deadlock = pipe (\(src,snk) -> compose src snk)

displaySnk :: Show a => Snk a
displaySnk = display

linesSrc :: Src Char -> Src String
linesSrc s Full = s Full
linesSrc s (Cont s') = s (Cont $ unlinesSnk s')

unlinesSnk :: Snk String -> Snk Char
unlinesSnk = unlinesSnk' []

unlinesSnk' :: String -> Snk String -> Snk Char
unlinesSnk' acc s Nil = s (Cons acc empty)
unlinesSnk' acc s (Cons '\n' s') = s (Cons (reverse acc) (linesSrc s'))
unlinesSnk' acc s (Cons c s') = s' (Cont $ unlinesSnk' (c:acc) s)

splitSrc :: Src a -> NN (Src a, Src a)
splitSrc s k = do
  v1 <- newEmptyMVar
  v2 <- newEmptyMVar
  w1 <- newEmptyMVar
  w2 <- newEmptyMVar
  let src v w Full = do putMVar v True
      src v w (Cont s) = do putMVar v False
                            ma <- takeMVar w
                            case ma of
                              Nothing -> s Nil
                              Just a -> s (Cons a $ src v w)
      ctrl s = do s1 <- takeMVar v1
                  s2 <- takeMVar v2
                  foo s s1 s2
      foo s True  True  = s Full
      foo s False False = s (Cont bar)
      -- Stop receiving as soon as one of the sources stop receiving
      foo s True  False = s Full
      foo s False True  = s Full
      bar Nil = putMVar w1 Nothing >> putMVar w2 Nothing
      bar (Cons a s) = putMVar w1 (Just a) >> putMVar w2 (Just a)
        >> ctrl s
  forkIO (ctrl s)
  k (src v1 w1,src v2 w2)

untilSnk :: (a -> Bool) -> Snk a
untilSnk p Nil = return ()
untilSnk p (Cons a s)
  | p a  = s Full
  | True = s (Cont (untilSnk p))

untilSnk' :: (a -> Bool) -> N a -> Snk a
untilSnk' p na Nil = return ()
untilSnk' p na (Cons a s)
  | p a  = s Full >> na a
  | True = s (Cont (untilSnk' p na))

thenSnk :: Snk a -> Snk a -> Snk a
thenSnk s1 s2 Nil = s1 Nil >> s2 Nil
thenSnk s1 s2 (Cons a s) = s1 (Cons a (thenFoo s2 s))

thenFoo :: Snk a -> Src a -> Src a
thenFoo s2 s Full = compose s s2
thenFoo s2 s (Cont s') = s (Cont (thenSnk s' s2))

scanrSrc :: (a -> b -> b) -> b -> Src a -> Src b
scanrSrc f a src Full = src Full
scanrSrc f a src (Cont s) = src (Cont (scanrSnk f a s))

scanrSnk :: (a -> b -> b) -> b -> Snk b -> Snk a
scanrSnk f b src Nil = src (Cons b empty)
scanrSnk f b src (Cons a s) = src (Cons b (scanrSrc f (f a b) s))

filterSrc :: (a -> Bool) -> Src a -> Src a
filterSrc p src Full = src Full
filterSrc p src (Cont s) = src (Cont (filterSnk p s))

filterSnk :: (a -> Bool) -> Snk a -> Snk a
filterSnk p snk Nil = snk Nil
filterSnk p snk (Cons a s)
  | p a       = snk (Cons a (filterSrc p s))
  | otherwise = s (Cont (filterSnk p snk))

ap :: Src (a -> b) -> Src a -> Src b
ap s1 s2 Full = s1 Full >> s2 Full
ap s1 s2 (Cont s) = s1 (Cont (\l1 -> s2 (Cont (\l2 -> apSnk s l1 l2))))

apSnk :: Snk b -> Source (a -> b) -> Source a -> Eff
apSnk s (Cons f s1) (Cons a s2) = s (Cons (f a) (ap s1 s2))
apSnk s _ _ = s Nil

concatSrc :: Src (Src a) -> Src a
concatSrc ss Full = ss Full
concatSrc ss (Cont s) = ss (Cont (concatSnk s))

concatSnk :: Snk a -> Snk (Src a)
concatSnk snk Nil = snk Nil
concatSnk snk (Cons src s) = src (Cont (concatAux snk s))

concatAux :: Snk a -> Src (Src a) -> Snk a
concatAux snk ssrc Nil = snk Nil >> ssrc Full
concatAux snk ssrc (Cons a s) = snk (Cons a (append s (concatSrc ssrc)))

append :: Src a -> Src a -> Src a
append s1 s2 Full = s1 Full >> s2 Full
append s1 s2 (Cont s) = s1 (Cont (appendSnk s s2))

appendSnk :: Snk a -> Src a -> Snk a
appendSnk snk src Nil = compose src snk
appendSnk snk src (Cons a s) = snk (Cons a (append s src))

interleave :: Src a -> Src a -> Src a
interleave s1 s2 Full = s1 Full >> s2 Full
interleave s1 s2 (Cont s) = s1 (Cont (interleaveSnk s s2))

interleaveSnk :: Snk a -> Src a -> Snk a
interleaveSnk snk src Nil = compose src snk
interleaveSnk snk src (Cons a s) = snk (Cons a (interleave s src))

unit :: a -> Src a
unit a = cons a empty

bindSrc :: Src a -> (a -> Src b) -> Src b
bindSrc s f = concatSrc (mapSrc f s)
{- Src is a type alias so we cannot make a Monad instance.
instance Monad Src where
  return = unit
  (>>=) = bindSrc
-}
