# Function to calculate the sum of even numbers
def sum_of_even_numbers(n):
    even_sum = 0
    for i in range(2, n+1, 2):  # Loop through even numbers only
        even_sum += i
    return even_sum

# Input: Upper limit
n = int(input("Enter a number: "))

# Output: Sum of even numbers
print("Sum of even numbers from 1 to", n, "is:", sum_of_even_numbers(n))
