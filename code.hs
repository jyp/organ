{-# LANGUAGE ScopedTypeVariables, TypeOperators, RankNTypes, LiberalTypeSynonyms, BangPatterns, TypeSynonymInstances, FlexibleInstances, FlexibleContexts, GADTs, LambdaCase  #-}
module Organ where
import System.IO
import Control.Exception
import Control.Concurrent (forkIO, readChan, writeChan, Chan, newChan, QSem, newQSem, waitQSem, signalQSem)
import Control.Applicative hiding (empty)
import Data.IORef
import Prelude hiding (tail, drop)
import Control.Monad (ap)
import Data.Monoid
type a ⊸ b = a -> b
infixr ⊸
data Source  a  where
  Nil :: Source a
  Cons :: a -> N (Sink a) -> Source a
data Sink    a  where
  Full :: Sink a
  Cont :: N (Source a) -> Sink a
type N a = a ⊸ Eff
type NN a = N (N a)
shift :: a ⊸ NN a
shift x k = k x
unshift :: N (NN a) ⊸ N a
unshift k x = k (shift x)
type Eff = IO ()
type a & b = N (Either (N a) (N b))
type Src   a = N  (Sink a)
type Snk'  a = N  (Source a)
type Snk   a = N (Src a)

await :: Source a ⊸ (Eff & (a -> Source a ⊸ Eff)) ⊸ Eff
await Nil r = r $ Left $ \eof -> eof
await (Cons x xs) r = r $ Right $ \c -> xs (Cont (c x))

yield :: a -> Sink a ⊸ (Sink a ⊸ Eff) ⊸ Eff
yield _ Full k = k Full
yield x (Cont c) k = c (Cons x k)

fwd' :: forall t a. (Sink a -> t) -> N (Source a) -> t
fwd' s t = s (Cont t)

fwd :: Src a -> Snk a -> Eff
fwd = shift

flipSnk' :: (Snk' a ⊸ Snk' b) -> Src b ⊸ Src a
flipSnk' _ s Full = s Full
flipSnk' f s (Cont k) = s (Cont (f k))

flipSrc :: (Src a ⊸ Src b) -> Snk b ⊸ Snk a
flipSrc f snk src = snk (f src)

mapSnk'  :: (b ⊸ a) -> Snk'  a ⊸ Snk'  b
mapSnk' _ snk Nil = snk Nil
mapSnk' f snk (Cons a s) = snk (Cons (f a) (mapSrc f s))

mapSrc  :: (a ⊸ b) -> Src  a ⊸ Src  b
mapSrc f = flipSnk' (mapSnk' f)

nnIntro' :: Snk' a -> Snk' (NN a)
nnIntro' k Nil = k Nil
nnIntro' k (Cons x xs) = x $ \x' -> k (Cons x' $ nnElim xs)

nnIntro :: Snk' a ⊸ Snk' (NN a)
nnIntro = flip nnElimSource

nnElimSource :: Source (NN a) ⊸ N (Source a) ⊸ Eff
nnElimSource Nil s = s Nil
nnElimSource (Cons x xs) s = x $ \x' -> s (Cons x' (nnElim xs))

nnElim :: Src (NN a) ⊸ Src a
nnElim = flipSnk' nnIntro'


empty :: Src a
empty Full = mempty
empty (Cont k) = k Nil

cons :: a -> Src a ⊸ Src a
cons a s s' = yield a s' s

plug :: Snk a
plug = shift Full

takeSrc  :: Int -> Src  a -> Src  a
takeSnk'  :: Int -> Snk'  a -> Snk'  a

takeSrc 0 s snk = s Full <> empty snk
takeSrc n s snk = flipSnk' (takeSnk' n) s snk

takeSnk' _ s Nil = s Nil
takeSnk' i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))

takeSnk :: forall a. Int -> Snk a ⊸ Snk a
takeSnk n = flipSrc (takeSrc n)

instance Monoid (Src a) where
  mappend = appendSrc
  mempty = empty

appendSrc :: Src a -> Src a -> Src a
appendSrc s1 s2 Full = s1 Full <> s2 Full
appendSrc s1 s2 (Cont s)
  = s1 (Cont (forwardThenSnk' s s2))

forwardThenSnk' :: Snk' a -> Src a -> Snk' a
forwardThenSnk' snk src Nil = fwd' src snk
forwardThenSnk' snk src (Cons a s)
  = snk (Cons a (appendSrc s src))

appendSnk' :: Snk' a -> Snk' a -> Snk' a
appendSnk' s1 s2 Nil = s1 Nil <> s2 Nil
appendSnk' s1 s2 (Cons a s)
  = s1 (Cons a (forwardThenSrc s2 s))

forwardThenSrc :: Snk' a -> Src a -> Src a
forwardThenSrc s2 = flipSnk' (appendSnk' s2)

appendSnk ::  Snk a -> Snk a -> Snk a
appendSnk t1 t2 s = t1 $ \case
  Full -> t2 empty <> s Full
  Cont k -> flipSrc (forwardThenSrc k) t2 s

instance Monoid (Snk a) where
  mappend = appendSnk
  mempty = plug

(-?) :: Snk' a ⊸ Src a ⊸ Snk' a
t -? s = forwardThenSnk' t s
(-!) :: Snk' a ⊸ Src a ⊸ Src a
t -! s = forwardThenSrc t s
infixr -!
infixl -?
prop_diff3 t1 t2 s = (t1 <> t2) -? s == t1 -? (t2 -! s)
prop_diff4 t s1 s2 = t -! (s1 <> s2) == (t -? s1) -! s2


class Drop a where drop :: a ⊸ b ⊸ b

zipSrc :: (Drop a, Drop b) => Src a ⊸ Src b ⊸ Src (a,b)
forkSnk' :: (Drop a, Drop b) => Snk' (a,b) ⊸ Src a ⊸ Snk' b
forkSrc :: Src (a,b) ⊸ Snk' a ⊸ Src b
zipSnk' :: Snk' a ⊸ Snk' b ⊸ Snk' (a,b)
scanSrc :: (b -> a -> (b,c)) -> b -> Src a ⊸ Src c
scanSnk' :: (b -> a -> (b,c)) -> b -> Snk' c ⊸ Snk' a
foldSrc' :: (b -> a -> b) -> b -> Src a ⊸ NN b
foldSnk' :: (b -> a -> b) -> b -> N b ⊸ Snk' a
dropSrc :: Drop a => Int -> Src a ⊸ Src a
dropSnk' :: Drop a => Int -> Snk' a ⊸ Snk' a
fromList :: [a] ⊸ Src a
toList :: Src a ⊸ NN [a]
linesSrc :: Src Char ⊸ Src String
unlinesSnk' :: Snk' String ⊸ Snk' Char
untilSnk' :: Drop a => (a -> Bool) ⊸ Snk' a
interleave :: Src a ⊸ Src a ⊸ Src a
interleaveSnk' :: Snk' a ⊸ Src a ⊸ Snk' a
filterSrc :: (a ⊸ Maybe b) ⊸ Src a ⊸ Src b
filterSnk' :: (a ⊸ Maybe b) ⊸ Snk' b ⊸ Snk' a
unchunk :: Src [a] ⊸ Src a
chunkSnk' :: Snk' a ⊸ Snk' [a]

zipSnk :: Snk a ⊸ Snk b ⊸ Snk (a,b)
zipSnk a b c = a $ \a' -> b $ \b' -> zipSnk (shift a') (shift b') c
scanSnk :: (b -> a -> (b,c)) -> b -> Snk c ⊸ Snk a
scanSnk f z = flipSrc (scanSrc f z)
chunkSnk :: Snk a ⊸ Snk [a]
chunkSnk = flipSrc unchunk
filterSnk :: (a ⊸ Maybe b) ⊸ Snk b ⊸ Snk a
filterSnk p = flipSrc (filterSrc p)
unlinesSnk :: Snk String ⊸ Snk Char
unlinesSnk = flipSrc linesSrc 
interleaveSnk :: Snk a ⊸ Src a ⊸ Snk a
interleaveSnk a b = flipSrc (interleave b) a

data P s res  =  Sym (Maybe s -> P s res)
              |  Fail
              |  Result res
newtype Parser s a = P (forall res. (a -> P s res) -> P s res)
instance Monad (Parser s) where
  return x  = P $ \fut -> fut x
  P f >>= k = P (\fut -> f (\a -> let P g = k a in g fut))
instance Applicative (Parser s) where
  pure = return
  (<*>) = ap
instance Functor (Parser s) where
  fmap = (<$>)
weave :: P s a -> P s a -> P s a
weave Fail x = x
weave x Fail = x
weave (Result res) _ = Result res
weave _ (Result res) = Result res
weave (Sym k1) (Sym k2)
    = Sym (\s -> weave (k1 s) (k2 s))
(<|>) :: Parser s a -> Parser s a -> Parser s a
P p <|> P q = P (\fut -> weave (p fut) (q fut))

parse :: forall s a. Parser s a -> Src s ⊸ Src a
parse _ src Full = src Full
parse q@(P p0) src (Cont k) = scan (p0 $ \x -> Result x) k src
 where
  scan :: P s a -> Snk' a ⊸ Src s ⊸ Eff
  scan (Result res  )  ret        xs     = ret (Cons res (parse q xs))
  scan Fail            ret        xs     = ret Nil <> xs Full
  scan (Sym f)         mres       xs     = xs $ Cont $ \case
    Nil        -> scan (f Nothing) mres empty
    Cons x cs  -> scan (f $ Just x) mres cs

hFileSnk' :: Handle -> Snk' String
hFileSnk' h Nil = hClose h
hFileSnk' h (Cons c s) = do
  hPutStrLn h c
  hFileSnk h s

hFileSnk :: Handle -> Snk String
hFileSnk h = shift (Cont (hFileSnk' h))

fileSnk' :: FilePath -> Snk' String
fileSnk' file s = do
  h <- openFile file WriteMode
  hFileSnk' h s

fileSnk :: FilePath -> Snk String
fileSnk file s = do
  h <- openFile file WriteMode
  hFileSnk h s

stdoutSink :: Sink String
stdoutSink = Cont (hFileSnk' stdout)

hFileSrc :: Handle -> Src String
hFileSrc h Full = hClose h
hFileSrc h (Cont c) = do
  e <- hIsEOF h
  if e   then   do  hClose h
                    c Nil
         else   do  x <- hGetLine h
                    c (Cons x $ hFileSrc h)

fileSrc :: FilePath -> Src String
fileSrc file sink = do
  h <- openFile file ReadMode
  hFileSrc h sink
copyFile :: FilePath -> FilePath -> Eff
copyFile source target = fwd' (fileSrc source)
                             (fileSnk' target)
read3Lines :: Eff
read3Lines = fwd' (hFileSrc stdin)
                 (takeSnk' 3 $ fileSnk' "text.txt")

hFileSrcSafe :: Handle -> Src String
hFileSrcSafe h Full = hClose h
hFileSrcSafe h (Cont c) = do
  e <- hIsEOF h
  if e then do
         hClose h
         c Nil
       else do
         mx <- catch  (Just <$> hGetLine h)
                      (\(_ :: IOException) -> return Nothing)
         case mx of
           Nothing -> c Nil
           Just x -> c (Cons x $ hFileSrcSafe h)

dmux' :: Src (Either a b) -> Sink a -> Sink b -> Eff
dmux' sab Full tb = sab Full <> empty tb
dmux' sab ta Full = sab Full <> empty ta
dmux' sab (Cont ta) (Cont tb) = sab $ Cont $ \s -> dmux ta tb s

dmux :: Snk' a -> Snk' b -> Snk' (Either a b)
dmux ta tb Nil = ta Nil <> tb Nil
dmux ta tb (Cons ab c) = case ab of
  Left a -> ta (Cons a $ \ta' -> dmux' c ta' (Cont tb))
  Right b -> tb (Cons b $ \tb' -> dmux' c (Cont ta) tb')

mux :: Source a ⊸ Source b ⊸ Source (a & b)
mux (Cons a as) (Cons b bs) = Cons
                         (\ab -> case ab of
                                  Left   ka -> as $ Cont $ \(Cons a resta) -> ka a
                                  Right  kb -> bs $ Cont $ \(Cons b restb) -> kb b)
                         (error "oops")

type CoSrc a = N (Src (N a))
type CoSnk a = Src (N a)

dmux'' :: Snk a -> Snk b -> Snk (Either a b)
dmux'' sa sb tab = sa $ \sa' -> sb $ \sb' -> dmux' tab sa' sb'

mux' :: CoSrc a -> CoSrc b -> CoSrc (a & b)
mux' sa sb tab = dmux'' sa sb (nnElim tab)

-- mux'' :: CoSrc' a -> CoSrc' b -> CoSrc' (a & b)
-- mux'' sa sb tab = (nnElimSource tab) $ \tab' -> dmux tab' sa sb

mapCoSnk :: (b ⊸ a) -> CoSnk a ⊸ CoSnk b
mapCoSnk f = mapSrc (\b' -> \a -> b' (f a))

mapCoSrc  :: (a ⊸ b) -> CoSrc a ⊸ CoSrc b
mapCoSrc f snk src = snk (mapCoSnk f src)

coToList :: Snk' (N a) -> NN [a]
coToList k1 k2 = k1 $ Cons (\a -> k2 [a]) (error "rest")
coToList k1 k2 = k2 $ (error "a?") : (error "rest")

coFileSrc :: Handle -> CoSrc String
coFileSrc h snk = do
  e <- hIsEOF h
  snk $ if not e
    then Full
    else Cont $ \case
       Nil -> hClose h
       Cons x xs -> do
          x' <- hGetLine h
          x x'              -- (1)
          (coFileSrc h) xs  -- (2)

coFileSink :: Handle -> CoSnk String
coFileSink h Full = hClose h
coFileSink h (Cont c) = c (Cons  (hPutStrLn h)
                                 (coFileSink h))

srcToCoSrc :: Schedule a -> Src a ⊸ CoSrc a
coSnkToSnk :: Schedule a -> CoSnk a ⊸ Snk a

srcToCoSrc strat s0 s = fwd' s0 (flip strat s)
coSnkToSnk strat s0 s = fwd' s (flip strat s0)
type Schedule a = Source a ⊸ Src (N a) ⊸ Eff

sequentially :: Drop a => Schedule a
sequentially Nil s = s Full
sequentially (Cons x xs) s = s $ Cont $ \s' -> case s' of
  Cons x' xs' -> do
    x' x
    xs $ Cont $ \t -> sequentially t xs'
  Nil -> drop x (xs Full)

concurrently :: Drop a => Schedule a
concurrently Nil s = s Full
concurrently (Cons x xs) s = s $ Cont $ \s' -> case s' of
  Cons x' xs' -> do
    forkIO (x' x)
    xs $ Cont $ \t -> concurrently t xs'
  Nil -> drop x (xs Full)


fileBuffer :: String -> CoSrc String ⊸ Src String
fileBuffer tmpFile f g = do
  h' <- openFile  tmpFile WriteMode
  forkIO $ f (coFileSink h')
  h <- openFile tmpFile ReadMode
  hFileSrc h g

chanCoSnk :: Chan a -> CoSnk a
chanCoSnk _ Full = return ()
chanCoSnk h (Cont c) = c (Cons  (writeChan h)
                                (chanCoSnk h))
chanSrc :: Chan a -> Src a
chanSrc _ Full = return ()
chanSrc h (Cont c) = do  x <- readChan h
                         c (Cons x $ chanSrc h)
chanBuffer :: CoSrc a ⊸ Src a
chanBuffer f g = do
  c <- newChan
  forkIO $ f (chanCoSnk c)
  chanSrc c g

chanCoSnk' :: Chan a -> QSem -> CoSnk a
chanCoSnk' _ _ Full = return ()
chanCoSnk' h s (Cont c) = c (Cons  write
                                   (chanCoSnk' h s))
 where write x = do  waitQSem s
                     writeChan h x
chanSrc' :: Chan a -> QSem -> Src a
chanSrc' _ _ Full = return ()
chanSrc' h s (Cont c) = do  x <- readChan h
                            signalQSem s
                            c (Cons x $ chanSrc' h s)
boundedChanBuffer :: Int -> CoSrc a ⊸ Src a
boundedChanBuffer n f g = do
  c <- newChan
  s <- newQSem n
  forkIO $ f (chanCoSnk' c s)
  chanSrc' c s g
varCoSnk :: IORef a -> CoSnk a
varCoSnk _ Full      = return ()
varCoSnk h (Cont c)  = c (Cons  (writeIORef h)
                                (varCoSnk h))
varSrc :: IORef a -> Src a
varSrc _ Full = return ()
varSrc h (Cont c) = do  x <- readIORef h
                        c (Cons x $ varSrc h)
varBuffer :: a -> CoSrc a ⊸ Src a
varBuffer a f g = do
  c <- newIORef a
  forkIO $ f (varCoSnk c)
  varSrc c g

flipBuffer :: (forall a. CoSrc a ⊸ Src a) -> Snk' b ⊸ CoSnk b
flipBuffer f s = f (flip fwd' (nnIntro s))

type Client a = (CoSrc a, Snk' a)
bufferedDmux :: CoSrc a ⊸ CoSrc a ⊸ Src a
bufferedDmux s1 s2 t = do
  c <- newChan
  forkIO $ s1 (chanCoSnk c)
  forkIO $ s2 (chanCoSnk c)
  chanSrc c t

tee :: (a ⊸ (b, c)) -> Src a -> Sink b -> Src c
tee deal s1 t1 Full = s1 Full <> empty t1
tee deal s1 Full t2 = s1 Full <> empty t2
tee deal s1 (Cont t1) (Cont t2) = s1 $ Cont $ collapseSnk' deal t1 t2

collapseSnk' :: (a ⊸ (b,c)) -> Snk' b ⊸ Snk' c ⊸ Snk' a
collapseSnk' _    t1 t2 Nil = t1 Nil <> t2 Nil
collapseSnk' dup  t1 t2 (Cons x xs)
  =  t1  (Cons y $ \c1 ->
     t2  (Cons z $ tee dup xs c1))
  where (y,z) = dup x


server :: (a ⊸ (a,a)) ⊸ Client a ⊸ Client a ⊸ Eff
server dup (i1,o1) (i2,o2) = (bufferedDmux i1 i2)
                             (Cont (collapseSnk' dup o1 o2))
{-
data I s m a = Done a | GetC (Maybe s -> m (I s m a))
type Enumerator el m a = I el m a -> m (I el m a)
type Enumeratee elo eli m a =
        I eli m a -> I elo m (I eli m a)
-}
zipSource :: (Drop a, Drop b) => Source a -> Source b -> NN (Source (a,b))
zipSource Nil Nil t = t Nil
zipSource Nil (Cons x xs) t = drop x (xs Full <> t Nil)
zipSource (Cons x xs) Nil t = drop x (xs Full <> t Nil)
zipSource (Cons x xs) (Cons y ys) t = t (Cons (x,y) (zipSrc xs ys)) 

zipSrc s1 s2 Full = s1 Full <> s2 Full
zipSrc s1 s2 (Cont k) = s1 $ Cont $ \sa -> 
                        s2 $ Cont $ \sb -> zipSource sa sb k

forkSnk' sab ta tb = ta $ Cont $ \ta' ->
                    zipSource ta' tb sab

zipSnk' ta tb sab = forkSource sab ta tb

forkSource :: Source (a,b) ⊸ N (Source a) ⊸ N (Source b) ⊸ Eff
forkSource Nil t1 t2 = t1 Nil <> t2 Nil
forkSource (Cons (a,b) xs) t1 t2 = t1 $ Cons a $ \sa' ->
  t2 $ Cons b $ \sb' -> forkSrc' xs sa' sb'

forkSrc' sab Full tb = empty tb <> sab Full
forkSrc' sab tb Full = empty tb <> sab Full
forkSrc' sab (Cont ta) (Cont tb) = sab $ Cont $ \sab' -> forkSource sab' ta tb

forkSrc sab ta tb = forkSrc' sab (Cont ta) tb

scanSrc _  _ src Full = src Full
scanSrc f !z src (Cont k) = src $ Cont (scanSnk' f z k)

scanSnk' _ _ snk Nil          = snk Nil
scanSnk' f z snk (Cons a s)   = snk $  Cons y $
                                      scanSrc f next s
  where (next,y) = f z a

foldSrc' f !z s nb = s (Cont (foldSnk' f z nb))
foldSnk' _ z nb Nil = nb z
foldSnk' f z nb (Cons a s) = foldSrc' f (f z a) s nb

dropSrc _ s Full = s Full
dropSrc i s (Cont k) = s $ Cont $ dropSnk' i k

dropSnk' 0 s s' = s s'
dropSnk' _ s Nil = s Nil
dropSnk' i s (Cons x s') = drop x (dropSrc (i-1) s' (Cont s))

fromList = foldr cons empty

enumFromToSrc :: Int -> Int -> Src Int
enumFromToSrc _ _ Full = mempty
enumFromToSrc b e (Cont s)
  | b > e     = s Nil
  | otherwise = s (Cons b (enumFromToSrc (b+1) e))

linesSrc = flipSnk' unlinesSnk'
unlinesSnk' = unlinesSnk'' []

unlinesSnk'' :: String -> Snk' String -> Snk' Char
unlinesSnk'' acc s Nil = s (Cons acc empty)
unlinesSnk'' acc s (Cons '\n' s') = s (Cons   (reverse acc)
                                             (linesSrc s'))
unlinesSnk'' acc s (Cons c s')
  = s' (Cont $ unlinesSnk'' (c:acc) s)

untilSnk' _ Nil = mempty
untilSnk' p (Cons a s)
  | p a  = s Full
  | True = s (Cont (untilSnk' p))
interleave s1 s2 Full = s1 Full <> s2 Full
interleave s1 s2 (Cont s) = s1 (Cont (interleaveSnk' s s2))
interleaveSnk' snk src Nil = src (Cont snk)
interleaveSnk' snk src (Cons a s)
  = snk (Cons a (interleave s src))


filterSrc p = flipSnk' (filterSnk' p)
filterSnk' _ snk Nil = snk Nil
filterSnk' p snk (Cons a s) = case p a of
  Just b -> snk (Cons b (filterSrc p s))
  Nothing -> s (Cont (filterSnk' p snk))
unchunk = flipSnk' chunkSnk'
chunkSnk' s Nil = s Nil
chunkSnk' s (Cons x xs)
  = fwd' (fromList x `appendSrc` unchunk xs) s



toList s k = fwd' s (toListSnk' k)

toListSnk' :: N [a] -> Snk' a
toListSnk' k Nil = k []
toListSnk' k (Cons x xs) = toList xs $ \xs' -> k (x:xs')

