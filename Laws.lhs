> {-# LANGUAGE FlexibleContexts #-}
> {-# LANGUAGE ScopedTypeVariables, TypeOperators, RankNTypes, LiberalTypeSynonyms, BangPatterns, TypeSynonymInstances, FlexibleInstances, GADTs  #-}

> module Laws where

> import Data.Monoid

> data Source' f  a   = Nil   | Cons a  ((Sink'   f a) -> f)
> data Sink'   f  a   = Full  | Cont    ((Source' f a) -> f)


> type Src f a = (Sink' f a) -> f
> type Snk f a = (Source' f a) -> f

> fwd :: Monoid f => Source' f a -> Sink' f a -> f
> fwd s (Cont s') = s' s
> fwd Nil Full = mempty
> fwd (Cons _ xs) Full = xs Full

> yield :: a -> Sink' f a -> (Sink' f a -> f) -> f
> yield x (Cont c) k = c (Cons x k)
> yield _ Full k = k Full

> onSource' :: Monoid f => (Src f a -> t) -> Source' f a -> t
> onSink' :: Monoid f => (Snk f a -> t) -> Sink' f a -> t

> onSource' f s = f (\t -> fwd s t)
> onSink'   f t = f (\s -> fwd s t)

> type N f a = a -> f
> type NN f a = (a -> f) -> f

And, while a negated \var{Sink'} cannot be converted to a
\var{Source'}, all the following conversions are implementable:

> unshiftSnk :: Monoid f => N f (Src f a) -> Snk f a
> unshiftSrc :: Monoid f => N f (Snk f a) -> Src f a
> shiftSnk :: Snk f a -> N f (Src f a)
> shiftSrc :: Src f a -> N f (Snk f a)

> unshiftSnk = onSource'
> unshiftSrc = onSink'
> shiftSnk k kk = kk (Cont k)
> shiftSrc k kk = k (Cont kk)

A different reading of the type of \var{shiftSrc} reveals that it implements
forwarding of data from \var{Src} to \var{Snk}:

> forward :: Src f a -> Snk f a -> f
> forward = shiftSrc

> flipSnk :: Monoid f => (Snk f a -> Snk f b) -> Src f b -> Src f a
> flipSnk f s = shiftSrc s . onSink' f

> flipSrc :: Monoid f => (Src f a -> Src f b) -> Snk f b -> Snk  f a
> flipSrc f t = shiftSnk t . onSource' f

> appendSnk :: Monoid f => Snk f a -> Snk f a -> Snk f a
> appendSnk s1 s2 Nil = s1 Nil <> s2 Nil
> appendSnk s1 s2 (Cons a s)
>   = s1 (Cons a (forwardThenSrc s2 s))

Forward all the data from the source to the sink; the remainder source is returned

> forwardThenSrc :: Monoid f => Snk f a -> Src f a -> Src f a
> forwardThenSrc s2 = flipSnk (appendSnk s2)

> appendSrc :: Monoid f => Src f a -> Src f a -> Src f a
> appendSrc s1 s2 Full = s1 Full <> s2 Full
> appendSrc s1 s2 (Cont s)
>   = s1 (Cont (forwardThenSnk s s2))

Forward all the data from the source to the sink; the remainder sink is returned.

> forwardThenSnk :: Monoid f => Snk f a -> Src f a -> Snk f a
> forwardThenSnk snk src Nil = forward src snk
> forwardThenSnk snk src (Cons a s)
>   = snk (Cons a (appendSrc s src))

> toList :: Src f a -> NN f [a]
> toList s k = shiftSrc s (toListSnk k)

> empty :: Monoid f => Src f a
> empty sink' = fwd Nil sink'

> cons :: a -> Src f a -> Src f a
> cons a s s' = yield a s' s

> fromList :: Monoid f => [a] -> Src f a
> fromList = foldr cons empty

> toListSnk :: N f [a] -> Snk f a
> toListSnk k Nil = k []
> toListSnk k (Cons x xs) = toList xs $ \xs' -> k (x:xs')

> data NN' a where
>   NN :: NN f a -> NN f a -> NN' a


-- > instance Eq a => Eq (NN [a] a) where
-- >   x == y = x (:[]) == y (:[])

> instance Show a => Show (NN [String] a) where
>   show x = case x $ \x' -> [show x'] of
>     [result] -> result
>     _ -> error "linearity broken!"

> showSrc :: forall a. Show a => (forall f. Src f a) -> String
> showSrc x = show (toList x :: NN [String] [a])

> instance Eq a => Eq (NN [Bool] a) where
>   x == y = case x $ \x' -> y $ \y' -> [x' == y'] of
>     [result] -> result
>     _ -> error "linearity broken!"

> newtype AnySrc a = S (forall f. Src f a)
> newtype AnySnk a = T (forall f. Snk f a)

> instance Eq a => Eq (AnySrc a) where
>   S s1 == S s2 = eq (toList s1) (toList s2)

> (-?) :: Monoid f => Snk f a -> Src f a -> Snk f a
> t -? s = forwardThenSnk t s

> (-!) :: Monoid f => Snk f a -> Src f a -> Src f a
> t -! s = forwardThenSrc t s

> prop_distr1 t s1 s2 = t -? (s1 <> s2) == t -? s1 -? s2
> prop_distr2 t1 t2 s = (t1 <> t2) -? s == t1 -? (t2 -! s)
> prop_distr3 t1 t2 s = (t1 <> t2) -! s == t1 -! (t2 -! s)
> prop_distr4 t s1 s2 = t -! (s1 <> s2) == (t -? s1) -! s2

> eqSrc :: Eq a => (forall f. Monoid f => Src f a) -> (forall f. Monoid f => Src f a) -> Bool
> eqSrc s1 s2 = eq (toList s1) (toList s2)


> eq :: Eq a => (forall f. Monoid f => NN f a) -> (forall f. Monoid f => NN f a) -> Bool
> eq s1 s2 = case s1 $ \x' -> s2 $ \y' -> [x' == y'] of
>     [result] -> result
>     _ -> error "eq: linearity broken!"


> l1, l2 :: Monoid f => Src f Int
> l1 = fromList [1..5]
> l2 = fromList [1..3]
