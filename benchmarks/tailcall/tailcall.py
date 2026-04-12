import sys
# Python does not have tail call optimization. We must artificially raise the limit 
# so it doesn't crash immediately, though it will still consume massive stack frames!
sys.setrecursionlimit(20000000)

def loop(count):
    if count < 10000000:
        return loop(count + 1)
    return count

try:
    loop(0)
except RecursionError:
    pass
except Exception:
    pass
