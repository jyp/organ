% A Classical Approach to IO Streaming

 <!--

> {-# LANGUAGE ScopedTypeVariables, TypeOperators, RankNTypes, LiberalTypeSynonyms #-}
> module Organ where
> import System.IO
> import Control.Exception
> import Control.Concurrent (forkIO, readChan, writeChan, Chan, newChan)
> import Control.Applicative hiding (empty)
> import Data.IORef
> import Prelude hiding (tail)

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

As \citet{hughes_functional_1989} famously noted, the stength of
functional programming languages lie in the composition mechanisms
that they provide. That is, simple components can be built and
understood in isolation; one does not need to worry about interference
effects when composing them. In particular, lazy evaluation affords to
contruct complex programs by pipelining simple list transformation
functions. Indeed, strict evaluation forces to fully reify each
intermediate result between each computational step, while lazy
evaluation allows to run all the computations concurrently, often
without ever allocating a single intermediate result in full.

Unfortunately, lazy evaluation suffers from two drawbacks. First, it
does not extend nicely to effectful processing. That is, if (say) an
input list is produced by reading a file lazily, one is exposed to
losing referential transparency (as Kiselyov has shown). In practice,
when using lazy IO, the point when a resource will be released depends
on what happens in the context.

(In particular, exception handling is hard to get right.) 
This context-dependency means that the compositionality principle cherished and touted by
Hughes is lost.

TODO: on this simple program it's not clear when (or if) the input stream is going to be closed.

http://stackoverflow.com/questions/296792/haskell-io-and-closing-files

> main = failure
> 
> func = do
>   input <- hGetContents stdin
>   writeFile "test1.txt" (unlines $ take 3 $ lines input)

> failure = do
>   func
>   func

The second issue with lazy evaluation is its memory behaviour. When
composing list-processing functions f and g, one always hopes that the
intermediate list will not be allocated. Unfortunately, this does not
necessarily happen. Indeed, the production pattern of g must match the
consumption pattern of f, otherwise buffering must occur. In practice,
this means that a seemingly innocuous change in either of the function
definitions may drastically change the memory behaviour of the
composition. Again, the compositionality principle breaks down (if one
cares about memory behaviour).

In this paper, we propose to tackle both of these problems, by means
of a new representation for streams of data, and a convention on how
to use streams. The convention to respect is linearity. In fact, the
ideas presented in this paper are heavily inspired by study of
Girards' linear logic \cite{girard_linear_1987}, and one way to read
this paper is as an advocacy for linear types support in Haskell.

First. TODO

Second.
Using our solution, the composition of two stream processors is
guaranteed not to allocate more memory than the sum of its components.
If the stream behaviours do not match, the types will not match
either. It will however be possible to add explicit buffering, which
will adjust the types:

\begin{spec} h = f . buffer . g \end{spec}


The contributions of this paper are

* a re-interpretation of coroutine-based effectful computing, based on
a computational interpretation of linear logic, and

* a Haskell library built on this approach. Besides supporting the
compositionality principle as outlined above, it features two novel
aspects:

  1. A more lightweight design than state-of-the-art co-routine based
    libraries, affored by the linearity convention.

  2. Support for explicit buffering and control structures, while
    still respecting compositionality.

TODO: outline

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

However, because we work with an intuitionistic language (Haskell), we
do not have this equality.  However, we can come close enough.

First, double negations can always be introduced, using the
\var{shift} operator.

> shift :: a -> NN a
> shift x k = k x

Second, it is possible to remove double negations, but only if an
effect can be outputted.  Equivalently, triple negations can be
collapsed to a single one:

> unshift :: N (NN a) -> N a
> unshift k x = k (shift x)

The above two functions are the \var{return} and \var{join} of the
double negation monad. However, we will not be using this monadic
structure anywhere in the following. Indeed, single negations play a
central role in our approach, and the monadic struture is a mere
diversion.


Streams
=======

As it should be clear by now, we embrace the principle of
duality. This approach is refected in the design of the streaming
library: we will not only have a type for sources of data but also a
type for sinks. For example, a simple stream processor reading from a
single source and writing to a single sink will be given the following
type:

\begin{spec}
simple :: Source a -> Sink a -> Eff
\end{spec}

We will make sure that \var{Sink} is the negation of a source (and vice
versa), and thus the type of the above program may equivalently have
been written as follows:

\begin{spec}
simple :: Source a -> Source a
\end{spec}

However, having explicit access to \var{Sink}s allows us to (for example)
dispatch a single source to mulitiple sinks. The presence of both
types will also make us familiar with duality, which will be crucial
in the later sections.

We will define sources and sinks by mutual recursion. Producing a
source means to select if there we are out of data (\var{Nil}) or some
more is available (\var{Cons}). If there is data, one must
then produce a data item and *consume* a sink.


> data Source' a   = Nil   | Cons a  (N (Sink' a))
> data Sink' a     = Full  | Cont    (N (Source' a))

Producing a sink means to select if one can accept more elements
(\var{Cont}) or not (\var{Full}). In the former case, one must then be
able to consume a source. The \var{Full} case is useful when the sink
closes early, for example when it encounters an exception.

Note that, in order to produce (or consume) the next element, the
source (or sink) must handle the effects generated by the other side
of the stream before proceeding. This means that each production is
matched by a consumption, and \textit{vice versa}.

Linearity
---------

For streams to be used safely, one cannot discard nor duplicate them,
for otherwise effects may be discarded and duplicated, which is
dangerous.  Indeed, the same file could be closed twice, or not at
all.  For example, the last action of a sink will typically be closing
the file. This can be guaranteed only if the actions are run until
reaching the end of the pipe (either \var{Full} or \var{Nil}).

We first define an effectful type as a type which mentions \var{Eff}
in its definition. We say that a variable with an effectful type is
itself effectful.

The linearity convention is then respected iff:

1. No effectful variable may not be duplicated or shared. In
particular, if passed as an argument to a function it may not be used
again.

2. Every effectful variable must be consumed (or passed to a function, which
will be in charged of consuming it).

3. A type variable α can be instantiated to an effectful type only if
it occurs in an effecful type. (For example it is ok to construct
Source (Source a), because Source is already effectful).


In this paper, the linearity convention is enforced by manual
inspection. Manual inspection is unreliable, but fortunately
implementing a linearity checker is straightforward.


Basics
------

We present a few basic combinators for \var{Source'} and \var{Sink'}.

One can forward the data from a source to a sink, as follows. The
effect generated by this operation is the combined effect of all
productions and consumptions on the stream.

> fwd :: Source' a -> Sink' a -> Eff
> fwd s (Cont s') = s' s
> fwd Nil Full = return ()
> fwd (Cons _ xs) Full = xs Full

One can send data to a sink. If the sink is full, the data is ignored.
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
same set of variables.  Indeed, this condition is often satisfied.


Baking in negations
-------------------

However, programming with Source' and Sink' is inherently
continuation-heavy: negations must be explicitly added in many places.
Therefore, we will use instead pre-negated versions of sources and sink:

> type Src a = N (Sink' a)
> type Snk a = N (Source' a)

These definitions have the added advantage to perfect the duality
between sources and sinks. Indeed, a negated \var{Sink'} cannot be converted
to a \var{Source'}.

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


Furthermore, both \var{Src} and \var{Snk} are functors and \var{Src}
is a monad. The instances are somewhat involved, so we'll defer them
to TODO. (Monad is a bit suspicious due to linearity) We will instead
show how to implement more concrete functions for Src and Snk.

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

The implementation follows the pattern introduced above: \var{mapSrc}
and \var{mapSnk} are defined by mutual recursion.

> mapSrc _ src Full = src Full
> mapSrc f src (Cont s)
>   = src (Cont (mapSnk f s))

> mapSnk _ snk Nil = snk Nil
> mapSnk f snk (Cons a s)
>   = snk (Cons (f a) (mapSrc f s))


\var{Src} is a monad (!!! Linearity !!!)

> appendSnk :: Snk a -> Snk a -> Snk a
> appendSnk s1 s2 Nil = s1 Nil >> s2 Nil
> appendSnk s1 s2 (Cons a s) 
>   = s1 (Cons a (forwardThenSrc s2 s))

> forwardThenSrc :: Snk a -> Src a -> Src a
> forwardThenSrc s2 s Full = forward s s2
> forwardThenSrc s2 s (Cont s')
>   = s (Cont (appendSnk s' s2))

> appendSrc :: Src a -> Src a -> Src a
> appendSrc s1 s2 Full = s1 Full >> s2 Full
> appendSrc s1 s2 (Cont s)
>   = s1 (Cont (forwardThenSnk s s2))

> forwardThenSnk :: Snk a -> Src a -> Snk a
> forwardThenSnk snk src Nil = forward src snk
> forwardThenSnk snk src (Cons a s)
>   = snk (Cons a (appendSrc s src))

> concatSrcSrc :: Src (Src a) -> Src a
> concatSrcSrc ss Full = ss Full
> concatSrcSrc ss (Cont s)
>   = ss (Cont (concatSnkSrc s))

> concatSnkSrc :: Snk a -> Snk (Src a)
> concatSnkSrc snk Nil = snk Nil
> concatSnkSrc snk (Cons src s)
>   = src (Cont (concatAux snk s))

> concatAux :: Snk a -> Src (Src a) -> Snk a
> concatAux snk ssrc Nil = snk Nil >> ssrc Full
> concatAux snk ssrc (Cons a s)
>   = snk (Cons a (appendSrc s (concatSrcSrc ssrc)))


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

Implementing multipexing on co-sources is straightforward, given
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

Compared to \var{fileSrc}, the difference is that this function can
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

When converting a \var{Src} to a \var{CoSrc} (or dually \var{CoSnk} to a \var{Snk}), we have
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

> flipSnk :: (Snk a -> Snk a) -> Src a -> Src a
> flipSnk f s s' = shiftSrc s (f (flip fwd s'))

> swapBuffer :: Buffering -> Snk b -> CoSnk b
> swapBuffer f s = f (dnintro' s)

> bufferedDmux :: CoSrc a -> CoSrc a -> Src a
> bufferedDmux s1 s2 t = do
>   c <- newChan
>   forkIO $ forward (chanCoSnk c) s1
>   forkIO $ forward (chanCoSnk c) s2
>   chanSrc c t


Application: chat server
========================

Here is the implementation of a chat server with two clients:

> type Client a = (CoSrc a, Snk a)



Everything sent to this sink will be sent to both arg. sinks.

> collapseSnk :: Snk a -> Snk a -> Snk a
> collapseSnk t1 t2 Nil = t1 Nil >> t2 Nil
> collapseSnk t1 t2 (Cons x xs)
>   =  t1  (Cons x $ \c1 ->
>      t2  (Cons x $ \c2 ->
>          shiftSrc xs (collapseSnk  (flip fwd c1)
>                                    (flip fwd c2))))


> server :: Client a -> Client a -> Eff
> server (i1,o1) (i2,o2) = forward  (bufferedDmux i1 i2)
>                                   (collapseSnk o1 o2)

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

> parse :: P s a -> Src s -> Src a
> parse p0 src snk = shiftSrc src (scan p0 (flip fwd snk))
>  where
>   scan :: P s a -> Snk a -> Snk s
>   scan (Result res p) ret        xs     = ret (Cons res (parse p $ fwd xs))
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


> zipSrc :: Src a -> Src b -> Src (a,b)
> zipSrc s1 s2 = unshiftSrc (\t -> unzipSnk t s1 s2)

> unzipSnk :: Snk (a,b) -> Src a -> Src b -> Eff
> unzipSnk sab ta tb =
>   shiftSrc ta $ \ta' ->
>   case ta' of
>     Nil -> tb Full >> sab Nil
>     Cons a as ->  shiftSrc tb $ \tb' ->  case tb' of
>       Nil -> as Full >> sab Nil
>       Cons b bs -> forward (cons (a,b) $ zipSrc as bs) sab

> unzipSrc :: Src (a,b) -> Snk a -> Snk b -> Eff
> unzipSrc sab ta tb = shiftSrc sab $ \sab' ->
>   case sab' of
>     Nil -> tb Nil >> ta Nil
>     Cons (a,b) xs -> ta $ Cons a $ \sa ->
>                      tb $ Cons b $ \sb ->
>                      unzipSrc xs
>                               (flip fwd sa)
>                               (flip fwd sb)
 

> zipSnk :: Snk a -> Snk b -> Snk (a,b)
> zipSnk sa sb Nil = sa Nil >> sb Nil
> zipSnk sa sb (Cons (a,b) tab) = sa $ Cons a $ \sa' ->
>                                 sb $ Cons b $ \sb' ->
>                                 shiftSnk (zipSnk (flip fwd sa') (flip fwd sb')) tab
> 
> scanSrc :: (a -> b -> b) -> b -> Src a -> Src b
> scanSrc f z src Full = src Full
> scanSrc f z src (Cont s) = src $ Cont $ scanSnk f z s
> 
> scanSnk :: (a -> b -> b) -> b -> Snk b -> Snk a
> scanSnk f z snk Nil = snk Nil
> scanSnk f z snk (Cons a s) = snk $ Cons next $ scanSrc f next s
>   where next = f a z

Return the last element of the source, or the first argument if the
source is empty.

> lastSrc :: a -> Src a -> NN a
> lastSrc x s k = shiftSrc s $ \s' -> case s' of
>   Nil -> k x
>   Cons x' cs -> lastSrc x' cs k

> dropSrc :: Int -> Src a -> Src a
> dropSrc _ s Full = s Full
> dropSrc 0 s (Cont s') = s (Cont s')
> dropSrc i s (Cont s') = s (Cont (dropSnk i s'))
 
> dropSnk :: Int -> Snk a -> Snk a
> dropSnk 0 s (Cons a s') = s (Cons a s')
> dropSnk 0 s Nil = s Nil
> dropSnk i s Nil = s Nil
> dropSnk i s (Cons a s') = s' (Cont (dropSnk (i-1) s))
 
> enumFromToSrc :: Int -> Int -> Src Int
> enumFromToSrc b e Full = return ()
> enumFromToSrc b e (Cont s)
>   | b > e     = s Nil
>   | otherwise = s (Cons b (enumFromToSrc (b+1) e))

> linesSrc :: Src Char -> Src String
> linesSrc s Full = s Full
> linesSrc s (Cont s') = s (Cont $ unlinesSnk s')
 
> unlinesSnk :: Snk String -> Snk Char
> unlinesSnk = unlinesSnk' []

> unlinesSnk' :: String -> Snk String -> Snk Char
> unlinesSnk' acc s Nil = s (Cons acc empty)
> unlinesSnk' acc s (Cons '\n' s') = s (Cons (reverse acc) (linesSrc s'))
> unlinesSnk' acc s (Cons c s') = s' (Cont $ unlinesSnk' (c:acc) s)

> untilSnk :: (a -> Bool) -> Snk a
> untilSnk p Nil = return ()
> untilSnk p (Cons a s)
>   | p a  = s Full
>   | True = s (Cont (untilSnk p))

> interleave :: Src a -> Src a -> Src a
> interleave s1 s2 Full = s1 Full >> s2 Full
> interleave s1 s2 (Cont s) = s1 (Cont (interleaveSnk s s2))

> interleaveSnk :: Snk a -> Src a -> Snk a
> interleaveSnk snk src Nil = forward src snk
> interleaveSnk snk src (Cons a s) = snk (Cons a (interleave s src))

> tee :: Src a -> Snk a -> Src a
> tee s1 t1 = flipSnk (collapseSnk t1) s1



Table of primitive functions (implementable by reference to IO, may break syncronicity)

Related Work
============


* "Conduits"
* "Pipes"

* Iteratees \cite{kiselyov_iteratees_2012}

> type ErrMsg = String
> data Stream el = EOF (Maybe ErrMsg) | Chunk [el]
> 
> data Iteratee el m a = IE_done a
>                           | IE_cont (Maybe ErrMsg)
>                                     (Stream el -> m (Iteratee el m a, Stream el))
>

http://johnlato.blogspot.se/2012/06/understandings-of-iteratees.html

*  \cite{kiselyov_lazy_2012}

\begin{spec}
type GenT e m = ReaderT (e -> m ()) m
--   GenT e m a  = (e -> m ()) -> m a
type Producer m e = GenT e m ()
type Consumer m e = e -> m ()
type Transducer m1 m2 e1 e2 = Producer m1 e1 -> Producer m2 e2
\end{spec}

* FeldSpar modadic streams

Feldspar, a DSL for digital signal processing, has a notion of streams
built on monads \citet{svenningsson15:monadic_streams}. In Haskell
the stream type can be written as follows:

\begin{spec}
type Stream a = IO (IO a)
\end{spec}

Intuitively the outer monad can be understood as performing
initialization which creates the inner monadic computation. The inner
computation is called iteratively to produce the elements of the
stream.

Compared to the representation in the present paper, the monadic
streams only has one form of stream, corresponding to a source. Also,
there is no support for timely release of resources, such things need
to be dealt with outside of the stream framework.

* Push/Pull

\citet{bernardy_composable_2015}

push arrays paper

but idea can be traced back to Jackson 75

via http://www.balisage.net/Proceedings/vol3/html/Kay01/BalisageVol3-Kay01.html#d28172e501

* Linear Types

Wadler 12, Pfenning and Caires.

Stream is the direct translation of a linear type for a stream protocol:

Source a = 1 ⊕ (a ⊗ N (Sink a))
Sink a = 1 ⊕ N (Source a)


Future Work
===========

Beyond Haskell: native support for linear types. Even classical!


Conclusion
==========

* In particular, we show that mismatch in duality correspond to
buffers and control structures, depending on the kind of mismatch.


* Cast an new light on coroutine-based io by drawing inspiration from
classical linear logic. Emphasis on polarity and duality.


\acks

The source code for this paper is a literate Haskell file, available
at this url: TODO. The paper is typeset using pandoc, lhs2TeX and
latex.

ScratchPad
==========


> data a + b = Inl a | Inr b
> data One = TT
> type Church f = forall x. (f x -> x) -> x
> newtype ChurchSrc' a = CS (forall x. ((One + (a, N (One + N x))) -> x) -> x)
> type ChurchSnk a = N (ChurchSrc' a)
> type ChurchSrc a = NN (ChurchSrc' a)

> -- forall x. (One + N (One + (a, N x))) -> x

> emptyCh :: ChurchSrc a
> emptyCh k = k $ CS $ \k' -> k' (Inl TT)

