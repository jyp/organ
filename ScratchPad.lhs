Possible titles:

- A Linear approach to streaming
- Push and Pull Streams
- On the Duality of Streams

 <!-- general terms are not compulsory anymore, you may leave them out 

\terms
term1, term2

 -->


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
