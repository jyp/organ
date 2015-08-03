Possible titles:

- A Linear approach to streaming
- Push and Pull Streams
- On the Duality of Streams

 <!-- general terms are not compulsory anymore, you may leave them out 

\terms
term1, term2

 -->

 <!--

  A bit ugly, and used nowhere.

A non-full sink decides what to do depending on the availability of
data. We could write the following:

> match :: Eff -> (a -> Snk a) -> Snk a
> match nil' cons' k = await k nil' cons'

However, calling \var{await} may break linearity, so we will instead use
\var{match} in the following.
-->

Monad: Problematic because we had the elements data; not effects.
=====

are instances of several common algebraic
structures, yielding a rich API to program using them. This subsection
and the next may be skipped on first reading, to jump to
Sec. \ref{effectful-streams}.



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

< Snk a -> a

There is no way to implement this function since sinks do not store
elements so that they can be returned. Sinks consume elements rather
than producing them.

\paragraph{Divisible and Decidable}

 <!--

> data Void

> class Contravariant f where
>   contramap :: (b -> a) -> f a -> f b


< instance Contravariant Snk where
<   contramap = mapSnk


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

< instance Divisible Snk where
<   divide div snk1 snk2 Nil = snk1 Nil <> snk2 Nil
<   divide div snk1 snk2 (Cons a ss) =
<     snk1 (Cons b $ \ss1 ->
<     snk2 (Cons c $ \ss2 ->
<     shiftSnk (divide div (sinkToSnk ss1)
<                          (sinkToSnk ss2)) ss))
<     where (b,c) = div a
< 
<   conquer = plug

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

< instance Decidable Snk where
<   choose choice snk1 snk2 Nil = snk1 Nil <> snk2 Nil
<   choose choice snk1 snk2 (Cons a ss)
<     | Left b <- choice a = snk1 (Cons b $ \snk1' ->
<       shiftSnk (choose choice (sinkToSnk snk1') snk2) ss)
<   choose choice snk1 snk2 (Cons a ss)
<     | Right c <- choice a = snk2 (Cons c $ \snk2' ->
<       shiftSnk (choose choice snk1 (sinkToSnk snk2')) ss)
< 
<   lose f Nil = return ()
<   lose f (Cons a ss) = ss (Cont (lose f))


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

> type a ⅋ b = N a -> N b -> Eff



Supporting both sources and sinks may appear to be a superficial
advantage, compared to the approach of Kiselyov. However, duality is
fundamental in our work: the existence of both sources and sinks is
based on support for streams with two kinds of polarities: pull
streams and push streams, while Kiselyov's iteratees are heavily
geared towards pull streams.
