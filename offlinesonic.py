import sqlite3
import asyncio
import aiohttp
import datetime
import json



loop = asyncio.get_event_loop()
session = aiohttp.ClientSession(loop=loop)

conn = sqlite3.connect("sonic.sqlite")
c = conn.cursor()
q = "SELECT name FROM sqlite_master WHERE type='table' AND name='songs';"
result = c.execute(q).fetchone()
if not result:
    q = '''CREATE TABLE 'songs' (
              "artist" text, 
              "title" text,
              "album" text,
              "spotify" text,
              "firstseen" integer,
              "count" integer default '1'
        );'''
    c.execute(q)
    c.execute("CREATE INDEX songid ON songs (artist, title);")
    conn.commit()



url = 'https://player.rogersradio.ca/chdi/widget/recently_played?page=0&num_per_page=10'
async def update():
    lastseen = 0 #TODO - keep this number for restarts?
    while True:
        dt = datetime.datetime.now()
        print(f'running at {dt}')

        async with session.get(url) as resp:
            data = await resp.json()
        for song in reversed(data):
            if song['updated_at'] > lastseen:
                await dbcheck(song)
                lastseen = song['updated_at']

        await asyncio.sleep(30 * 60)


async def dbcheck(song):
    artist = song['artist']
    title = song['song_title']
    q = "SELECT count FROM songs WHERE artist=(?) AND title=(?)"
    res = c.execute(q, (artist, title)).fetchone()
    if res:
        q = "UPDATE songs SET count=count+1 WHERE artist=(?) AND title=(?)"
        c.execute(q, (artist, title))
    else:
        q = "INSERT INTO songs(artist, title, album, spotify, firstseen, count) VALUES (?, ?, ?, ?, ?, 1)"
        c.execute(q, (artist, title, song['album'], song['spotify'], song['updated_at']))
    conn.commit()


try:
    task = asyncio.ensure_future(update())
    loop.run_forever()
except KeyboardInterrupt:
    pass
finally:
    print("Closing Loop")
    session.close()
    loop.close()
