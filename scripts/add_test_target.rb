#!/usr/bin/env ruby
# Adds LowbeerTests unit test target to the Xcode project.
# Usage: ruby scripts/add_test_target.rb

require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Lowbeer.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Check if test target already exists
if project.targets.any? { |t| t.name == 'LowbeerTests' }
  puts "LowbeerTests target already exists — skipping."
  exit 0
end

# Find the main app target
app_target = project.targets.find { |t| t.name == 'Lowbeer' }
raise "Could not find Lowbeer target" unless app_target

# Create test target
test_target = project.new_target(:unit_test_bundle, 'LowbeerTests', :osx, '14.0')
test_target.add_dependency(app_target)

# Configure build settings for both configurations
test_target.build_configurations.each do |config|
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Lowbeer.app/Contents/MacOS/Lowbeer'
  config.build_settings['SWIFT_VERSION'] = '5.9'
  config.build_settings['SDKROOT'] = 'macosx'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.mistakeknot.LowbeerTests'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
end

# Create group structure for test files
tests_group = project.main_group.new_group('LowbeerTests', 'LowbeerTests')
models_group = tests_group.new_group('Models', 'Models')
core_group = tests_group.new_group('Core', 'Core')
mocks_group = tests_group.new_group('Mocks', 'Mocks')

# Add test source files
test_files = {
  models_group => %w[
    ProcessHistoryTests.swift
    AppIdentityTests.swift
    ThrottleRuleCodableTests.swift
    ScheduleEvaluatorTests.swift
  ],
  core_group => %w[
    SafetyListTests.swift
    RuleEvaluatorTests.swift
    ThrottleEngineTests.swift
  ],
  mocks_group => %w[
    MockForegroundObserver.swift
  ],
}

test_files.each do |group, files|
  files.each do |filename|
    file_ref = group.new_file(filename)
    test_target.source_build_phase.add_file_reference(file_ref)
  end
end

# Add test target to the scheme (or create a new scheme)
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target)
scheme.save_as(project_path, 'Lowbeer', true)

project.save

puts "Added LowbeerTests target with #{test_files.values.flatten.count} test files."
puts "Scheme 'Lowbeer' updated to include test target."
