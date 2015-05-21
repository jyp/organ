---
title: Push Streams, Pull Streams
subtitle: How Can Linear Types Help to Solve the Lazy IO Problem?
...

 <!--

Possible titles:

- A Linear approach to streaming
- Push and Pull Streams

> {-# LANGUAGE ScopedTypeVariables, TypeOperators, RankNTypes, LiberalTypeSynonyms, BangPatterns, TypeSynonymInstances, FlexibleInstances  #-}
> module Organ where
> import System.IO
> import Control.Exception
> import Control.Concurrent (forkIO, readChan, writeChan, Chan, newChan)
> import Control.Applicative hiding (empty)
> import Data.IORef
> import Data.Monoid
> import Prelude hiding (tail)
> -- import Control.Monad

-->

\begin{abstract}
In this paper, we present a novel stream-programming library for
Haskell.  As other coroutine-based stream libraries, our library
allows synchronous execution, which implies that effects are run in
lockstep and no buffering occurs.

A novelty of our implementation is that it allows to locally introduce
buffering or re-scheduling of effects. The buffering requirements (or
re-scheduling opportunities) are indicated by the type-system.

Our library is based on a number of design principles, adapted from
the theory of Girard's Linear Logic. These principles are applicable
to the design of any Haskell structure where resource management
(memory, IO, ...) is critical.
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

As \citet{hughes_functional_1989} famously noted, the strength of
functional programming languages lie in the composition mechanisms
that they provide. That is, simple components can be built and
understood in isolation; one does not need to worry about interference
effects when composing them. In particular, lazy evaluation affords to
construct complex programs by pipelining simple list transformation
functions. Indeed, while strict evaluation forces to fully reify each
intermediate result between each computational step, lazy
evaluation allows to run all the computations concurrently, often
without ever allocating more that a single intermediate element at a time.

Unfortunately, lazy evaluation suffers from two drawbacks.  First, it
has unpredictable memory behavior. Consider the following function
composition:

\begin{spec}
f :: [a] -> [b]
g :: [b] -> [c]
h = g . f
\end{spec}

One hopes that, at run-time, the intermediate list ($[b]$)
will only be allocated element-wise, as outlined above. Unfortunately,
this desired behavior does not necessarily happen. Indeed, a
necessary condition is that the production pattern of $f$ matches the
consumption pattern of $g$; otherwise buffering occurs. In practice,
this means that a seemingly innocuous change in either of the function
definitions may drastically change the memory behavior of the
composition, without warning. If one cares about memory behavior,
this means that the compositionality principle touted by Hughes breaks
down.

Second, lazy evaluation does not extend nicely to effectful
processing. That is, if (say) an input list is produced by reading a
file lazily, one is exposed to losing referential transparency (as
\citet{kiselyov_lazy_2013} has shown). For example, one may rightfully
expect\footnote{This expectation is expressed in a
Stack Overflow question, accessible at this URL:
http://stackoverflow.com/questions/296792/haskell-io-and-closing-files
} that both following programs have the same behavior:

\begin{spec}
main = do  inFile <- openFile "foo" ReadMode
           contents <- hGetContents inFile
           putStr contents
           hClose inFile

main = do  inFile <- openFile "foo" ReadMode
           contents <- hGetContents inFile
           hClose inFile
           putStr contents
\end{spec}

Indeed, the \var{putStr} and \var{hClose} commands act on unrelated
resources, and thus swapping them should have no observable effect.
However, while the first program prints the `foo` file, the second one
prints nothing.  Indeed, because \var{hGetContents} reads the file
lazily, the \var{hClose} operation has the effect to truncate the
list. In the first program, printing the contents force reading the
file. One may argue that \var{hClose} should not be called in the
first place --- but then, closing the handle happens only when the
\var{contents} list can be garbage collected (in full), and relying on
garbage collection for cleaning resources is brittle; furthermore
this effect compounds badly with the first issue discussed above.  If
one wants to use lazy effectful computations, again, the
compositionality principle is lost.

In this paper, we propose to tackle both of these issues by mimicking
the computational behavior of Girard's linear logic
\cite{girard_linear_1987} in Haskell. In fact, one way to read this
paper is as an advocacy for linear types support in Haskell. While
Kiselyov's *iteratees* (\citeyear{kiselyov_iteratees_2012}) already
solves the issues described above, our grounding in linear logic
allows us to support more stream programs, as we discuss below.

We introduce two types, \var{Src} and \var{Snk}, for solving the two
problems above. These two types denote streams that
produce and consume elements respectively. Composing functions
on such streams is guaranteed not to allocate more memory than the sum
of its components. Translating the first code example above would
look as follows:

\begin{spec}
f :: Src a -> Src b
g :: Src b -> Src c
h = g . f
\end{spec}

Second, closing of resources is reliable, even in the presence of
exceptions. Printing a file can thus implemented as follows:

TODO: leftover stdOut sink?

> main = fileSrc "foo" `fwd` stdoutSnk

where the various library functions have the following types:

\begin{spec}
stdoutSnk :: Snk String
fileSrc :: FilePath -> Src String
fwd :: Src a -> Snk a -> IO ()
\end{spec}

The type \var{Snk} stands for a data sink, and \var{fwd} forwards data
from a source to a sink.  The above type signatures reveal a first
improvement of our approach over Kiselyov's: we natively support both
sources and sinks. In itself this may appear to be a superficial
advantage.  However, duality is fundamental in our work: the existence
of both sources and sinks is based on support for two kinds of
streams: pull streams and push streams, while Kiselyov's iteratees are
heavily geared towards pull streams. Push streams control the flow of
computation, while pull stream respond to it. We support in particular
data sources with push-flavour, called co-sources.  This is useful for
example when a source needs precise control over the execution of
effects it embeds (sec Sec. \ref{async}). For example, sources cannot
be unzipped, but co-sources can.

In a program which uses both sources and co-sources, the need might
arise to compose a function producing a co-source with a program
consuming a source: this is the situation where list-based programs
would silently cause memory allocation. In our approach, this
situation is caught by the type system, and the user must explicitly
conjure a buffer to be able to write the composition:

\begin{spec}
f :: Src a -> CoSrc b
g :: Src b -> Src c
h = g . buffer . f
\end{spec}

The contributions of this paper are

* The formulation of principles for compositional resource-aware
programming in Haskell (resources include memory and files). The
principles are linearity, duality, and polarization. While borrowed
from linear logic, as far as we know they have not been applied to
Haskell programming before.

* An embodiment of the above principles, in the form of a Haskell
library for streaming `IO`. Besides supporting compositionality as
outlined above, our library features two concrete novel aspects:

  1. A more lightweight design than state-of-the-art co-routine based
    libraries.

  2. Support for explicit buffering and control structures, while
    still respecting compositionality.

\paragraph{Outline} The rest of the paper is structured as follows.
In Sec. \ref{negations}, we recall the notions of continuations in presence of effects.
In Sec. \ref{streams}, we present our design for streams, and justify it by appealing to linearity principles.
In Sec. \ref{effect-free}, we give an API to program with streams, and analyze their algebraic structure.
In Sec. \ref{effectful}, we show how to embed IO into streams.
In Sec. \ref{async}, we discuss polarity mismatch.
Related work and future work are discussed respectively in sections \ref{related-work} and \ref{future-work}.
We conclude in Sec. \ref{conclusion}.



Preliminary: negation and continuations
=======================================
\label{negations}

In this section we recall the basics of continuation-based
programming. Readers familiar with continuations only need to read
this section to pick up our notation.

We begin by assuming a type of effects \var{Eff}. For users of the
stream library, this type should remain an abstract monoid. However in
this paper we will develop concrete effectful streams, and this is
possible only if we pick a concrete type of effects. Because we will
provide streams interacting with files and other operating-system
resources, we must pick $\var{Eff} = \var{IO} ()$, and ensure that
\var{Eff} can be treated as a monoid.

> type Eff = IO ()

> instance Monoid Eff where
>   mempty = return ()
>   mappend = (>>)

We can then define negation as follows:

> type N a = a -> Eff

A shortcut for double negations is also convenient.

> type NN a = N (N a)

The basic idea (imported from classical logic) pervading this paper
is that producing a result of type α is equivalent to consuming an
argument of type $N α$. Dually, consuming an argument of type α is
equivalent to producing a result of type $N α$. In this paper we call
these equivalences the duality principle.

In classical logic, negation is involutive; that is:
$\var{NN}\,a = a$
However, because we work within Haskell, we
do not have this equality.  We can come close enough though.
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
double negation monad\footnote{for \var{join}, substitute $N\,a$ for
$a$}; indeed adding a double negation in the type corresponds to
sending the return value to its consumer. However, we will not be
using this monadic structure anywhere in the following. Indeed, single
negations play a central role in our approach, and the monadic
structure is a mere diversion.



Streams
=======
\label{streams}

Our guiding design principle is duality. This principle is reflected in
the design of the streaming library: we will not only have a type for
sources of data but also a type for sinks. For example, a simple
stream processor reading from a single source and writing to a single
sink will be given the following type:

\begin{spec}
simple :: Src a -> Snk a -> Eff
\end{spec}

We will make sure that \var{Snk} is the negation of a source (and vice
versa), and thus the type of the above program may equivalently have
been written as follows:

\begin{spec}
simple :: Src a -> Src a
\end{spec}

However, having explicit access to sinks allows us to (for example)
dispatch a single source to multiple sinks, as in the following type signature:
\begin{spec}
forkSrc :: Src (a,b) -> Snk a -> Snk b -> Eff
\end{spec}
Familiarity with duality will be crucial in the later sections of this paper.

We define sources and sinks by mutual recursion. Producing a
source means to select if some more is available (\var{Cons}) or not
(\var{Nil}). If there is data, one must then produce a data item and
*consume* a sink.

> data Source  a   = Nil   | Cons a  (N (Sink    a))
> data Sink    a   = Full  | Cont    (N (Source  a))

Producing a sink means to select if one can accept more elements
(\var{Cont}) or not (\var{Full}). In the former case, one must then be
able to consume a source. The \var{Full} case is useful when the sink
bails out early, for example when it encounters an exception.

Note that, in order to produce (or consume) the next element, the
source (or sink) must handle the effects generated by the other side
of the stream before proceeding. This means that each production is
matched by a consumption, and \textit{vice versa}.

Linearity
---------

For streams to be used safely, one cannot discard nor duplicate them,
for otherwise effects may be discarded and duplicated, which is
dangerous.  For example, the same file could be closed twice, or not
at all.  Indeed, the last action of a sink will typically be closing
the file. Timely closing of the sink can only be guaranteed if the
actions are run until reaching the end of the pipe (either \var{Full}
or \var{Nil}). In the rest of the section we precisely define the condition
that programs need to respect in order to safely use our streams.

We first notion that we need to define is that of an effectful type.
A type is deemed effectful iff it mentions \var{Eff} in its
definition. We say that a variable with an effectful type is itself
effectful.

The linearity convention is then respected iff:

1. No effectful variable may be duplicated or shared. In
particular, if passed as an argument to a function it may not be used
again.

2. Every effectful variable must be consumed (or passed to a function, which
will be in charged of consuming it).

3. A type variable α can be instantiated to an effectful type only if
it occurs in an effectful type. (For example it is OK to construct
$\var{Src}\,(\var{Src}\,a)$, because $\var{Src}\, α$ is already effectful).


In this paper, the linearity convention is enforced by manual
inspection. Manual inspection is unreliable, but weather the linearity
convention is respected can be algorithmically decided. (See
sec. \ref{future})


Basics
------

We begin by presenting three basic function to manipulate
\var{Source} and \var{Sink}: one to read from sources, one to write
to sinks, and one to connect sources and sinks.

\paragraph{Reading}
One may want to provide the following function, waiting for data to be
produced by a source. The second argument is the effect to run if no
data is produced, and the third is the effect to run given the data
and the remaining source.

> await :: Source a -> Eff -> (a -> Source a -> Eff) -> Eff
> await Nil eof _ = eof
> await (Cons x cs) _ k = cs $ Cont $ \xs -> k x xs

However, the above function breaks the linearity invariant, so we will
refrain to use it as such. The pattern that it defines is still
useful: it is valid when the second and third argument consume the
same set of variables.  Indeed, this condition is often satisfied.

\paragraph{Writing}
One can send data to a sink. If the sink is full, the data is ignored.
The third argument is a continuation getting the "new" sink, that
obtained after the "old" sink has consumed the data.

> yield :: a -> Sink a -> (Sink a -> Eff) -> Eff
> yield x (Cont c) k = c (Cons x k)
> yield _ Full k = k Full

\paragraph{Forwarding}
One can forward the data from a source to a sink, as follows. The
effect generated by this operation is the combined effect of all
productions and consumptions on the stream.

> forward :: Source a -> Sink a -> Eff
> forward s (Cont s') = s' s
> forward Nil Full = mempty
> forward (Cons _ xs) Full = xs Full




Baking in negations: exercise in duality
-------------------

Programming with \var{Source} and \var{Sink} explicitly is
inherently continuation-heavy: negations must be explicitly added in
many places. This style is somewhat inconvenient; therefore, we will
use instead pre-negated versions of sources and sink:

> type Src   a = N  (Sink a)
> type Snk   a = N  (Source a)

These definitions have the added advantage to perfect the duality
between sources and sinks, while not restricting the programs one can
write.
Indeed, one can access the underlying structure as follows:

> onSource   :: (Src  a -> t) -> Source   a -> t
> onSink     :: (Snk  a -> t) -> Sink     a -> t

> onSource  f   s = f   (\t -> forward s t)
> onSink    f   t = f   (\s -> forward s t)


And, while a negated \var{Sink} cannot be converted to a
\var{Source}, all the following conversions are implementable:

> unshiftSnk :: N (Src a) -> Snk a
> unshiftSrc :: N (Snk a) -> Src a
> shiftSnk :: Snk a -> N (Src a)
> shiftSrc :: Src a -> N (Snk a)

> unshiftSnk = onSource
> unshiftSrc = onSink
> shiftSnk k kk = kk (Cont k)
> shiftSrc k kk = k (Cont kk)

A different reading of the type of \var{shiftSrc} reveals that it implements
forwarding of data from \var{Src} to \var{Snk}:

> fwd :: Src a -> Snk a -> Eff
> fwd = shiftSrc

In particular, one can flip sink transformers to obtain source transformers,
and vice versa.

> flipSnk :: (Snk a -> Snk b) -> Src b -> Src a
> flipSnk f s = shiftSrc s . onSink f

> flipSrc :: (Src a -> Src b) -> Snk b -> Snk a
> flipSrc f t = shiftSnk t . onSource f


Flipping allows to choose the most convenient direction to
implement, and get the other one for free. Consider as an example the
implementation of the mapping functions:

> mapSrc  :: (a -> b) -> Src  a -> Src  b
> mapSnk  :: (b -> a) -> Snk  a -> Snk  b

Mapping sources is defined by flipping mapping of sinks:

> mapSrc f = flipSnk (mapSnk f)

Sink mapping is defined by case analysis on the concrete
source, and the recursive case conveniently calls \var{mapSrc}.

> mapSnk _ snk Nil = snk Nil
> mapSnk f snk (Cons a s)
>   = snk (Cons (f a) (mapSrc f s))


When using double negations, it is sometimes useful to insert or
remove them inside type constructor. For sources and sinks, one proceeds
as follows. Introduction of double negation in sources and its elimination
in sinks is a special case of mapping.

> dnintro :: Src a -> Src (NN a)
> dnintro = mapSrc shift

> dndel' :: Snk (NN a) -> Snk a
> dndel' = mapSnk shift

The duals are easily implemented by case analysis, following the mutual
recursion pattern introduced above.

> dndel :: Src (NN a) -> Src a
> dnintro' :: Snk a -> Snk (NN a)

> dndel = flipSnk dnintro'
> dnintro' k Nil = k Nil
> dnintro' k (Cons x xs) = x $ \x' -> k (Cons x' $ dndel xs)


Effect-Free Streams
===================
\label{effect-free}

The functions seen so far make no use of the fact that \var{Eff} can
embed IO actions. In fact, a large number of useful functions over
streams can be implemented without relying on IO. We give an overview
of effect-free streams in this section.

List-Like API
-------------

To begin, we show that one can implement a list-like API for
sources, as follows:

> empty :: Src a
> empty sink' = forward Nil sink'

> cons :: a -> Src a -> Src a
> cons a s s' = yield a s' s

> tail :: Src a -> Src a
> tail = flipSnk $ \t s -> case s of
>   Nil -> t Nil
>   Cons _ xs -> fwd xs t

(Taking just the head is not meaningful due to the linearity
constraint)

Dually, the full sink is simply

> plug :: Snk a
> plug source' = forward source' Full


 <!--

  A bit ugly, and used nowhere.

A non-full sink decides what to do depending on the availability of
data. We could write the following:

> match :: Eff -> (a -> Snk a) -> Snk a
> match nil' cons' k = await k nil' cons'

However, calling \var{await} may break linearity, so we will instead use
\var{match} in the following.
-->

Another useful function is the equivalent of \var{take} on lists.
Given a source, we can create a new source which ignores all but its
first $n$ elements. Conversely, we can prune a sink to consume only
the first $n$ elements of a source.

> takeSrc  :: Int -> Src  a -> Src  a
> takeSnk  :: Int -> Snk  a -> Snk  a

The natural implementation is again by mutual recursion. The main
subtlety is that, when reaching the $n$th element, both ends of the
stream must be notified of its closing. Note the use of the monoidal
structure of \var{Eff} in this case.

> takeSrc i = flipSnk (takeSnk i)

> takeSnk _ s Nil = s Nil
> takeSnk 0 s (Cons _ s') = s Nil <> s' Full
> takeSnk i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))


Algebraic structure
-------------------

Sources and sinks are instances of several common algebraic
structures, yielding a rich API to program using them.

\paragraph{Monoid} Source and sinks form a monoid under concatenation:

> instance Monoid (Src a) where
>   mappend = appendSrc
>   mempty = empty

> instance Monoid (Snk a) where
>   mappend = appendSnk
>   mempty = plug

We have already encountered the units (\var{empty} and \var{plug});
the appending operations are defined below.  Intuitively,
\var{appendSrc} first gives control to the first source until it runs
out of elements and then turns control over to the second source. This
behavior is implemented in the helper function \var{forwardThenSnk}.

> appendSrc :: Src a -> Src a -> Src a
> appendSrc s1 s2 Full = s1 Full <> s2 Full
> appendSrc s1 s2 (Cont s)
>   = s1 (Cont (forwardThenSnk s s2))

> forwardThenSnk :: Snk a -> Src a -> Snk a
> forwardThenSnk snk src Nil = fwd src snk
> forwardThenSnk snk src (Cons a s)
>   = snk (Cons a (appendSrc s src))

Sinks can be appended is a similar fashion.

> appendSnk :: Snk a -> Snk a -> Snk a
> appendSnk s1 s2 Nil = s1 Nil <> s2 Nil
> appendSnk s1 s2 (Cons a s)
>   = s1 (Cons a (forwardThenSrc s2 s))

> forwardThenSrc :: Snk a -> Src a -> Src a
> forwardThenSrc s2 = flipSnk (appendSnk s2)

The operations \var{forwardThenSnk} and \var{forwardThenSrc} are akin
to making the difference of sources and sinks, thus we find it
convenient to give them the following aliases:

> (-?) :: Snk a -> Src a -> Snk a
> t -? s = forwardThenSnk t s

> (-!) :: Snk a -> Src a -> Src a
> t -! s = forwardThenSrc t s

> infixr -!
> infixl -?

Appending and differences interact in the expected way: the following
equalities hold.

\begin{spec}
t -? (s1 <> s2) == t -? s2 -? s1
(t1 <> t2) -! s == t1 -! t2 -! s
\end{spec}

 <!--

Not sure if these are true or what

> prop_diff3 t1 t2 s = (t1 <> t2) -? s == t1 -? (t2 -! s)
> prop_diff4 t s1 s2 = t -! (s1 <> s2) == (t -? s1) -! s2

 -->

The proofs for the above laws can be found in Appendix \ref{proof}.

\paragraph{Functor}
We have already seen the mapping functions for sources and sinks:
sources are functors and sinks are contravariant functors. (Given the
implementation of the morphism actions it is straightforward to check
the functor laws.)

\paragraph{Monad}

Besides, \var{Src} is a monad. The unit is trivial. The join operation
is the concatenation of sources:

> concatSrcSrc :: Src (Src a) -> Src a

Concatenation is defined using the two auxiliary functions
\var{concatSnkSrc} and \var{concatAux}. The function
\var{concatSnkSrc} transforms a sink such that it no longer just consumes elements, but sequences of elements in the form of sources. All of these sources are to be fed into the
sink, one after the other. Appending all the sources together happens
in \var{concatAux}.

> concatSrcSrc = flipSnk concatSnkSrc

> concatSnkSrc :: Snk a -> Snk (Src a)
> concatSnkSrc snk Nil = snk Nil
> concatSnkSrc snk (Cons src s)
>   = src (Cont (concatAux snk s))

> concatAux :: Snk a -> Src (Src a) -> Snk a
> concatAux snk ssrc Nil = snk Nil <> ssrc Full
> concatAux snk ssrc (Cons a s)
>   = snk (Cons a (appendSrc s (concatSrcSrc ssrc)))

(The monad laws can be proved by mutual induction, using a pattern
similar to the monoid laws.)

\paragraph{Comonad?}

Given the duality between sources and sinks, and the fact that sources
are monads, it might be tempting to draw the conclusion that sinks are
comonads. This is not the case. To see why, consider that every
comonad has a counit, which, in the case for sinks, would have the
following type

\begin{spec}
Snk a -> a
\end{spec}

There is no way to implement this function since sinks do not store
elements so that they can be returned. Sinks consume elements rather
than producing them.

\paragraph{Divisible and Decidable}

 <!--

> data Void

> class Contravariant f where
>   contramap :: (b -> a) -> f a -> f b


\begin{spec}
instance Contravariant Snk where
  contramap = mapSnk
\end{spec}


> sinkToSnk :: Sink a -> Snk a
> sinkToSnk Full Nil = return ()
> sinkToSnk Full (Cons a n) = n Full
> sinkToSnk (Cont f) s = f s

-->

If sinks are not comonads, are there some other structures that they
implement? The package contravariant on hackage gives two classes;
\var{Divisible} and \var{Decidable}, which are subclasses of
\var{Contravariant}, a class for contravariant functors \citep{kmett_contravariant}. They are
defined as follows:

> class Contravariant f => Divisible f where
>   divide :: (a -> (b, c)) -> f b -> f c -> f a
>   conquer :: f a

The method \var{divide} can be seen as a dual of \var{zipWith} where
elements are split and fed to two different sinks.

\begin{spec}
instance Divisible Snk where
  divide div snk1 snk2 Nil = snk1 Nil <> snk2 Nil
  divide div snk1 snk2 (Cons a ss) =
    snk1 (Cons b $ \ss1 ->
    snk2 (Cons c $ \ss2 ->
    shiftSnk (divide div (sinkToSnk ss1)
                         (sinkToSnk ss2)) ss))
    where (b,c) = div a

  conquer = plug
\end{spec}

By using \var{divide} it is possible to split data and feed it to several
sinks. Producing and consuming elements still happens in lock-step;
both sinks consume their respective elements before the source gets to
produce a new element. The \var{conquer} method is a unit for \var{divide}.

The class \var{Decidable} has the methods \var{lose} and \var{choose}:

> class Divisible f => Decidable f where
>   choose :: (a -> Either b c) -> f b -> f c -> f a
>   lose :: (a -> Void) -> f a

The function \var{choose} can split up a sink so that some elements
go to one sink and some go to another.

\begin{spec}
instance Decidable Snk where
  choose choice snk1 snk2 Nil = snk1 Nil <> snk2 Nil
  choose choice snk1 snk2 (Cons a ss)
    | Left b <- choice a = snk1 (Cons b $ \snk1' ->
      shiftSnk (choose choice (sinkToSnk snk1') snk2) ss)
  choose choice snk1 snk2 (Cons a ss)
    | Right c <- choice a = snk2 (Cons c $ \snk2' ->
      shiftSnk (choose choice snk1 (sinkToSnk snk2')) ss)

  lose f Nil = return ()
  lose f (Cons a ss) = ss (Cont (lose f))
\end{spec}

Table of effect-free functions
------------------------------

The above gives already an extensive API for sources and sinks, many
more useful effect-free functions can be implemented on this basis. We
give here a menu of functions that we have implemented, and whose
implementation is available in the appendix.

Zip two sources, and the dual.

> zipSrc :: Src a -> Src b -> Src (a,b)
> forkSnk :: Snk (a,b) -> Src a -> Snk b

 <!--
or: forkSnk :: Snk (a,b) -> Snk a ⅋ Snk b
-->

Zip two sinks, and the dual.

> forkSrc :: Src (a,b) -> Snk a -> Src b
> zipSnk :: Snk a -> Snk b -> Snk (a,b)

Equivalent of \var{scanl'} for sources, and the dual

> scanSrc :: (b -> a -> b) -> b -> Src a -> Src b
> scanSnk :: (b -> a -> b) -> b -> Snk b -> Snk a

Equivalent of \var{foldl'} for sources, and the dual.

> foldSrc' :: (b -> a -> b) -> b -> Src a -> NN b
> foldSnk' :: (b -> a -> b) -> b -> N b -> Snk a

Drop some elements from a source, and the dual.

> dropSrc :: Int -> Src a -> Src a
> dropSnk :: Int -> Snk a -> Snk a

Convert a list to a source, and vice versa.

> fromList :: [a] -> Src a
> toList :: Src a -> NN [a]

Split a source in lines, and the dual.

> linesSrc :: Src Char -> Src String
> unlinesSnk :: Snk String -> Snk Char


Consume elements until the predicate is reached; then the sink is
closed.

> untilSnk :: (a -> Bool) -> Snk a

Interleave two sources, and the dual.

> interleave :: Src a -> Src a -> Src a
> interleaveSnk :: Snk a -> Src a -> Snk a

Forward data coming from the input source to the result source and to
the second argument sink.

> tee :: Src a -> Snk a -> Src a

Filter a source, and the dual.

> filterSrc :: (a -> Bool) -> Src a -> Src a
> filterSnk :: (a -> Bool) -> Snk a -> Snk a

Turn a source of chunks of data into a single source; and the dual.

> unchunk :: Src [a] -> Src a
> chunkSnk :: Snk a -> Snk [a]


App: Stream-Based Parsing
-------------------------

To finish with effect-free function, we give an example of a complex
stream processor, which turns source of unstructured data into a
source of structured data, given a parser.  This conversion is useful
for example to turn an XML file, provided as a stream of characters
into a stream of (opening and closing) tags.

We begin by defining a pure parsing structure, modeled after the
parallel parsing processes of \citet{claessen_parallel_2004}.  The
parser is continuation based, but the effects being accumulated are
parsing processes, defined as follows. The \var{Sym} constructor parses \var{Just}
a symbol, or \var{Nothing} if the end of stream is reached. A process may
also \var{Fail} or return a \var{Result}.

> data P s res  =  Sym (Maybe s -> P s res)
>               |  Fail
>               |  Result res

A parser is producing the double negation of $a$:

> newtype Parser s a = P (forall res. (a -> P s res) -> P s res)

The monadic interface can then be built in the standard way:

> instance Monad (Parser s) where
>   return x  = P $ \fut -> fut x
>   P f >>= k = P (\fut -> f (\a -> let P g = k a in g fut))

The essential parsing ingredient, choice, rests on the
ability to weave processes together; picking that which
succeeds first, and that which fails as last resort:

> weave :: P s a -> P s a -> P s a
> weave Fail x = x
> weave x Fail = x
> weave (Result res) y = Result res
> weave x (Result res) = Result res
> weave (Sym k1) (Sym k2)
>     = Sym (\s -> weave (k1 s) (k2 s))

> (<|>) :: Parser s a -> Parser s a -> Parser s a
> P p <|> P q = P (\fut -> weave (p fut) (q fut))


Parsing then reconciles the execution of the process with the
traversal of the source. In particular, whenever a result is
encountered, it is fed to the sink. If the parser fails, both ends of
the stream are closed.

> parse :: forall s a. Parser s a -> Src s -> Src a
> parse q@(P p0) = flipSnk $ scan $ p0 $ \x -> Result x
>  where
>   scan :: P s a -> Snk a -> Snk s
>   scan (Result res  )  ret        xs     = ret
>                                            (Cons res $ parse q $ forward xs)
>   scan Fail            ret        xs     = ret Nil <> forward xs Full
>   scan (Sym f)         mres       xs     = case xs of
>     Nil        -> scan (f Nothing) mres Nil
>     Cons x cs  -> fwd cs (scan (f $ Just x) mres)




Effectful streams
=================
\label{effectful}

So far, we have constructed only effect-free streams. That is, effects
could be any monoid, and in particular the unit type.  In this
section we bridge this gap and provide some useful sources and sinks
performing IO effects, namely reading and writing to files.

We first define the following helper function, which sends data to a
handle, thereby constructing a sink.

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

And the sink for standard output is:

> stdoutSnk :: Snk String
> stdoutSnk = hFileSnk stdout

(For ease of experimenting with our functions, the data items are
lines of text --- but an industrial variant would provide chunks of
raw binary data, to be further parsed.)

Conversely, a file source reads data from a file, as follows:

> hFileSrc :: Handle -> Src String
> hFileSrc h Full = hClose h
> hFileSrc h (Cont c) = do
>   e <- hIsEOF h
>   if e   then   do  hClose h
>                     c Nil
>          else   do  x <- hGetLine h
>                     c (Cons x $ hFileSrc h)

> fileSrc :: FilePath -> Src String
> fileSrc file sink = do
>   h <- openFile file ReadMode
>   hFileSrc h sink

Combining the above primitives, we can then implement file copy as
follows:

> copyFile :: FilePath -> FilePath -> Eff
> copyFile source target = fwd  (fileSrc source)
>                               (fileSnk target)

It should be emphasized at this point that when running \var{copyFile} reading and writing will be
interleaved: in order to produce the next line in the source (in this
case by reading from the file), the current line must first be
consumed in the sink (in this case by writing it to disk).  The stream
behaves fully synchronously, and no intermediate data is buffered.

Whenever a sink is full, the source connected to it should be finalized.
The next example shows what happens when a sink closes the stream
early. Instead of connecting the source to a bottomless sink, we
connect it to one which stops receiving input after three lines.

> read3Lines :: Eff
> read3Lines = fwd  (hFileSrc stdin)
>                   (takeSnk 3 $ fileSnk "text.txt")

Indeed, testing the above program reveals that it properly closes
\var{stdin} after reading three lines. This early closing of sinks
allows modular stream programming. In particular, it is easy to
support proper finalization in the presence of exceptions, as the next
section shows.

Exception Handling
------------------

While the above implementations of file source and sink are fine for
illustrative purposes, their production-strength versions should
handle exceptions. Doing so is straightforward: as shown above, our
sinks and sources readily support early closing of the stream.

The following code fragment shows how to handle an exception when
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

Exceptions raised in \var{hIsEOF} should be handled in the same
way, as well as those raised in a file sink; we leave this simple
exercise to the reader.

In an industrial-strength implementation, one would probably have a
field in both the \var{Nil} and \var{Full} constructors indicating the
nature of the exception encountered, if any, but we will not bother in the
proof of concept implementation presented in this paper.




Synchronicity and Asynchronicity
================================
\label{async}

One of the main benefits of streams as defined here is that the
programming interface is (or appears to be) asynchronous, while the
run-time behavior is synchronous.
That is, one can build a data source regardless of how the data is be consumed,
or dually one can build a sink regardless of how the data is produced;
but, despite the independence of definitions, all the code can (and
is) executed synchronously: composing a source and a sink require no
concurrency (nor any external control structure).

As discussed above, a consequence of synchronicity is that the
programmer cannot be implicitly buffering data when connecting a source
to a sink: every production must be matched by a consumption (and vice
versa).  In sum, synchronicity restricts the kind of operations one
can construct, in exchange for two guarantees:

1. Execution of connected sources and sinks is synchronous
2. No implicit memory allocation happens

While the guarantees have been discussed so far, it may be unclear how
synchronicity actually restricts the programs one can write. In the
rest of the section we show by example how the restriction plays out.

Example: demultiplexing
-----------------------

One operation supported by synchronous behavior is the demultiplexing
of a source, by connecting it to two sinks.

> dmux' :: Src (Either a b) -> Snk a -> Snk b -> Eff

We can implement this demultiplexing operation as follows:

> dmux :: Source (Either a b) -> Sink a -> Sink b -> Eff
> dmux Nil ta tb = forward Nil ta <> forward Nil tb
> dmux (Cons ab c) ta tb = case ab of
>   Left a -> c $ Cont $ \src' -> case ta of
>     Full -> forward Nil tb <> plug src'
>     Cont k -> k (Cons a $ \ta' -> dmux src' ta' tb)
>   Right b -> c $ Cont $ \src' -> case tb of
>     Full -> forward Nil ta <> plug src'
>     Cont k -> k (Cons b $ \tb' -> dmux src' ta tb')

> dmux' sab' ta' tb' =
>   shiftSnk ta' $ \ta ->
>   shiftSnk tb' $ \tb ->
>   shiftSrc sab' $ \sab ->
>   dmux sab ta tb

The key ingredient is that demultiplexing starts by reading the next
value available on the source. Depending on its value, we feed the
data to either of the sinks are proceed. Besides, as soon as any of
the three parties closes the stream, the other two are notified.

However, multiplexing sources cannot be implemented while respecting
synchronicity. To see why, let us attempt anyway, using the following
type signature:

\begin{spec}
mux :: Src a -> Src b -> Src (Either a b)
mux sa sb = ?
\end{spec}

We can try to fill the hole by reading on a source. However, if we do
this, the choice falls to the multiplexer to choose which source to
run first. We may pick \var{sa}, however it may be blocking, while
\var{sb} is ready with data. This is not really multiplexing, at best
this approach would give us interleaving of data sources, by taking
turns.

In order to make any progress, we can let the choice of which source
to pick fall on the consumer of the stream. The type that we need for
output data in this case is a so-called additive conjunction. It is
the dual of the \var{Either} type: there is a choice, but this choice
falls on the consumer rather than the producer of the data. Additive
conjunction, written &, can be encoded by sandwiching \var{Either}
between two inversion of the control flow, thus switching the party
who makes the choice:

> type a & b = N (Either (N a) (N b))

(One will recognize the similarity between this definition and the
De Morgan's laws.)

We can then amend the type of multiplexing:

> mux :: Src a -> Src b -> Src (a & b)

Unfortunately, we still cannot implement multiplexing typed as
above. Consider the following attempt, where we begin by asking the
consumer if it desires $a$ or $b$. If the answer is $a$,
we can extract a value from \var{sa} and yield it; and
symmetrically for $b$.

> mux sa sb (Cont tab) = tab $ Cons
>                         (\ab -> case ab of
>                                  Left   ka -> sa $ Cont $ \(Cons a resta) -> ka a
>                                  Right  kb -> sb $ Cont $ \(Cons b restb) -> kb b)
>                         (error "oops")

However, there is no way to then make a recursive call (`oops`) to
continue processing.  Indeed the recursive call to make must depend on
the choice made by the consumer (in one case we should be using
\var{resta}, in the other \var{restb}). However the type of \var{Cons}
forces us to produce its arguments independently.

What we need to do is to reverse the control fully: we need a data
source which is in control of the flow of execution.

Co-Sources, Co-Sinks
-------------------

We call the structure that we are looking for a
*co-source*. Co-sources are the subject of this section.  Remembering
that producing $N a$ is equivalent to consuming $a$, thus a sink of $N
a$ is a (different kind of) source of $a$. We define:

> type CoSrc a = Snk (N a)
> type CoSnk a = Src (N a)

Implementing multiplexing on co-sources is then straightforward, by
leveraging \var{dmux'}:

> mux' :: CoSrc a -> CoSrc b -> CoSrc (a & b)
> mux' sa sb = unshiftSnk $ \tab -> dmux' (dndel tab) sa sb


We use the rest of the section to study the property of co-sources and
co-sinks.

\var{CoSrc} is a functor, and \var{CoSnk} is a contravariant functor.

> mapCoSrc :: (a -> b) -> CoSrc a -> CoSrc b
> mapCoSrc f = mapSnk (\b' -> \a -> b' (f a))

> mapCoSnk :: (b -> a) -> CoSnk a -> CoSnk b
> mapCoSnk f = mapSrc (\b' -> \a -> b' (f a))

Elements of a co-source are access only "one at a time". That is, one
cannot extract the contents of a co-source as a list. Attempting to
implement this extraction looks as follows.

> coToList :: CoSrc a -> NN [a]
> coToList k1 k2 = k1 $ Cons (\a -> k2 [a]) (error "rest") -- (1)
> coToList k1 k2 = k2 $ (error "a?") : (error "rest")      -- (2)

If one tries to begin by eliminating the co-source (1), then there is no
way to produce subsequent elements of the list. If one tries to begin
by constructing the list (2), then no data is available.

Yet it is possible to define useful and effectful co-sources and
co-sinks. The first example shows how to provide a file as a co-source:

> coFileSrc :: Handle -> CoSrc String
> coFileSrc h Nil = hClose h
> coFileSrc h (Cons x xs) = do
>   e <- hIsEOF h
>   if e then do
>          hClose h
>          xs Full
>        else do
>          x' <- hGetLine h
>          x x'                     -- (1)
>          xs $ Cont $ coFileSrc h  -- (2)


Compared to \var{fileSrc}, the difference is that this function can
decide the ordering of effects run a co-sink connected to it. That is,
the lines (1) and (2) have no data dependency. Therefore they may be
run in any order. (Blindly doing so is a bad idea though, as the
\var{Full} action on the sink will be run before all other actions.)
We will see in the next section how this situation generalizes.

The second example is a infinite co-sink that sends data to a file.

> coFileSink :: Handle -> CoSnk String
> coFileSink h Full = hClose h
> coFileSink h (Cont c) = c (Cons  (hPutStrLn h)
>                                  (coFileSink h))

Compared to \var{fileSnk}, the difference is that one does not control
the order of execution of effects. The effect of writing the current
line is put in a data structure, and its execution is up to the
co-source which eventually connects to the co-sink. Thus, the
order of writing lines in the file depends on the order of effects chosen
in the co-source connected to this co-sink.

In sum, using co-sources and co-sinks shifts the flow of control from
the sink to the source. It should be stressed that, in the programs
which use the functions defined so far (even those that use IO),
synchronicity is preserved: no data is buffered implicitly, and
reading and writing are interleaved.

Asynchronicity
--------------

We have seen so far that synchronicity gives useful guarantees, but
restricts the kind of programs one can write. In this section, we
provide primitives which allow forms of asynchronous programming within
our framework.
The main benefit of sticking to our framework in this case is that
asynchronous behavior is cornered to the explicit usages of these
primitives. That is, the benefits of synchronous programming still
hold locally.

\paragraph{Scheduling}

When converting a \var{Src} to a \var{CoSrc} (or dually \var{CoSnk} to
a \var{Snk}), we have two streams which are ready to respond to
pulling of data from them.  This means that effects must be scheduled
explicitly, as we have seen an example above when manually converting
the file source to a file co-source.

In general, given a \var{Schedule}, we can implement the above two
conversions:

> srcToCoSrc :: Schedule a -> Src a -> CoSrc a
> coSnkToSnk :: Schedule a -> CoSnk a -> Snk a

We define a \var{Schedule} as the reconciliation between a source and a
co-sink:

> type Schedule a = Source a -> Source (N a) -> Eff

Implementing the conversions is then straightforward:

> srcToCoSrc strat s s0 = shiftSrc s $ \ s1 -> strat s1 s0
> coSnkToSnk strat s s0 = shiftSrc s $ \ s1 -> strat s0 s1

What are possible scheduling strategies? The simplest, and most
natural one is sequential execution: looping through both sources and
match the consumptions/productions element-wise, as follows.

> sequentially :: Schedule a
> sequentially Nil (Cons _ xs) = xs Full
> sequentially (Cons _ xs) Nil = xs Full
> sequentially (Cons x xs) (Cons x' xs') =
>   x' x <>   (shiftSrc xs  $ \sa ->
>              shiftSrc xs' $ \sna ->
>              sequentially sa sna)

When effects are arbitrary IO actions, sequential execution is the
only sensible schedule: indeed, the sources and sinks expect their
effects to be run in the order prescribed by the stream. Swapping the
arguments to `<>` in the above means that \var{Full} effects will be
run first, spelling disaster.

However, in certain cases running effects out of order may make
sense. If the monoid of effects is commutative (or if the programmer
is confident that execution order does not matter), one can shuffle
the order of execution of effects. This re-ordering can be taken
advantage of to run effects concurrently, as follows:

> concurrently :: Schedule a
> concurrently Nil (Cons _ xs) = xs Full
> concurrently (Cons _ xs) Nil = xs Full
> concurrently (Cons x xs) (Cons x' xs') = do
>   forkIO $ x' x
>   (shiftSrc xs  $ \sa ->
>    shiftSrc xs' $ \sna ->
>    concurrently sa sna)

The above strategy is useful if the production or consumption
of elements is expensive and distributable over computation units.
While the above implementation naively spawns a thread for every
element, in reality one will most likely want to divide the stream
into chunks before spawning threads. Because strategies are separate
components, a bad choice is easily remedied to by swapping one
strategy for another.

\paragraph{Buffering}

Consider now the situation where one needs to convert from a
\var{CoSrc} to a \var{Src} (or from a \var{Snk} to a \var{CoSnk}).
Here, we have two streams, both of which want to control the execution
flow. The conversion can only be implemented by running both streams
in concurrent threads, and have them communicate via some form of
buffer. A form of buffer that we have seen before is the file. Using
it yields the following buffering implementation:

> fileBuffer :: String -> CoSrc String -> Src String
> fileBuffer tmpFile f g = do
>   h' <- openFile  tmpFile WriteMode
>   forkIO $ fwd (coFileSink h') f
>   h <- openFile tmpFile ReadMode
>   hFileSrc h g

If the temporary file is a regular file, the above implementation is
likely to fail. For example the reader may be faster than the writer
and reach an end of file prematurely. Thus the temporary file should
be a UNIX pipe. One then faces the issue that UNIX pipes are of fixed
maximum size, and if the writer overshoots the capacity of the pipe, a
deadlock will occur.

Thus, one may prefer to use Concurrent Haskell channels as a buffering
means, as they are bounded only by the size of the memory and do not
rely on any special feature of the operating system:

> chanCoSnk :: Chan a -> CoSnk a
> chanCoSnk _ Full = return ()
> chanCoSnk h (Cont c) = c (Cons  (writeChan h)
>                                 (chanCoSnk h))

> chanSrc :: Chan a -> Src a
> chanSrc _ Full = return ()
> chanSrc h (Cont c) = do  x <- readChan h
>                          c (Cons x $ chanSrc h)

> chanBuffer :: CoSrc a -> Src a
> chanBuffer f g = do
>   c <- newChan
>   forkIO $ fwd (chanCoSnk c) f
>   chanSrc c g

In certain situations (for example for a stream yielding a status
whose history does not matter, like mouse positions) one may want to
ignore all but the latest datum. In this case a single memory cell can
serve as buffer:

> varCoSnk :: IORef a -> CoSnk a
> varCoSnk _ Full      = return ()
> varCoSnk h (Cont c)  = c (Cons  (writeIORef h)
>                                 (varCoSnk h))

> varSrc :: IORef a -> Src a
> varSrc _ Full = return ()
> varSrc h (Cont c) = do  x <- readIORef h
>                         c (Cons x $ varSrc h)

> varBuffer :: a -> CoSrc a -> Src a
> varBuffer a f g = do
>   c <- newIORef a
>   forkIO $ fwd (varCoSnk c) f
>   varSrc c g

All the above buffering operations work on sources, but they can be generically
inverted to work on sinks, as follows.

> flipBuffer :: (forall a. CoSrc a -> Src a) -> Snk b -> CoSnk b
> flipBuffer f s = f (dnintro' s)


Summary
-------

In sum, we can classify streams according to polarity:

- Positive: source and co-sinks
- Negative: sinks and co-sources

We then have three situations when composing stream processors:

1. Matching polarities. In this case behavior is synchronous; no
concurrency appears.

2. Two positives. In this case an explicit loop must process the
streams.  If effects commute, the programmer may run effects out of
order, potentially concurrently.

3. Two negatives. In this case the streams must run in independent
threads, and the programmer needs to make a choice for the communication
buffer. One needs to be careful: if the buffer is to small a deadlock
may occur.

Therefore, when programming with streams, one should consume negative
types when one can, and positive ones when one must. Conversely, one
should produce positive types when one can, and negative ones when one
must.

App: idealized echo server
---------------------

We finish exposition of asynchronous behavior with a small program
sketching the skeleton of a client-server application. This is a small
server with two clients, which echoes the requests of each client to
both of them.

The server communicates with each client via two streams, one for
inbound messages, one for outbound ones. We want each client to be
able to send and receive messages in the order that they like. That
is, from their point of view, they are in control of the message
processing order. Hence a client should have a co-sink for sending
messages to the server, and a source for receiving them.  On the
server side, types are dualized and thus, a client is represented by a
pair of a co-source and a sink:

> type Client a = (CoSrc a, Snk a)

For simplicity we implement a chat server handling exactly two
clients.

The first problem is to multiplex the inputs of the clients. In the
server, we do not actually want any client to be controlling the
processing order. Hence we have to multiplex the messages in real time,
using a channel (note the similarity with \var{chanBuffer}):

> bufferedDmux :: CoSrc a -> CoSrc a -> Src a
> bufferedDmux s1 s2 t = do
>   c <- newChan
>   forkIO $ fwd (chanCoSnk c) s1
>   forkIO $ fwd (chanCoSnk c) s2
>   chanSrc c t

We then have to send each message to both clients. This may be done
using the following effect-free function, which forwards everything
sent to a sink to its two argument sinks.

> collapseSnk :: Snk a -> Snk a -> Snk a
> collapseSnk t1 t2 Nil = t1 Nil <> t2 Nil
> collapseSnk t1 t2 (Cons x xs)
>   =  t1  (Cons x $ \c1 ->
>      t2  (Cons x $ \c2 ->
>          shiftSrc xs (collapseSnk  (flip forward c1)
>                                    (flip forward c2))))


The server can then be defined by composing the above two functions.

> server :: Client a -> Client a -> Eff
> server (i1,o1) (i2,o2) = fwd  (bufferedDmux i1 i2)
>                               (collapseSnk o1 o2)



Related Work
============
\label{related}


Polarities, data structures and control
---------------------------------------

One of keys ideas formalized in this paper is to classify streams by
polarity. The negative polarity (Sinks, CoSrc) controls the execution
thread, whereas the positive one (Sources, Co-sinks) provide
data. This idea has recently been taken advantage of to
bring efficient array programming facilities to functional programming
\citep{bernardy_composable_2015,claessen2012expressive,ankner_edsl_2013}.

This concept is central in the literature on Girard's linear logic
\citep{laurent_etude_2002,zeilberger_logical_2009}. However, in the
case of streams, this idea dates back at least to
\citet{jackson_principles_1975} (\citet{kay_you_2008} gives a good
summary of Jacksons' insight).

Our contribution is to bring this idea to stream programming in
Haskell. (While duality was used for Haskell array programming, it has
not been taken advantage for stream programming.) We believe that our
implementation brings together the practical applications that Jackson
intended, while being faithful to the theoretical foundations in
logic, via the double-negation embedding.


Iteratees
---------

We consider that the state of the art in Haskell stream processing is
embodied by Kiselyov's iteratees \citeyear{kiselyov_iteratees_2012}.


The type for iteratees can be given the following definitions:

> data I s m a = Done a | GetC (Maybe s -> m (I s m a))

An iteratee $I\,s\,m\,a$ roughly corresponds to a sink of $s$ which also
returns an $a$ --- but it uses a monad $m$ rather than a monoid
\var{Eff} for effects.

As far as we understand, the above type is meant to be transparent:
iteratee users may access the continuation in the \var{GetC}
constructor. Therefore, users can in principle discard and duplicate
continuations, thereby potentially duplicating or ignoring effects.
This makes iteratees subject to the same linearity constraint as we
have: a first advantage of our approach is the formulation and
emphasis on the linearity constraint. It appears that variants of
iteratees (including the *pipes* library) make
the representation abstract, but at the cost of a complex interface
for programming them. By stating the linearity requirement no abstract
API is necessary to guarantee safety.

A second advantage of our library is that effects are not required to
be monads. Indeed, the use of continuations already provide the
necessary structure to combine computations (recall in particular
that double negation is already a monad). We believe that having a
single way to bind intermediate results (continuations vs. both
continuations and monads) is a simplification in design, which may make
our library more approachable.

The presence of source and sinks also clarifies how to build complex
types programs from basic blocks. Indeed, iteratee-based libraries
make heavy use of the following types:

> type Enumerator el m a = I el m a -> m (I el m a)
> type Enumeratee elo eli m a =
>         I eli m a -> I elo m (I eli m a)

It is our understanding that these types make up for the lack of explicit
sources by putting iteratees (sinks) on the left-hand-side of an
arrow. Enumerators are advantageously replaced by sources, and
enumeratees by simple functions from source to source (or sink to
sink).


A third advantage of our approach is that the need for buffering (or
the scheduling opportunities) are clearly indicated by the type
system, as mismatching polarities.



In more recent work \citet{kiselyov_lazy_2012} present a
continuation-based pretty printer, which fosters a more stylized used
of continuations, closer to what we advocate here. Producers and
consumers (sources and sinks) are defined more simply, using types
which correspond more directly to negations:

\begin{spec}
type GenT e m = ReaderT (e -> m ()) m
type Producer m e = GenT e m ()
type Consumer m e = e -> m ()
type Transducer m1 m2 e1 e2 =
  Producer m1 e1 -> Producer m2 e2
\end{spec}

Yet, linearity is still not mentioned, the use of a monad rather
than monoid persists, and mismatching polarities are not discussed.

Several production-strength libraries have been built upon the concept
of iteratees, including *pipes* \citep{gonzalez_pipes_2015},
*conduits* \citep{snoyman_conduit_2015} and *machines*
\citep{kmett_machines_2015}.  While we focus our comparison with
iteratees, most of our analysis carries to the production libraries.
There is additionally a large body of non peer-reviewed literature
discussing and analyzing on either iteratees or its variants. The
proliferation of libraries for IO in Haskell indicates that a unifying
foundation for them is needed, and we hope that the present paper
provides a basis for such a foundation.


Feldspar monadic streams
------------------------

Feldspar, a DSL for digital signal processing, has a notion of streams
built on monads \citep{axelsson_feldspar_2010,svenningsson15:monadic_streams}. In Haskell
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
to be dealt with outside of the stream framework. Additionally, even
conceptually effect-free streams rely on running IO effects.

Session Types
-------------

In essence our pair of types for stream is an encoding of a protocol
for data transmission. This protocol is readily expressible using
linear types, following the ideas of \citet{wadler_propositions_2012}
and \citet{caires_concurrent_2012}:

\begin{spec}
Source a = 1 ⊕ (a ⊗ N (Sink a))
Sink a = 1 ⊕ N (Source a)
\end{spec}

For the translation to Haskell, we have chosen to use a lightweight
encoding, assuming linearity of effectful variables; arguing at the
same time for support of linearity in future Haskell versions.  Yet,
other encodings could be chosen. For example, we could have used the
technique of Pucella and Tov (Haskell session types with almost no
class), which does not require abiding to linearity.


Future Work
===========
\label{future}

As we see it, a natural next step for the present work is to show that
intermediate sources and sinks can be deforested. As it stands, we
believe that a standard approach
\cite{gill_short_1993,svenningsson_shortcut_2002,coutts_stream_2007}
should work: 1. encode sources (and sinks) as non-recursive data types
2. show that standard evaluation rules remove the intermediate
occurrences of the encoded types. However, this work has not been
carried out yet.

The duality principle exposed here as already been taken advantage of
to support fusible array types \cite{bernardy_composable_2015,ankner_edsl_2013}. The
present paper has shown how to support effectful stream
computations. One would naturally think that the same principle can be
applied to other lazily-evaluated data structures, such as the game
trees discussed by \citet{hughes_functional_1989}: as far as we know
this remains to be investigated.

Another line of development would be to implement language support for
the linearity convention, directly in Haskell. There has been many
proposals to extend functional languages with linear types (see for
example \cite[Ch. 9]{tov_practical_2012} for a survey). These
proposals are often rather involved, because they typically support
advanced forms of polymorphism allowing to abstract over the linearity
of an argument. The linearity convention that we use here calls for no
such complexity, therefore we hope it may be enough of a motivation to
add simple linear type support in research-grade Haskell compilers.


Conclusion
==========

We have cast an new light on the current state of coroutine-based
computation in Haskell. We have done so by drawing inspiration from
classical linear logic. We have shown that the concepts of duality and
polarity provide design principles to structure continuation-based
code. In particular, we have shown that mismatches in polarity
correspond to buffers and control structures, depending on the kind of
mismatch.


\acks

We gratefully thank Koen Claessen, Atze van der Ploeg and Nicolas
Pouillard for feedback on drafts of this paper.  The source code for
this paper is a literate Haskell file, available at this url:
TODO. The paper is typeset using pandoc, lhs2TeX and latex.



\bibliographystyle{abbrvnat}
\bibliography{PaperTools/bibtex/jp,js}


\appendix

Table of Functions: implementations
===================================

> zipSrc s1 s2 t3 = shiftSrc s2 $ \s ->
>                   unshiftSrc (\t -> forkSnk t s1 s) t3

> forkSnk sab ta tb =
>   shiftSrc ta $ \ta' ->
>   case ta' of
>     Nil -> (forward tb) Full <> sab Nil
>     Cons a as ->  case tb of
>       Nil -> as Full <> sab Nil
>       Cons b bs -> fwd (cons (a,b) $ zipSrc as bs) sab

> forkSrc sab ta tb = shiftSnk (zipSnk ta (flip forward tb)) sab

> zipSnk sa sb Nil = sa Nil <> sb Nil
> zipSnk sa sb (Cons (a,b) tab) = sa $ Cons a $ \sa' ->
>                                 sb $ Cons b $ \sb' ->
>                                 forkSrc tab (flip forward sa') sb'

> scanSrc f !z = flipSnk (scanSnk f z)

> scanSnk _ _ snk Nil          = snk Nil
> scanSnk f z snk (Cons a s)   = snk $ Cons next $ scanSrc f next s
>   where next = f z a

> foldSrc' f !z s nb = s (Cont (foldSnk' f z nb))

> foldSnk' _ z nb Nil = nb z
> foldSnk' f z nb (Cons a s) = foldSrc' f (f z a) s nb

Return the last element of the source, or the first argument if the
source is empty.

> lastSrc :: a -> Src a -> NN a
> lastSrc x s k = shiftSrc s $ \s' -> case s' of
>   Nil -> k x
>   Cons x' cs -> lastSrc x' cs k

> dropSrc i = flipSnk (dropSnk i)

> dropSnk 0 s s' = s s'
> dropSnk _ s Nil = s Nil
> dropSnk i s (Cons _ s') = shiftSrc (dropSrc (i-1) s') s

> fromList = foldr cons empty

> enumFromToSrc :: Int -> Int -> Src Int
> enumFromToSrc _ _ Full = mempty
> enumFromToSrc b e (Cont s)
>   | b > e     = s Nil
>   | otherwise = s (Cons b (enumFromToSrc (b+1) e))

> enumFromToSrc' :: Int -> Int -> CoSrc Int
> enumFromToSrc' _ _ Nil = mempty
> enumFromToSrc' from to (Cons x xs) = do
>   x from
>   let !from' = from+1
>   shiftSnk (enumFromToSrc' from' to) xs

> linesSrc = flipSnk unlinesSnk

> unlinesSnk = unlinesSnk' []

> unlinesSnk' :: String -> Snk String -> Snk Char
> unlinesSnk' acc s Nil = s (Cons acc empty)
> unlinesSnk' acc s (Cons '\n' s') = s (Cons   (reverse acc)
>                                              (linesSrc s'))
> unlinesSnk' acc s (Cons c s')
>   = s' (Cont $ unlinesSnk' (c:acc) s)

> untilSnk _ Nil = mempty
> untilSnk p (Cons a s)
>   | p a  = s Full
>   | True = s (Cont (untilSnk p))

> interleave s1 s2 Full = s1 Full <> s2 Full
> interleave s1 s2 (Cont s) = s1 (Cont (interleaveSnk s s2))

> interleaveSnk snk src Nil = fwd src snk
> interleaveSnk snk src (Cons a s)
>   = snk (Cons a (interleave s src))

> tee s1 t1 = flipSnk (collapseSnk t1) s1

> filterSrc p = flipSnk (filterSnk p)

> filterSnk _ snk Nil = snk Nil
> filterSnk p snk (Cons a s)
>   | p a       = snk (Cons a (filterSrc p s))
>   | otherwise = s (Cont (filterSnk p snk))

> unchunk = flipSnk chunkSnk

> chunkSnk s Nil = s Nil
> chunkSnk s (Cons x xs)
>   = fwd (fromList x `appendSrc` unchunk xs) s

> toList s k = shiftSrc s (toListSnk k)

> toListSnk :: N [a] -> Snk a
> toListSnk k Nil = k []
> toListSnk k (Cons x xs) = toList xs $ \xs' -> k (x:xs')


Proof of associativity of append for sinks
==========================================

\var{Nil} case.

\begin{spec}
    ((t1 <> t2) <> t3) Nil
== -- by def
    (t1 <> t2) Nil <> t3 Nil
== -- by def
    (t1 Nil <> t2 Nil) <> t3 Nil
==
    t1 Nil <> (t2 Nil <> t3 Nil)
== -- by def
    t1 Nil <> ((t2 <> t3) Nil)
== -- by def
    (t1 <> (t2 <> t3)) Nil
\end{spec}

 \var{Cons} case.

\begin{spec}
    ((t1 <> t2) <> t3) (Cons a s0)
== -- by def
    (t1 <> t2) (Cons a (t3 -! s0))
== -- by def
    t1 (Cons a (t2 -! (t3 -! s0)))
== -- by IH
    t1 (Cons a ((t2 <> t3) -! s0))
== -- by def
    (t1 <> (t2 <> t3)) (Cons a s0)
\end{spec}

 \var{Full} case.
\begin{spec}
  ((t1 <> t2) -! s) Full
== -- by def
  s (Cont (t1 <> t2))
== -- by def
   (t2 -! s) (Cont t1)
== -- by def
  (t1 -! (t2 -! s)) Full
\end{spec}

 \var{Cont} case.
\begin{spec}
  ((t1 <> t2) -! s) (Cont t0)
== -- by def
  s (Cont (t0 <> (t1 <> t2)))
== -- by IH
  s (Cont ((t0 <> t1) <> t2))
== -- by def
  (t2 -! s) (Cont (t0 <> t1))
== -- by def
  (t1 -! (t2 -! s)) (Cont t0)
\end{spec}

Proof of difference laws
========================

\label{proof}

The laws can be proved by mutual induction with the associative
laws of the monoids. Let us show only the case for sources, the case
for sinks being similar.

The \var{Full} case relies on the monoidal structure of effects:

\begin{spec}
   ((s1 <> s2) <> s3) Full
==  -- by def
   (s1 <> s2) Full <> s3 Full
==  -- by def
   (s1 Full <> s2 Full) <> s3 Full
==  -- \var{Eff} is a monoid
   s1 Full <> (s2 Full <> s3 Full)
==  -- by def
   s1 Full <> (s2 <> s3) Full
==  -- by def
   (s1 <> (s2 <> s3)) Full
\end{spec}

The \var{Cont} case uses mutual induction:

\begin{spec}
  ((s1 <> s2) <> s3) (Cont k)
== -- by def
  (s1 <> s2) (Cont (k -? s3)
== -- by def
  s1 (Cont (k -? s3) -? s2)
== -- mutual IH
  s1 (Cont (k -? (s2 <> s3)))
== -- by def
  (s1 <> (s2 <> s3)) (Cont k)
\end{spec}

The \var{Cons} case uses mutual induction:

\begin{spec}
  ((k -? s2) -? s1) (Cons a s0)
== -- by def
  (k -? s2) (Cons a (s0 <> s1))
== -- by def
  k (Cons a ((s0 <> s1) <> s2))
== -- mutual IH
  k (Cons a (s0 <> (s1 <> s2))
== -- def
  (k -? (s1 <> s2)) (Cons a s0)
\end{spec}

(We omit the \var{Nil} case; it is similar to the \var{Full} case)

 <!--

ScratchPad
==========


> data a + b = Inl a | Inr b
> data One = TT
> type Church f = forall x. (f x -> x) -> x
> newtype ChurchSrc' a = CS (forall x. ((One + (a, N (One + N x))) -> x) -> x)
> type ChurchSnk a = N (ChurchSrc' a)
> type ChurchSrc a = NN (ChurchSrc' a)


> emptyCh :: ChurchSrc a
> emptyCh k = k $ CS $ \k' -> k' (Inl TT)


> printSrc :: Show a => Src a -> IO ()
> printSrc s = fwd (mapSrc show s) dbg

> dbg :: Snk String
> dbg Nil = return ()
> dbg (Cons c s) = do
>   putStrLn c
>   s (Cont dbg)


> type Pull a = NN (Int -> a)
> type Push a = N (Int -> N a)


Yet, if one so decides, one can explicity build a
list by extracting all the contents out of a source. This operation provides a
bridge to pure list-processing code, by loading all the data to
memory.

> coFileSrc' :: String -> CoSrc String
> coFileSrc' f k = do
>   h <- openFile f ReadMode
>   coFileSrc'h h k


> coFileSrc'h :: Handle -> CoSrc String
> coFileSrc'h h Nil = hClose h
> coFileSrc'h h (Cons x xs) = do
>   e <- hIsEOF h
>   if e then do
>          hClose h
>          xs Full
>        else do
>          x' <- hGetLine h
>          xs $ Cont $ coFileSrc'h h 
>          x x'                      

> coFileSink' :: Handle -> CoSnk String
> coFileSink' h Full = return ()
> coFileSink' h (Cont c) = c (Cons  (hPutStrLn h)
>                                   (coFileSink' h))

> cpy = do
>   h' <- openFile "t" WriteMode
>   fwd  (coFileSink' h') (srcToCoSrc reverted $ fileSrc "Organ.lhs")
>   hClose h'

NOTE: commutative monads is SPJ Open Challenge #2 in his 2009 Talk "Wearing the Hair Shirt -- A retrospective on haskell"

> reverted :: Schedule a
> reverted Nil (Cons _ xs) = xs Full
> reverted (Cons _ xs) Nil = xs Full
> reverted (Cons x xs) (Cons x' xs') = do
>   (shiftSrc xs  $ \sa ->
>    shiftSrc xs' $ \sna ->
>    reverted sa sna)
>   x' x


--  LocalWords:  forkIO readChan writeChan newChan Applicative IORef
--  LocalWords:  coroutine Coroutines hughes compositionality inFile
--  LocalWords:  effectful kiselyov openFile ReadMode hGetContents NN
--  LocalWords:  putStr hClose Girard fileSrc stdoutSnk stdout Src
--  LocalWords:  compositional mempty mappend Dually involutive Snk
--  LocalWords:  unshift monadic versa forkSrc textit iff rw eof pre
--  LocalWords:  consumptions onSource onSink unshiftSnk unshiftSrc
--  LocalWords:  shiftSnk shiftSrc kk flipSnk flipSrc mapSrc mapSnk
--  LocalWords:  snk formers dnintro dndel duals takeSrc takeSnk th
--  LocalWords:  monoidal appendSrc appendSnk forwardThenSnk src IH
--  LocalWords:  forwardThenSrc infixr infixl equalities morphism ss
--  LocalWords:  contravariant concatSrcSrc concatSnkSrc concatAux mx
--  LocalWords:  TODO ssrc monads comonads comonad counit contramap
--  LocalWords:  sinkToSnk superclasses josef subclasses zipWith Sym
--  LocalWords:  zipSrc forkSnk zipSnk scanl scanSrc scanSnk foldl
--  LocalWords:  foldSrc foldSnk dropSrc dropSnk fromList toList ret
--  LocalWords:  linesSrc unlinesSnk untilSnk interleaveSnk filterSrc
--  LocalWords:  filterSnk unchunk chunkSnk claessen newtype forall
--  LocalWords:  longestResultSnk mres hFileSnk hPutStrLn fileSnk txt
--  LocalWords:  FilePath WriteMode hFileSrc hIsEOF hGetLine copyFile
--  LocalWords:  stdin hFileSrcSafe IOException Asynchronicity dually
--  LocalWords:  demultiplexing dmux tb sab mux sa sb De ka resta kb
--  LocalWords:  restb CoSrc CoSnk mapCoSrc mapCoSnk coToList strat
--  LocalWords:  coFileSrc coFileSink srcToCoSrc coSnkToSnk sna tmp
--  LocalWords:  distributable fileBuffer chanCoSnk chanSrc varCoSnk
--  LocalWords:  chanBuffer writeIORef varSrc readIORef varBuffer kay
--  LocalWords:  newIORef flipBuffer dualized bufferedDmux laurent el
--  LocalWords:  collapseSnk zeilberger jackson Jacksons FeldSpar DSL
--  LocalWords:  svenningsson iteratively Iteratees Kiselyov's GetC
--  LocalWords:  iteratees citeyear iteratee Enumeratee elo eli GenT
--  LocalWords:  enumeratees ReaderT caires Pucella Tov coutts tov js
--  LocalWords:  acks url pandoc lhs bibliographystyle abbrvnat bs nb
--  LocalWords:  PaperTools lastSrc foldr Kiselov's natively runtime
--  LocalWords:  async algorithmically tmpFile gonzalez snoyman kmett
--  LocalWords:  Atze der Ploeg enumFromToSrc

-->
