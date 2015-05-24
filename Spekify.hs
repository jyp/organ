

spek :: [String] -> [String] -> [String]
spek curblock (('<':x):xs) = spek (x:curblock) xs
spek [] [] = []
spek [] (x:xs) = x:spek [] xs
spek curblock xs = "\\begin{spec}":reverse curblock++"\\end{spec}":spek [] xs

main = putStr . unlines . spek [] . lines =<< getContents
