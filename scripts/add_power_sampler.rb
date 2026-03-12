#!/usr/bin/env ruby
# Adds PowerSampler.swift to the Lowbeer Xcode project's Core group.
require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Lowbeer.xcodeproj')
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'Lowbeer' }
raise "Could not find Lowbeer target" unless app_target

lowbeer_group = project.main_group.children.find { |g| g.display_name == 'Lowbeer' }
core_group = lowbeer_group.children.find { |g| g.display_name == 'Core' }
raise "Could not find Core group" unless core_group

if core_group.children.any? { |f| f.display_name == 'PowerSampler.swift' }
  puts "PowerSampler.swift already in project — skipping."
  exit 0
end

file_ref = core_group.new_file('PowerSampler.swift')
app_target.source_build_phase.add_file_reference(file_ref)
project.save
puts "Added PowerSampler.swift to Lowbeer target (Core group)."
