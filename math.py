import math

price_ratio = 1/1000
sqrt_price_ratio = math.sqrt(price_ratio)
sqrt_price_x96 = sqrt_price_ratio * (2**96)

print(sqrt_price_x96)