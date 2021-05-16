import random

def monty(switch):
    ans = random.randint(1,3)
    new = guess = random.randint(1,3)
    removed = 0    
    for x in range(1,4):
        if x != ans and x != guess:
             removed = x
    
    if switch:
        for x in range(1,4):
            if x != guess and x != removed:           
                new = x
        guess = new

    if guess == ans:
        return 1
    else:
        return 0


switch = 0
for _ in range(100):
    switch += monty(True)
print(f"Switching is {switch}% correct")

stay = 0
for _ in range(100):
    stay += monty(False)

print(f"Staying is {stay}% correct")


# $ python3 montyhall.py 
# Switching is 63% correct
# Staying is 36% correct

# $ python3 montyhall.py 
# Switching is 69% correct
# Staying is 27% correct

# $ python3 montyhall.py 
# Switching is 59% correct
# Staying is 29% correct

# $ python3 montyhall.py 
# Switching is 63% correct
# Staying is 30% correct
