% A Classical Approach to IO Streaming

 <!--

> {-# LANGUAGE ScopedTypeVariables, TypeOperators, RankNTypes #-}
> module Organ where
> import System.IO
> import Control.Exception
> import Control.Concurrent (forkIO, readChan, writeChan, Chan, newChan)
> import Control.Applicative hiding (empty)
> import Data.IORef
> import Prelude hiding (tail)
> import Control.Monad.Reader

-->

\begin{abstract}
We present an alternative paradigm for IO in Haskell.

- based on continuations
- linear type-checking helps programmer ensure program correctness

Application: stream processing

- API for allocation-free stream processing
- with escape hatch
- making parallelism opportunities explicit
\end{abstract}

\category{D.1.1}{Applicative (Functional) Programming}{}
\category{D.3.3}{Language Constructs and Features}{Coroutines}

 <!-- general terms are not compulsory anymore, you may leave them out 

\terms
term1, term2

 -->

\keywords
Streams, Continuations, Linear Types

Introduction
============

Problem:
* Lazy IO Problem (Ref Kiselyov et al.)
* An actual issue in practice: lazy IO tends to leave files open, etc.

TODO: better example?

> main = failure
> 
> func = do
>   input <- hGetContents stdin
>   writeFile "test1.txt" (unlines $ take 3 $ lines input)

> failure = do
>   func
>   func

Contributions.

* Provide a simplified design for coroutine-based IO

* Modularity

* Cast an new light on coroutine-based io by drawing inspiration from
classical linear logic. Emphasis on polarity and duality.

* In particular, we show that mismatch in duality correspond to
buffers and control structures, depending on the kind of mismatch.

Approach.

A pipe can be accessed through both ends, explicitly.

    Source -->  Program --> Sink

Solution to the example. API?


The ideas presented in this paper are heavily inspired by study of
Girards' linear logic \cite{girard_linear_1987}. One way to read this
paper is as an advocacy for linear types support in Haskell.

Paper outline.

* New design for coroutine-based io

Preliminary: negations and continuations
========================================

In this section we recall the basics of continuation-based
programming. Readers familiar with continuations only need to read
this section to pick up our notation.

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

TODO: flow

> dnintro :: Src a -> Src (NN a)
> dnintro = mapSrc shift

> dndel' :: Snk (NN a) -> Snk a
> dndel' = mapSnk shift

> dndel :: Src (NN a) -> Src a
> dndel s Full = s Full
> dndel s (Cont k) = s $ Cont $ dnintro' k

> dnintro' :: Snk a -> Snk (NN a)
> dnintro' k Nil = k Nil
> dnintro' k (Cons x xs) = x $ \x' -> k (Cons x' $ dndel xs)



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

However, calling await may break linearity, so we will refrain to use
\var{match} in the following.


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

> copyFile :: FilePath -> FilePath -> Eff
> copyFile source target = forward  (fileSrc source)
>                                   (fileSnk target)

It should be emphasised at this point that reading and writing will be
interleaved: in order to produce the next file line (in the source),
the current line must be consumed by writing it to disk (in the sink).
The stream behaves fully synchronously, and no intermediate data is
buffered.

When the sink is full, the source connected to it should be finalized.
The next example shows what happens when a sink closes the stream
early. Instead of connecting the source to a full sink, we connect it
to one which stops receiving input after three lines.

> read3Lines :: Eff
> read3Lines = forward  (hFileSrc stdin)
>                       (takeSnk 3 $ fileSnk "text.txt")

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
>          mx <- catch  (Just <$> hGetLine h)
>                       (\(_ :: IOException) -> return Nothing)
>          case mx of
>            Nothing -> c Nil
>            Just x -> c (Cons x $ hFileSrcSafe h)

Exceptions raised in hIsEOF should be handled in a similar same way,
as well as those raised in a file sink.

Algebraic structure
-------------------

Sources are functors, while sinks are contravariant functors:

> mapSrc :: (a -> b) -> Src a -> Src b
> mapSnk :: (b -> a) -> Snk a -> Snk b

The implementation follows the pattern introduced above: mapSrc and
mapSnk are defined by mutual recursion.

> mapSrc _ src Full = src Full
> mapSrc f src (Cont s) = src (Cont (mapSnk f s))

> mapSnk _ snk Nil = snk Nil
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


Synchronicity and Asynchronicity
================================

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


> mux0 :: Src a -> Src b -> Src (Either a b)
> mux0 sa sb tab = error "impossible"


Try to begin by reading on a source. However, if we do this, the
choice falls to us to choose which source to run first. We may pick
sa, while it is blocking and sb is ready with data. This is not
satisfactory situation.

Can we let the choice fall on the consumer?

> type a & b = N (Either (N a) (N b))

> mux1 :: Src a -> Src b -> Src (a & b)

 This helps, but we still can't implement the multiplexer.

> mux1 sa sb (Cont tab) = tab $ Cons
>                         (\ab -> case ab of
>                                  Left a -> sa $ Cont $ \(Cons a' rest) -> a a')
>                         (error "rest out of scope")

Indeed the shape of the recursive call (second argument to Cons) must
depend on the choice made by the consumer (first argument of
Cons). However the type of Cons forces us to produce its arguments
independently.

What we need to do is to reverse the control fully: we need a data
source which behaves like a sink on the outside.

Co-Sources, Co-Sinks
-------------------

The structure we are looking for are co-sources. Which we study in this section.

Remembering that producing $N a$ is equivalent to consuming $a$, we
define:

> type CoSrc a = Snk (N a)
> type CoSnk a = Src (N a)

Implementing mutlipexing on co-sources is straightforward, given
demultiplexing on sources:

> mux' :: CoSrc a -> CoSrc b -> CoSrc (a & b)
> mux' sa sb = unshiftSnk $ \tab -> dmux' (dndel tab) sa sb


We use the rest of the section to study the property of co-sources and
co-sinks.

CoSrc is a functor, and CoSnk is a contravariant functor.

> mapCoSrc :: (a -> b) -> CoSrc a -> CoSrc b
> mapCoSrc f = mapSnk (\b' -> \a -> b' (f a))

> mapCoSnk :: (b -> a) -> CoSnk a -> CoSnk b
> mapCoSnk f = mapSrc (\b' -> \a -> b' (f a))


One access elements of a co-source only "one at a time". One cannot
extract the contents of a co-source as a list.

> toList' :: CoSrc a -> NN [a]
> toList' k1 k2 = k1 $ Cons (error "N a?") (error "rest")
> toList' k1 k2 = k2 $ (error "a?") : (error "rest")
> toList' k1 k2 = error "impossible"

Yet it is possible to define useful and effectful co-sources and
co-sinks. The first example is providing a file as a co-source:

> coFileSrc :: Handle -> CoSrc String
> coFileSrc h Nil = hClose h
> coFileSrc h (Cons x xs) = do
>   e <- hIsEOF h
>   if e then do
>          hClose h
>          xs Full
>        else do
>          x =<< hGetLine h          -- (1)
>          xs $ Cont $ coFileSrc h   -- (2)

Compared to fileSrc, the difference is that this function can
decide the ordering of effects. That is, the effects (1) and (2) have
no data dependency. Therefore they may be run in any order, including
concurrently.


The second example is a co-sink which sends its contents to a file.

> coFileSink :: Handle -> CoSnk String
> coFileSink h Full = hClose h
> coFileSink h (Cont c) = c (Cons  (hPutStrLn h)
>                                  (coFileSink h))

Compared to fileSnk, the difference is that one does not control the
order of execution of effects. The effect of writing the current line
is put in a data structure, and its execution is up to the source
which one will eventually connect to the sink.

In sum, using co-sources and co-sinks shifts the flow of control from
the sink to the source. It should be stressed that, in the programs
which use the functions defined so far (and treats \var{Eff} as an
abstract type otherwise) synchronicity is preserved. The next section
generalises.

Asynchronicity
--------------

We have seen so far that synchronicity gives useful guarantees, but
restricts the kind of programs one can write. In this section, we will
provide primitives which allow forms of asynchronous programming using
our framework.

The main benefit of sticking to our framework in this case is that
asynchronous behaviour is cornered to explicit usage of these
primitives. That is, the benefits of synchronous programming still
hold locally.

\paragraph{Concurrency}

When converting a Src to a CoSrc (or dually CoSnk to a Snk), we have
two streams which are ready to respond to pulling of data from them.
This means that concurrency opportunities arise, as we have seen an
example above when manually converting the file source to a file
co-source.

In general, given a concurrency strategy, we can implement the above
conversions:

> srcToCoSrc :: Strategy a -> Src a -> CoSrc a
> coSnkToSnk :: Strategy a -> CoSnk a -> Snk a

We define a strategy as the reconciliation between a source and a
co-sink:

> type Strategy a = Source' a -> Source' (N a) -> Eff

Implementing the conversions is then straightforward:

> srcToCoSrc strat k s0 = k $ Cont $ \ s1 -> strat s1 s0
> coSnkToSnk strat k s0 = k $ Cont $ \ s1 -> strat s0 s1

There are (infinitely) many possible concurrency strategies, however
we think that one will mostly be using either of the following two.
The simplest one (used in \var{coFileSrc}) is sequential execution,
and is defined by looping through both sources and match the
consumptions/productions elementwise.

> sequentially :: Strategy a
> sequentially Nil (Cons _ xs) = xs Full
> sequentially (Cons _ xs) Nil = xs Full
> sequentially (Cons x xs) (Cons x' xs') = do
>   x' x
>   (shiftSrc xs  $ \sa ->
>    shiftSrc xs' $ \sna ->
>    sequentially sa sna)

Another possible strategy is concurrent execution. This strategy is
useful if one expects production or consumption of elements to be
expensive and distributable over computation units.

> concurrently :: Strategy a
> concurrently Nil (Cons _ xs) = xs Full
> concurrently (Cons _ xs) Nil = xs Full
> concurrently (Cons x xs) (Cons x' xs') = do
>   forkIO $ x' x
>   (shiftSrc xs  $ \sa ->
>    shiftSrc xs' $ \sna ->
>    concurrently sa sna)

The above implementation naively spawns a thread for every element,
but in reality one will most likely want to divide the stream into
chunks before spawning threads. Because strategies are separate
components, if it turns out that a bad choice was made it is easy to
swap a strategy for another.

\paragraph{Buffering}

Consider now the situation where one needs to convert from a CoSrc to
a Src (or from a Snk to a CoSnk).  Here, we have two streams which
want to control the execution flow. The conversion can only be
implemented by running both streams in concurrent threads, and have
them communicate via a form of buffer. A form of buffer that we have
seen before is the file. Using it yields the following buffering
implementation:

> fileBuffer :: CoSrc String -> Src String
> fileBuffer f g = do
>   h' <- openFile  "tmp" WriteMode
>   forkIO $ forward (coFileSink h') f
>   h <- openFile "tmp" ReadMode
>   hFileSrc h g

If the temporary file is a regular file, the above implementation is
likely to fail. For example the reader may be faster than the writer
and reach an end of file prematurely. Thus the temporary file should
be a UNIX pipe. Yet, one may prefer to use Concurrent Haskell channels
as a buffering means:

> chanCoSnk :: Chan a -> CoSnk a
> chanCoSnk h Full = return ()
> chanCoSnk h (Cont c) = c (Cons  (writeChan h)
>                                 (chanCoSnk h))

> chanSrc :: Chan a -> Src a
> chanSrc h Full = return ()
> chanSrc h (Cont c) = do  x <- readChan h
>                          c (Cons x $ chanSrc h)

> chanBuffer :: CoSrc a -> Src a
> chanBuffer f g = do
>   c <- newChan
>   forkIO $ forward (chanCoSnk c) f
>   chanSrc c g

In certain situations (for example for a stream yielding mouse
positions), one may want to ignore all but the latest datum. In this
case a single memory reference can serve as buffer:

> varCoSnk :: IORef a -> CoSnk a
> varCoSnk h Full      = return ()
> varCoSnk h (Cont c)  = c (Cons  (writeIORef h)
>                                 (varCoSnk h))

> varSrc :: IORef a -> Src a
> varSrc h Full = return ()
> varSrc h (Cont c) = do  x <- readIORef h
>                         c (Cons x $ varSrc h)

> varBuffer :: a -> CoSrc a -> Src a
> varBuffer a f g = do
>   c <- newIORef a
>   forkIO $ forward (varCoSnk c) f
>   varSrc c g

All the above bufferings work on sources, but they can be generically
inverted to work on sinks, as follows.

> type Buffering = forall a. CoSrc a -> Src a

> swap' :: (Snk a -> Snk a) -> Src a -> Src a
> swap' f s s' = shiftSrc s (f (flip fwd s'))

> swap :: Buffering -> Snk b -> CoSnk b
> swap f s = f (dnintro' s)

> bufferedDmux :: CoSrc a -> CoSrc a -> Src a
> bufferedDmux s1 s2 t = do
>   c <- newChan
>   forkIO $ forward (chanCoSnk c) s1
>   forkIO $ forward (chanCoSnk c) s2
>   chanSrc c t

> type Client a = (CoSrc a, Snk a)


Everything sent to this sink will be sent to both arg. sinks.

> collapseSnk :: Snk a -> Snk a -> Snk a
> collapseSnk t1 t2 Nil = t1 Nil >> t2 Nil
> collapseSnk t1 t2 (Cons x xs) = t1 (Cons x $ \c1 -> t2 (Cons x $ \c2 -> shiftSrc xs (collapseSnk (flip fwd c1) (flip fwd c2))))

> tee :: Src a -> Snk a -> Src a
> tee s1 t1 = swap' (collapseSnk t1) s1

> server :: Client a -> Client a -> Eff
> server (i1,o1) (i2,o2) = forward (bufferedDmux i1 i2) (collapseSnk o1 o2)

Application: Stream-Based Parsing
=================================

TODO

Parsing processes

> data P s res  =  Sym (Maybe s -> P s res)
>               |  Fail
>               |  Result res (P s res)

Another kind of continuations here.

> newtype Parser s a = P (forall res. (a -> P s res) -> P s res)

> instance Monad (Parser s) where
>   return x  = P $ \fut -> fut x
>   P f >>= k = P (\fut -> f (\a -> let P g = k a in g fut))

> P p <|> P q = P (\fut -> best (p fut) (q fut))

> best :: P s a -> P s a -> P s a
> best Fail x = x
> best x Fail = x
> best (Result res x) y = Result res (best x y)
> best x (Result res y) = Result res (best x y)
> best (Sym k1) (Sym k2) = Sym (\s -> best (k1 s) (k2 s))

> longestResultSnk :: forall a s. P s a -> N (Maybe a) -> Snk s
> longestResultSnk p0 ret = scan p0 Nothing
>  where
>   scan :: P s a -> Maybe a -> Snk s
>   scan (Result res p)  _         xs     = scan p (Just res) xs
>   scan Fail           mres       xs     = ret mres >> fwd xs Full
>   scan (Sym f)        mres       xs     = case xs of
>     Nil        -> scan (f Nothing) mres Nil
>     Cons x cs  -> forward cs (scan (f $ Just x) mres)

> results :: P s a -> Src s -> Src a
> results p0 src snk = shiftSrc src (scan p0 (flip fwd snk))
>  where
>   scan :: P s a -> Snk a -> Snk s
>   scan (Result res p) ret        xs     = ret (Cons res (results p $ fwd xs))
>   scan Fail           ret        xs     = ret Nil >> fwd xs Full
>   scan (Sym f)        mres       xs     = case xs of
>     Nil        -> scan (f Nothing) mres Nil
>     Cons x cs  -> forward cs (scan (f $ Just x) mres)







Summary
=======

produce Src if you can, CoSrc if you must.
produce CoSnk if you can, Snk if you must.

consume CoSrc if you can, Src if you must.
consume Snk if you can, CoSnk if you must.


             Src                  Snk
            CoSnk                CoSrc
       Easy to consume          Easy to produce
        Try to produce          Try  to consume

Table of transparent functions (implementable without reference to IO, preserving syncronicity)

Table of primitive functions (implementable by reference to IO, may break syncronicity)

Related Work
============


* \citet{bernardy_composable_2015}
* "Conduits"
* "Pipes"

* Iteratees \cite{kiselyov_iteratees_2012}

> type ErrMsg = String
> data Stream el = EOF (Maybe ErrMsg) | Chunk [el]
> 
> data Iteratee el m a = IE_done a
>                           | IE_cont (Maybe ErrMsg)
>                                     (Stream el -> m (Iteratee el m a, Stream el))

*  \cite{kiselyov_lazy_2012}

> type GenT e m = ReaderT (e -> m ()) m
> --   GenT e m a  = (e -> m ()) -> m a
> type Producer m e = GenT e m ()
> type Consumer m e = e -> m ()
> type Transducer m1 m2 e1 e2 = Producer m1 e1 -> Producer m2 e2

* FeldSpar modadic streams

TODO: Josef

* Push/Pull

http://www.balisage.net/Proceedings/vol3/html/Kay01/BalisageVol3-Kay01.html#d28172e501


Future Work
===========

Beyond Haskell: native support for linear types. Even classical!


Conclusion
==========


\acks

The source code for this paper is a literate Haskell file, available
at this url: TODO. The paper is typeset using pandoc, lhs2TeX and
latex.
