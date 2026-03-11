#!/usr/bin/env ruby
# Adds DefaultRules.swift to the Lowbeer Xcode project's Models group.
# Usage: ruby scripts/add_default_rules.rb

require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Lowbeer.xcodeproj')
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'Lowbeer' }
raise "Could not find Lowbeer target" unless app_target

# Find the Models group under Lowbeer
lowbeer_group = project.main_group.children.find { |g| g.display_name == 'Lowbeer' }
raise "Could not find Lowbeer group" unless lowbeer_group

models_group = lowbeer_group.children.find { |g| g.display_name == 'Models' }
raise "Could not find Models group" unless models_group

# Check if already added
if models_group.children.any? { |f| f.display_name == 'DefaultRules.swift' }
  puts "DefaultRules.swift already in project — skipping."
  exit 0
end

# Add the file reference
file_ref = models_group.new_file('DefaultRules.swift')
app_target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Added DefaultRules.swift to Lowbeer target (Models group)."
