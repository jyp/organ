{-# LANGUAGE ScopedTypeVariables #-}
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

-- | Quadruple negation
type NNNN a = NN (NN a)

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

-- State the algebraic structure here (def. later)
-- (Functor, Monad?)

-- Source and Sink are true duals:
unshiftSnk :: N (Src a) -> Snk a
unshiftSnk k1 k2 = k1 $ \x -> fwd k2 x

unshiftSrc :: N (Snk a) -> Src a
unshiftSrc k1 k2 = k1 $ \x -> fwd x k2


-- Perhaps better name is "forward" (see ax in LL)
forward :: Src a -> Snk a -> Eff
forward source sink = source $ Cont sink

empty :: Src a
empty sink' = fwd Nil sink'

-- | Yield some data, sent to a sink. If the sink is full, ignore.
yield :: a -> Sink' a -> (Sink' a -> Eff) -> Eff
yield x (Cont c) k = c (Cons x k)
yield _ Full k = k Full

cons :: a -> Src a -> Src a
cons a s s' = yield a s' s


tail :: Src a -> Src a
tail s Full = s Full
tail s (Cont s') = s (Cont (\source -> case source of
  Nil -> s' Nil
  (Cons _ s'') -> forward s'' s'))


-- -- !!! the continuations must contain the same set of free vars !!!
-- await :: Source' a -> Eff -> (a -> Source' a -> Eff) -> Eff
-- await Nil eof _ = eof
-- await (Cons x cs) _ k = cs $ Cont $ \xs -> k x xs


-- -- !!! nil and cons must contain the same set of free vars !!!
-- match :: Eff -> (a -> Snk a) -> Snk a
-- match nil' cons' k = await k nil' cons'


plug :: Snk a
plug source' = fwd source' Full




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

takeSrc :: Int -> Src a -> Src a
takeSrc _ s Full = s Full
takeSrc 0 s (Cont s') = s Full >> s' Nil -- Subtle case
takeSrc i s (Cont s') = s (Cont (takeSnk i s'))

takeSnk :: Int -> Snk a -> Snk a
takeSnk _ s Nil = s Nil
takeSnk 0 s (Cons _ s') = s Nil >> s' Full -- Subtle case
takeSnk i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))


test1 = forward (hFileSrc stdin) (takeSnk 3 $ fileSnk "text.txt") 


-- TODO: Example: a sink that prints 10 elements, connected with a
-- file reading source. (Check: close the file after reading only 10
-- lines.)


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


-- TODO: co-objects


main = test1
