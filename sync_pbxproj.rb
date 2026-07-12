require 'xcodeproj'
require 'find'

def sync_project(project_path, source_dir, target_name)
  puts "Syncing #{project_path}"
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == target_name }
  
  if target.nil?
    puts "Error: Target '#{target_name}' not found!"
    exit 1
  end

  # Find all .swift files in the source directory
  swift_files = []
  Find.find(source_dir) do |path|
    swift_files << path if path =~ /.*\.swift$/
  end
  
  puts "Found #{swift_files.count} .swift files."
  
  added_count = 0
  swift_files.each do |file_path|
    file_name = File.basename(file_path)
    
    # Check if the file is already in the project to avoid duplicates
    unless project.files.any? { |f| f.path == file_name || f.path == file_path }
      # Add file to project group (main group)
      group = project.main_group.find_subpath(File.dirname(file_path), true)
      group.set_source_tree('<group>')
      file_ref = group.new_reference(File.basename(file_path))
      target.add_file_references([file_ref])
      added_count += 1
      puts "Added: #{file_path}"
    end
  end
  
  if added_count > 0
    project.save
    puts "Successfully added #{added_count} new files to #{target_name}."
  else
    puts "No new files to add."
  end
end

sync_project('HaispaceBooths/HaispaceBooths.xcodeproj', 'HaispaceBooths/HaispaceBooths', 'HaispaceBooths')
sync_project('HaispaceCamera/HaispaceCamera.xcodeproj', 'HaispaceCamera/HaispaceCamera', 'HaispaceCamera')
