import Organ


-- What this does: filters the input source. When done, the max will
-- be pushed to "resMax".
filterMaxSrc :: (Num a, Ord a) => (a -> Bool) -> Src a -> N a -> Src a
filterMaxSrc f src resMax = filterSrc f (tee src $ (foldSnk' max 0 resMax))

-- When the result (max) is demanded, traverse the data and push it to
-- the resFilt sink. Equivalent to the above.
filterMaxSrc' :: (Num a, Ord a) => (a -> Bool) -> Src a -> Snk a -> NN a
filterMaxSrc' f src resFilt = foldSrc' max 0 (tee src (filterSnk f resFilt))

-- Same as above, but the argument is mastering the order.
filterMaxSnk :: (Num a, Ord a) => (a -> Bool) -> Snk a -> N a -> Snk a
filterMaxSnk f snk resMax = filterSnk f (collapseSnk snk (foldSnk' max 0 resMax))





