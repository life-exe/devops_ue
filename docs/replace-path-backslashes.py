# This script is designed to replace back slashes ("\") with forward slashes ("/") in file paths in a Doxygen config file (Doxyfile).
# Back slashes are used in Windows paths, while forward slashes are used in Linux paths.
# Use this script if you are running Doxygen on a Linux system.

# Usage: python replace-backslashes.py <file_to_process>
# Example of usage:
# py replace-path-backslashes.py Doxyfile

# Example of usage in GitHub Workflow:
#      - name: Replace back slashes
#        run: |
#          py devops_ue/docs/replace-path-backslashes.py devops_data/Doxyfile
#        working-directory: ${{ github.workspace }}

import sys
import os
import re

def process_line(line):
    # Check if the line is a comment
    if line.startswith('#'):
        return line
    
    # Replace "\" with "/" except in specified cases
    line = re.sub(r'(?<!\\)\\(?!["\s]|$)', '/', line)
    line = re.sub(r'(?<=\S)\\(?=\s|$)', '/', line)
    return line

def process_file(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    with open(file_path, 'w') as file:
        for line in lines:
            file.write(process_line(line))

if __name__ == "__main__": 
    if len(sys.argv) != 2: 
        print("Expected usage: python replace-backslashes.py <file_to_process>")
        sys.exit(1)

    file_path = sys.argv[1]
    # Construct the absolute path based on the current working directory
    file_path = os.path.abspath(file_path)
    process_file(file_path)
