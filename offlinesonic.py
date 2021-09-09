import sqlite3
import asyncio
import aiohttp
import datetime
import json
import yt_dlp
from ytmusicapi import YTMusic


def my_hook(d):
    if d['status'] == 'finished':
        print(d['filename'])

def download(url,artist,title):
    ydl_opts = {
        'format': "bestaudio[ext=m4a]",
        'outtmpl': f'/vids/lolmusic/sonic/{artist} - {title}.m4a',
        'progress_hooks': [my_hook]}

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([url])

ytmusic = YTMusic()

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
    lastseen = 1631153871 #TODO - keep this number for restarts?
    while True:
        dt = datetime.datetime.now()
        print(f'running at {dt}')

        async with session.get(url) as resp:
            data = await resp.json()
        lastsong = ""
        for song in reversed(data):
            if song['updated_at'] > lastseen:
                if f"{song['artist']} {song['song_title']}" == lastsong:
                    # they occasionally dupe them
                    print(f"Duplicate song {song['artist']} {song['song_title']}")
                    continue
                await dbcheck(song)
                lastseen = song['updated_at']
                lastsong = f"{song['artist']} {song['song_title']}"

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

        res = ytmusic.search(f"{artist} {title}", filter="songs")
        yturl = f"https://music.youtube.com/watch?v={res[0]['videoId']}"
        print(artist, title, yturl)
        download(yturl, artist, title)

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
