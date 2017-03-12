---
title: On the Duality of Streams
subtitle: How Can Linear Types Help to Solve the Lazy IO Problem?
author:
- name: Jean-Philippe Bernardy
- name: Josef Svenningsson
...

 <!--

> {-# LANGUAGE ScopedTypeVariables, TypeOperators, RankNTypes, LiberalTypeSynonyms, BangPatterns, TypeSynonymInstances, FlexibleInstances, FlexibleContexts, LambdaCase, GADTs  #-}
> module Organ where
> import System.IO
> import Control.Exception
> import Control.Concurrent (forkIO, readChan, writeChan, Chan, newChan, QSem, newQSem, waitQSem, signalQSem)
> import Control.Applicative hiding (empty)
> import Data.IORef
> import Prelude hiding (tail, drop)
> import Control.Monad (ap)
> import Data.Monoid

> type a ⊸ b = a -> b
> type a ⊗ b = (a,b)
> infixr ⊸


> data Source  a  where
>   Nil :: Source a
>   Cons :: a -> N (Sink a) -> Source a
> data Sink    a  where
>   Full :: Sink a
>   Cont :: (N (Source  a)) -> Sink a

-->

\begin{abstract} We present a novel stream-programming library for a
variant of Haskell extended with linear
types\cite{bernardy_retrofitting_2017}.  As other coroutine-based stream
libraries, our library allows synchronous execution, which implies
that effects are run in lockstep and that no buffering occurs.

A novelty of our implementation is that it allows to locally introduce
buffering or re-scheduling of effects. The buffering requirements (or
re-scheduling opportunities) are indicated by the type-system.

Our additionally serves to expand the corpus of effectful programs and
libraries written in functional programming languages with linear
types. Our aim is to present principles which are applicable to the
design of libraries and programs where resource management (memory,
IO, ...) is critical.  \end{abstract}

\keywords
Streams, Continuations, Linear Types

Introduction
============

As \citet{hughes_functional_1989} famously noted, the strength of
functional programming languages resides in the composition mechanisms
that they provide. That is, simple components can be built and
understood in isolation; one does not need to worry about interference
effects when composing them. In particular, lazy evaluation affords to
construct complex programs by pipelining simple transformation
functions. Indeed, whereas strict evaluation forces to fully reify each
intermediate result between each computational step, lazy
evaluation allows to run all the computations concurrently, often
without ever allocating more than a single intermediate element at a time.

Unfortunately, lazy evaluation suffers from two drawbacks.  First, it
has unpredictable memory behavior. Consider the following function
composition:

< f :: [a] -> [b]
< g :: [b] -> [c]
< h = g . f

One hopes that, at run-time, the intermediate list ($[b]$)
will only be allocated element-wise, as outlined above. Unfortunately,
this desired behavior does not always happen. Indeed, a
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

< main = do  inFile <- openFile "foo" ReadMode
<            contents <- hGetContents inFile
<            putStr contents
<            hClose inFile
<
< main = do  inFile <- openFile "foo" ReadMode
<            contents <- hGetContents inFile
<            hClose inFile
<            putStr contents

Indeed, the \var{putStr} and \var{hClose} commands act on unrelated
resources, and thus swapping them should have no observable effect.
However, while the first program prints the `foo` file, the second one
prints nothing.  Indeed, because \var{hGetContents} reads the file
lazily, the \var{hClose} operation has the effect to truncate the
list. In the first program, printing the contents forces reading the
file. One may argue that \var{hClose} should not be called in the
first place --- but then, closing the handle happens only when the
\var{contents} list can be garbage collected (in full), and relying on
garbage collection for cleaning resources is brittle; furthermore
this effect compounds badly with the first issue discussed above (unpredictability of buffering).  If
one wants to use lazy effectful computations, again, the
compositionality principle is lost.

In this paper, we propose to tackle both of these issues by taking
advantage of linear types.  One way to read this paper is as
an advocacy for linear types support in Haskell. Indeed, even though
one can tackle the above issues by using Monad-based libraries
\citep{kiselyov_iteratees_2012} our linear-logic-based types naturally capture
a wealth of useful production and consumption patterns.

The first noteworthy type, corresponding to on-demand production of elements, is called a
source (\var{Src}). An adaptation of the first code example above to
use sources would look as follows.

< f :: Src a ⊸ Src b
< g :: Src b ⊸ Src c
< h = g . f

Thanks to type-checking, we get the guarantee that the
composition does not allocate more memory than the sum of its
components. The second useful type, driving the consumption of elements, is called a sink
(\var{Snk}).  For example, the standard output is naturally given a
sink type:

< stdoutSnk :: Snk String

Using it, we can implement the printing of a file as follows.

> main = fileSrc "foo" `fwd` stdoutSnk

Beyond frugal memory usage, we have the
guarantee of a timely release of resources, even in the presence of
exceptions.
In the above, \var{fileSrc} provides the contents of a file, and
\var{fwd} forwards data from a source to a sink.  The types are as
follows:

< fileSrc :: FilePath -> Src String
< fwd :: Src a ⊸ Snk a ⊸ IO ()

Sources provide data on-demand, while sinks decide when they are ready
to consume data. This is an instance of the push/pull duality.  In
general, push-streams control the flow of computation, while
pull-streams respond to it. We will see that this polarization does
not need to match the flow of data: for example we support data
sources with push-flavor, called co-sources (\var{CoSrc}).
Co-sources are useful for example when a source data stream needs precise
control over the execution of effects it embeds (see
Sec. \ref{async}). For example, sources cannot be demultiplexed, but
co-sources can.

In a program which uses both sources and co-sources, the need might
arise to compose a function which returns a co-source with a function
which takes a source as input: this is the situation where list-based
programs would silently cause memory allocation. In our approach, this
mismatch is caught by the type system, and the user must explicitly
conjure a buffer to be able to write the composition:

< f :: Src a ⊸ CoSrc b
< g :: Src b ⊸ Src c
< h = g . buffer . f

The contributions of this paper are

* The formulation of principles for compositional resource-aware
programming in Haskell (resources include memory and files), based on
linearity and polarization. While these principles are borrowed
from linear logic, as far as we know they have not been applied to
Haskell programming before.

* An embodiment of the above principles, in the form of a Hask-LL\footnote{Hask-LL is an extension of Haskell to linear types fully described by \citet{bernardy_retrofitting_2017}. For the purposes of this paper, the main addition is the linear arrow (⊸) for functions which guarantee to consume their argument exactly once. Pairs also become linear.}
library for streaming `IO`.
Besides supporting compositionality as
outlined above, our library features two concrete novel aspects:

  1. A more lightweight design than state-of-the-art co-routine based
    libraries.

  2. Support for explicit buffering and control structures, while
    still respecting compositionality (Sec. \ref{async}).

\paragraph{Outline} The rest of the paper is structured as follows.
In Sec. \ref{negations}, we recall the notions of continuations in presence of effects.
In Sec. \ref{streams}, we present our design for streams, and justify it by appealing to linearity principles.
In Sec. \ref{effect-free-streams}, we give an API to program with streams, and analyze their algebraic structure.
In Sec. \ref{effectful-streams}, we show how to embed IO into streams.
In Sec. \ref{async}, we discuss polarity mismatch.
Related work and future work are discussed respectively in sections \ref{related-work} and \ref{future-work}.
We conclude in Sec. \ref{conclusion}.



Preliminary: negation and continuations
=======================================
\label{negations}

In this section we recall the basics of continuation-based
programming. We introduce our notation, and justify effectful
continuations.

We begin by assuming a type of effects \var{Eff}, which we keep
abstract for now. We can then define negation as follows:

> type N a = a ⊸ Eff

A shortcut for double negations is also convenient.

> type NN a = N (N a)

The basic idea (imported from classical logic) pervading this paper
is that in the presence of effects, producing a result of type α is equivalent to consuming an
argument of type $N α$. Dually, consuming an argument of type α is
equivalent to producing a result of type $N α$. We call
these equivalences the duality principle.

In classical logic, negation is involutive; that is: $\var{NN}\,α = α$.
However, because we work within Haskell, we do not have this
equality\footnote{Even though
\citet{munch-maccagnoni_formulae-as-types_2014} achieves an involutive
negation in an intuitionistic language, he does so by stack
manipulation, which is not available in Haskell.}.  We can come close
enough though.  First, double negations can always be introduced,
using the \var{shift} operator:

> shift :: a ⊸ NN a
> shift x k = k x

Second, it is possible to remove double negations, but only if an
effect can be outputted.  Equivalently, triple negations can be
collapsed to a single one:

> unshift :: N (NN a) ⊸ N a
> unshift k x = k (shift x)

Aside. The above two functions are the \var{return} and \var{join} of the
double negation monad\footnote{for \var{join}, substitute $N\,a$ for
$a$ in the type of \var{unshift}}; indeed adding a double negation in
the type corresponds to sending the return value to its
consumer. However, we will not be using this monadic structure
anywhere in the following, because single negations play a central
role in our approach. The monadic structure is a mere diversion.

Structure of Effects
--------------------

When dealing with purely functional programs, continuations have no
effects. In this case, one can let \var{Eff} remain abstract, or
define it to be the empty type: $\var{Eff} = \bot$. This choice is also
natural when interpreting the original linear logic of
\citet{girard_linear_1987,laurent_etude_2002}.

The pure logic treats effects purely abstractly, but interpretations
may choose to impose a richer structure on them. Such interpretations
would then not be complete with respect to the logic --- but they
would remain sound.
In our case, we first require \var{Eff} to be a monoid. Its unit
(\var{mempty}) corresponds to program termination, while the operator
(\var{mappend}) corresponds to sequential composition of effects.
(This structure is standard to interpret the \smallcaps{halt} and
\smallcaps{mix} rules in linear logic
\citep{bernardy_composable_2015,mellis_resource_2010})

For users of the stream library, \var{Eff} shall remain an abstract
monoid. However in this paper we develop concrete effectful
streams, and therefore we greatly extend the structure of effects. In
fact, because we will provide streams interacting with files and other
operating-system resources, and write the whole code in standard
Hask-LL, we must pick $\var{Eff} = \var{IO} ()$, and ensure that
\var{Eff} can be treated as a linear monoid.

> type Eff = IO ()

< class Monoid a where
<   mempty :: a
<   mappend :: a ⊸ a ⊸ a
< instance Monoid Eff

The parts of the code which know about $\var{Eff} = \var{IO} ()$ must
be carefully written, because the type system does not provide strong
guarantees about such code. In fact these IO-interacting functions do not
interpret ⊥ in a standard way: they are non-standard extensions of its model.

Streams
=======

Our main guiding design principle is duality. In fact we will make
crucial use of duality in the later sections of this paper.  The
duality principle is reflected in the design of the streaming
library: we not only have a type for sources of data but also a type
for sinks. For example, a simple stream processor reading from a
single source and writing to a single sink may be given the
following type:

< simple :: Src a ⊸ Snk a ⊸ Eff

We will make sure that \var{Snk} is the negation of a source (and vice
versa), and thus the type of the above program may equivalently be
be given the following type:

< simple :: Src a ⊸ Src a

However, having explicit access to sinks allows us to (for example)
dispatch a single source to multiple sinks, as in the following type signature:

< forkSrc :: Src (a,b) ⊸ Snk a ⊸ Snk b ⊸ Eff

We define sources and sinks by mutual recursion. Producing a
source means to select if some more is available (\var{Cons}) or not
(\var{Nil}). If there is data, one must then produce a data item and
*consume* a sink.

< data Source  a  where
<   Nil :: Source a
<   Cons :: a ⊸ N (Sink a) ⊸ Source a
< data Sink    a  where
<   Full :: Sink a
<   Cont :: (N (Source  a)) ⊸ Sink a

Producing a sink means to select whether one can accept more elements
(\var{Cont}) or not (\var{Full}). In the former case, one must then be
able to consume a source. The \var{Full} case is useful when the sink
bails out early, for example when it runs out of space.

Note that, in order to produce (or consume) the next element, the
source (or sink) must handle the effects generated by the other side
of the stream before proceeding. This means that each production is
matched by a consumption, and \textit{vice versa}; element-wise.

Linearity
---------

For streams to be used safely, one cannot discard nor duplicate them,
for otherwise effects may be discarded and duplicated, which is
dangerous.  For example, the same file could be closed twice, or not
at all.  Indeed, the last action of a sink typically involves closing
the file. Timely closing of the sink can only be guaranteed if the
actions are run until reaching the end of the pipe (either \var{Full}
or \var{Nil}).

Linear types allow to capture such an invariant: all functions from our
library treat sources and sinks linearly. We underline that
even individual elements are declared linear, which allow us to
store even effects in them.

Basics
------

As a first illustration, we present three basic functions to manipulate
\var{Source}s and \var{Sink}s: one to read from sources, one to write
to sinks, and one to connect sources and sinks.

\paragraph{Reading}
One may attempt to write the following function, waiting for data to be
produced by a source. The second argument is the effect to run if no
data is produced, and the third is the effect to run given the data
and the remaining source.

< await :: Source a ⊸ Eff ⊸ (a ⊸ Source a ⊸ Eff) ⊸ Eff
< await Nil          eof  _ = eof
< await (Cons x cs)  _    k = cs $ Cont $ \xs -> k x xs

However, the above function breaks linearity (\var{eof} and \var{k} are not
always used), so we cannot define it as such. Instead we have to
arrange the types so that \var{await} can choose *itself* between the \var{eof}
continuation and \var{k}. To do so, we must provide them as a so-called
additive conjunction. The additive conjunction is the dual of the
\var{Either} type: there is a choice, but this choice falls on the
consumer rather than the producer of the input. The additive conjunction,
written &, can be encoded by sandwiching \var{Either} between two
inversions of the control flow, thereby switching the party which makes
the choice:

> type a & b = N (Either (N a) (N b))

(One will recognize the similarity between this definition and the
De Morgan's laws.) Await can then be written as follows:

> await :: Source a ⊸ (Eff & (a ⊸ Source a ⊸ Eff)) ⊸ Eff
> await Nil r = r $ Left $ \eof -> eof
> await (Cons x xs) r = r $ Right $ \c -> xs (Cont (c x))

\paragraph{Writing}

One can also write data into a sink, and obtain a new, (doubly
negated) sink which represents the state of the sink after the "old"
sink has consumed the data.  If the sink is full, the data is ignored.

> yield :: a -> Sink a ⊸ (Sink a ⊸ Eff) ⊸ Eff
> yield x (Cont c) k = c (Cons x k)
> yield x Full k = k Full


Baking in negations
-------------------

Programming with \var{Source} and \var{Sink} explicitly is inherently
continuation-heavy. As we have seen in the definition of `unshift`,
double-negations cannot simply be removed: effects must be collected
and thus most functions must return an `Eff`. Thus it is convenient to
introduce negated variants of source and sink types.

> type Src   a = N  (Sink a)
> type Snk   a = N  (Src a)

These definitions have the added advantage to perfect the duality
between sources and sinks, while not restricting the programs one can
write. A benefit of the above definitions is that it becomes
possible to forward data from \var{Src} to \var{Snk} without dropping elements:

> fwd :: Src a ⊸ Snk a ⊸ Eff
> fwd = shift

We additionally introduce the following type synonym, which is used to
write the types of functions which manipulate `Source`s directly.

> type Snk'  a = N (Source a)

Functions over \var{Snk'} can be lifted manipulate \var{Src}, and in turn
\var{Snk}. We can do so generically for endomorphisms:

> flipSnk ::  (Snk' a  ⊸ Snk' b)  ->  Src b  ⊸ Src a
> flipSrc  ::  (Src a  ⊸ Src b)  ->  Snk b  ⊸ Snk a
> flipSnk _ s Full = s Full
> flipSnk f s (Cont k) = s $ Cont $ (f k)
> flipSrc f snk src = snk (f src)

As a particular case, consider the mapping functions:

> mapSrc  :: (a ⊸ b) -> Src  a ⊸ Src  b
> mapSnk  :: (b ⊸ a) -> Snk  a ⊸ Snk  b

Mapping sinks is defined by flipping the mapping of sources; and
mapping of sources is defined by flipping mapping of negated sources:

> mapSnk f = flipSrc (mapSrc f)
> mapSrc f = flipSnk (mapSnk' f)

Mapping of negated sources is defined by case analysis on the concrete
source, and the recursive case conveniently calls \var{mapSrc}.

> mapSnk' _ snk Nil = snk Nil
> mapSnk' f snk (Cons a s)
>   = snk (Cons (f a) (mapSrc f s))


When using double negations, it is sometimes useful to insert or
remove them inside type constructor. Introduction of double negation
in sources and its elimination in sinks is a special case of mapping.

> nnIntro :: Src a ⊸ Src (NN a)
> nnIntro = mapSrc shift

> nnElim' :: Snk (NN a) ⊸ Snk a
> nnElim' = mapSnk shift

The duals are implemented by case analysis, following the mutual
recursion pattern introduced above.

> nnElim :: Src (NN a) ⊸ Src a
> nnIntro' :: Snk' a ⊸ Snk' (NN a)

> nnElim = flipSnk nnIntro'
> nnIntro' k Nil = k Nil
> nnIntro' k (Cons x xs) = x $ \x' -> k (Cons x' $ nnElim xs)

Effect-Free Streams
===================

The functions seen so far make no use of the fact that \var{Eff} can
embed IO actions. Indeed, a large number of useful functions over
streams can be implemented without relying on IO. We give an overview
of effect-free streams in this section.

List-Like API
-------------

To begin, we show that one can implement a list-like API for
sources, as follows:

> empty :: Src a
> empty Full = mempty
> empty (Cont k) = k Nil

> cons :: a ⊸ Src a ⊸ Src a
> cons a s s' = yield a s' s

(Taking the head or tail is not meaningful due to the linearity
constraints: \var{await} must be used instead.)

Another useful function is the equivalent of \var{take} on lists.
Given a source, we can create a new source which ignores all but its
first $n$ elements. Conversely, we can prune a sink to consume only
the first $n$ elements of a source. We can even do it without breaking linearity,
because all streams support early stopping.

> takeSrc  :: Int -> Src  a ⊸ Src  a
> takeSnk  :: Int -> Snk  a ⊸ Snk  a

The natural implementation is again by mutual recursion. The main
subtlety is that, when reaching the $n$th element, both ends of the
stream must be notified of its closing. Note the use of the monoidal
structure of \var{Eff} in this case.

> takeSrc 0 s t = s Full <> empty t
> takeSrc i s t = flipSnk (takeSnk' i) s t

> takeSnk' _ s Nil = s Nil
> takeSnk' i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))

> takeSnk n = flipSrc (takeSrc n)


Algebraic structure
-------------------

Source form a (linear) monoid under concatenation:

> instance Monoid (Src a) where
>   mappend = appendSrc
>   mempty = empty

> instance Monoid (Snk a) where
>   mappend = appendSnk
>   mempty = shift Full

We have already encountered \var{empty} above;
the appending operations are defined below.  Intuitively,
\var{appendSrc} first gives control to the first source until it runs
out of elements and then turns control over to the second source. This
behavior is implemented in the helper function \var{forwardThenSnk}.

> appendSrc :: Src a ⊸ Src a ⊸ Src a
> appendSrc s1 s2 Full = s1 Full <> s2 Full
> appendSrc s1 s2 (Cont s)
>   = s1 (Cont (forwardThenSnk' s s2))

> forwardThenSnk' :: Snk' a ⊸ Src a ⊸ Snk' a
> forwardThenSnk' snk' src Nil = src (Cont snk')
> forwardThenSnk' snk' src (Cons a s)
>   = snk' (Cons a (appendSrc s src))

Sinks can be appended is a similar fashion.

> appendSnk' :: Snk' a ⊸ Snk' a ⊸ Snk' a
> appendSnk' s1 s2 Nil = s1 Nil <> s2 Nil
> appendSnk' s1 s2 (Cons a s)
>   = s1 (Cons a (forwardThenSrc s2 s))

> forwardThenSrc :: Snk' a ⊸ Src a ⊸ Src a
> forwardThenSrc s2 = flipSnk (appendSnk' s2)

> appendSnk ::  Snk a -> Snk a -> Snk a
> appendSnk t1 t2 s = t1 $ \case
>   Full -> t2 empty <> s Full
>   Cont k -> flipSrc (forwardThenSrc k) t2 s

The operations \var{forwardThenSnk} and \var{forwardThenSrc} are akin
to taking the difference between a source and a sink. Thus we find it
convenient to give them the following aliases:

> (-?) :: Snk' a ⊸ Src a ⊸ Snk' a
> t -? s = forwardThenSnk' t s

> (-!) :: Snk' a ⊸ Src a ⊸ Src a
> t -! s = forwardThenSrc t s

> infixr -!
> infixl -?

Appending and subtracting interact in the expected way. That is, the
following equalities hold observationally:

< t -? (s1 <> s2) == t -? s2 -? s1
< (t1 <> t2) -! s == t1 -! t2 -! s

 <!--

Not sure if these are true or what

> prop_diff3 t1 t2 s = (t1 <> t2) -? s == t1 -? (t2 -! s)
> prop_diff4 t s1 s2 = t -! (s1 <> s2) == (t -? s1) -! s2

The proofs for the above laws can be found in Appendix \ref{proof}.

  -->

\paragraph{Functor}
We have already seen the mapping functions for sources and sinks:
sources are functors and sinks are contravariant functors. (Given the
implementation of the morphism actions it is straightforward to check
the functor laws.)

Table of effect-free functions
------------------------------

The above gives already an extensive API for sources and sinks, many
more useful effect-free functions can be implemented on this basis. We
give here a menu of functions that we have implemented, and whose
implementation is available online\footnote{https://github.com/jyp/organ/blob/master/Organ-HaskeLL.lhs}.

Two sources can be zipped if some extra left-over elements can be
dropped. Equivalently, a sink can be forked in the same situation.

> class Drop a where drop :: a ⊸ b ⊸ b

> zipSrc :: (Drop a, Drop b) => Src a ⊸ Src b ⊸ Src (a,b)
> forkSnk :: (Drop a, Drop b) => Snk (a,b) ⊸ Src a ⊸ Snk b

 <!--
or: forkSnk :: Snk (a,b) ⊸ Snk a ⅋ Snk b
-->

Zip two sinks, and the dual.

> forkSrc :: Src (a,b) ⊸ Snk a ⊸ Src b
> zipSnk :: Snk a ⊸ Snk b ⊸ Snk (a,b)

Equivalent of \var{scanl'} for sources, and the dual

> scanSrc :: (b -> a ⊸ (b,c)) -> b -> Src a ⊸ Src c
> scanSnk :: (b -> a ⊸ (b,c)) -> b -> Snk c ⊸ Snk a

Equivalent of \var{foldl'} for sources, and the dual.

> foldSrc' :: (b -> a ⊸ b) -> b -> Src a ⊸ NN b
> foldSnk' :: (b -> a ⊸ b) -> b -> N b ⊸ Snk a

Drop some elements from a source, and the dual.

> dropSrc :: Drop a => Int -> Src a ⊸ Src a
> dropSnk :: Drop a => Int -> Snk a ⊸ Snk a

Convert a list to a source, and vice versa.

> fromList :: [a] ⊸ Src a
> toList :: Src a ⊸ NN [a]

Split a source in lines, and the dual.

> linesSrc :: Src Char ⊸ Src String
> unlinesSnk :: Snk String ⊸ Snk Char

Interleave two sources, and the dual.

> interleave :: Src a ⊸ Src a ⊸ Src a
> interleaveSnk :: Snk a ⊸ Src a ⊸ Snk a

Forward data coming from the input source to the result source and to
the second argument sink.

> tee :: (a ⊸ (b,c)) -> Src a ⊸ Snk b ⊸ Src c

Filter a source, and the dual.

> filterSrc :: (a ⊸ Maybe b) ⊸ Src a ⊸ Src b
> filterSnk :: (a ⊸ Maybe b) ⊸ Snk b ⊸ Snk a

Turn a source of chunks of data into a single source; and the dual.

> unchunk :: Src [a] ⊸ Src a
> chunkSnk :: Snk a ⊸ Snk [a]


App: Stream-Based Parsing
-------------------------

To finish with effect-free functions, we give an example of a
stream processor which applies a parser to a source of symbols and returns
a source of parse results.  This conversion is useful
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
> instance Applicative (Parser s) where
>   pure = return
>   (<*>) = ap
> instance Functor (Parser s) where
>   fmap = (<$>)

The essential parsing ingredient, choice, rests on the
ability to weave processes together; picking that which
succeeds first, and that which fails as last resort:

> weave :: P s a -> P s a -> P s a
> weave Fail x = x
> weave x Fail = x
> weave (Result res) _ = Result res
> weave _ (Result res) = Result res
> weave (Sym k1) (Sym k2)
>     = Sym (\s -> weave (k1 s) (k2 s))

> (<|>) :: Parser s a -> Parser s a -> Parser s a
> P p <|> P q = P (\fut -> weave (p fut) (q fut))


Parsing then reconciles the execution of the process with the
traversal of the source. In particular, whenever a result is
encountered, it is fed to the sink. If the parser fails, both ends of
the stream are closed.

> parse :: forall s a. Parser s a -> Src s ⊸ Src a
> parse _ src Full = src Full
> parse q@(P p0) src (Cont k) = scan (p0 $ \x -> Result x) k src
>  where
>  scan :: P s a -> Snk' a ⊸ Src s ⊸ Eff
>  scan (Result res  )  ret        xs     = ret (Cons res (parse q xs))
>  scan Fail            ret        xs     = ret Nil <> xs Full
>  scan (Sym f)         mres       xs     = xs $ Cont $ \case
>    Nil        -> scan (f Nothing) mres empty
>    Cons x cs  -> scan (f $ Just x) mres cs




Effectful streams
=================

So far, we have constructed only effect-free streams. That is, effects
could be any monoid, and in particular the unit type.  In this
section we bridge this gap and provide some useful sources and sinks
performing IO effects, namely reading and writing to files.

We first define the following helper function, which sends data to a
handle, thereby constructing a sink.

> hFileSnk' :: Handle -> Snk' String
> hFileSnk' h Nil = hClose h
> hFileSnk' h (Cons c s) = do
>   hPutStrLn h c
>   hFileSnk h s

> hFileSnk :: Handle -> Snk String
> hFileSnk h = shift (Cont (hFileSnk' h))

A file sink is then simply:

> fileSnk :: FilePath -> Snk String
> fileSnk file s = do
>   h <- openFile file WriteMode
>   hFileSnk h s

And the sink for standard output is:

> stdoutSnk :: Snk String
> stdoutSnk = hFileSnk stdout

(For ease of experimenting with our functions, the data items are
lines of text --- but an production-strength version would provide
chunks of raw binary data, to be further parsed.)

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

It should be emphasized at this point that when running \var{copyFile}
reading and writing will be interleaved: in order to produce the next
line in the source (in this case by reading from the file), the
current line must first be consumed in the sink (in this case by
writing it to disk).  The stream behaves fully synchronously, and no
intermediate data is buffered.

Whenever a sink is full, the source connected to it should be finalized.
The next example shows what happens when a sink closes the stream
early. Instead of connecting the source to a bottomless sink, we
connect it to one which stops receiving input after three lines.

> read3Lines :: Eff
> read3Lines = fwd  (hFileSrc stdin)
>                   (takeSnk 3 $ fileSnk "text.txt")

Indeed, testing the above program reveals that it properly closes
\var{stdin} after reading three lines. This early closing is
critical to modular stream programming: it allows proper finalization
of one end when an exception occurs at the other end.

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
way. The file sink is responsible for handling its own exceptions so
there is no need to insert a handler around the invocation of the
continuation \var{c}. 
Thus, dealing with exceptions is done once and for all when implementing the
library of streams. The programmer using the library does not have to
be concerned with exceptions as they are caught and communicated
properly under the hood, even if one would probably have a component of
the \var{Eff} type indicating the nature
of the exception encountered, if any. Yet we leave it out in the proof
of concept implementation presented in this paper.

Using exception handlers, as in the above snippet, will secure the
library from synchronous exceptions arising from accessing the file,
but not from asynchronous exceptions which may come from other
sources. Asynchronous exception-safety requires more machinery. The
region library presented in \citet{kiselyov2008lightweight} can be
used for this purpose, as outlined in
\citet{kiselyov12:region_iteratees}.


Synchronicity and Asynchronicity
================================
\label{async}

One of the main benefits of streams as defined here is that
the details of synchronizing concrete sink and sources are abstracted over.
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

1. The effects of connected sources and sinks are run synchronously
2. No implicit memory allocation happens

While the guarantees have been discussed so far, it may be unclear how
synchronicity actually restricts the programs one can write. In the
rest of the section we show by example how the restriction plays out.

Example: demultiplexing
-----------------------

One operation supported by synchronous behavior is the demultiplexing
of a source, by connecting it to two sinks (and the dual operation of mutiplexing sinks).

> dmux' :: Src (Either a b) -> Sink a -> Sink b -> Eff
> dmux' sab Full tb = sab Full <> empty tb
> dmux' sab ta Full = sab Full <> empty ta
> dmux' sab (Cont ta) (Cont tb) = sab $ Cont $ \s -> dmux ta tb s

> dmux :: Snk' a -> Snk' b -> Snk' (Either a b)
> dmux ta tb Nil = ta Nil <> tb Nil
> dmux ta tb (Cons ab c) = case ab of
>   Left a -> ta (Cons a $ \ta' -> dmux' c ta' (Cont tb))
>   Right b -> tb (Cons b $ \tb' -> dmux' c (Cont ta) tb')

The key ingredient is that demultiplexing starts by reading the next
value available on the source. Depending on its value, we feed the
data to either of the sinks and proceed. Besides, as soon as any of
the three parties closes the stream, the other two are notified.

However, multiplexing sources cannot be implemented while respecting
synchronicity. To see why, let us attempt anyway, using the following
type signature:

< mux :: Src a ⊸ Src b ⊸ Src (Either a b)
< mux sa sb = ?

We can try to fill the hole by reading on a source. However, if we do
this, it falls onto the multiplexer to choose which source to
run first. We may pick \var{sa}, however it may be blocking, while
\var{sb} is ready with data. This is not really multiplexing, at best
this approach would give us interleaving of data sources, by taking
turns.

In order to make any progress, we can let the choice of which source
to pick fall on the consumer of the stream. The type that we need for
output data in this situation is the additive conjunction. 
We can then amend the type of multiplexing:

> mux :: Src a ⊸ Src b ⊸ Src (a & b)

Unfortunately, we still cannot implement multiplexing with the above
type. Indeed, consider the following attempt, where we begin by asking
the consumer if it desires $a$ or $b$. If the answer is $a$, we can
extract a value from \var{sa} and yield it; and symmetrically for $b$.

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
--------------------

We call the structure that we are looking for a
*co-source*. Co-sources are the subject of this section.  We remember
that producing $N a$ is equivalent to consuming $a$, thus that a sink of $N
a$ is a (different kind of) source of $a$. We define:

> type CoSrc a = Snk (N a)
> type CoSnk a = Src (N a)

Implementing multiplexing on co-sources is then straightforward, by
leveraging \var{dmux'}:

> mux' :: CoSrc a ⊸ CoSrc b ⊸ CoSrc (a & b)
> mux' sa sb tab = sa $ \sa' -> sb $ \sb' -> dmux' (nnElim tab) sa' sb'


We use the rest of this section to study the property of co-sources and
co-sinks. Firstly \var{CoSrc} is a functor, and \var{CoSnk} is a contravariant functor.

> mapCoSnk :: (b ⊸ a) -> CoSnk a ⊸ CoSnk b
> mapCoSnk f = mapSrc (\b' -> \a -> b' (f a))

> mapCoSrc :: (a ⊸ b) -> CoSrc a ⊸ CoSrc b
> mapCoSrc f snk src = snk (mapCoSnk f src)

Elements of a co-source are accessed only in when and in the order
that the co-source imposes. Consequently, one cannot in general
extract the contents of a co-source as a list. Attempting to implement
this extraction looks as follows.

> coToList :: Snk' (N a) -> NN [a]
> coToList k1 k2 = k1 $ Cons (\a -> k2 [a]) (error "rest")
> coToList k1 k2 = k2 $ (error "a?") : (error "rest")

If one tries to begin by eliminating the co-source (first equation), then there is no
way to produce subsequent elements of the list. If one tries to begin
by constructing the list (second equation), then no data is available.

Yet it is possible to define useful co-sources and co-sinks. The first
example shows how to provide a file as a co-source:

> coFileSrc :: Handle -> CoSrc String
> coFileSrc h snk = do
>   e <- hIsEOF h
>   snk $ if not e
>     then Full
>     else Cont $ \case
>        Nil -> hClose h
>        Cons x xs -> do
>           x' <- hGetLine h
>           x x'              -- (1)
>           (coFileSrc h) xs  -- (2)


Compared to \var{fileSrc}, the difference are that this function
decides the ordering of effects ran in a co-sink connected to it. That is,
even though there is no data dependency between the lines (1) and (2), they are
run in a specific, given order.
We will see in the next section how this situation generalizes.

The second example is an infinite co-sink that sends data to a file.

> coFileSink :: Handle -> CoSnk String
> coFileSink h Full = hClose h
> coFileSink h (Cont c) = c (Cons  (hPutStrLn h)
>                                  (coFileSink h))

Compared to \var{fileSnk}, the difference is that the program does not control
the order of execution of effects. The effect of writing the current
line is put in a data structure, and its execution is up to the
co-source which eventually connects to the co-sink. Thus, the
order of writing lines in the file depends on the order of effects chosen
in the co-source connected to this co-sink.

In sum, shifting from streams to co-streams shifts the control flow
responsibility from the sink to the (co-)source. It should be stressed
that, in the programs which use the functions defined so far (even
those that use \var{IO}), synchronicity is preserved: no data is buffered
implicitly, and reading and writing occur in lockstep.

Asynchronicity
--------------

We have seen so far that synchronicity gives useful guarantees, but
restricts the kind of programs one can write. In this section, we
provide primitives which allow controlled asynchronous programming within
our framework.
The main benefit of sticking to our framework in this case is that
asynchronous behavior is circumscribed to the explicit usages of these
primitives. That is, the benefits of synchronous programming still
hold locally.

\paragraph{Scheduling} Asynchronicity arises either from an excess or
a deficit of control. Let us first examine the latter case, which
involves two streams that do not control the flow of execution. This
means that effects must be scheduled explicitly and externally to the
streams.  This situation arises for example converting a \var{Src} to
a \var{CoSrc}, as we have seen in the example above, when writing the
file co-source.

In general, given a \var{Schedule}, we can implement the following two
conversions:

> srcToCoSrc :: Schedule a -> Src a ⊸ CoSrc a
> coSnkToSnk :: Schedule a -> CoSnk a ⊸ Snk a

We define a \var{Schedule} as the reconciliation between a source and a
co-sink:

> type Schedule a = Source a ⊸ CoSnk a ⊸ Eff

Implementing the conversions is then straightforward:

> srcToCoSrc strat s0 s = s0 $ Cont (flip strat s)
> coSnkToSnk strat s0 s = s $ Cont (flip strat s0)

What are possible scheduling strategies? The simplest, and most
natural one is sequential execution. Namely, looping through both sources and
match the consumptions/productions element-wise, as follows.

> sequentially :: Drop a => Schedule a
> sequentially Nil s = s Full
> sequentially (Cons x xs) s = s $ Cont $ \s' -> case s' of
>   Cons x' xs' -> do
>     x' x
>     xs $ Cont $ \t -> sequentially t xs'
>   Nil -> drop x (xs Full)

For most streams, sequential execution is the only sensible schedule:
indeed, sources and sinks often expect their effects to be run in the
order prescribed by the stream. Swapping the arguments to `<>` in the
above means that \var{Full} effects will be run first, spelling
disaster.

However, in certain cases running effects out of order may make
sense. If the monoid of effects is commutative (or if the programmer
is confident that execution order does not matter) one can shuffle
the order of execution of effects. This re-ordering can be taken
advantage of to run effects concurrently, as follows:


> concurrently :: Drop a => Schedule a
> concurrently Nil s = s Full
> concurrently (Cons x xs) s = s $ Cont $ \s' -> case s' of
>   Cons x' xs' -> do
>     forkIO (x' x)
>     xs $ Cont $ \t -> concurrently t xs'
>   Nil -> drop x (xs Full)

The above strategy is useful if the production or consumption
of elements is expensive and distributable over computation units.
While the above implementation naively spawns a thread for every
element, in reality one should most likely divide the stream
into chunks before spawning threads. Because strategies are separate
components, a bad choice is easily remedied to by swapping one
strategy for another.

\paragraph{Buffering}

Consider now the dual situation where we have two streams and both of
them want to control the execution flow, for example when converting a
\var{CoSrc} to a \var{Src}.  The conciliation can only be implemented
by running both streams in concurrent threads, and have them
communicate via some form of buffer. Using the primitives seen so far,
one can implement a file-based buffer, as follows:

> fileBuffer :: String -> CoSrc String ⊸ Src String
> fileBuffer tmpFile f g = do
>   h' <- openFile  tmpFile WriteMode
>   forkIO $ f (coFileSink h')
>   h <- openFile tmpFile ReadMode
>   hFileSrc h g

It should be stressed that buffering is a risky operation: it is a
balancing act between the amount of resources one is prepared to
allocate and the dynamic behaviours of the streams.  In fact, our
simple file-buffer above is likely to fail if the intermediate file is
a regular file. Indeed, the reader may for example be faster than the
writer and reach an end of file prematurely. One can use instead a
UNIX pipe, but then one then faces the issue that pipes are of fixed
maximum size: if the writer outputs data in too large chunks, a
deadlock will occur.

If one is prepared to use unbounded memory, one may use Concurrent Haskell
channels as a buffering means:

> chanCoSnk :: Chan a -> CoSnk a
> chanCoSnk _ Full = return ()
> chanCoSnk h (Cont c) = c (Cons  (writeChan h)
>                                 (chanCoSnk h))

> chanSrc :: Chan a -> Src a
> chanSrc _ Full = return ()
> chanSrc h (Cont c) = do  x <- readChan h
>                          c (Cons x $ chanSrc h)

> chanBuffer :: CoSrc a ⊸ Src a
> chanBuffer f g = do
>   c <- newChan
>   forkIO $ f (chanCoSnk c)
>   chanSrc c g


Note that it is easy to create a bounded channel-based buffer, by
guarding the writes with a semaphore.

> chanCoSnk' :: Chan a -> QSem -> CoSnk a
> chanCoSnk' _ _ Full = return ()
> chanCoSnk' h s (Cont c) = c (Cons  write
>                                    (chanCoSnk' h s))
>  where write x = do  waitQSem s
>                      writeChan h x

> chanSrc' :: Chan a -> QSem -> Src a
> chanSrc' _ _ Full = return ()
> chanSrc' h s (Cont c) = do  x <- readChan h
>                             signalQSem s
>                             c (Cons x $ chanSrc' h s)

> boundedChanBuffer :: Int -> CoSrc a ⊸ Src a
> boundedChanBuffer n f g = do
>   c <- newChan
>   s <- newQSem n
>   forkIO $ f (chanCoSnk' c s)
>   chanSrc' c s g


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

> varBuffer :: a -> CoSrc a ⊸ Src a
> varBuffer initialValue f g = do
>   c <- newIORef initialValue
>   forkIO $ f (varCoSnk c)
>   varSrc c g

The above buffering operations work on sources, but they can be generically
inverted to work on sinks, as follows.

> flipBuffer :: (forall a. CoSrc a ⊸ Src a) -> Snk b ⊸ CoSnk b
> flipBuffer f s = f (s . nnElim)


Summary
-------

In sum, we can classify streams according to polarity:

- Pull: source and co-sinks
- Push: sinks and co-sources

We then have three situations when composing stream processors:

1. Matching polarities (one pull, one push). In this case behavior is
synchronous; no concurrency appears.

2. Two pull streams. In this case an explicit loop must process the
streams.  If effects commute, the programmer may run effects out of
order, potentially concurrently.

3. Two push streams. In this case the streams must run in independent
threads, and the programmer needs to make a choice for the communication
buffer. One needs to be careful: if the buffer is to small a deadlock
may occur.

Therefore, when programming with streams, one should consume push
types when one can, and pull ones when one must. Conversely, one
should produce pull types when one can, and push ones when one
must.

App: idealized echo server
---------------------

We finish the exposition of asynchronous behavior with a small program
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

> type Client a = (CoSrc a ⊗ Snk a)

For simplicity we implement a chat server handling exactly two
clients.

The first problem is to multiplex the inputs of the clients. In the
server, we do not actually want any client to be controlling the
processing order. Hence we have to multiplex the messages in real time,
using a channel (note the similarity with \var{chanBuffer}):

> bufferedDmux :: CoSrc a ⊸ CoSrc a ⊸ Src a
> bufferedDmux s1 s2 t = do
>   c <- newChan
>   forkIO $ s1 (chanCoSnk c)
>   forkIO $ s2 (chanCoSnk c)
>   chanSrc c t

We then have to send each message to both clients. This may be done
using the following effect-free function, which forwards everything
sent to a sink to its two argument sinks.

> collapseSnk' :: (a ⊸ (b,c)) -> Snk' b ⊸ Snk' c ⊸ Snk' a
> collapseSnk' _    t1 t2 Nil = t1 Nil <> t2 Nil
> collapseSnk' dup  t1 t2 (Cons x xs)
>   =  t1  (Cons y $ \c1 ->
>      t2  (Cons z $ tee' dup xs c1))
>   where (y,z) = dup x

> tee' :: (a ⊸ (b, c)) -> Src a -> Sink b -> Src c
> tee' deal s1 t1 Full = s1 Full <> empty t1
> tee' deal s1 Full t2 = s1 Full <> empty t2
> tee' deal s1 (Cont t1) (Cont t2) = s1 $ Cont $ collapseSnk' deal t1 t2

The server can then be defined by composing the above two functions.

> server :: (a ⊸ (a,a)) ⊸ Client a ⊸ Client a ⊸ Eff
> server dup (i1,o1) (i2,o2) = fwd  (bufferedDmux i1 i2)
>                                   (collapseSnk dup o1 o2)



Related Work
============



Polarities, data structures and control
---------------------------------------

One of keys ideas formalized in this paper is to classify streams by
polarity. The push polarity (sinks, co-sources) controls the execution
thread, whereas the pull one (sources, co-sinks) provide
data. This idea has been leveraged to
bring efficient array programming facilities to functional programming
\citep{bernardy_composable_2015,claessen2012expressive,ankner_edsl_2013}.

This concept is central in the literature on Girard's linear logic
\citep{laurent_etude_2002,zeilberger_logical_2009}. However, in the
case of streams, this idea dates back at least to
\citet{jackson_principles_1975} (\citet{kay_you_2008} gives a good
summary of Jacksons' insight).

Our contribution is to bring this idea to stream programming in
Hask-LL. (While duality was used for Haskell array programming, it has
not been taken advantage for stream programming, and there was no
emphasis on linearity.) We believe that our implementation brings
together the practical applications that Jackson intended, while being
faithful to the theoretical foundations in logic, via the
double-negation embedding.

Transducers
-----------

\citet{shivers2006continuations} introduces a transducer library which
enables fusing the transducers to avoid the overhead of composition.
Transducers are defined on top of channels, a recursive datatype
reminiscent of our \var{Source} and \var{Sink}. In particular they use
a type for continuations similar to \var{N}. However, a channel is
just one type and does not exhibit the duality that our sources and
sinks provide. Their library do feature a notion of sources and sinks
but they are not the main abstraction. They are simply aids for
providing and consuming data from transducers,
respectively. Transducers are "affine"; they can be used at most
once. The reason linearity is not required is that none of the
transducers are effectful, the library only provides pure
transducers. Therefore it is also not concerned with releasing
resources in a timely fashion.

Iteratees
---------

We consider that the state of the art in Haskell stream processing is
embodied by Kiselyov's iteratees \citeyear{kiselyov_iteratees_2012}.

The type for iteratees can be given the following definitions:

> data I s m a = Done a | GetC (Maybe s -> m (I s m a))

An iteratee $I\,s\,m\,a$ roughly corresponds to a sink of $s$ which also
returns an $a$ --- but it uses a monad $m$ rather than a monoid
\var{Eff} for effects.

The above type contains a continuation in the \var{GetC}
constructor. Therefore, one must be careful about discarding or
duplicating iteratees. Hence, such libraries typically provide
higher-level interfaces to discourage non-linear usages.

A first advantage of our approach is the formulation and emphasis on
the linearity constraint, which is central to correct use of effectful
continuations. It appears that variants of iteratees (including the
*pipes* library) make the representation abstract, but at the cost of
a complex interface for programming them. By stating the linearity
requirement no complex abstract API is necessary to guarantee safety.

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

< type GenT e m = ReaderT (e -> m ()) m
< type Producer m e = GenT e m ()
< type Consumer m e = e -> m ()
< type Transducer m1 m2 e1 e2 =
<   Producer m1 e1 -> Producer m2 e2

Yet, in that work, linearity is only briefly mentioned; the use of a
monad rather than monoid persists; and mismatching polarities are not
discussed, let alone taken advantage of.

Several production-strength libraries have been built upon the concept
of iteratees, including *pipes* \citep{gonzalez_pipes_2015},
*conduits* \citep{snoyman_conduit_2015} and *machines*
\citep{kmett_machines_2015}.  While we focus our comparison with
iteratees, most of our analysis carries to the production libraries.
There is additionally a large body of non peer-reviewed literature
discussing and analyzing either iteratees or its variants. The
proliferation of libraries for IO streaming in Haskell indicates that
a unifying foundation for them is needed, and we hope that the present
paper provides a basis for such a foundation.


Feldspar monadic streams
------------------------

Feldspar, a DSL for digital signal processing, has a notion of streams
built on monads \citep{axelsson_feldspar_2010,svenningsson15:monadic_streams}. In Haskell
the stream type can be written as follows:

< type Stream a = IO (IO a)

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

< Source a = 1 ⊕ (a ⊗ N (Sink a))
< Sink a = 1 ⊕ N (Source a)

For the translation to Haskell, we have chosen to use a lightweight
encoding, assuming linearity of effectful variables; arguing at the
same time for support of linearity in future Haskell versions.  Yet,
other encodings could be chosen. For example, we could have used the
technique of Pucella and Tov (Haskell session types with almost no
class), which does not require abiding to linearity.


Future Work
===========

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

Conclusion
==========

We have cast a new light on the current state of coroutine-based
computation in Haskell, which we have done by drawing inspiration
from classical linear logic. We have further shown that the concepts
of duality and polarity provide design principles to structure
continuation-based code. In particular, we have shown that mismatches
in polarity correspond to buffers and control structures, depending on
the kind of mismatch.

Using effectful continuations is not a new idea; in fact it was the
standard way of writing effectful programs in Haskell 1.2. Later
versions of Haskell switched to a monadic approach. However, given the
issues outlined in the introduction, and especially the error-prone
character of lazy monadic IO, many libraries have reverted to explicitly
using co-routines.

A possible reason for selecting monads over co-routines is that monads
are rooted in solid theory (categories). However, we hope to have
shown that co-routines are also rooted in solid theory, namely
linear logic. If Haskell had support for linear types, co-routines
could be used safely, without the quirks of lazy IO.



\begin{acks}
We gratefully thank Koen Claessen, Atze van der Ploeg and Nicolas
Pouillard for feedback on drafts of this paper.  The source code for
this paper is a literate Haskell file, whose latest version is
available at this url:
https://github.com/jyp/organ/blob/master/Organ-HaskeLL.lhs
\end{acks}


\bibliographystyle{abbrvnat}
\bibliography{PaperTools/bibtex/jp.short,js}

  <!--

\appendix

Table of Functions: implementations
===================================

> zipSource :: (Drop a, Drop b) => Source a -> Source b -> NN (Source (a,b))
> zipSource Nil Nil t = t Nil
> zipSource Nil (Cons x xs) t = drop x (xs Full <> t Nil)
> zipSource (Cons x xs) Nil t = drop x (xs Full <> t Nil)
> zipSource (Cons x xs) (Cons y ys) t = t (Cons (x,y) (zipSrc xs ys)) 
> 
> zipSrc s1 s2 Full = s1 Full <> s2 Full
> zipSrc s1 s2 (Cont k) = s1 $ Cont $ \sa -> 
>                         s2 $ Cont $ \sb -> zipSource sa sb k
> 

> forkSnk t s1 s2 = t (zipSrc s1 s2)

> forkSnk' sab ta tb = ta $ Cont $ \ta' ->
>                     zipSource ta' tb sab
> zipSnk' ta tb sab = forkSource sab ta tb
> zipSnk a b c = a $ \a' -> b $ \b' -> zipSnk (shift a') (shift b') c
>
> forkSource :: Source (a,b) ⊸ N (Source a) ⊸ N (Source b) ⊸ Eff
> forkSource Nil t1 t2 = t1 Nil <> t2 Nil
> forkSource (Cons (a,b) xs) t1 t2 = t1 $ Cons a $ \sa' ->
>   t2 $ Cons b $ \sb' -> forkSrc' xs sa' sb'
> 
> forkSrc' sab Full tb = empty tb <> sab Full
> forkSrc' sab tb Full = empty tb <> sab Full
> forkSrc' sab (Cont ta) (Cont tb) = sab $ Cont $ \sab' -> forkSource sab' ta tb
> 
> forkSrc sab ta tb = ta $ \x -> forkSrc' sab x tb

> tee f s t1 t2 = t1 $ \t -> tee' f s t t2

> collapseSnk :: (a ⊸ (b,c)) -> Snk b ⊸ Snk c ⊸ Snk a
> collapseSnk f t1 t2 s = t2 (tee f s t1)

> scanSrc f !z = flipSnk (scanSnk' f z)

> scanSnk' _ _ snk Nil          = snk Nil
> scanSnk' f z snk (Cons a s)   = snk $  Cons y $
>                                       scanSrc f next s
>   where (next,y) = f z a

> scanSnk f z = flipSrc (scanSrc f z)

> foldSrc' f !z s nb = s (Cont (foldSnk'' f z nb))

> foldSnk' f z nb src = foldSrc' f z src nb

> foldSnk'' _ z nb Nil = nb z
> foldSnk'' f z nb (Cons a s) = foldSrc' f (f z a) s nb

> dropSrc i = flipSnk (dropSnk' i)
> dropSnk' 0 s s' = s s'
> dropSnk' _ s Nil = s Nil
> dropSnk' i s (Cons x s') = drop x (dropSrc (i-1) s' (Cont s))

> dropSnk i = flipSrc (dropSrc i)

> fromList = foldr cons empty

> interleaveSnk a b = flipSrc (interleave b) a
> chunkSnk = flipSrc unchunk
> unlinesSnk = flipSrc linesSrc 
> filterSnk p = flipSrc (filterSrc p)

> enumFromToSrc :: Int -> Int -> Src Int
> enumFromToSrc _ _ Full = mempty
> enumFromToSrc b e (Cont s)
>   | b > e     = s Nil
>   | otherwise = s (Cons b (enumFromToSrc (b+1) e))

> linesSrc = flipSnk unlinesSnk''

> unlinesSnk'' = unlinesSnk' []

> unlinesSnk' :: String -> Snk' String -> Snk' Char
> unlinesSnk' acc s Nil = s (Cons acc empty)
> unlinesSnk' acc s (Cons '\n' s') = s (Cons   (reverse acc)
>                                              (linesSrc s'))
> unlinesSnk' acc s (Cons c s')
>   = s' (Cont $ unlinesSnk' (c:acc) s)

> untilSnk' _ Nil = mempty
> untilSnk' p (Cons a s)
>   | p a  = s Full
>   | True = s (Cont (untilSnk' p))

> interleave s1 s2 Full = s1 Full <> s2 Full
> interleave s1 s2 (Cont s) = s1 (Cont (interleaveSnk' s s2))

> interleaveSnk' snk src Nil = src (Cont snk)
> interleaveSnk' snk src (Cons a s)
>   = snk (Cons a (interleave s src))

> filterSrc p = flipSnk (filterSnk' p)

> filterSnk' _ snk Nil = snk Nil
> filterSnk' p snk (Cons a s) = case p a of
>   Just b -> snk (Cons b (filterSrc p s))
>   Nothing -> s (Cont (filterSnk' p snk))

> unchunk = flipSnk chunkSnk'

> chunkSnk' s Nil = s Nil
> chunkSnk' s (Cons x xs)
>   = (fromList x `appendSrc` unchunk xs) (Cont s)

> toList s k = s (Cont $ toListSnk' k)


> toListSnk' :: N [a] -> Snk' a
> toListSnk' k Nil = k []
> toListSnk' k (Cons x xs) = toList xs $ \xs' -> k (x:xs')


Proofs
======

\label{proof}

The laws can be proved by induction, for finite streams. The following
reasoning is only fast-and-loose in the infinite case, but morally
correct \citet{danielsson_fast_2006}.

Associativity
-------------

\var{Nil} case.

<     ((t1 <> t2) <> t3) Nil
< == -- by def
<     (t1 <> t2) Nil <> t3 Nil
< == -- by def
<     (t1 Nil <> t2 Nil) <> t3 Nil
< == -- by associativity of effect composition
<     t1 Nil <> (t2 Nil <> t3 Nil)
< == -- by def
<     t1 Nil <> ((t2 <> t3) Nil)
< == -- by def
<     (t1 <> (t2 <> t3)) Nil

 \var{Cons} case.

<     ((t1 <> t2) <> t3) (Cons a s0)
< == -- by def
<     (t1 <> t2) (Cons a (t3 -! s0))
< == -- by def
<     t1 (Cons a (t2 -! (t3 -! s0)))
< == -- by IH
<     t1 (Cons a ((t2 <> t3) -! s0))
< == -- by def
<     (t1 <> (t2 <> t3)) (Cons a s0)

 \var{Full} case.
<   ((t1 <> t2) -! s) Full
< == -- by def
<   s (Cont (t1 <> t2))
< == -- by def
<    (t2 -! s) (Cont t1)
< == -- by def
<   (t1 -! (t2 -! s)) Full

 \var{Cont} case.
<   ((t1 <> t2) -! s) (Cont t0)
< == -- by def
<   s (Cont (t0 <> (t1 <> t2)))
< == -- by IH
<   s (Cont ((t0 <> t1) <> t2))
< == -- by def
<   (t2 -! s) (Cont (t0 <> t1))
< == -- by def
<   (t1 -! (t2 -! s)) (Cont t0)

Difference laws
---------------

Let us show only the case for sources, the case for sinks being
similar.


The \var{Full} case relies on the monoidal structure of effects:

<    ((s1 <> s2) <> s3) Full
< ==  -- by def
<    (s1 <> s2) Full <> s3 Full
< ==  -- by def
<    (s1 Full <> s2 Full) <> s3 Full
< ==  -- \var{Eff} is a monoid
<    s1 Full <> (s2 Full <> s3 Full)
< ==  -- by def
<    s1 Full <> (s2 <> s3) Full
< ==  -- by def
<    (s1 <> (s2 <> s3)) Full

The \var{Cont} case uses mutual induction:

<   ((s1 <> s2) <> s3) (Cont k)
< == -- by def
<   (s1 <> s2) (Cont (k -? s3)
< == -- by def
<   s1 (Cont (k -? s3) -? s2)
< == -- mutual IH
<   s1 (Cont (k -? (s2 <> s3)))
< == -- by def
<   (s1 <> (s2 <> s3)) (Cont k)

The \var{Cons} case uses mutual induction:

<   ((k -? s2) -? s1) (Cons a s0)
< == -- by def
<   (k -? s2) (Cons a (s0 <> s1))
< == -- by def
<   k (Cons a ((s0 <> s1) <> s2))
< == -- mutual IH
<   k (Cons a (s0 <> (s1 <> s2))
< == -- def
<   (k -? (s1 <> s2)) (Cons a s0)

(We omit the \var{Nil} case; it is similar to the \var{Full} case)

 -->


 <!--


--  LocalWords:  forkIO readChan writeChan newChan Applicative IORef
--  LocalWords:  coroutine Coroutines hughes compositionality inFile
--  LocalWords:  effectful kiselyov openFile ReadMode hGetContents NN
--  LocalWords:  putStr hClose Girard fileSrc stdoutSnk stdout Src ap
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
--  LocalWords:  zipSrc forkSnk zipSnk scanl scanSrc scanSnk foldl yy
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
--  LocalWords:  Atze der Ploeg enumFromToSrc ScopedTypeVariables acc
--  LocalWords:  TypeOperators RankNTypes LiberalTypeSynonyms reify
--  LocalWords:  BangPatterns TypeSynonymInstances FlexibleInstances
--  LocalWords:  pipelining demultiplexed nnIntro nnElim QSem newQSem
--  LocalWords:  ankner edsl axelsson toListSnk waitQSem signalQSem
--  LocalWords:  maccagnoni formulae smallcaps mellis mazurak CIH zz
--  LocalWords:  boundedChanBuffer danielsson FlexibleContexts Hask

-->
--  LocalWords:  LambdaCase bernardy citep xs endomorphisms fmap dup
--  LocalWords:  observationally mutiplexing affine zipSource ys
--  LocalWords:  forkSource initialValue
