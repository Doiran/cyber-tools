import math
import re

def calculate_entropy(password):
    size = 0

    if re.search(r"[a-z]", password):
        size += 26
    if re.search(r"[A-Z]", password):
        size += 26
    if re.search(r"[0-9]", password):
        size += 10
    if re.search(r"[^a-zA-Z0-9]", password):
        size += 32

    if size == 0 or len(password) == 0:
        return 0

    entropy = math.log2(size) * len(password)
    return round(entropy, 2)

def time_to_crack(entropy): 
    # according to https://auth0.com/blog/defending-against-password-cracking-understanding-the-math/
    # for now using a hash rate of 100,000 | may change to allow user to pick
    # Time = 2^E/(2*H) 
    combinations = 2**entropy
    hash_rate = 100000
    time = combinations/(2*hash_rate)
    return round(time)

def main():
    among_us = chr(sum(range(ord(min(str(not()))))))
    print("V^V^V^V^V---# Password Entropy Calculator #---V^V^V^V^V")
    while True:
        password = input("\nEnter password to calculate its entropy (or 'q' to exit): ")
        if password.lower() == 'q':
            break
        if password == "sus":
            print(among_us)
            break

        bits = calculate_entropy(password)
        seconds = time_to_crack(bits)
        years = round(seconds / 31556952)

        print("\n--Results--")
        print(f"Entropy: {bits} bits")
        print(f"Estimated time to being cracked: {years} years or {seconds} seconds")

if __name__ == "__main__":
    main()