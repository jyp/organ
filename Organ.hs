{-# LANGUAGE TypeOperators #-}
module Organ where

import System.IO
import Data.IORef

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

-- | Collapsing three negations to one
unshift :: NNN a -> N a
unshift k x = k (shift x)
-- unshift =  (. shift)


-- Double negation is a monad; but we won't use that.
-- newtype P a = P {fromP :: NN a}
-- instance Monad P where
--   return = P . shift
--   (P k) >>= f = P $ \b -> k (\a -> fromP (f a) b)


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

-}

-- | A source of @a@'s. Given a source, one can: 1. Obtain a certain
-- number of @a@'s. Getting more than one requires to run effects. The
-- source may be able to provide only a certain number of @a@'s
-- 2. Close the source (notify that we will not demand any @a@ any
-- longer).
data Source a = Nil | Cons a (N (Sink a))

-- | A sink of @a@'s. Given a sink, one can: 1. Send a number of
-- @a@'s. 2. Close the sink
data Sink a = Full | Cont (N (Source a))

-- | Open a pipe (connect two sides together)
open :: (Sink a -> Eff) -> (Source a -> Eff) -> Eff
open producer consumer = producer $ Cont consumer

-- | Notify a source that we won't accept anything it may send
close :: Source a -> Eff
close Nil = return ()
close (Cons _ k) = k Full

-- | Wait for some data on a source
await :: Source a -> Eff -> (a -> Source a -> Eff) -> Eff
await Nil eof _ = eof
await (Cons x cs) _ k = cs $ Cont $ \xs -> k x xs

-- | Yield some data, sent to a sink. If the sink is full, ignore.
yield :: a -> Sink a -> (Sink a -> Eff) -> Eff
yield _ Full k = k Full
yield x (Cont c) k = c (Cons x k)

-- | Yield some data, sent to a sink. If the sink is full, handle that
-- case specially
yield' :: a -> Sink a -> Eff -> (Sink a -> Eff) -> Eff
yield' _ Full     full _ = full
yield' x (Cont c) _    k = c (Cons x k)

-- | Notify that we won't send any data
done :: Sink a -> Eff
done Full = return ()
done (Cont c) = c Nil


-- Examples

-- | Display all the data available from a source
display :: Show a => Source a -> Eff
display src = await src (return ()) $ \x xs -> do
    print x
    display xs

-- | Display @n@ pieces of data from a source (if available)
displayN :: Show a => Int -> Source a -> Eff
displayN 0 src = close src
displayN n src = await src (return ()) $ \x xs -> do
    print x
    displayN (n-1) xs

-- | Fill a sink with data from a handle. If the sink is full, close the handle.
readF :: Handle -> Sink Char -> Eff
readF h snk = do
  e <- hIsEOF h
  if e
     then done snk
     else do
       x <- hGetChar h
       yield' x snk (hClose h) (\snk -> readF h snk)


-- Example:
-- Tranformation
linesP :: String -> Source Char -> Sink String -> Eff
linesP xs src snk = do
  await src
    (yield xs snk $ \snk -> done snk)
    (\x src -> case x of
          '\n' -> yield (reverse xs) snk $ \snk -> linesP [] src snk
          _ -> linesP (x:xs) src snk)

lines' = linesP []

main = do
  open (\chars -> do h <- openFile "Organ.hs" ReadMode
                     readF h chars)
       (\chars -> open (\lines -> lines' chars lines)
                       (\lines -> display lines))

-- | Demultiplex
dmux :: Source (Either a b) -> Sink a -> Sink b -> Eff
dmux sab ta tb = await sab (done ta >> done tb) $ \ab sab ->
  case ab of
    Left a  -> yield a ta (\ta -> dmux sab ta tb)
    Right b -> yield b tb (\tb -> dmux sab ta tb)

-- CoSources, CoSinks
---------------------

type CoSource a = Sink (N a)
type CoSink a = Source (N a)

-- | Fill a sink with data from a handle. If the sink is full, close the handle.
-- Invariant: end of file not reached.
coreadF :: Handle -> CoSink Char -> Eff
coreadF h Nil = hClose h
coreadF h (Cons c cs) = do
  x <- hGetChar h
  c x
  e <- hIsEOF h
  if e
    then cs Full
    else do
      cs (Cont $ coreadF h)

-- | Display a CoSource of strings. This function does not control the
-- order of printing the elements.
codisplay :: CoSource String -> Eff
codisplay Full = return ()
codisplay (Cont c) = c (Cons putStrLn codisplay)

-- | Additive conjuction
type a & b = N (Either (N a) (N b))

mux :: CoSource a -> CoSource b -> CoSink (a & b) -> Eff
mux sa sb tab = smap id tab $ \tab' -> dmux tab' sa sb

smap :: (a -> NN b) -> Source a -> NN (Source b)
smap _ Nil g = g Nil
smap f (Cons x xs) g =
  f x $ \x' ->
  g (Cons x' $ \s -> csmap f s xs)

csmap :: (a -> NN b) -> Sink b -> NN (Sink a)
csmap _ Full g = g Full
csmap f (Cont k) g = g (Cont $ \s -> smap f s k)

-- Conversions between sources and sinks.
-----------------------------------------

-- It is in general easier to deal with a source argument than to deal
-- with a sink argument. Conversion from source to sink is easy;
-- conversion from sink to source is hard (and lossy).

-- | Conversion from source to sink by doing sequential processing.
sourceToSink :: Source a -> Sink (N a)
sourceToSink s = Cont $ \s' -> zipSources s s'

-- | Loop through two sources and make them communicate
zipSources :: Source a -> Source (N a) -> Eff
zipSources Nil _ = return ()
zipSources _ Nil = return ()
zipSources (Cons x xs) (Cons x' xs') = do
  x' x
  xs (Cont $ \sa -> xs' $ Cont $ \sna -> zipSources sa sna)

-- | Convert a sink to a source (by buffering). Attention: the closing
-- operation on the resulting source will not be propagated to the
-- input sink.
sinkToSource :: Sink a -> NN (Source (N a))
sinkToSource (Cont f) g = alloc g f
sinkToSource Full _ = return ()

sinkToSource' :: Sink (N a) -> NN (Source a)
sinkToSource' (Cont f) g = alloc f g
sinkToSource' Full _ = return ()

fromList :: [a] -> Source a
fromList (a':as') = Cons a' $ \snk -> case snk of
  (Cont s) -> s (fromList as')
  Full -> return ()

alloc :: (Source (N a) -> Eff) -> (Source a -> Eff) -> Eff
alloc f g = do
  a <- newIORef []
  f $ fromList $ repeat $ \x -> modifyIORef a (x:)
  x <- readIORef a
  g $ fromList $ reverse x


