#!/usr/bin/python

import os
import sys
import re
from subprocess import call

def find_rars(path):
    rarfiles = []
    files = os.listdir(path)
    for di in files:
        if os.path.isdir(os.path.join(path, di)):
            find_rars(os.path.join(path, di))
    print("Searching {} for rars".format(path))
    rarfiles = [f for f in files if re.search(r'\.part(\d+)\.rar$|\.rar$|\.r\d{2}$', f)]

    if rarfiles:
        extracted = False
        print("found {} - Extracting..".format(rarfiles))
        for rar in rarfiles:
            target = ""
            if re.search(r'\.part(0+)?1\.rar$', rar):
                target = rar
            elif ".rar" in rar and not re.search(r'\.part(\d+)\.rar$', rar):
                target = rar

            if target:
                print("Unraring {}".format(target))
                if not call(["unrar", "x", os.path.join(path, target), path]):
                    extracted = True

        if extracted:
            for rar in rarfiles:
                #Remove the unrared files
                print("Deleting {}".format(os.path.join(path,rar)))
                os.remove(os.path.join(path,rar))
            #Now check if we just unrared a rar
            find_rars(path)
    else:
        print("No Rar files found")


def main():
    try:
        path = sys.argv[1]
    except:
        path = "."
    find_rars(path)

if __name__ == "__main__":
    main()

