# Use this script to tell if you can pedict the future
# OK it's not cryptographically random but still it's good enough.

import random
q = 0
correct = 0

qs = int(input("number of qs: "))

while q < qs:
    ans = 42
    r = 0
    val = input("Pick 1 to 3: ")
    try:
        ans = int(val)
        if not 0 < ans < 4:
            print("no.")
            continue
    except:
        print("No.")
        continue

    r = random.randint(1, 3)

    if ans == r:
        print("Correct")
        correct += 1
    else:
        print(r)
    q += 1

print(f"{correct} correct of {q}")
