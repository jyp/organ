{-# LANGUAGE ScopedTypeVariables, TypeOperators #-}
module New where

import System.IO
import Control.Concurrent.MVar
import Control.Monad (ap)
import Control.Exception
import Control.Concurrent (forkIO)
import Control.Applicative hiding (empty)
import Data.IORef
import qualified Control.Concurrent as C


-- | The Effect type. (The core library should be parametric over this
-- type. However, IO being a common use case, we'll stick to that)
type Eff = IO ()

-- | The type of continuations (Negation)
type N a = a -> Eff

-- | Double negation
type NN a = N (N a)

-- | Triple negation
type NNN a = N (NN a)

-- | Introducing a double negation
shift :: a -> NN a
shift x k = k x

-- | Collapsing three negations to one.  This means that, in the
-- presence of effects, it is possible to remove double negations.
unshift :: NNN a -> N a
unshift k x = k (shift x)
-- unshift =  (. shift)


-- Double negation is a monad; so we can recover our good old IO
-- monad, as follows. But we won't use it!
newtype IO' a = IO {fromIO :: NN a}
instance Functor IO' where
  fmap f (IO k) = IO $ \x -> k $ x . f
instance Applicative IO' where
  (<*>) = ap
  pure = return
instance Monad IO' where
  return = IO . shift
  (IO k) >>= f = IO $ \b -> k (\a -> fromIO (f a) b)

--------------------------
-- Pipe, source, sink.

{-

A pipe can be accessed through both ends, explicitly.

 Producer --> Sink >------ Pipe ----> Source --> Consumer

Data is sent to a sink, and can be read from a source. The naming
convention may seem counterintuitive, but it makes sense from the
point of view of the Producer/Consumer programs using those objects.


Attention! For this to make sense, sinks and sources must be used linearly.

1. They MUST NOT be duplicated (or shared!) That is, they may not be re-used after (after
calling one of the primitive functions.)

2. They MUST be consumed (or passed to a function consuming them)

Otherwise the effects contained in the objects may be run multiple
times; and this can be bad! For example, the same file may be closed
twice, etc. (Missiles ... ) or we may forget to run an effect


-}

-- | A source of @a@'s. Given a source, one can: 1. Obtain a certain
-- number of @a@'s. Getting more than one requires to run effects. The
-- source may be able to provide only a certain number of @a@'s
-- 2. Close the source (notify that we will not demand any @a@ any
-- longer).
data Source' a = Nil | Cons a (N (Sink' a))

-- | A sink of @a@'s. Given a sink, one can: 1. Send a number of
-- @a@'s. 2. Close the sink
data Sink' a = Full | Cont (N (Source' a))


----------------------------------
-- Duality of Source and Sink

-- definition: a necessary condition for  A being dual to B is
--  f : N A -> B     f' : A -> N B
--  g : N B -> A     g' : B -> N A
--

-- | Forwarding (ax)
fwd :: Source' a -> Sink' a -> Eff
fwd s (Cont s') = s' s
fwd Nil Full = return ()
fwd (Cons _ xs) Full = xs Full

shiftSource :: Source' a -> N (Sink' a)
shiftSource = fwd

-- source and sinks are NOT true duals:
unshiftSink :: N (Sink' a) -> Source' a
unshiftSink = error "cannot be implemented!"

type Src a = N (Sink' a)
type Snk a = N (Source' a)


-- Source and Sink are true duals:
unshiftSnk :: N (Src a) -> Snk a
unshiftSnk k1 k2 = k1 $ \x -> fwd k2 x

unshiftSrc :: N (Snk a) -> Src a
unshiftSrc k1 k2 = k1 $ \x -> fwd x k2

snkToSink :: Snk a -> N (Src a)
snkToSink k kk = kk (Cont k)

srcToSource :: Src a -> N (Snk a)
srcToSource k kk = k (Cont kk)

-- State the algebraic structure here (def. later)
-- (Functor, Monad?)

-- Perhaps better name is "forward" (see ax in LL)
forward :: Src a -> Snk a -> Eff
forward source sink = source $ Cont sink


empty :: Src a
empty sink' = fwd Nil sink'

cons :: a -> Src a -> Src a

-- | Yield some data, sent to a sink. If the sink is full, ignore.
yield :: a -> Sink' a -> (Sink' a -> Eff) -> Eff
yield x (Cont c) k = c (Cons x k)
yield _ Full k = k Full

cons a s s' = yield a s' s

tail :: Src a -> Src a
tail s Full = s Full
tail s (Cont s') = s (Cont (\source -> case source of
  Nil -> s' Nil
  (Cons _ s'') -> forward s'' s'))

head :: Src a -> NN (Maybe a)
head k1 k2 = k1 $ Cont $ \src -> case src of
  Nil -> k2 Nothing
  (Cons x s'') -> s'' Full >> k2 (Just x)

viewSrc :: Src a -> NN (Source' a)
viewSrc k1 k2 = k1 $ Cont $ k2
  

plug :: Snk a
plug source' = fwd source' Full


-- -- !!! the continuations must contain the same set of free vars !!!
-- await :: Source' a -> Eff -> (a -> Source' a -> Eff) -> Eff
-- await Nil eof _ = eof
-- await (Cons x cs) _ k = cs $ Cont $ \xs -> k x xs


-- -- !!! nil and cons must contain the same set of free vars !!!
-- match :: Eff -> (a -> Snk a) -> Snk a
-- match nil' cons' k = await k nil' cons'

-------------
-- ???

takeSrc :: Int -> Src a -> Src a
takeSrc _ s Full = s Full
takeSrc 0 s (Cont s') = s Full >> s' Nil -- Subtle case
takeSrc i s (Cont s') = s (Cont (takeSnk i s'))

takeSnk :: Int -> Snk a -> Snk a
takeSnk _ s Nil = s Nil
takeSnk 0 s (Cons _ s') = s Nil >> s' Full -- Subtle case
takeSnk i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))

takeSink' :: Int -> Sink' a -> Sink' a
takeSink' _ s Nil = s Nil
takeSink' 0 s (Cons _ s') = s Nil >> s' Full -- Subtle case
takeSink' i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))

--------------
-- File sink

fileSnk :: FilePath -> Snk String
fileSnk file s = do
  h <- openFile file WriteMode
  hFileSnk h s

hFileSnk :: Handle -> Snk String
hFileSnk h Nil = hClose h
hFileSnk h (Cons c s) = do
  hPutStrLn h c
  s (Cont (hFileSnk h))

stdoutSnk :: Snk String
stdoutSnk = hFileSnk stdout

hFileSrc :: Handle -> Src String
hFileSrc h Full = hClose h
hFileSrc h (Cont c) = do
  e <- hIsEOF h
  if e then do
         hClose h
         c Nil
       else do
         x <- hGetLine h
         c (Cons x $ hFileSrc h)


hFileSrcSafe :: Handle -> Src Char
hFileSrcSafe h Full = hClose h
hFileSrcSafe h (Cont c) = do
  e <- hIsEOF h
  if e then do
         hClose h
         c Nil
       else do
         mx <- catch (Just <$> hGetChar h) (\(_ :: IOException) -> return Nothing)
         case mx of
           Nothing -> c Nil
           Just x -> c (Cons x $ hFileSrcSafe h)

fileSrc :: FilePath -> Src String
fileSrc file sink = do
  h <- openFile file ReadMode
  hFileSrc h sink


-- Example: a sink that prints 10 elements, connected with a
-- file reading source. (Check: close the file after reading only 10
-- lines.)

example1 = forward (hFileSrc stdin) (takeSnk 3 $ fileSnk "text.txt") 


-------------------------
-- Algebraic structure

-- General pattern:

mapSrc :: (a -> b) -> Src a -> Src b
mapSrc f src Full = src Full
mapSrc f src (Cont s) = src (Cont (mapSnk f s))

mapSnk :: (b -> a) -> Snk a -> Snk b
mapSnk f snk Nil = snk Nil
mapSnk f snk (Cons a s) = snk (Cons (f a) (mapSrc f s))




-- src is a monad:
appendSnk :: Snk a -> Snk a -> Snk a
appendSnk s1 s2 Nil = s1 Nil >> s2 Nil
appendSnk s1 s2 (Cons a s) = s1 (Cons a (forwardThenSrc s2 s))

forwardThenSrc :: Snk a -> Src a -> Src a
forwardThenSrc s2 s Full = forward s s2
forwardThenSrc s2 s (Cont s') = s (Cont (appendSnk s' s2))

appendSrc :: Src a -> Src a -> Src a
appendSrc s1 s2 Full = s1 Full >> s2 Full
appendSrc s1 s2 (Cont s) = s1 (Cont (forwardThenSnk s s2))

forwardThenSnk :: Snk a -> Src a -> Snk a
forwardThenSnk snk src Nil = forward src snk
forwardThenSnk snk src (Cons a s) = snk (Cons a (appendSrc s src))

concatSrcSrc :: Src (Src a) -> Src a
concatSrcSrc ss Full = ss Full
concatSrcSrc ss (Cont s) = ss (Cont (concatSnkSrc s))

concatSnkSrc :: Snk a -> Snk (Src a)
concatSnkSrc snk Nil = snk Nil
concatSnkSrc snk (Cons src s) = src (Cont (concatAux snk s))

concatAux :: Snk a -> Src (Src a) -> Snk a
concatAux snk ssrc Nil = snk Nil >> ssrc Full
concatAux snk ssrc (Cons a s) = snk (Cons a (appendSrc s (concatSrcSrc ssrc)))


-- TODO: concatSnkSnk ?


-- Synchronicity

-- Seemingly asynchronous interface, but everything can (and is)
-- executed synchronously: there is only one thread of control.

-- every production is matched by a consuption (and vice versa)

-- A consequence of synchronicity is that there won't be implicity
-- buffering of data. However, the programmer can still build lists
-- explicity if so they decide.

toList :: Src a -> NN [a]
toList k1 k2 = k1 $ Cont $ \src -> case src of
   Nil -> k2 []
   Cons x xs -> toList xs $ \xs' -> k2 (x:xs')

--------------------------------------------
-- Co-objects

-- Consequence: can de-multiplex, but cannot multiplex sources.

-- Can implement:
-- mux :: Src (Either a b) -> Snk a -> Snk b -> Eff


-- TODO: nicer definition?

dmux' :: Src (Either a b) -> Snk a -> Snk b -> Eff

dmux :: Source' (Either a b) -> Sink' a -> Sink' b -> Eff
dmux Nil ta tb = fwd Nil ta >> fwd Nil tb
dmux (Cons ab c) ta tb = case ab of
  Left a -> c $ Cont $ \src' -> case ta of
    Full -> fwd Nil tb >> plug src'
    Cont k -> k (Cons a $ \ta' -> dmux src' ta' tb)
  Right b -> c $ Cont $ \src' -> case tb of
    Full -> fwd Nil ta >> plug src'
    Cont k -> k (Cons b $ \tb' -> dmux src' ta tb')

dmux' sab' ta' tb' =
  snkToSink ta' $ \ta ->
  snkToSink tb' $ \tb ->
  srcToSource sab' $ \sab ->
  dmux sab ta tb

-- This is not implementable (without resorting to primitives in the
-- IO monad):

-- mux :: Src a -> Src b -> Src (Either a b)

-- or even
-- muxWith :: Src a -> Src b -> Src (a & b)
-- (on subsequent readings, one might wonder about it)


-- However we can implement this one:

mux' :: CoSrc a -> CoSrc b -> CoSrc (a & b)

-- where
type a & b = N (Either (N a) (N b))
type CoSrc a = Snk (N a)
type CoSnk a = Src (N a)

-- Indeed, a sink of "N a" is a source of "a" (albeit different
-- properties), and dually a source of "N a" is a kind of sink of a.


-- A co-source

-- TODO: what about their algebraic structure?

-- One access elements of a co-source only "one at a time"; for
-- example the following can't be implemented:

toList' :: CoSrc a -> NN [a]
-- toList' k1 k2 = k1 $ Cons _ _
-- toList' k1 k2 = k2 $ _ : _
toList' = error "impossible"

-- Yet it's possible to define useful co-sources and co-sinks.

-- | Display a CoSource of strings. This function does not control the
-- order of printing the elements.
coFileSink :: Handle -> CoSnk String
coFileSink h Full = hClose h
coFileSink h (Cont c) = c (Cons (hPutStrLn h) (coFileSink h))

coFileSrc :: Handle -> CoSrc String
coFileSrc h Nil = hClose h
coFileSrc h (Cons x xs) = do
  e <- hIsEOF h
  if e then do
         hClose h
         xs Full
       else do
         forkIO $ x =<< hGetLine h
         xs $ Cont $ coFileSrc h


-- Finally, here is the def. of mux' in all its glory.
mux' sa sb = unshiftSnk $ mux sa sb

dnintro :: Src a -> Src (NN a)
dnintro k Full = k Full
dnintro s (Cont k) = s $ Cont $ dndel' k

dndel :: Src (NN a) -> Src a
dndel s Full = s Full
dndel s (Cont k) = s $ Cont $ dnintro' k

dnintro' :: Snk a -> Snk (NN a)
dnintro' k Nil = k Nil
dnintro' k (Cons x xs) = x $ \x' -> k (Cons x' $ dndel xs)

dndel' :: Snk (NN a) -> Snk a
dndel' s Nil = s Nil
dndel' s (Cons x xs) = s (Cons (shift x) (dnintro xs))

mux :: CoSrc a -> CoSrc b -> CoSnk (a & b) -> Eff
mux sa sb tab = dmux' (dndel tab) sa sb

-- This all preserves synchronicity still.

-----------
-- Asynch

-- Transition: what can you do if you want more flexibility while
-- remaining in the framework? (Asynchronous behaviour) (Useful to
-- still have the guarantees locally, "breakage" is limited to
-- explicit use of escape hatches.)


-- 1. Concurrency opportunities arise whenever we convert from Src to
-- CoSrc or dually from CoSnk to Snk.

-- For every concurrency strategy we can build such a conversion:

srcToCoSrc :: Strategy a -> Src a -> CoSrc a
srcToCoSrc strat k s0 = k $ Cont $ \ s1 -> strat s1 s0

coSnkToSnk :: Strategy a -> CoSnk a -> Snk a
coSnkToSnk strat k s0 = k $ Cont $ \ s1 -> strat s0 s1

-- what a strat. is:
type Strategy a = Source' a -> Source' (N a) -> Eff

-- examples
concurrently :: Source' a -> Source' (N a) -> Eff
concurrently Nil (Cons _ xs) = xs Full
concurrently (Cons _ xs) Nil = xs Full
concurrently (Cons x xs) (Cons x' xs') = do
  C.forkIO $ x' x
  xs (Cont $ \sa -> xs' $ Cont $ \sna -> concurrently sa sna)

-- | Loop through two sources and make them communicate
sequentially :: Source' a -> Source' (N a) -> Eff
sequentially Nil (Cons _ xs) = xs Full
sequentially (Cons _ xs) Nil = xs Full
sequentially (Cons x xs) (Cons x' xs') = do
  -- C.forkIO $ x' x parallel zipping
  x' x
  xs (Cont $ \sa -> xs' $ Cont $ \sna -> sequentially sa sna)

-- 2. Buffering requirements.  Buffering is required whenever one
-- converts from a CoSrc to a Src (or dually ...)

type Buffering a = CoSrc a -> Src a

-- These buffering operations can be implemented by accessing the
-- underlying buffering features of the IO monad.

-- example:

fileBuffer :: Buffering String
fileBuffer f g = do
  h' <- openFile  "tmp" WriteMode
  forkIO $ forward (coFileSink h') f

  h <- openFile "tmp" ReadMode
  hFileSrc h g

-- The above buffer works only if there is no static dep

-- TODO: chat server.
-- chat :: 

-- More useful buffering:
chanCoSnk :: C.Chan a -> CoSnk a
chanCoSnk h Full = return ()
chanCoSnk h (Cont c) = c (Cons (C.writeChan h) (chanCoSnk h))

chanSrc :: C.Chan a -> Src a
chanSrc h Full = return ()
chanSrc h (Cont c) = do x <- C.readChan h
                        c (Cons x $ chanSrc h)

chanBuffer :: Buffering a
chanBuffer f g = do
  c <- C.newChan
  forkIO $ forward (chanCoSnk c) f 
  chanSrc c g


-- For statuses  things like mouse pos. event, where only the last message matters.
varCoSnk :: IORef a -> CoSnk a
varCoSnk h Full = return ()
varCoSnk h (Cont c) = c (Cons (writeIORef h) (varCoSnk h))

varSrc :: IORef a -> Src a
varSrc h Full = return ()
varSrc h (Cont c) = do x <- readIORef h
                       c (Cons x $ varSrc h)

varBuffer :: a -> Buffering a
varBuffer a f g = do
  c <- newIORef a
  forkIO $ forward (varCoSnk c) f 
  varSrc c g

swpBuffering :: Buffering a -> Snk a -> CoSrc a
swpBuffering f s g = f s _

-- CoSnk ~ Src ~ ⊗
-- CoSrc ~ Snk ~ ⅋

main = example1

