#!/usr/bin/env ruby
# Adds ArqmaRescanWidget extension target to Runner.xcodeproj (requires: gem install xcodeproj).
require 'xcodeproj'

ios_dir = File.expand_path('../ios', __dir__)
project_path = File.join(ios_dir, 'Runner.xcodeproj')
widget_dir = 'ArqmaRescanWidget'
widget_name = 'ArqmaRescanWidget'
bundle_id = 'com.arqma.arqmaWalletMobile.ArqmaRescanWidget'

project = Xcodeproj::Project.open(project_path)
if project.targets.any? { |t| t.name == widget_name }
  puts "[embed_ios_live_activity] #{widget_name} target already present"
  exit 0
end

group = project.main_group.find_subpath(widget_dir, true)
group.set_source_tree('<group>')
group.set_path(widget_dir)

bundle_swift = group.new_file('ArqmaRescanWidgetBundle.swift')
live_swift = group.new_file('ArqmaRescanWidgetLiveActivity.swift')
info_plist = group.new_file('Info.plist')
entitlements = group.new_file('ArqmaRescanWidget.entitlements')

target = project.new_target(
  :app_extension,
  widget_name,
  :ios,
  '16.1',
  project.products_group,
  :swift
)
target.product_reference.name = "#{widget_name}.appex"
target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = "#{widget_dir}/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{widget_dir}/ArqmaRescanWidget.entitlements"
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
  config.build_settings['DEVELOPMENT_TEAM'] = '75L2UT4BNN'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.1'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
end

target.add_file_references([bundle_swift, live_swift])

runner = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Foundation Extensions'
  embed.dst_subfolder_spec = '13'
  runner.build_phases << embed
end
build_file = embed.add_file_reference(target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

target.add_dependency(runner)

project.save
puts "[embed_ios_live_activity] added #{widget_name} — open ios/Runner.xcworkspace and enable App Group on both targets in Xcode if needed"
