#art_type = "poster"
quality = "w780" # w500, w1280, original - lower also available
bears_token = "Bearer ##XXX##"
db_name = "MyVideos121"
db_un = "xbmc"
db_pw = "xbmc"


import requests
import sys
import MySQLdb
db=MySQLdb.connect(user=db_un, password=db_pw, database=db_name)
c=db.cursor()

# Pull the 'url' - check it with Head - if it's valid continue to next. 
# Need to acount for both 404 and request timeout/lookup failure/etc.

# If it's not search TMDB for the 'value' (imdb ID) and get the poster URL.
# Assume that's valid, and UPDATE art where art_id and media_id = what we pulled out here.

good = 0
replaced = 0
failed = 0
http404 = 0
httptimeout = 0

def get_art(row):
    url = "https://api.themoviedb.org/3/find/{}?external_source=imdb_id&language=en"
    headers = {
        "accept": "application/json",
        "Authorization": bears_token,
    }
    res = requests.get(url.format(row[8]), headers=headers)
    res = res.json()
    poster = ""
    if res['movie_results']:
        poster_path = res['movie_results'][0]['poster_path']
        poster = f"https://image.tmdb.org/t/p/{quality}{poster_path}" 
    elif res['tv_results']:
        poster_path = res['tv_results'][0]['poster_path']
        poster = f"https://image.tmdb.org/t/p/{quality}{poster_path}"
    if not poster:
        print(f"MEDIA NOT FOUND https://www.imdb.com/title/{row[8]}/")
        global failed
        failed += 1
        return
    global replaced 
    replaced += 1
    q = f"UPDATE art SET url='{poster}' WHERE art_id={row[0]} and media_id={row[1]}; for IMDB {row[8]}"
    print(q)
    q = "UPDATE art SET url=%s WHERE art_id=%s and media_id=%s;"
    c.execute(q, (poster, row[0], row[1],))
    db.commit()

# NOTE need to match art/unique media_type!
# I use 'imdb' here instead of tmdb as most entries just dont have a tmdb entry
# or sometimes have one but its actualyl an IMDB id
# | art_id | media_id | media_type | type   | url| uniqueid_id | media_id | media_type | value     | type |
q = 'select * from art INNER JOIN uniqueid on art.media_id = uniqueid.media_id where art.type="poster" and uniqueid.type = "imdb" and art.url like "http%" and art.media_type=uniqueid.media_type;'
c.execute(q)
for row in c.fetchall():
    print(f"{failed} failed. {good} good. {replaced} replaced. {http404} 404s. {httptimeout} timeouts", end='\r')
    url = row[4]
    try:
        res = requests.head(url, timeout=2)
        if res.status_code == 200:
            good += 1
 #           print(f"{url} is good for IMDB {row[8]}")
            continue
        else:
            print(f"{url} is {res.status_code}")
            http404 += 1
            get_art(row)
    except:
        httptimeout += 1
        get_art(row)

print("\nDone.") 

