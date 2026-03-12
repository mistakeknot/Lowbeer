#!/usr/bin/env ruby
# Adds PowerSamplerTests.swift to the LowbeerTests target.
# Usage: ruby scripts/add_power_sampler_tests.rb

require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Lowbeer.xcodeproj')
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'LowbeerTests' }
raise "Could not find LowbeerTests target" unless test_target

# Find the LowbeerTests > Core group (create if needed)
tests_group = project.main_group.children.find { |g| g.display_name == 'LowbeerTests' }
raise "Could not find LowbeerTests group" unless tests_group

core_group = tests_group.children.find { |g| g.display_name == 'Core' }
unless core_group
  core_group = tests_group.new_group('Core')
end

# Check if already added
if core_group.children.any? { |f| f.display_name == 'PowerSamplerTests.swift' }
  puts "PowerSamplerTests.swift already in project — skipping."
  exit 0
end

file_ref = core_group.new_file('PowerSamplerTests.swift')
test_target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Added PowerSamplerTests.swift to LowbeerTests target (Core group)."
