#!/usr/bin/env ruby
# Adds DefaultRulesTests.swift to the LowbeerTests target.
# Usage: ruby scripts/add_default_rules_tests.rb

require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Lowbeer.xcodeproj')
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'LowbeerTests' }
raise "Could not find LowbeerTests target" unless test_target

# Find the LowbeerTests > Models group
tests_group = project.main_group.children.find { |g| g.display_name == 'LowbeerTests' }
raise "Could not find LowbeerTests group" unless tests_group

models_group = tests_group.children.find { |g| g.display_name == 'Models' }
raise "Could not find Models group in LowbeerTests" unless models_group

# Check if already added
if models_group.children.any? { |f| f.display_name == 'DefaultRulesTests.swift' }
  puts "DefaultRulesTests.swift already in project — skipping."
  exit 0
end

file_ref = models_group.new_file('DefaultRulesTests.swift')
test_target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Added DefaultRulesTests.swift to LowbeerTests target (Models group)."
