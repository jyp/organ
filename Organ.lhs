% A Linear Approach to Streaming

 <!--

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
functions. Indeed, while strict evaluation forces to fully reify each
intermediate result between each computational step, lazy
evaluation allows to run all the computations concurrently, often
without ever allocating more that a single intermediate result at a time.

Unfortunately, lazy evaluation suffers from two drawbacks.  First, it
has unpredictable memory behaviour. Consider the following function
composition:

\begin{spec}
f :: [a] -> [b]
g :: [b] -> [c]
h = g . f
\end{spec}

One hopes that, at runtime, the intermediate list ($[b]$) list
will only be allocated elementwise, as outlined above. Unfortunately,
this desired behaviour does not necessarily happen. Indeed, a
necessary condition is that the production pattern of $f$ matches the
consumption pattern of $g$; otherwise buffering occurs. In practice,
this means that a seemingly innocuous change in either of the function
definitions may drastically change the memory behaviour of the
composition, without warning. If one cares about memory behaviour,
this means that the compositionality principle touted by Hughes breaks
down.

Second, lazy evaluation does not extend nicely to effectful
processing. That is, if (say) an input list is produced by reading a
file lazily, one is exposed to losing referential transparency (as
\citet{kiselyov_lazy_2013} has shown). For example, one may rightfully
expect\footnote{This expectation is expressed in a
Stack Overflow question, accessible at this URL:
http://stackoverflow.com/questions/296792/haskell-io-and-closing-files
} that both following programs have the same behaviour:

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

Indeed, the \var{putStr} and \var{hClose} command act on unrelated
resources, and thus swapping them should have no observable effect.
However, while the first program prints the `foo` file, the second one
prints nothing.  Indeed, because \var{hGetContents} reads the file
lazily, the \var{hClose} operation has the effect to truncate the
list. In the first program, printing the contents force reading the
file. One may argue that \var{hClose} should not be called in the
first place. But then, closing the handle happens only when the
\var{contents} list can be garbage collected (in full), and relying on
garabage collection for cleaning resources is brittle; furthermore
this effect compounds badly with the first issue discussed above.  If
one wants to use lazy effectful computations, again, the
compositionality principle is lost.

In this paper, we propose to tackle both of these problems, by means
of a new representation for streams of data, and a convention on how
to use streams. The convention to respect is *linearity*. In fact, the
ideas presented in this paper are heavily inspired by study of
Girards' linear logic \cite{girard_linear_1987}, and one way to read
this paper is as an advocacy for linear types support in Haskell.

How does our approach fare on the issues identified above? First,
using our solution, the composition of two stream processors is
guaranteed not to allocate more memory than the sum of its components.
If the stream behaviours do not match, the types will not match
either. It is however be possible to adjust the types by adding
explicit buffering, in a natural manner:

\begin{spec} h = g . buffer . f \end{spec}

Second, stream closing is reliable. Printing a file can be implemented
as follows:

> main = fileSrc "foo" `forward` stdoutSnk

In particular, if an exception occurs on \var{stdout}, the input file
will be properly closed anyway. (In the general case, stream
processors will be run in-between reading and printing. )

The contributions of this paper are

* A Haskell library for streaming `IO`, built on the linearity
principle. Besides supporting compositionality as outlined above, it
features two novel aspects:

  1. A more lightweight design than state-of-the-art co-routine based
    libraries, afforded by the linearity convention.

  2. Support for explicit buffering and control structures, while
    still respecting compositionality.

* Besides, the approach followed for developing this library
generalises to other types than stream. (TODO?)

TODO: outline

Preliminary: negations and continuations
========================================

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

The basic idea (imported from classical logics) pervading this paper
is that producing a result of type α is equivalent to consuming an
argument of type $N α$. Dually, consuming an argument of type α is
equivalent to producing a result of type $N α$. In this paper we call
these equivalences the duality principle.

In classical logics, negation is involutive; that is:
$\var{NN}\,a = a$
However, because we work with an intuitionistic language (Haskell), we
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
simple :: Src a -> Snk a -> Eff
\end{spec}

We will make sure that \var{Sink} is the negation of a source (and vice
versa), and thus the type of the above program may equivalently have
been written as follows:

\begin{spec}
simple :: Src a -> Src a
\end{spec}

However, having explicit access to sinks allows us to (for example)
dispatch a single source to mulitiple sinks, as in the following type signature:
\begin{spec}
unzipSrc :: Src (a,b) -> Snk a -> Snk b -> Eff
\end{spec}
Familiarity with duality will be crucial in the later sections of this paper.

We will define sources and sinks by mutual recursion. Producing a
source means to select if some more is available (\var{Cons}) or not
(\var{Nil}). If there is data, one must then produce a data item and
*consume* a sink.

> data Source'  a   = Nil   | Cons a  (N (Sink'    a))
> data Sink'    a   = Full  | Cont    (N (Source'  a))

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
> fwd Nil Full = mempty
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


Baking in negations: exercise in duality
-------------------

Programming with \var{Source'} and \var{Sink'} explicitly is
inherently continuation-heavy: negations must be explicitly added in
many places.  Therefore, we will use instead pre-negated versions of
sources and sink:

> type Src a = N (Sink' a)
> type Snk a = N (Source' a)

These definitions have the added advantage to perfect the duality
between sources and sinks, while not restricting the programs one can
write.
Indeed, one can access the underlying structure as follows:

> onSource' :: (Src a -> t) -> Source' a -> t
> onSink' :: (Snk a -> t) -> Sink' a -> t

> onSource' f s = f (\t -> fwd s t)
> onSink'   f t = f (\s -> fwd s t)


And, while a negated \var{Sink'} cannot be converted to a
\var{Source'}, all the following conversions are implementable:

> unshiftSnk :: N (Src a) -> Snk a
> unshiftSrc :: N (Snk a) -> Src a
> shiftSnk :: Snk a -> N (Src a)
> shiftSrc :: Src a -> N (Snk a)

> unshiftSnk = onSource'
> unshiftSrc = onSink'
> shiftSnk k kk = kk (Cont k)
> shiftSrc k kk = k (Cont kk)

A different reading of the type of \var{shiftSrc} reveals that it implements
forwarding of data from \var{Src} to \var{Snk}:

> forward :: Src a -> Snk a -> Eff
> forward = shiftSrc

In particular, one can flip sink transformers to source transformers,
and vice versa.

> flipSnk :: (Snk a -> Snk b) -> Src b -> Src a
> flipSnk f s = shiftSrc s . onSink' f

> flipSrc :: (Src a -> Src b) -> Snk b -> Snk a
> flipSrc f t = shiftSnk t . onSource' f


This means that one can choose the most convenient version to
implement, and get the other one for free. Consider as an example the
implementation of the mapping functions:

> mapSrc  :: (a -> b) -> Src  a -> Src  b
> mapSnk  :: (b -> a) -> Snk  a -> Snk  b

Mapping sources is defined by flipping mapping of sinks:

> mapSrc f = flipSnk (mapSnk f)

And sink mapping is defined by case analysis on the concrete
source. The recursive case can call \var{mapSrc}.

> mapSnk _ snk Nil = snk Nil
> mapSnk f snk (Cons a s)
>   = snk (Cons (f a) (mapSrc f s))


When using double negations, it is sometimes useful to insert or
remove them inside type formers. For sources and sinks, one proceeds
as follows. First, introduction of double negation and its elimination
in sinks is a special case of mapping.

> dnintro :: Src a -> Src (NN a)
> dnintro = mapSrc shift

> dndel' :: Snk (NN a) -> Snk a
> dndel' = mapSnk shift

The duals are easily implementd by case analysis, following the mutual
recursion pattern introduced above.

> dndel :: Src (NN a) -> Src a
> dnintro' :: Snk a -> Snk (NN a)

> dndel = flipSnk dnintro'
> dnintro' k Nil = k Nil
> dnintro' k (Cons x xs) = x $ \x' -> k (Cons x' $ dndel xs)


Effect-Free Streams
-------------------

Given the above definitions, one can implement a list-like API for
sources, as follows:

> empty :: Src a
> empty sink' = fwd Nil sink'

> cons :: a -> Src a -> Src a
> cons a s s' = yield a s' s

> tail :: Src a -> Src a
> tail = flipSnk $ \t s -> case s of
>   Nil -> t Nil
>   Cons _ xs -> forward xs t

(Taking just the head is not meaningful due to the linearity
constraint)

Dually, the full sink is simply

> plug :: Snk a
> plug source' = fwd source' Full


A non-full sink decides what to do depending on the availability of
data. We could write the following:

> match :: Eff -> (a -> Snk a) -> Snk a
> match nil' cons' k = await k nil' cons'

However, calling \var{await} may break linearity, so we will refrain to use
\var{match} in the following.

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

Sources and sinks are instances of several common algrebraic
structures.

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
behaviour is implemented in the helper function \var{forwardThenSnk}.

> appendSrc :: Src a -> Src a -> Src a
> appendSrc s1 s2 Full = s1 Full <> s2 Full
> appendSrc s1 s2 (Cont s)
>   = s1 (Cont (forwardThenSnk s s2))

> forwardThenSnk :: Snk a -> Src a -> Snk a
> forwardThenSnk snk src Nil = forward src snk
> forwardThenSnk snk src (Cons a s)
>   = snk (Cons a (appendSrc s src))

Sinks can be appended is a similar fasion.

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

Appending and differences interact in the expected way:

> prop_diff1 t s1 s2 = t -? (s1 <> s2) == t -? s2 -? s1
> prop_diff2 t1 t2 s = (t1 <> t2) -! s == t1 -! t2 -! s

> prop_diff3 t1 t2 s = (t1 <> t2) -? s == t1 -? (t2 -! s) -- ???
> prop_diff4 t s1 s2 = t -! (s1 <> s2) == (t -? s1) -! s2 -- ???


The above laws can be proved by mutual induction with the associative
laws of the monoids. Let us show the case for sources.

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


\paragraph{Functor}
We have already seen the mapping functions for sources and sinks:
sources are functors and sinks are contravariant functors. (Given the
implementation of the morphism actions it is straightforward to check
the functor laws.)

\paragraph{Monad}

Besides, \var{Src} is a monad. The unit is trivial. The join operation
is the concatenation of sources:

> concatSrcSrc :: Src (Src a) -> Src a

Before implementing concatenation we will first implement append as it
is both independently useful and important when defining
concatenation.


> concatSrcSrc = flipSnk concatSnkSrc

> concatSnkSrc :: Snk a -> Snk (Src a)
> concatSnkSrc snk Nil = snk Nil
> concatSnkSrc snk (Cons src s)
>   = src (Cont (concatAux snk s))

> concatAux :: Snk a -> Src (Src a) -> Snk a
> concatAux snk ssrc Nil = snk Nil <> ssrc Full
> concatAux snk ssrc (Cons a s)
>   = snk (Cons a (appendSrc s (concatSrcSrc ssrc)))

Given the duality between sources and sinks, and the fact that sources
are monads, it might be tempting to draw the conclusion that sinks are
comonads. This is not the case. To see why, consider that every
comonad has a counit, which, in the case for sinks, would have the
following type

\begin{spec}
Snk a -> a
\end{spec}

There is no way to implement this function since sinks don't store
elements so that they can be returned. Sinks consume elements rather
than producing them.

\paragraph{Divisible and Decidable}

 <!--

> data Void

> class Contravariant f where
>   contramap :: (b -> a) -> f a -> f b

> instance Contravariant Snk where
>   contramap = mapSnk


> sinkToSnk :: Sink' a -> Snk a
> sinkToSnk Full Nil = return ()
> sinkToSnk Full (Cons a n) = n Full
> sinkToSnk (Cont f) s = f s

-->

If sinks are not comonads, are there some other structures that they
implement? The package contravariant on hackage gives two classes;
\var{Divisible} and \var{Decidable\, which are superclasses of
\var{Contravariant}, a class for contravariant functors. They are
defined as follows:

> class Contravariant f => Divisible f where
>   divide :: (a -> (b, c)) -> f b -> f c -> f a
>   conquer :: f a

The method \var{divide} can be seen as a dual of \var{zipWith} where
elements are split and fed to two different sinks.

> instance Divisible Snk where
>   divide div snk1 snk2 Nil = snk1 Nil >> snk2 Nil
>   divide div snk1 snk2 (Cons a ss) =
>     snk1 (Cons b $ \ss1 ->
>     snk2 (Cons c $ \ss2 ->
>     shiftSnk (divide div (sinkToSnk ss1)
>                          (sinkToSnk ss2)) ss))
>     where (b,c) = div a
>
>   conquer = plug

The class \var{Decidable} has the methods \var{lose} and \var{choose}:

> class Divisible f => Decidable f where
>   choose :: (a -> Either b c) -> f b -> f c -> f a
>   lose :: (a -> Void) -> f a

The function \var{choose} can split up a sink so that some elements
go to one sink and some go to another.

> instance Decidable Snk where
>   choose choice snk1 snk2 Nil = snk1 Nil >> snk2 Nil
>   choose choice snk1 snk2 (Cons a ss)
>     | Left b <- choice a = snk1 (Cons b $ \snk1' ->
>       shiftSnk (choose choice (sinkToSnk snk1') snk2) ss)
>   choose choice snk1 snk2 (Cons a ss)
>     | Right c <- choice a = snk2 (Cons c $ \snk2' ->
>       shiftSnk (choose choice snk1 (sinkToSnk snk2')) ss)
>
>   lose f Nil = return ()
>   lose f (Cons a ss) = ss (Cont (lose f))



Effectful streams
=================

So far, we have constructed only effect-free streams. That is, the
equality $\var{Eff} = \var{IO} ()$ was never used. In this section we bridge this
gap and provide some useful sources and sinks performing input or
output.

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
> copyFile source target = forward  (fileSrc source)
>                                   (fileSnk target)

It should be emphasised at this point that reading and writing will be
interleaved: in order to produce the next file line (in the source),
the current line must be consumed by writing it to disk (in the sink).
The stream behaves fully synchronously, and no intermediate data is
buffered.

When the sink is full, the source connected to it should be finalized.
The next example shows what happens when a sink closes the stream
early. Instead of connecting the source to a bottomless sink, we
connect it to one which stops receiving input after three lines.

> read3Lines :: Eff
> read3Lines = forward  (hFileSrc stdin)
>                       (takeSnk 3 $ fileSnk "text.txt")

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

Exceptions raised in \var{hIsEOF} should be handled in a similar same
way, as well as those raised in a file sink; we leave this simple
exercise to the reader.

In an industrial-strength implementation, one would probably have a
field in both the \var{Nil} and \var{Full} constructors indicating the
nature of the exception encountered, but we will not bother in the
proof of concept implementation presented in this paper.



App: Stream-Based Parsing
-------------------------

The next application is a stream transformer which parses an input
stream into structured chunks. This is useful for example to turn an
XML file inputted as stream of characters into a stream of (opening
and closing) tags.

We beging by defining a pure parsing structure, modeled after the
parallel parsing processes of \citet{claessen_parallel_2004}.  The
parser is continuation based, but the effects being accumulated are
parsing processes, defined as follows. The \var{Sym} constructor parses just
a symbol, or \var{Nothing} if the end of stream is reached. A process may
also \var{Fail} or return a \var{Result} (and continue).

> data P s res  =  Sym (Maybe s -> P s res)
>               |  Fail
>               |  Result res (P s res)

A parser producing $a$ the double negation of $a$:

> newtype Parser s a = P (forall res. (a -> P s res) -> P s res)

The monading interface can then be built using shift and unshift:

> instance Monad (Parser s) where
>   return x  = P $ \fut -> fut x
>   P f >>= k = P (\fut -> f (\a -> let P g = k a in g fut))

The essential parsing ingredient, disjunction, rests on the
possibility to weave processes together, always picking that which
fails as last resort:

> weave :: P s a -> P s a -> P s a
> weave Fail x = x
> weave x Fail = x
> weave (Result res x) y = Result res (weave x y)
> weave x (Result res y) = Result res (weave x y)
> weave (Sym k1) (Sym k2)
>     = Sym (\s -> weave (k1 s) (k2 s))

> (<|>) :: Parser s a -> Parser s a -> Parser s a
> P p <|> P q = P (\fut -> weave (p fut) (q fut))


 <!--

> longestResultSnk :: forall a s. P s a -> N (Maybe a) -> Snk s
> longestResultSnk p0 ret = scan p0 Nothing
>  where
>   scan :: P s a -> Maybe a -> Snk s
>   scan (Result res p)  _         xs     = scan p (Just res) xs
>   scan Fail           mres       xs     = ret mres >> fwd xs Full
>   scan (Sym f)        mres       xs     = case xs of
>     Nil        -> scan (f Nothing) mres Nil
>     Cons x cs  -> forward cs (scan (f $ Just x) mres)

-->

Parsing then reconciles the execution of the process with the
traversal of the source. In particular, whenever a result is
encountered, it is fed to the sink. If the parser fails, both ends of
the stream are closed.

> parse :: forall s a. Parser s a -> Src s -> Src a
> parse q@(P p0) = flipSnk $ scan $ p0 $ \x -> Result x Fail
>  where
>   scan :: P s a -> Snk a -> Snk s
>   scan (Result res _) ret        xs     = ret (Cons res $ parse q $ fwd xs)
>   scan Fail           ret        xs     = ret Nil <> fwd xs Full
>   scan (Sym f)        mres       xs     = case xs of
>     Nil        -> scan (f Nothing) mres Nil
>     Cons x cs  -> forward cs (scan (f $ Just x) mres)




Synchronicity and Asynchronicity
================================

One of the main benefits of streams as defined here is that the
programming interface is (or appears to be) asynchronous, while the
runtime behaviour is synchronous.

One can build a data source regardless of how the data is be consumed,
or dually one can build a sink regardless of how the data is produced;
but, despite the independency of definitions, all the code can (and
is) executed synchronously: composing a source and a sink require no
concurrency (nor any external control structures).

A consequence of synchronicity is that the programer cannot be
implicity buffering data: every production must be matched by a
consuption (and vice versa). However, explicity build a list with a
source contents, if one so decides. This essentially builds a bridge
to pure list processing code, by loading all the data to memory.

> toList :: Src a -> NN [a]
> toList s k = shiftSrc s (toListSnk k)

> toListSnk :: N [a] -> Snk a
> toListSnk k Nil = k []
> toListSnk k (Cons x xs) = toList xs $ \xs' -> k (x:xs')

In sum, synchronicity restricts the kind of operations one can
construct, in exchange for two guarantees:

1. Finalization of sources and stream is synchronous
2. No implicit memory allocation happens

While the guarantees have been discussed so far, it may be unclear how
synchronicity actually restricts the programs one can write. In the
rest of the section we show by example how the restriction plays out.

Example: demultiplexing
-----------------------

One operation supported by synchronous behaviour is the demultiplexing
of a source, by connecting it to two sinks.

> dmux' :: Src (Either a b) -> Snk a -> Snk b -> Eff

We can implement this demultiplexing operation as follows:

> dmux :: Source' (Either a b) -> Sink' a -> Sink' b -> Eff
> dmux Nil ta tb = fwd Nil ta <> fwd Nil tb
> dmux (Cons ab c) ta tb = case ab of
>   Left a -> c $ Cont $ \src' -> case ta of
>     Full -> fwd Nil tb <> plug src'
>     Cont k -> k (Cons a $ \ta' -> dmux src' ta' tb)
>   Right b -> c $ Cont $ \src' -> case tb of
>     Full -> fwd Nil ta <> plug src'
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
this, the choice falls to us to choose which source to run first. We
may pick \var{sa}, however it may be blocking, while \var{sb} is ready
with data. This is not really multiplexing, at best this approach
would give us interleaving of data sources by taking turns.

In order to make any progress, we can let the choice of which source
to pick fall on the consumer of the stream. What we need in this case
is the so-called additive conjuction. It is the dual of the
\var{Either} type: there is a choice, but this choice falls on the
consumer rather than the producer of the data. Additive conjuction,
written &, can be encoded by sandwiching \var{Either} between two
inversion of the control flow, thus switching the party who makes the
choice:

> type a & b = N (Either (N a) (N b))

(One will recognize the similarity between this definition and the
deMorgan law.)

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
>                         (error "???")

However, there is no way to then make a recursive call (???) to
continue processing.  Indeed the recursive call to make must depend on
the choice made by the consumer (in one case we should be using
\var{resta}, in the other \var{restb}). However the type of \var{Cons}
forces us to produce its arguments independently.

What we need to do is to reverse the control fully: we need a data
source which is in control of the flow of execution.

Co-Sources, Co-Sinks
-------------------

We call the structure that we are looking for *co-sources*, and they
are the subject of this section.
Remembering that producing $N a$ is equivalent to consuming $a$, we
define:

> type CoSrc a = Snk (N a)
> type CoSnk a = Src (N a)

Implementing multipexing on co-sources is then straightforward, by
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


One access elements of a co-source only "one at a time". That is, one
cannot extract the contents of a co-source as a list. Attempting to
implement this extraction looks as follows.

> coToList :: CoSrc a -> NN [a]
> coToList k1 k2 = k1 $ Cons (\a -> k2 [a]) (error "rest") -- (1)
> coToList k1 k2 = k2 $ (error "a?") : (error "rest")      -- (2)

If one tries to begin by eliminating the co-source (1), then there is no
way to produce subsequent elements of the list. If one tries to begin
by constructing the list (2), then no data is available.
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
concurrently (we will see in the next section how this situation
generalises).

The second example is a co-sink which sends its contents to a file.

> coFileSink :: Handle -> CoSnk String
> coFileSink h Full = hClose h
> coFileSink h (Cont c) = c (Cons  (hPutStrLn h)
>                                  (coFileSink h))

Compared to \var{fileSnk}, the difference is that one does not control the
order of execution of effects. The effect of writing the current line
is put in a data structure, and its execution is up to the co-source
which will eventually connect to the co-sink.

In sum, using co-sources and co-sinks shifts the flow of control from
the sink to the source. It should be stressed that, in the programs
which use the functions defined so far (even those that use IO)
synchronicity is preserved.

Asynchronicity
--------------

We have seen so far that synchronicity gives useful guarantees, but
restricts the kind of programs one can write. In this section, we will
provide primitives which allow forms of asynchronous programming using
our framework.
The main benefit of sticking to our framework in this case is that
asynchronous behaviour is cornered to the explicit usages of these
primitives. That is, the benefits of synchronous programming still
hold locally.

\paragraph{Concurrency}

When converting a \var{Src} to a \var{CoSrc} (or dually \var{CoSnk} to
a \var{Snk}), we have two streams which are ready to respond to
pulling of data from them.  This means that concurrency opportunities
arise, as we have seen an example above when manually converting the
file source to a file co-source.

In general, given a scheduling strategy, we can implement the above
two conversions:

> srcToCoSrc :: Strategy a -> Src a -> CoSrc a
> coSnkToSnk :: Strategy a -> CoSnk a -> Snk a

We define a strategy as the reconciliation between a source and a
co-sink:

> type Strategy a = Source' a -> Source' (N a) -> Eff

Implementing the conversions is then straightforward:

> srcToCoSrc strat s s0 = shiftSrc s $ \ s1 -> strat s1 s0
> coSnkToSnk strat s s0 = shiftSrc s $ \ s1 -> strat s0 s1

There are (infinitely) many possible concurrency strategies, however
in practice we think that one will mostly be combining either of the
following two flavours.  The simplest one (used in \var{coFileSrc}) is
sequential execution, and is defined by looping through both sources
and match the consumptions/productions elementwise.

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

The above implementation naively spawns a thread for every element.
In reality one will most likely want to divide the stream into
chunks before spawning threads. Because strategies are separate
components, if it turns out that a bad choice was made it is easy to
swap a strategy for another.

\paragraph{Buffering}

Consider now the situation where one needs to convert from a
\var{CoSrc} to a \var{Src} (or from a \var{Snk} to a \var{CoSnk}).
Here, we have two streams which want to control the execution
flow. The conversion can only be implemented by running both streams
in concurrent threads, and have them communicate via some form of
buffer. A form of buffer that we have seen before is the file. Using
it yields the following buffering implementation:

> fileBuffer :: CoSrc String -> Src String
> fileBuffer f g = do
>   h' <- openFile  "tmp" WriteMode
>   forkIO $ forward (coFileSink h') f
>   h <- openFile "tmp" ReadMode
>   hFileSrc h g

If the temporary file is a regular file, the above implementation is
likely to fail. For example the reader may be faster than the writer
and reach an end of file prematurely. Thus the temporary file should
be a UNIX pipe. One then faces the issue that UNIX pipes are of fixed
maximum size, and if the writer overshoots the capacity of the pipe, a
deadlock will occur.

Thus, one may prefer to use Concurrent Haskell channels as a buffering
means, as they are bounded only by the size of the memory and do not
rely on a feature of the operating system:

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
>   forkIO $ forward (chanCoSnk c) f
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
>   forkIO $ forward (varCoSnk c) f
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

1. Matching polarities. In this case behaviour is synchronous; no
concurrency appears.

2. Two positives. In this case the programmer needs to make a
scheduling choice. This choice can be any static or dynamic processing
order. In particular parallel processing is allowed.

3. Two negatives. In this case the streams must run in independent
threads, and programmer needs to make a choice for the communication
buffer. One needs to be careful: if the buffer is to small a deadlock
may occur.

Therefore, when programming with streams, one should prefer to consume
negative types and produce positive ones.

App: idealised echo server
---------------------


The server will communicate with each client via two streams, one for
inbound messages, one for outbound ones. We want each client to be
able to send and recieve messages in the order that they like. That
is, from their point of view, they are in control of the message
processing order. Hence a client should have a co-sink for sending
messages to the server, and a source for recieving them.  On the
server side, a client is thus represented by a pair of a co-source and
a sink:

> type Client a = (CoSrc a, Snk a)

For simplicity we implement a chat server handling exactly two
clients.

The first problem is to mulitiplex the inputs of the clients. In the
server, we do not actually want any client to be controlling the
processing order. Hence we have to mulitiplex the messages in real time,
using a channel:

> bufferedDmux :: CoSrc a -> CoSrc a -> Src a
> bufferedDmux s1 s2 t = do
>   c <- newChan
>   forkIO $ forward (chanCoSnk c) s1
>   forkIO $ forward (chanCoSnk c) s2
>   chanSrc c t

We then have to send each message to both clients. This may be done
sending by the followig function, which forwards everything sent to a
sink to its two argument sinks.

> collapseSnk :: Snk a -> Snk a -> Snk a
> collapseSnk t1 t2 Nil = t1 Nil <> t2 Nil
> collapseSnk t1 t2 (Cons x xs)
>   =  t1  (Cons x $ \c1 ->
>      t2  (Cons x $ \c2 ->
>          shiftSrc xs (collapseSnk  (flip fwd c1)
>                                    (flip fwd c2))))


The server can then be given the following  definition.


> server :: Client a -> Client a -> Eff
> server (i1,o1) (i2,o2) = forward  (bufferedDmux i1 i2)
>                                   (collapseSnk o1 o2)





Table of transparent functions
------------------------------

(implementable without reference to IO, preserving syncronicity)

Zip two sources:

> zipSrc :: Src a -> Src b -> Src (a,b)
> zipSrc s1 s2 = unshiftSrc (\t -> unzipSnk t s1 s2)

Unzip a sink (recieving data from parallel sources)

> unzipSnk :: Snk (a,b) -> Src a -> Src b -> Eff
> unzipSnk sab ta tb =
>   shiftSrc ta $ \ta' ->
>   case ta' of
>     Nil -> tb Full <> sab Nil
>     Cons a as ->  shiftSrc tb $ \tb' ->  case tb' of
>       Nil -> as Full <> sab Nil
>       Cons b bs -> forward (cons (a,b) $ zipSrc as bs) sab

Unzip a source (sending data to parallel sources)

> unzipSrc :: Src (a,b) -> Snk a -> Snk b -> Eff
> unzipSrc sab ta tb = shiftSnk (zipSnk ta tb) sab

Zipping sinks

> zipSnk :: Snk a -> Snk b -> Snk (a,b)
> zipSnk sa sb Nil = sa Nil <> sb Nil
> zipSnk sa sb (Cons (a,b) tab) = sa $ Cons a $ \sa' ->
>                                 sb $ Cons b $ \sb' ->
>                                 unzipSrc tab (flip fwd sa') (flip fwd sb')

Equivalent of \var{scanl'} for sources

> scanSrc :: (b -> a -> b) -> b -> Src a -> Src b
> scanSrc f !z = flipSnk (scanSnk f z)

Dual to \var{scanSrc}

> scanSnk :: (b -> a -> b) -> b -> Snk b -> Snk a
> scanSnk _ _ snk Nil          = snk Nil
> scanSnk f z snk (Cons a s)   = snk $ Cons next $ scanSrc f next s
>   where next = f z a

Equivalent of \var{foldl'} for sources

> foldSrc' :: (b -> a -> b) -> b -> Src a -> NN b
> foldSrc' f !z s nb = s (Cont (foldSnk' f z nb))

> foldSnk' :: (b -> a -> b) -> b -> N b -> Snk a
> foldSnk' _ z nb Nil = nb z
> foldSnk' f z nb (Cons a s) = foldSrc' f (f z a) s nb

Return the last element of the source, or the first argument if the
source is empty.

> lastSrc :: a -> Src a -> NN a
> lastSrc x s k = shiftSrc s $ \s' -> case s' of
>   Nil -> k x
>   Cons x' cs -> lastSrc x' cs k

Drop some elements from a sources

> dropSrc :: Int -> Src a -> Src a
> dropSrc i = flipSnk (dropSnk i)

Dual to \var{dropSrc}

> dropSnk :: Int -> Snk a -> Snk a
> dropSnk 0 s s' = s s'
> dropSnk _ s Nil = s Nil
> dropSnk i s (Cons _ s') = shiftSrc (dropSrc (i-1) s') s


> fromList :: [a] -> Src a
> fromList = foldr cons empty

> enumFromToSrc :: Int -> Int -> Src Int
> enumFromToSrc _ _ Full = mempty
> enumFromToSrc b e (Cont s)
>   | b > e     = s Nil
>   | otherwise = s (Cons b (enumFromToSrc (b+1) e))

> linesSrc :: Src Char -> Src String
> linesSrc = flipSnk unlinesSnk

> unlinesSnk :: Snk String -> Snk Char
> unlinesSnk = unlinesSnk' []

> unlinesSnk' :: String -> Snk String -> Snk Char
> unlinesSnk' acc s Nil = s (Cons acc empty)
> unlinesSnk' acc s (Cons '\n' s') = s (Cons (reverse acc) (linesSrc s'))
> unlinesSnk' acc s (Cons c s') = s' (Cont $ unlinesSnk' (c:acc) s)

Consume elements until the predicate is reached; then the sink is
closed.

> untilSnk :: (a -> Bool) -> Snk a
> untilSnk _ Nil = mempty
> untilSnk p (Cons a s)
>   | p a  = s Full
>   | True = s (Cont (untilSnk p))

> interleave :: Src a -> Src a -> Src a
> interleave s1 s2 Full = s1 Full <> s2 Full
> interleave s1 s2 (Cont s) = s1 (Cont (interleaveSnk s s2))

> interleaveSnk :: Snk a -> Src a -> Snk a
> interleaveSnk snk src Nil = forward src snk
> interleaveSnk snk src (Cons a s) = snk (Cons a (interleave s src))

Forward data coming from the input source to the result source and to
the second argument sink.

> tee :: Src a -> Snk a -> Src a
> tee s1 t1 = flipSnk (collapseSnk t1) s1

Filter a source

> filterSrc :: (a -> Bool) -> Src a -> Src a
> filterSrc p = flipSnk (filterSnk p)

Dual to \var{filterSrc}

> filterSnk :: (a -> Bool) -> Snk a -> Snk a
> filterSnk _ snk Nil = snk Nil
> filterSnk p snk (Cons a s)
>   | p a       = snk (Cons a (filterSrc p s))
>   | otherwise = s (Cont (filterSnk p snk))

> unchunk :: Src [a] -> Src a
> unchunk = flipSnk chunkSnk

> chunkSnk :: Snk a -> Snk [a]
> chunkSnk s Nil = s Nil
> chunkSnk s (Cons x xs) = forward (fromList x `appendSrc` unchunk xs) s

Table of primitive functions (implementable by reference to IO, may break syncronicity)

Related Work
============


Polarities, data structures and control
---------------------------------------

One of keys ideas formalized in this paper is to classify streams by
polarity. The negative polarity (Sinks, CoSrc) controls the execution
thread, whereas the positive one (Sources, Co-sinks) provide
data. This idea has recently been taken advantage of this idea to
bring efficient array programming facilities to functional programming
\citep{bernardy_composable_2015}.  TODO: josef: other citations

This concept is central in the literature on Girard's linear logic
(\citep{laurent_etude_2002,zeilberger_logical_2009}). However, in the
case of streams, this idea dates back at least to
\citet{jackson_principles_1975} (\citet{kay_you_2008} gives a good
summary of Jacksons' insight).

Our contribution is to bring this idea to stream programming in
Haskell. (While duality was used for Haskell array programming, it has
not been taken advantage for stream programming.) We belive that our
implementation brings together the practical applications that Jackson
intended, while being faithful to the theoretical foundations in
logic, via the double-negation embedding.


FeldSpar modadic streams
------------------------

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

Iteratees
---------

The state of the art.

Iteratees are parsers also.

Iteratee is subject to the linearity convention as well:

the type of
iteratees is transparent, so users can in principle discard and
duplicate continuations, thereby potentially duplicating or ignoring
effects.



\cite{kiselyov_iteratees_2012}

> data I s m a = Done a | GetC (Maybe s -> m (I s m a))
> 
> type Enumerator el m a = I el m a -> m (I el m a)
> type Enumeratee elo eli m a =
>         I eli m a -> I elo m (I eli m a)

http://johnlato.blogspot.se/2012/06/understandings-of-iteratees.html

* "Conduits"
* Pipes
* Yield

\cite{kiselyov_lazy_2012}

\begin{spec}
type GenT e m = ReaderT (e -> m ()) m
--   GenT e m a  = (e -> m ()) -> m a
type Producer m e = GenT e m ()
type Consumer m e = e -> m ()
type Transducer m1 m2 e1 e2 = Producer m1 e1 -> Producer m2 e2
\end{spec}


Session Types
-------------

In essence our pair of types for stream is an encoding of a protocol
for data transmission. This protocol is readily expressible using
linear types, following the ideas of TODO {Wadler 12, Pfenning and Caires}:

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


Parallelism ?
===========


> type Pull a = NN (Int -> a)
> type Push a = N (Int -> N a)

Bidirectional protocols. 

Future Work
===========

Beyond Haskell: native support for linear types. Even classical!

Fusion

Conclusion
==========

* In particular, we show that mismatch in duality correspond to
buffers and control structures, depending on the kind of mismatch.


* Cast an new light on coroutine-based io by drawing inspiration from
classical linear logic. Emphasis on polarity and duality.


* A re-interpretation of coroutine-based effectful computing, based on
a computational interpretation of linear logic, and


\acks

The source code for this paper is a literate Haskell file, available
at this url: TODO. The paper is typeset using pandoc, lhs2TeX and
latex.



\bibliographystyle{abbrvnat}
\bibliography{PaperTools/bibtex/jp,js}


\appendix
\section{Appendix: implementation details}



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


TODO: on this simple program it's not clear when (or if) the input stream is going to be closed.


> func = do
>   input <- hGetContents stdin
>   writeFile "test1.txt" (unlines $ take 3 $ lines input)

> failure = do
>   func
>   func

> printSrc :: Show a => Src a -> IO ()
> printSrc s = forward (mapSrc show s) dbg

> dbg :: Snk String
> dbg Nil = return ()
> dbg (Cons c s) = do
>   putStrLn c
>   s (Cont dbg)

