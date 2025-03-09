#!/usr/bin/python3

# This is not well written by any means, just a quick script to make maildirs out of uw-imap mbx
# (Often confused with mbox because some .mbx files are in fact mbox)

# It ignores imap "keywords" because setting them in dovecot is annoying 
# It assumes all emails are 'seen' 
# It assumes you're running it in the user folder and outputs in to that ie: 
# [root@svr /home/testuser/]# python3 mbx2maildir.py Deleted\ Items
# That will create /home/testuser/Maildir/.Deleted Items/cur/
# It assumes the owner of the mbx file will be the owner of the folder and chowns it to that. 
# This script is written for linux. It will likel fail in some way on any other OS

import re
import sys
import os
import subprocess
from pwd import getpwuid
from grp import getgrgid
from datetime import datetime
import socket
# https://github.com/uw-imap/imap/
# *mbx*
# 5c196345000018d4
#    This is imap UIDVALIDITY 32 bits + another 32 bits (UID?) for some reason
#    I think I'm safe to just ignore it?

# 30-Jun-2020 06:11:59 -0600,7281;000000000019-00000001
#  7-Oct-2022 07:23:27 -0600,12730479;000000090031-000018cd
msg_header = re.compile(r"^((?: |\d)\d\-\w{3}\-\d{4} \d{2}:\d{2}:\d{2} "
r"(?:\+|\-)\d{4}),(\d+);[0-9a-fA-F]{8}([0-9a-fA-F]{4})\-([0-9a-fA-F]{8})")

# 1 = date time tz
# 2 = size in bytes (not including this header)
#     there's 8 chars here for something? maybe keyword/flags?
# 3 = flags (hex)
# 4 = hexuid (just being used for maildir)

# a complete guess is the first 8 chars are identifying *which* keyword is set..
# I think I'm just going to ignore keywords entirely.

timefmt = "%d-%b-%Y %H:%M:%S %z"
hostname = socket.getfqdn()
filename = "{}_{:04d}P{:08x}.{},S={}:2,{}"


def mbx(mbxfile: str, mbdir: str, owner: str):
    with open(mbxfile, 'rb') as f:
        if f.readline().decode() != "*mbx*\r\n":
            print("{} Does not appear to be a uw-imap mbx file.\n"
            "It might be mbox which can be imported directly by dovecot".format(mbxfile))
            exit()
        
        old_umask = os.umask(0o077)
        path = "./Maildir/.{}/".format(mbdir)
        if os.path.isdir(path):
            print("Warning: the above is an existing maildir foder".format(mbdir))
        os.makedirs(path + "cur/", mode=0o700, exist_ok=True)
        os.makedirs(path + "new/", mode=0o700, exist_ok=True)
        os.makedirs(path + "tmp/", mode=0o700, exist_ok=True)
        os.umask = old_umask
        path += "cur/"

        f.read(2041) #normally would be 2048 but we read that *mbx* line first.

        incr = 0
        outfile = None
        file = ""
        for line in f:
            header = msg_header.match(line.decode('utf-8', 'ignore'))
            if header:
                if outfile:
                    outfile.flush()
                    outfile.close()
                    outfile = None
                # print(line)
                time = datetime.strptime(header.group(1), timefmt)
                size = int(header.group(2)) 

                flags = int("0x" + header.group(3), 16)
                seen = (flags & 0x1) == 0x1
                trashed = (flags & 0x2) == 0x2
                flagged = (flags & 0x4) == 0x4 #probably ignoring this
                replied = (flags & 0x8) == 0x8
                uid = int("0x" + header.group(4), 16)

                # since we're sticking them in 'cur' we're going to assume Seen
                flagstr = "S"
                if trashed:
                    flagstr += "T"
                if replied:
                    flagstr += "R"
                
                size += len(line)
                incr += 1
                file = filename.format(time.timestamp(), incr, uid, hostname, size, flagstr)
                print(file)
                outfile = open(path + file, "xb")
            if outfile:
                outfile.write(line)
        if outfile:
            outfile.flush()
            outfile.close()
    print("Doing: chown -R {} ./Maildir/".format(owner))
    subprocess.run(["chown", "-R",  owner, "./Maildir/"])
    


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("mbx2maildir.py [filename] - filename is the mbx formatted mailbox\n"
        "The script will assume the folder will be named the same as the mailbox file")
        quit()
    file = sys.argv[1]
    if file.endswith(".mbx"):
        mbdir = file[:-4]
    else:
        mbdir = file
    if "." in mbdir:
        parts = mbdir.split(".")
        print("Warning: {} appears to be a subfolder `{}` of `{}`.\n"
        "I will create it but I can't guarantee it will work normally"
        .format(mbdir, parts[1], parts[0]))
    print("Trying", file, "to ./Maildir/.{}/cur/".format(mbdir))
    user = getpwuid(os.stat(file).st_uid).pw_name
    group = getgrgid(os.stat(file).st_gid).gr_name
    owner = "{}:{}".format(user, group)
    mbx(file, mbdir, owner)

    print("Done.")
