du -bs * | sort -n | cut -f2-|awk '{ print "\""$0"\""}' | xargs du -hs > hdmoviesizes.txt
