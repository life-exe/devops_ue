# This script removes BOM from the specified file.
# It can be used, for example, to process files with UTF encoding which were saved with powershell version 5 or older
# Usage: python remove_bom.py input_filename

def remove_bom(input_filename):
    # Read the file in binary mode to preserve BOM
    with open(input_filename, 'rb') as f:
        content = f.read()
    
    # Check for BOM and remove it
    if content.startswith(b'\xef\xbb\xbf'):
        content = content[3:]

    # Write the content back to the same file with UTF-8 encoding
    with open(input_filename, 'wb') as f:
        f.write(content)

if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("[remove_bom.py]: Wrong usage. Correct usage: python remove_bom.py input_filename")
        sys.exit(1)

    input_filename = sys.argv[1]

    remove_bom(input_filename)
