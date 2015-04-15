% A Classical Approach to IO Streaming

 <!--

> {-# LANGUAGE ScopedTypeVariables, TypeOperators, RankNTypes #-}
> module Organ where

> import System.IO
> import Control.Concurrent.MVar 
> import Control.Monad (ap)
> import Control.Exception
> import Control.Concurrent (forkIO)
> import Control.Applicative hiding (empty)
> import Data.IORef
> import qualified Control.Concurrent as C

 -->

 # Intro: Goals and Examples

A pipe can be accessed through both ends, explicitly.

   Source -->  Program --> Sink

Data is sent to a sink, and can be read from a source. The naming
convention may seem counterintuitive, but it makes sense from the
point of view of the Producer/Consumer programs using those objects.

* Modularity
* Synchronicity?

Preliminary: negations and continuations
========================================

We begin by providing a type of effects. For users of the stream
library, this type should remain abstract. However in this paper we
will develop stream components. This is possible only if we pick a
concrete type of effects. Because we will provide streams interacting
with files, etc. we must pick \var{IO}.

> type Eff = IO ()

We can then define negation as follows:

> type N a = a -> Eff

A shortcut for double negations is also convenient.

> type NN a = N (N a)

The basic idea (imported from classical logics) pervading this paper
is that producing a result of type α is equivalent to consuming an
argument of type $N α$. Dually, consuming an argument of type α is
equivalent to producing a result of type $N α$.

In classical logics, negation is involutive; that is:

$NN a = a$

However, because we work with Haskell, we do not have this
equality. We can come close however.

First, double negations can always be introduced, using the
\var{shift} operator.

> shift :: a -> NN a
> shift x k = k x

Second, it is possible to remove double negations, as long as a
side-effect can be outputted.  Equivalently, triple negations can be
collapsed to a single one.

> unshift :: NN (N a) -> N a
> unshift k x = k (shift x)

The above two functions are the \var{return} and \var{join} of the
double negation monad. However, we will not be using this monadic
structure anywhere in the following. Indeed, single negations play a
central role in our approach.


Streams
=======

We will define sources and sinks by mutual recursion. Producing a
source means to select if the source is empty (\var{Nil}) or not
(\var{Cons}). If the source is not empty, one must then produce an
element and *consume* a sink.

> data Source' a = Nil | Cons a (N (Sink' a))
> data Sink' a = Full | Cont (N (Source' a))

Producing a sink means to select if one an accept more elements
(\var{Cont}) or not (\var{Full}). In the former case, one must then be
able to consume a source. The full case is useful for example when the
sink encounters an exception.

Note that, in order to produce (or consume) the next element, the
source (or sink) must run the effects on the other side of the pipe.

This means that each production is matched by a consumption, and
\textit{vice versa}.

Linearity
---------

For streams to be used safely, we must have the following extra
contract between the user and the implementer: **each \var{Eff}-valued
variable must be used linearly**. That is, assuming $x$ an \var{Eff}-valued
variable:

1. The variable $x$ may not be duplicated or shared. In particular, if
passed as an argument to a function it may not be used again.

2. The variable $x$ must be consumed (or passed to a function, which
will be in charged of consuming it).


If the above condition is not respected, the effects contained in the
objects may be run multiple times; and this can be bad! For example,
the same file may be closed twice, etc. (Missiles ... ) or we may
forget to run an effect


For example, the last action of a
sink will typically be closing the file. This can be guaranteed only
if the actions are run until reaching the end of the pipe (either
\var{Full} or \var{Nil}).

In this paper, linearity is enforced by manual inspection. Doing so is
error prone; fortunately implementing a linearity checker is
straightforward. (TODO: if type variables can be instanciated by Eff
things it's a bit tricky. (Need for two kinds of variables...) We do
this instanciation in the concat function.)


Basics
------

A few basic combinators for Source' and Sink' are the following.

One can connect a source and a sink, as follows. The effect is the
combined effect of all productions and consumptions on the stream.

> fwd :: Source' a -> Sink' a -> Eff
> fwd s (Cont s') = s' s
> fwd Nil Full = return ()
> fwd (Cons _ xs) Full = xs Full

One send data to a sink. If the sink is full, the da"ta is ignored.
The third argument is a continuation getting the "new" sink, that
obtained after the "old" sink has consumed the data.

> yield :: a -> Sink' a -> (Sink' a -> Eff) -> Eff
> yield x (Cont c) k = c (Cons x k)
> yield _ Full k = k Full

One may want to provide the following function, waiting for data to be
produced by a source. The second argument is the effect to run if no
data is produced, and the third is the effect to run given the data
and the remaining source.

> await :: Source' a -> Eff -> (a -> Source' a -> Eff) -> Eff
> await Nil eof _ = eof
> await (Cons x cs) _ k = cs $ Cont $ \xs -> k x xs

However, the above function breaks the linearity invariant, so we will
refrain to use it as such. The pattern that it defines is still
useful: it is valid when the second and third argument consume the
sameset of variables.  Indeed, this condition is often satisfied.


Baking in negations
-------------------

However, programming with Source' and Sink' is inherently
continuation-heavy: negations must be explicitly added in many places.
Therefore, we will use instead pre-negated versions of sources and sink:

> type Src a = N (Sink' a)
> type Snk a = N (Source' a)

These definitions have the added advantage to perfect the duality
between sources and sinks. Indeed, a negated sink' cannot be converted
to a source.

> unshiftSink :: N (Sink' a) -> Source' a
> unshiftSink = error "cannot be implemented!"

All the following conversions are implementable:

> unshiftSnk :: N (Src a) -> Snk a
> unshiftSrc :: N (Snk a) -> Src a
> shiftSnk :: Snk a -> N (Src a)
> shiftSrc :: Src a -> N (Snk a)

> unshiftSnk k1 k2 = k1 $ \x -> fwd k2 x
> unshiftSrc k1 k2 = k1 $ \x -> fwd x k2
> shiftSnk k kk = kk (Cont k)
> shiftSrc k kk = k (Cont kk)

A different reading of the type of shiftSrc reveals that it implements
forwarding of data from Src to Snk:

> forward :: Src a -> Snk a -> Eff
> forward = shiftSrc

Examples: Effect-Free Streams
-----------------------------

Given the above definitions, one can implement a natural API for sources:

> empty :: Src a
> empty sink' = fwd Nil sink'

> cons :: a -> Src a -> Src a
> cons a s s' = yield a s' s

> tail :: Src a -> Src a
> tail s Full = s Full
> tail s (Cont s') = s (Cont (\source -> case source of
>   Nil -> s' Nil
>   (Cons _ s'') -> forward s'' s'))

Dually, the full sink is simply

> plug :: Snk a
> plug source' = fwd source' Full


A non-full sink decides what to do depending on the availability of
data. We could write the following:

> match :: Eff -> (a -> Snk a) -> Snk a
> match nil' cons' k = await k nil' cons'

However, calling await may break linearity, so we'll refrain to use
match in the following.


Furthermore, both Src and Snk are functors and monads. The instances
are somewhat involved, so we'll defer them to TODO. (Monad is a bit
suspicious due to linearity) We will instead show how to implement
more concrete functions for Src and Snk.

Given a source, we can create a new source which ignores all but its
first $n$ elements. Conversely, we can prune a Sink to consume only
the first $n$ elements of a source.

> takeSrc :: Int -> Src a -> Src a
> takeSnk :: Int -> Snk a -> Snk a

The natural implementation is by mutual recursion. The main subtlety
is that, when reaching the $n$th element, both ends of the stream must
be notified of its closing.

> takeSrc _ s Full = s Full
> takeSrc 0 s (Cont s') = s Full >> s' Nil -- Subtle case
> takeSrc i s (Cont s') = s (Cont (takeSnk i s'))

> takeSnk _ s Nil = s Nil
> takeSnk 0 s (Cons _ s') = s Nil >> s' Full -- Subtle case
> takeSnk i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))

Examples: Effectful streams
---------------------------

So far, we have constructed only effect-free streams. The fact that
Eff = IO () was never used. In this section we fill this gap.

We first define the followig helper function, which sends data to a
file; thus constructing a sink.

> hFileSnk :: Handle -> Snk String
> hFileSnk h Nil = hClose h
> hFileSnk h (Cons c s) = do
>   hPutStrLn h c
>   s (Cont (hFileSnk h))

A file sink is then simply:

> fileSnk :: FilePath -> Snk String
> fileSnk file s = do
>   h <- openFile file WriteMode
>   hFileSnk h s

And a sink for standard output is:

> stdoutSnk :: Snk String
> stdoutSnk = hFileSnk stdout

A file source reads data from a file, as follows:

> hFileSrc :: Handle -> Src String
> hFileSrc h Full = hClose h
> hFileSrc h (Cont c) = do
>   e <- hIsEOF h
>   if e then do
>          hClose h
>          c Nil
>        else do
>          x <- hGetLine h
>          c (Cons x $ hFileSrc h)

> fileSrc :: FilePath -> Src String
> fileSrc file sink = do
>   h <- openFile file ReadMode
>   hFileSrc h sink

We can then implement file copy as follows:

> copyFile source target = forward (fileSrc source) (fileSnk target)

It should be emphasised at this point that reading and writing will be
interleaved: in order to produce the next file line (in the source),
the current line must be consumed by writing it to disk (in the sink).
The stream behaves fully synchronously, and no intermediate data is
buffered.

When the sink is full, the source connected to it should be finalized.
The next example shows what happens when a sink closes the stream
early. Instead of connecting the source to a full sink, we connect it
to one which stops receiving input after three lines.

> read3Lines = forward (hFileSrc stdin) (takeSnk 3 $ fileSnk "text.txt")

Indeed, testing the above program reveals that it properly closes
stdin after reading three lines. This early closing of sinks allows
modular stream programming. In particular, it is easy to support
proper finalization in the presence of exceptions, as the next section shows.

Exception Handling
------------------

While the above implementations of file source and sink are fine for
illustrative purposes, their production-strength versions should
handle exceptions. Doing so is straightforward: as shown above, our
sinks and sources readily support early closing of the stream.

The following code fragment shows how to hande an exception when
reading a line in a file source.

> hFileSrcSafe :: Handle -> Src String
> hFileSrcSafe h Full = hClose h
> hFileSrcSafe h (Cont c) = do
>   e <- hIsEOF h
>   if e then do
>          hClose h
>          c Nil
>        else do
>          mx <- catch (Just <$> hGetLine h)
>                (\(_ :: IOException) -> return Nothing)
>          case mx of
>            Nothing -> c Nil
>            Just x -> c (Cons x $ hFileSrcSafe h)

Exceptions raised in hIsEOF should be handled in a similar same way,
as well as those raised in a file sink.

Algebraic structure
-------------------

Sources are functors, while sinks are covariant functors:

> mapSrc :: (a -> b) -> Src a -> Src b
> mapSnk :: (b -> a) -> Snk a -> Snk b

The implementation follows the pattern introduced above: mapSrc and
mapSnk are defined by mutual recursion.

> mapSrc f src Full = src Full
> mapSrc f src (Cont s) = src (Cont (mapSnk f s))

> mapSnk f snk Nil = snk Nil
> mapSnk f snk (Cons a s) = snk (Cons (f a) (mapSrc f s))


src is a monad (!!! Linearity !!!)

> appendSnk :: Snk a -> Snk a -> Snk a
> appendSnk s1 s2 Nil = s1 Nil >> s2 Nil
> appendSnk s1 s2 (Cons a s) = s1 (Cons a (forwardThenSrc s2 s))

> forwardThenSrc :: Snk a -> Src a -> Src a
> forwardThenSrc s2 s Full = forward s s2
> forwardThenSrc s2 s (Cont s') = s (Cont (appendSnk s' s2))

> appendSrc :: Src a -> Src a -> Src a
> appendSrc s1 s2 Full = s1 Full >> s2 Full
> appendSrc s1 s2 (Cont s) = s1 (Cont (forwardThenSnk s s2))

> forwardThenSnk :: Snk a -> Src a -> Snk a
> forwardThenSnk snk src Nil = forward src snk
> forwardThenSnk snk src (Cons a s) = snk (Cons a (appendSrc s src))

> concatSrcSrc :: Src (Src a) -> Src a
> concatSrcSrc ss Full = ss Full
> concatSrcSrc ss (Cont s) = ss (Cont (concatSnkSrc s))

> concatSnkSrc :: Snk a -> Snk (Src a)
> concatSnkSrc snk Nil = snk Nil
> concatSnkSrc snk (Cons src s) = src (Cont (concatAux snk s))

> concatAux :: Snk a -> Src (Src a) -> Snk a
> concatAux snk ssrc Nil = snk Nil >> ssrc Full
> concatAux snk ssrc (Cons a s) = snk (Cons a (appendSrc s (concatSrcSrc ssrc)))


Synchronicity
-------------

One of the main benefits of streams as defined here is that the
programming interface appears to be asynchronous. That is, in the
source code, production and consumption of data are described in
isolation and can be composed freely later. In other words, one can
build a data source regardless of how the data is be consumed, or
dually one can build a sink regardless of how the data is produced.
Despite the apparent asynchronicity, all the code can (and is)
executed synchronously: there is a single thread of control.

A consequence of synchronicity is that the programer cannot be
implicity buffering data: every production is matched by a consuption
(and vice versa). However, one can buffer data by explicity
buiding lists, if one so decides:

> toList :: Src a -> NN [a]
> toList k1 k2 = k1 $ Cont $ \src -> case src of
>    Nil -> k2 []
>    Cons x xs -> toList xs $ \xs' -> k2 (x:xs')

In sum, synchronicity restricts the kind of operations one can
constructs, in exchange for two guarantees:

1. Finalization of sources and stream is synchronous
2. No implicit memory allocation happen

While the guarantees have been discussed so far, it may be unclear how
synchronicity actually restricts the programs one can write. In the
rest of the section we show by example how the restriction plays out.

One operation supported by synchronous behaviour is demultiplexing of
sources, by connecting it to two sinks.

> dmux' :: Src (Either a b) -> Snk a -> Snk b -> Eff

which we can implement as follows:

> dmux :: Source' (Either a b) -> Sink' a -> Sink' b -> Eff
> dmux Nil ta tb = fwd Nil ta >> fwd Nil tb
> dmux (Cons ab c) ta tb = case ab of
>   Left a -> c $ Cont $ \src' -> case ta of
>     Full -> fwd Nil tb >> plug src'
>     Cont k -> k (Cons a $ \ta' -> dmux src' ta' tb)
>   Right b -> c $ Cont $ \src' -> case tb of
>     Full -> fwd Nil ta >> plug src'
>     Cont k -> k (Cons b $ \tb' -> dmux src' ta tb')

> dmux' sab' ta' tb' =
>   shiftSnk ta' $ \ta ->
>   shiftSnk tb' $ \tb ->
>   shiftSrc sab' $ \sab ->
>   dmux sab ta tb

The key ingredient is that demultiplexing starts by reading the next
value available on the source. Depending on its value, we feed the
data to either of the sinks are proceed.



Indeed, there is no

This is not implementable (without resorting to primitives in the
IO monad):


or even
muxWith :: Src a -> Src b -> Src (a & b)
(on subsequent readings, one might wonder about it)


However we can implement this one:

> mux' :: CoSrc a -> CoSrc b -> CoSrc (a & b)

where

> type a & b = N (Either (N a) (N b))
> type CoSrc a = Snk (N a)
> type CoSnk a = Src (N a)

Indeed, a sink of "N a" is a source of "a" (albeit different
properties), and dually a source of "N a" is a kind of sink of a.


A co-source

TODO: what about their algebraic structure?

One access elements of a co-source only "one at a time"; for
example the following can't be implemented:

> toList' :: CoSrc a -> NN [a]

toList' k1 k2 = k1 $ Cons _ _
toList' k1 k2 = k2 $ _ : _

> toList' = error "impossible"

Yet it's possible to define useful co-sources and co-sinks.

Display a CoSource of strings. This function does not control the
order of printing the elements.

> coFileSink :: Handle -> CoSnk String
> coFileSink h Full = hClose h
> coFileSink h (Cont c) = c (Cons (hPutStrLn h) (coFileSink h))

> coFileSrc :: Handle -> CoSrc String
> coFileSrc h Nil = hClose h
> coFileSrc h (Cons x xs) = do
>   e <- hIsEOF h
>   if e then do
>          hClose h
>          xs Full
>        else do
>          forkIO $ x =<< hGetLine h
>          xs $ Cont $ coFileSrc h


Finally, here is the def. of mux' in all its glory.

> mux' sa sb = unshiftSnk $ mux sa sb

> dnintro :: Src a -> Src (NN a)
> dnintro k Full = k Full
> dnintro s (Cont k) = s $ Cont $ dndel' k

> dndel :: Src (NN a) -> Src a
> dndel s Full = s Full
> dndel s (Cont k) = s $ Cont $ dnintro' k

> dnintro' :: Snk a -> Snk (NN a)
> dnintro' k Nil = k Nil
> dnintro' k (Cons x xs) = x $ \x' -> k (Cons x' $ dndel xs)

> dndel' :: Snk (NN a) -> Snk a
> dndel' s Nil = s Nil
> dndel' s (Cons x xs) = s (Cons (shift x) (dnintro xs))

> mux :: CoSrc a -> CoSrc b -> CoSnk (a & b) -> Eff
> mux sa sb tab = dmux' (dndel tab) sa sb

This all preserves synchronicity still.

Asynch

Transition: what can you do if you want more flexibility while
remaining in the framework? (Asynchronous behaviour) (Useful to
still have the guarantees locally, "breakage" is limited to
explicit use of escape hatches.)


1. Concurrency opportunities arise whenever we convert from Src to
CoSrc or dually from CoSnk to Snk.

For every concurrency strategy we can build such a conversion:

> srcToCoSrc :: Strategy a -> Src a -> CoSrc a
> srcToCoSrc strat k s0 = k $ Cont $ \ s1 -> strat s1 s0

> coSnkToSnk :: Strategy a -> CoSnk a -> Snk a
> coSnkToSnk strat k s0 = k $ Cont $ \ s1 -> strat s0 s1

what a strat. is:

> type Strategy a = Source' a -> Source' (N a) -> Eff

examples

> concurrently :: Source' a -> Source' (N a) -> Eff
> concurrently Nil (Cons _ xs) = xs Full
> concurrently (Cons _ xs) Nil = xs Full
> concurrently (Cons x xs) (Cons x' xs') = do
>   C.forkIO $ x' x
>   xs (Cont $ \sa -> xs' $ Cont $ \sna -> concurrently sa sna)

Loop through two sources and make them communicate

> sequentially :: Source' a -> Source' (N a) -> Eff
> sequentially Nil (Cons _ xs) = xs Full
> sequentially (Cons _ xs) Nil = xs Full
> sequentially (Cons x xs) (Cons x' xs') = do
>   x' x
>   xs (Cont $ \sa -> xs' $ Cont $ \sna -> sequentially sa sna)

2. Buffering requirements.  Buffering is required whenever one
converts from a CoSrc to a Src (or dually ...)

> type Buffering a = CoSrc a -> Src a

These buffering operations can be implemented by accessing the
underlying buffering features of the IO monad.

example:

> fileBuffer :: Buffering String
> fileBuffer f g = do
>   h' <- openFile  "tmp" WriteMode
>   forkIO $ forward (coFileSink h') f

>   h <- openFile "tmp" ReadMode
>   hFileSrc h g

The above buffer works only if there is no static dep

TODO: chat server.
chat :: 

More useful buffering:

> chanCoSnk :: C.Chan a -> CoSnk a
> chanCoSnk h Full = return ()
> chanCoSnk h (Cont c) = c (Cons (C.writeChan h) (chanCoSnk h))

> chanSrc :: C.Chan a -> Src a
> chanSrc h Full = return ()
> chanSrc h (Cont c) = do x <- C.readChan h
>                         c (Cons x $ chanSrc h)

> chanBuffer :: Buffering a
> chanBuffer f g = do
>   c <- C.newChan
>   forkIO $ forward (chanCoSnk c) f 
>   chanSrc c g


For statuses  things like mouse pos. event, where only the last message matters.

> varCoSnk :: IORef a -> CoSnk a
> varCoSnk h Full = return ()
> varCoSnk h (Cont c) = c (Cons (writeIORef h) (varCoSnk h))

> varSrc :: IORef a -> Src a
> varSrc h Full = return ()
> varSrc h (Cont c) = do x <- readIORef h
>                        c (Cons x $ varSrc h)

> varBuffer :: a -> Buffering a
> varBuffer a f g = do
>   c <- newIORef a
>   forkIO $ forward (varCoSnk c) f 
>   varSrc c g

> swpBuffering :: (forall a. Buffering a) -> Snk b -> CoSnk b
> swpBuffering f s = f (dnintro' s)

CoSnk ~ Src ~ ⊗
CoSrc ~ Snk ~ ⅋


Related Work
============


\citet{bernardy_composable_2015}


Future Work
===========

Beyond Haskell: native support for linear types. Even classical!


Conclusion
==========
