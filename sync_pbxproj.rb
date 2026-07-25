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

  # Normalize all existing file paths to use forward slashes to prevent backslash issues
  dirty = false
  project.files.each do |f|
    if f.path
      normalized_path = f.path.gsub('\\', '/')
      if f.path != normalized_path
        f.path = normalized_path
        dirty = true
      end
    end
  end

  # Find all .swift files in the source directory
  swift_files = []
  Find.find(File.expand_path(source_dir)) do |path|
    swift_files << path.gsub('\\', '/') if path =~ /.*\.swift$/
  end
  
  puts "Found #{swift_files.count} .swift files."
  
  added_count = 0
  swift_files.each do |file_path|
    file_path_normalized = File.expand_path(file_path).gsub('\\', '/').downcase
    
    # Check if the file is already in the project by matching normalized relative path
    rel_path = file_path.gsub('\\', '/').downcase
    exists = project.files.any? do |f|
      next false if f.path.nil? || f.path.empty?
      f_norm = f.path.gsub('\\', '/').downcase
      rel_path.end_with?(f_norm) || f_norm.end_with?(rel_path)
    end

    unless exists
      # Add file directly to main group with absolute/relative path properly mapped
      file_ref = project.main_group.new_file(file_path)
      file_ref.path = file_ref.path.gsub('\\', '/') if file_ref.path
      target.add_file_references([file_ref])
      added_count += 1
      puts "Added: #{file_path}"
    end
  end
  
  if added_count > 0 || dirty
    project.save
    puts "Successfully synchronized #{target_name} project files."
  else
    puts "No new files to add."
  end

  # Link .xcconfig
  # The project is in HaispaceBooths/HaispaceBooths.xcodeproj
  # The secrets are in HaispaceBooths/Secrets/HaispaceBooths.xcconfig
  # Relative to the project root (HaispaceBooths/), it is "Secrets/#{target_name}.xcconfig"
  xcconfig_path = "Secrets/#{target_name}.xcconfig"
  xcconfig_ref = project.files.find { |f| f.path == xcconfig_path || f.path&.end_with?(xcconfig_path) }
  if xcconfig_ref.nil?
    xcconfig_ref = project.main_group.new_file("../#{xcconfig_path}")
  end
  
  target.build_configurations.each do |config|
    config.base_configuration_reference = xcconfig_ref
  end
  project.build_configurations.each do |config|
    config.base_configuration_reference = xcconfig_ref
  end
  
  project.save
  puts "Linked #{xcconfig_path} to build configurations."
end

sync_project('HaispaceBooths/HaispaceBooths.xcodeproj', 'HaispaceBooths/HaispaceBooths', 'HaispaceBooths')
sync_project('HaispaceCamera/HaispaceCamera.xcodeproj', 'HaispaceCamera/HaispaceCamera', 'HaispaceCamera')
