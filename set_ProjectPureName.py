"""
Automates the update of the ProjectPureName in a config.bat file with the name of a found .uproject file.
"""

import os
import re

def find_uproject_file():
    """
    Find the .uproject file in the upper directory.
    """
    current_directory = os.getcwd()
    upper_directory = os.path.dirname(current_directory)
    uproject_files = [f for f in os.listdir(upper_directory) if f.endswith('.uproject')]
    
    if len(uproject_files) == 1:
        return os.path.splitext(uproject_files[0])[0]  # Return the name without extension
    else:
        script_filename = os.path.basename(__file__)
        print(f"[{script_filename}] Warning: Found multiple or no .uproject files in the upper directory.")
        return None

def update_config_bat(uproject_name, config_bat_file):
    """
    Update the config.bat file with the ProjectPureName.
    """
    if os.path.exists(config_bat_file):
        with open(config_bat_file, 'r') as file:
            content = file.read()
        
        updated_content = re.sub(r'set ProjectPureName=<ProjectName>', f'set ProjectPureName={uproject_name}', content)
        
        with open(config_bat_file, 'w') as file:
            file.write(updated_content)
        script_filename = os.path.basename(__file__)
        print(f"[{script_filename}] ProjectPureName updated successfully to '{uproject_name}' in config.bat.")
    else:
        script_filename = os.path.basename(__file__)
        print(f"[{script_filename}] Warning: config.bat file not found.")

if __name__ == "__main__":
    current_directory = os.getcwd()
    uproject_name = find_uproject_file()
    if uproject_name:
        config_bat_file = os.path.join(current_directory, "..", "devops_data", "config.bat")
        update_config_bat(uproject_name, config_bat_file)
