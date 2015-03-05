{-# LANGUAGE RankNTypes, MultiParamTypeClasses, TypeFamilies, FlexibleContexts #-}
-- |
--
-- Module      :  Parsek
-- Copyright   :  Koen Claessen 2003, JP Bernardy 2012
-- License     :  GPL
--
-- Maintainer  :  JP Bernardy
-- Stability   :  provisional
-- Portability :  portable
--
-- This module provides the /Parsek/ library developed by Koen Claessen in his
-- functional pearl article /Parallel Parsing Processes/, Journal of Functional
-- Programming, 14(6), 741&#150;757, Cambridge University Press, 2004:
--
-- <http://www.cs.chalmers.se/~koen/pubs/entry-jfp04-parser.html>
--
-- <http://www.cs.chalmers.se/Cs/Grundutb/Kurser/afp/>
--
-- <http://www.cs.chalmers.se/Cs/Grundutb/Kurser/afp/code/week3/Parsek.hs>

module Parser
  -- basic parser type
  ( Parser         -- :: * -> * -> *; Functor, Monad, MonadPlus
  , Expect         -- :: *; = [String]

  -- parsing & parse methods
  , ParseMethod   
  , ParseResult   
  , mapErrR
  , parseFromFile 
  , parse         

  , shortestResult             
  , longestResult
  , longestResultIO
  , longestResults             
  , allResults                 
  , allResultsStaged           
  , completeResults            

  , shortestResultWithLeftover 
  , longestResultWithLeftover  
  , longestResultsWithLeftover 
  , allResultsWithLeftover     
  
  , module Control.Applicative
  , module Control.Monad
  -- , completeResultsWithLine    -- :: ParseMethod Char a Int [a]
  )
 where

import Prelude hiding (exp,pred)
import Data.Char
import Data.Traversable (sequenceA,forM)
-- import Data.Foldable (forM)
import Data.Maybe (listToMaybe, isNothing)
import Control.Applicative
import Control.Monad
  ( MonadPlus(..)
  , forM_
  , guard
  , ap
  )
import Organ (Source(..), Sink(..), N, NN, shift)

-------------------------------------------------------------------------
-- type Parser

newtype Parser s a
  = Parser (forall res. (a -> Expect s -> P s res) -> Expect s -> P s res)

-- | Parsing processes
data P s res
  = Skip Int (P s res) -- ^ skip ahead a number of symbols. At end of file, no effect.
  | Look (Maybe s -> P s res)
  | Fail (Err s)
  | Result res (P s res)
  | Kill (P s res) -- ^ This is a high priority process trying to kill a low-priority one. See <<|>.

-- | Suppress 1st kill instruction 
noKill :: P s a -> P s a
noKill (Skip n p) = Skip n (noKill p)
noKill (Look fut) = Look $ noKill . fut
noKill (Fail e) = Fail e
noKill (Result res p) = Result res (noKill p)
noKill (Kill p) = p

skip :: Int -> P s a -> P s a
skip 0 = id
skip n = Skip n 

-- The boolean indicates how to interpret 'Kill' instructions. If
-- 'True', the lhs process has a high priority and will kill the rhs
-- when it reaches its Kill instruction (otherwise it fails). If
-- 'False', then both processes have the same priority, and 'Kill'
-- instructions are just propagated.
plus' :: Bool -> P s res -> P s res -> P s res
plus' hasKiller p0 q0 = plus p0 q0 where
  noKill' = if hasKiller then noKill else id
  Kill p         `plus` q              | hasKiller = p
                                       | otherwise = Kill $ p `plus` noKill q
  p              `plus` Kill q         | hasKiller = error "plus': Impossible"
                                       | otherwise = Kill $ noKill p `plus` q
  Skip m p       `plus` Skip n q       | m <= n    = Skip m $ p `plus` skip (n-m) q
                                       | otherwise = Skip n $ skip (m-n) p `plus` skip n q
  Fail err1      `plus` Fail err2      = Fail (err1 ++ err2)
  p              `plus` Result res q   = Result res (p `plus` q)
  Result res p   `plus` q              = Result res (p `plus` q)
  Look fut1      `plus` Look fut2      = Look (\s -> fut1 s `plus` fut2 s)
  Look fut1      `plus` q              = Look (\s -> fut1 s `plus` q)
  p              `plus` Look fut2      = Look (\s -> p `plus` fut2 s)
  p@(Skip _ _)   `plus` _              = noKill' p
  _              `plus` q@(Skip _ _)   = q

type Err s = [(Expect s, -- we expect this stuff
               String -- but failed for this reason
              )]

-- | An intersection (nesting) of things currently expected
type Expect s = [(String, -- Expect this
                  Maybe s -- Here
                )]

-------------------------------------------------------------------------
-- instances

instance Functor (Parser s) where
  fmap p (Parser f) =
    Parser (\fut -> f (fut . p))

instance Monad (Parser s) where
  return a = Parser (\fut -> fut a)

  Parser f >>= k =
    Parser (\fut -> f (\a -> let Parser g = k a in g fut))

  fail s = Parser (\_fut exp -> Fail [(exp,s)])

instance MonadPlus (Parser s) where
  mzero = Parser (\_fut exp -> Fail [(exp,"mzero")])

  mplus (Parser f) (Parser g) =
    Parser (\fut exp -> plus' False (f fut exp) (g fut exp))

instance Applicative (Parser s) where
  pure = return
  (<*>) = ap

instance Alternative (Parser s) where
  (<|>) = mplus
  empty = mzero

satisfy pred =
  Parser $ \fut exp -> Look $ \xs -> case xs of
    Just c | pred c -> Skip 1 $ fut c exp
    _ -> Fail [(exp,"satisfy")]
  
look = Parser $ \fut exp -> Look $ \s -> fut s exp

label msg (Parser f) =
  Parser $ \fut exp ->
      Look $ \xs -> 
      f (\a _ -> fut a exp) -- drop the extra expectation in the future
        ((msg,xs):exp) -- locally have an extra expectation

Parser f <<|> Parser g = Parser $ \fut exp -> 
  plus' True (f (\a x -> Kill (fut a x)) exp) (g fut exp)

-------------------------------------------------------------------------
-- type ParseMethod, ParseResult

type ParseMethod s a r = P s a -> [s] -> ParseResult s r

type ParseResult s r
  = Either (Err s) r

mapErrR :: (s -> s') -> ParseResult s r -> ParseResult s' r
mapErrR _ (Right x) = Right x
mapErrR f (Left x) = Left (mapErr f x)

first f (a,b) = (f a,b)
second f (a,b) = (a, f b)

mapErr :: (a -> b) -> Err a -> Err b
mapErr f = map (first (mapExpect f))

mapExpect :: (a -> b) -> Expect a -> Expect b
mapExpect f = map (second (fmap f))

-- parse functions

parseFromFile :: Parser Char a -> ParseMethod Char a r -> FilePath -> IO (ParseResult Char r)
parseFromFile p method file =
  do s <- readFile file
     return (parse p method s)

parse :: Parser s a -> ParseMethod s a r -> [s] -> ParseResult s r
parse (Parser f) method xs = method (f (\a _exp -> Result a (Fail [])) []) xs

-- parse methods
shortestResult :: ParseMethod s a a
shortestResult = scan
 where
  scan (Skip n p)     xs     = scan p (drop n xs)
  scan (Result res _) _      = Right res
  scan (Fail err) _          = Left err 
  scan (Look f)       xs     = scan (f $ listToMaybe xs) xs

longestResult :: ParseMethod s a a
longestResult p0 = scan p0 Nothing 
 where
  scan (Skip n p)     mres       xs     = scan p mres (drop n xs)
  scan (Result res p) _          xs     = scan p (Just res) xs
  scan (Fail err)     Nothing    _      = Left err 
  scan (Fail _  )     (Just res) _      = Right res
  scan (Look f)       mres       xs     = scan (f $ listToMaybe xs) mres xs


longestResultIO :: P Char a -> N (ParseResult Char a) -> N (Source Char)
longestResultIO p0 ret src = scan p0 Nothing src
 where
  scan (Skip n p)     mres       xs     = dropSrc n xs $ scan p mres
  scan (Result res p) _          xs     = scan p (Just res) xs
  scan (Fail err)     Nothing    _      = ret $ Left err 
  scan (Fail _  )     (Just res) _      = ret $ Right res
  scan (Look f)       mres       xs     = case xs of
    Nil -> scan (f Nothing) mres xs
    Cons x cs -> cs $ Cont $ \ys -> scan (f $ Just x) mres ys
  dropSrc :: Int -> Source a -> NN (Source a)
  dropSrc 0 x k = k x
  dropSrc _ Nil k = k Nil
  dropSrc n (Cons _ cs) k = cs $ Cont $ \ys -> dropSrc (n-1) ys k


longestResults :: ParseMethod s a [a]
longestResults p0 = scan p0 [] [] 
 where
  scan (Skip n p)     []  old xs     = scan p [] old (drop n xs)
  scan (Skip n p )    new old xs     = scan p [] new (drop n xs)
  scan (Result res p) new old xs     = scan p (res:new) [] xs
  scan (Fail err)     []  []  _      = Left err
  scan (Fail _)       []  old _      = Right old
  scan (Fail _)       new _   _      = Right new
  scan (Look f)       new old xs     = scan (f $ listToMaybe xs) new old xs

allResultsStaged :: ParseMethod s a [[a]]
allResultsStaged p0 xs0 = Right (scan p0 [] xs0)
 where
  scan (Skip n p)     ys xs     = ys : scan p [] (drop n xs)
  scan (Result res p) ys xs     = scan p (res:ys) xs
  scan (Fail _)       ys _      = [ys]
  scan (Look f)       ys xs     = scan (f $ listToMaybe xs) ys xs

allResults :: ParseMethod s a [a]
allResults = scan
 where
  scan (Skip n p)     xs     = scan p (drop n xs)
  scan (Result res p) xs     = Right (res : scan' p xs)
  scan (Fail err)     _      = Left err
  scan (Look f)       xs     = scan (f $ listToMaybe xs) xs

  scan' p xs =
    case scan p xs of
      Left  _    -> []
      Right ress -> ress

completeResults :: ParseMethod s a [a]
completeResults = scan
 where
  scan (Skip n p)     xs     = scan p (drop n xs)
  scan (Result res p) []     = Right (res : scan' p [])
  scan (Result _ p)   xs     = scan p xs
  scan (Fail err)     _      = Left err
  scan (Look f)       xs     = scan (f $ listToMaybe xs) xs

  scan' p xs =
    case scan p xs of
      Left  _    -> []
      Right ress -> ress

-- with left overs

shortestResultWithLeftover :: ParseMethod s a (a,[s])
shortestResultWithLeftover = scan
 where
  scan (Skip n p)     xs     = scan p (drop n xs)
  scan (Result res _) xs     = Right (res,xs)
  scan (Fail err)     _      = Left err
  scan (Look f)       xs     = scan (f $ listToMaybe xs) xs

longestResultWithLeftover :: ParseMethod s a (a,[s])
longestResultWithLeftover p0 = scan p0 Nothing
 where
  scan (Skip n p)     mres         xs     = scan p mres (drop n xs)
  scan (Result res p) _            xs     = scan p (Just (res,xs)) xs
  scan (Fail err)     Nothing      _      = Left err
  scan (Fail _)       (Just resxs) _      = Right resxs
  scan (Look f)       mres         xs     = scan (f $ listToMaybe xs) mres xs

longestResultsWithLeftover :: ParseMethod s a ([a],Maybe [s])
longestResultsWithLeftover p0 = scan p0 empty empty
 where
  scan (Skip n p)     ([],_) old    xs     = scan p empty old $ drop n xs
  scan (Skip n p)     new    _      xs     = scan p empty new $ drop n xs
  scan (Result res p) (as,_) _      xs     = scan p (res:as,Just xs) empty xs
  scan (Fail err)     ([],_) ([],_) _      = Left err
  scan (Fail _)       ([],_)  old _        = Right old
  scan (Fail _)       new _   _            = Right new
  scan (Look f)       new    old    xs     = scan (f $ listToMaybe xs) new old xs

  empty = ([],Nothing)

allResultsWithLeftover :: ParseMethod s a [(a,[s])]
allResultsWithLeftover = scan
 where
  scan (Skip n p)     xs     = scan p $ drop n xs
  scan (Result res p) xs     = Right ((res,xs) : scan' p xs)
  scan (Fail err)     []     = Left err
  scan (Look f)       xs     = scan (f $ listToMaybe xs) xs

  scan' p xs =
    case scan p xs of
      Left  _    -> []
      Right ress -> ress

--------------
-- Derived parsers

infix  2 <?>
infixr 3 <<|>

-- | Label a parser
p <?> s = label s p

char c    = satisfy (==c) <?> show [c]
noneOf cs = satisfy (\c -> not (c `elem` cs)) <?> ("none of " ++ cs) 
oneOf cs  = satisfy (\c -> c `elem` cs) <?> ("one of " ++ cs) 

spaces    = skipMany space     <?> "white space"
space     = satisfy isSpace    <?> "space"
newline   = char '\n'          <?> "new-line"
tab       = char '\t'          <?> "tab"
upper     = satisfy isUpper    <?> "uppercase letter"
lower     = satisfy isLower    <?> "lowercase letter"
alphaNum  = satisfy isAlphaNum <?> "letter or digit"
letter    = satisfy isAlpha    <?> "letter"
digit     = satisfy isDigit    <?> "digit"
hexDigit  = satisfy isHexDigit <?> "hexadecimal digit"
octDigit  = satisfy isOctDigit <?> "octal digit"

anySymbol = satisfy (const True)

string s = forM s char <?> show s

choice :: Alternative f => [f a] -> f a
choice ps = foldr (<|>) empty ps

option :: Alternative f => a -> f a -> f a
option x p = p <|> pure x

between :: Applicative m => m x -> m y -> m a -> m a
between open close p = open *> p <* close

-- repetition
-- | Greedy repetition: match as many occurences as possible of the argument.
manyGreedy p = do 
  x <- (Just <$> p) <<|> pure Nothing
  case x of
    Nothing -> return []
    Just y -> (y:) <$> manyGreedy p

skipMany1 p = p *> skipMany p
skipMany  p = let scan = (p *> scan) <|> pure () in scan

sepBy  p sep = sepBy1 p sep <|> pure []
sepBy1 p sep = (:) <$> p <*> many (sep *> p)

count :: Applicative m => Int -> m a -> m [a]
count n p = sequenceA (replicate n p)

chainr p op x = chainr1 p op <|> return x
chainl p op x = chainl1 p op <|> return x

chainr1 p op = scan
 where
  scan   = do x <- p; rest x
  rest x = (do f <- op; y <- scan; return (f x y)) <|> return x

chainl1 p op = scan
 where
  scan   = do x <- p; rest x
  rest x = (do f <- op; y <- p; rest (f x y)) <|> return x

munch p = manyGreedy (satisfy p)

munch1 p = (:) <$> satisfy p <*> munch p

endOfFile = label "end of file" $ do 
  s <- look
  guard (isNothing s)
