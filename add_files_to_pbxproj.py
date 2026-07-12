import os
import sys
from pbxproj import XcodeProject

def add_files_to_target(project_path, source_dir):
    print(f"Loading {project_path}")
    project = XcodeProject.load(project_path)
    
    # Get all .swift files
    swift_files = []
    for root, dirs, files in os.walk(source_dir):
        for file in files:
            if file.endswith('.swift'):
                swift_files.append(os.path.join(root, file))
                
    print(f"Found {len(swift_files)} .swift files")
    
    for file_path in swift_files:
        # Check if already added
        file_name = os.path.basename(file_path)
        if len(project.get_files_by_name(file_name)) == 0:
            print(f"Adding {file_path}")
            # Add file to project
            project.add_file(file_path, force=False)
        else:
            print(f"Skipping {file_path} (already in project)")
            
    project.save()
    print("Project saved.")

if __name__ == '__main__':
    add_files_to_target('HaispaceBooths/HaispaceBooths.xcodeproj/project.pbxproj', 'HaispaceBooths/HaispaceBooths')
    add_files_to_target('HaispaceCamera/HaispaceCamera.xcodeproj/project.pbxproj', 'HaispaceCamera/HaispaceCamera')
