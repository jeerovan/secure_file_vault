import math
import sys

def calculate_encrypted_size(original_size: int) -> int:
    """Calculates the encrypted file size based on the 4096-byte chunking formula."""
    if original_size < 0:
        raise ValueError("File size cannot be negative.")
        
    chunks = math.ceil(original_size / 4096)
    encrypted_size = original_size + 24 + (chunks * 17)
    return encrypted_size

if __name__ == "__main__":
    # Check if a file size argument was provided
    if len(sys.argv) != 2:
        print("Usage: python encrypt_calc.py <original_file_size>")
        sys.exit(1)
    
    try:
        size = int(sys.argv[1])
        print(calculate_encrypted_size(size))
    except ValueError:
        print("Error: Please provide a valid integer for the file size.")
        sys.exit(1)
