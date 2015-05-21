

clean :: [String] -> [String]
clean ("\\end{hscode}\\resethooks":"":rest) = "\\end{hscode}\\resethooks":clean rest
clean (x:xs) = x:clean xs
clean [] = []

main = putStr . unlines . clean . lines =<< getContents
