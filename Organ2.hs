{- Some code written with Phil Wadler
  late on a pub in Edinburgh.
  Turns out not to be very useful
  but saved for posterity.
-}
module Organ2 where

import Prelude hiding (flip)
import System.IO

type Eff = IO ()
type N a = a -> Eff

data Source a = Nil | Cons a (N (Sink a))
type Sink   a = N (Source a)
type Src    a = N (Sink a)
type Snk    a = N (Source a)

takeSrc :: Int -> Src a -> Src a
takeSrc i = flip (takeSnk i)

takeSnk :: Int -> Snk a -> Snk a
takeSnk 0 k _   = k Nil
takeSnk n k Nil = k Nil
takeSnk n k (Cons a s) = k (Cons a (takeSrc (n-1) s))

fromList :: [a] -> Src a
fromList as = \k -> k (case as of
                         [] -> Nil
                         (a:as) -> Cons a (fromList as))

printSnk :: Show a => Snk a
printSnk Nil = return ()
printSnk (Cons a s) = do print a
                         s printSnk

fileSrc :: FilePath -> Src String
fileSrc f = \k ->
  do h <- openFile f ReadMode
     hFileSrc h k

hFileSrc :: Handle -> Src String
hFileSrc h = \k -> do
  e <- hIsEOF h
  if e then do hClose h
               putStrLn "Closed the file!"
               k Nil
       else do x <- hGetLine h
               k (Cons x $ hFileSrc h)

boom :: [a] -> [a]
boom x = x ++ error "boom"

fwd :: Src a -> Snk a -> Eff
fwd s k = s k

ret :: a -> N (N a)
ret a = \k -> k a

flip :: (a -> b) -> N b -> N a
flip f k = k . f

empty :: Src a
empty = \k -> k Nil

plug :: Snk a
plug _ = return ()

test1 = fwd (fromList (boom [0..9])) (takeSnk 10 $ printSnk)

test2 = fwd (fileSrc "foo.txt") (takeSnk 1 printSnk)
