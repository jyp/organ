---
title: On the Duality of Streams
subtitle: How Can Linear Types Help to Solve the Lazy IO Problem?
author:
 - Jean-Philippe Bernardy
 - '**Josef Svenningsson**'
institute: Chalmers University of Technology
date: Dundee University September 22, 2015
...

# Lazy IO

## Lazy IO

~~~ {.haskell}
main = do
  file <- openFile "foo.txt"
  writeFile "bar.txt" (map toUpper file)
~~~

. . .

* The file is processed in a streaming fashion
* Low memory usage

## Lazy IO is fragile


~~~ {.haskell}
main = do
  file <- openFile "foo.txt"
  writeFile "bar.txt" (map toUpper file)
  writeFile "baz.txt" (map toLower file)
~~~

. . .

* This program reads all of "foo.txt" into memory
* High memory usage

## Lazy IO is fragile

From a stackoverflow question:

~~~{.haskell}
main = do
  inFile   <- openFile "foo" ReadMode
  contents <- hGetContents inFile
  putStr contents
  hClose inFile
~~~

~~~{.haskell}
main = do
  inFile   <- openFile "foo" ReadMode
  contents <- hGetContents inFile
  hClose inFile
  putStr contents
~~~

. . .

* The first program runs as expected

* The second program doesn't print anything

* Compositionality is lost

## Lazy IO

* Lazy IO is a wonderful idea

* Unfortunately it doesn't work in practice

  * Unpredictable memory behaviour
  * Non-compositional

## Previous solutions

Previous work solving the problems with Lazy IO

* Iteratees
* Pipes
* Conduits
* Machines

# Stream IO Library

## Our Approach

* A principled approach to dealing with streaming IO
* A particularly simple implementation
* Guarantees
  * Timely release of resources
  * No implicit memory allocation


We use Linear Logic and Duality as a guiding principle

## Streams

The central types in our library are:

~~~ {.haskell}
data Src a
data Snk a
~~~

* `Src a` produces elements of type `a`
* `Snk a` consumes elements of type `a`

. . .

Top level effect type:

~~~ {.haskell}
data Eff
~~~

This is the type of the `main` function.

## List Like Interface for `Src`

~~~ {.haskell}
empty     :: Src a
cons      :: a -> Src a -> Src a
tail      :: Src a -> Src a
takeSrc   :: Int -> Src a -> Src a
scanSrc   :: (b -> a -> b) -> b -> Src a -> Src b
dropSrc   :: Int -> Src a -> Src a
fromList  :: [a] -> Src a
filterSrc :: (a -> Bool) -> Src a -> Src a
fmap      :: (a -> b) -> Src a -> Src b
~~~

## Effectful combinators

~~~ {.haskell}
fileSrc  :: FilePath -> Src String
hFileSrc :: Handle   -> Src String
~~~

~~~{.haskell}
fileSnk  :: FilePath -> Snk String
hFileSnk :: Handle   -> Snk String
~~~

~~~ {.haskell}
fwd :: Src a -> Snk a -> Eff
~~~

## Copying a file

~~~ {.haskell}
copyFile :: FilePath -> FilePath -> Eff
copyFile source target = fwd (fileSrc source)
                             (fileSnk target)
~~~

## Timely closure of resources

~~~{.haskell}
read3Lines :: Eff
read3Lines = fwd (hFileSrc stdin)
                 (takeSnk 3 $ fileSnk "text.txt")
~~~

* The source is guaranteed to be closed when the sink doesn't demand
  any more data

## Linearity Condition

Stream programs have to be written on a particular form:

1. **No effectful variable may be duplicated or shared**

2. **Every effectful variable must be consumed**

3. **A type variable** $\alpha$ **can not be instantiated to an effectful type**

An effectful variable has a type containing an effect, such as `Source`

(Exact definition in draft paper)

## Consequences of Linearity Condition

* Makes sure effects are executed exactly once

* We cannot write the following functions:
  * `head`, it would discard the effectful computation
  * `(>>=)`, it would instantiate a type variable to an effectful type

* Hence, `Src` is not a monad

* It is possible to make `Src` a monad by making the Linearity
  Condition more complicated

* These restrictions are not a big problem in practice

## Pipes and branching streams

![](linear.eps "")

## Pipes and branching streams

![](branch.eps "")

## Branching streams

* We cannot return a pair of sources, because that would duplicate effects.

. . .

* Duality to the rescue!

. . .

* Returning a **source** is equivalent to taking a **sink** as argument
 and vice versa

. . .

Intuitively we want this type:

~~~{.haskell}
tee :: Source a -> (Source a, Source a)
~~~

For a correct implementation, one source becomes a sink argument

~~~{.haskell}
tee :: Source a -> Sink a -> Source a
~~~

## Branching streams

Problematic Lazy IO

~~~ {.haskell}
main = do
  file <- openFile "foo.txt"
  writeFile "bar.txt" (map toUpper file)
  writeFile "baz.txt" (map toLower file)
~~~

Our library

~~~{.haskell}
main = fwd (tee (fileSrc "foo.txt")
                (fileSnk "bar.txt"))
           (fileSnk "baz.txt")
~~~

## Other Branching streams

Concatenating streams. First produce the elements of the first stream.
When that closes, produce the elements of the second stream.

~~~ {.haskell}
(<>)   :: Src a -> Src a -> Src a
~~~

. . .

Zipping streams. The sources are consumed synchronously.

~~~ {.haskell}
zipSrc :: Src a -> Src b -> Src (a,b)
~~~

# Implementation

## Linear logic

The design of our library is guided by 

* Linear Logic
* Duality

## Cheap and cheerful embedding of Linear Logic in Haskell

Falsum $\bot$, becomes an effect

~~~{.haskell}
type Eff = IO ()
~~~

. . .

Negation is a callback

~~~{.haskell}
type N a  = a -> Eff
~~~
. . .

Linear Function $\multimap$, ordinary functions plus Linearity Condition


~~~{.haskell}
->
~~~

## Implementation of Streams

~~~ {.haskell}
data Source a = Nil  | Cons a (N (Sink a))
data Sink   a = Full | Cont (N (Source a))
~~~

~~~ {.haskell}
type Src a = N (Sink a)
type Snk a = N (Source a)
~~~

. . .

* Each production is matched by a consumption and *vice versa*
* This is how we can guarantee timely release of resources

## Duality 

* The types `Src` and `Snk` are duals:

  `N (Src a)` $\simeq$ `Snk a`

  `N (Snk a)` $\simeq$ `Src a`

* Functions transforming `Src` have duals that transforms `Snk` and vice versa

* The functions on `Src` tend to be more *natural*

  which is why we advocate programming mainly with `Src`

## Useful functions

The `fwd` function connecting sources and sinks

~~~ {.haskell}
fwd :: Src a -> Snk a -> Eff
fwd k kk = k (Cont kk)
~~~

. . .

Helper function to convert bewteen functions on sources and sink

~~~ {.haskell}
flipSnk :: (Snk a -> Snk b) -> Src b -> Src a
flipSrc :: (Src a -> Src b) -> Snk b -> Snk a
~~~

## Mutual recursion

Mutually recursive data types $\Rightarrow$ mutually recursive functions

Here is a typical example of how to write a pair of functions in our
library

~~~ {.haskell}
takeSrc :: Int -> Src a -> Src a
takeSrc i = flipSnk (takeSnk i)

takeSnk :: Int -> Snk a -> Snk a
takeSnk _ s Nil         = s Nil
takeSnk 0 s (Cons _ s') = s Nil <> s' Full
takeSnk i s (Cons a s') = s (Cons a (takeSrc (i-1) s'))
~~~

## Pairs of dual functions

Straightforward dualities

~~~{.haskell}
filterSrc :: (a -> Bool) -> Src a -> Src a
filterSnk :: (a -> Bool) -> Snk a -> Snk a
~~~

~~~{.haskell}
dropSrc :: Int -> Src a -> Src a
dropSnk :: Int -> Snk a -> Snk a
~~~

## Pairs of dual functions

Somewhat more surprising dualities

~~~{.haskell}
mapSrc   :: (a -> b) -> Src a -> Src b
comapSnk :: (b -> a) -> Snk a -> Snk b
~~~

~~~{.haskell}
(<>) :: Src a -> Src a -> Src a
(-?) :: Snk a -> Src a -> Snk a
~~~

~~~{.haskell}
(<>) :: Snk a -> Snk a -> Snk a
(-!) :: Snk a -> Src a -> Src a
~~~

## Dual of `tee`

~~~{.haskell}
tee :: Source a -> Sink a -> Source a
tee s1 t1 = flipSnk (collapseSnk t1) s1

collapseSnk :: Snk a -> Snk a -> Snk a
collapseSnk t1 t2 Nil = t1 Nil <> t2 Nil
collapseSnk t1 t2 (Cons x xs)
  =  t1 (Cons x $ \c1 ->
     t2 (Cons x $ \c2 ->
        shiftSrc xs (collapseSnk (flip forward c1)
                                 (flip forward c2))))
~~~

. . .

`collapseSnk` enables a more symmetric solution to stream splitting

~~~{.haskell}
main = fwd (fileSrc "foo.txt")
           (collapseSnk (fileSnk "bar.txt")
                        (fileSnk "baz.txt"))
~~~

## Effectful streams

~~~ {.haskell}
fileSrc :: FilePath -> Src String
fileSrc file sink = do
  h <- openFile file ReadMode
  hFileSrc h sink

hFileSrc :: Handle -> Src String
hFileSrc h Full = hClose h
hFileSrc h (Cont c) = do
  e <- hIsEOF h
  if e then do hClose h
               c Nil
       else do x <- hGetLine h
               c (Cons x $ hFileSrc h)
~~~

# Asynchronicity

## Synchronicity and Asynchronicity

* So far, all communication has been completely synchronous

* There are certain functions we cannot write.

  * ~~~{.haskell}
    mux :: Src a -> Src b -> Src (Either a b)
    ~~~

* We might want to be able to use buffers or schedule things
  concurrently

## Co-Sources, Co-Sinks

~~~{.haskell}
type CoSrc a = Snk (N a)
type CoSnk a = Src (N a)
~~~

* Streams containing callbacks.

* Asynchronous; elements may not necessarily be processed in order

## `CoSrc` File reading

~~~{.haskell}
coFileSrc :: Handle -> CoSrc String
coFileSrc h Nil = hClose h
coFileSrc h (Cons x xs) = do
  e <- hIsEOF h
  if e then do
         hClose h
         xs Full
       else do
         s <- hGetLine h
         x s                     -- (1)
         xs $ Cont $ coFileSrc h -- (2)
~~~

* No data dependency between (1) and (2)
* We have the option to schedule them in any order

## Scheduling

* We can convert from `Src` to `CoSrc` (and from `CoSnk` to `Snk`) but
  we have to decide on a schedule

* `CoSrc` can process its elements in different order. We have to pick
  what order that should be using a schedule

~~~{.haskell}
type Schedule a = Source a -> Source (N a) -> Eff
~~~

Conversion functions:

~~~{.haskell}
srcToCoSrc :: Schedule a -> Src a   -> CoSrc a
coSnkToSnk :: Schedule a -> CoSnk a -> Snk a
~~~

Several possible schedules:

~~~{.haskell}
sequentially :: Schedule a
concurrently :: Schedule a
~~~

## Buffering

* Converting from `CoSrc` to `Src` might require buffering
* `CoSrc` produces elements asynchronously whereas `Src` is synchronous

~~~{.haskell}
chanBuffer :: CoSrc a -> Src a
chanBuffer f g = do
  c <- newChan
  forkIO $ fwd (chanCoSnk c) f
  chanSrc c g
~~~

* Allows for writing concurrent applications in a compositional style

## Buffering

A variant of `chanBuffer` which can merge two asynchronous `CoSrc` into
a synchronous `Src`

~~~{.haskell}
bufferedDmux :: CoSrc a -> CoSrc a -> Src a
bufferedDmux s1 s2 t = do
  c <- newChan
  forkIO $ fwd (chanCoSnk c) s1
  forkIO $ fwd (chanCoSnk c) s2
  chanSrc c t
~~~

. . .

Solves the `mux` problem

## Example: Simple Echo Server

~~~{.haskell}
type Client a = (CoSrc a, Snk a)
~~~

From the point of view of the server the client does two things:

* Produces messages asynchronously
* Consumes messages synchronously

. . .

~~~{.haskell}
server :: Client a -> Client a -> Eff
server (i1,o1) (i2,o2) = fwd (bufferedDmux i1 i2)
                             (collapseSnk o1 o2)
~~~

## Conclusions

* A library for streaming IO
* Based on principles of Linearity and Duality
  * Linearity Condition
* Simple design
* Guarantees
  * Timely release of resources
  * No implicit memory allocation

More in draft paper:

* More functions
* Proofs of algebraic laws
* Streaming parsers
