#!/usr/bin/env ruby
# Adds ArqmaRescanWidget extension target to Runner.xcodeproj (gem install xcodeproj).
# Extension bundle id: com.arqma.arqmaWalletMobile.RescanLiveActivity (App Store Connect friendly).
require 'xcodeproj'

ios_dir = File.expand_path('../ios', __dir__)
project_path = File.join(ios_dir, 'Runner.xcodeproj')
widget_dir = 'ArqmaRescanWidget'
widget_name = 'ArqmaRescanWidget'
extension_bundle_id = 'com.arqma.arqmaWalletMobile.RescanLiveActivity'
team_id = '75L2UT4BNN'
app_group = 'group.com.arqma.arqmaWalletMobile'
embed_script = 'embed_live_activity_extension.sh'

def ensure_embed_script_phase(runner, ios_dir, embed_script)
  phase_name = 'Embed Live Activity Extension'
  runner.shell_script_build_phases.each do |phase|
    next unless phase.name == phase_name

    runner.build_phases.delete(phase)
    runner.build_phases << phase
    return phase
  end

  phase = runner.new_shell_script_build_phase(phase_name)
  phase.shell_script = "\"${SRCROOT}/#{embed_script}\"\n"
  phase.show_env_vars_in_log = '0'
  runner.build_phases.delete(phase)
  runner.build_phases << phase
  phase
end

def remove_copy_files_embed(runner)
  runner.copy_files_build_phases.each do |phase|
    next unless phase.name == 'Embed Foundation Extensions'

    runner.build_phases.delete(phase)
  end
end

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless runner

runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = team_id
end

existing = project.targets.find { |t| t.name == widget_name }
if existing
  extension_xcconfig = project.files.find { |f| f.path == 'Flutter/Extension.xcconfig' }
  existing.build_configurations.each do |config|
    config.base_configuration_reference = extension_xcconfig if extension_xcconfig
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = extension_bundle_id
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{widget_dir}/ArqmaRescanWidget.entitlements"
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
    config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
    config.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
    config.build_settings['DEVELOPMENT_TEAM'] = team_id
  end
  remove_copy_files_embed(runner)
  ensure_embed_script_phase(runner, ios_dir, embed_script)
  unless runner.dependencies.any? { |d| d.target == existing }
    runner.add_dependency(existing)
  end
  project.save
  puts "[embed_ios_live_activity] updated #{widget_name} bundle id -> #{extension_bundle_id}"
  exit 0
end

group = project.main_group.find_subpath(widget_dir, true)
group.set_source_tree('<group>')
group.set_path(widget_dir)

bundle_swift = group.new_file('ArqmaRescanWidgetBundle.swift')
live_swift = group.new_file('ArqmaRescanWidgetLiveActivity.swift')
group.new_file('Info.plist')
group.new_file('ArqmaRescanWidget.entitlements')

target = project.new_target(
  :app_extension,
  widget_name,
  :ios,
  '16.1',
  project.products_group,
  :swift
)
target.product_reference.name = "#{widget_name}.appex"
extension_xcconfig = project.files.find { |f| f.path == 'Flutter/Extension.xcconfig' }

target.build_configurations.each do |config|
  config.base_configuration_reference = extension_xcconfig if extension_xcconfig
  config.build_settings['INFOPLIST_FILE'] = "#{widget_dir}/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{widget_dir}/ArqmaRescanWidget.entitlements"
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = extension_bundle_id
  config.build_settings['PRODUCT_NAME'] = widget_name
  config.build_settings['DEVELOPMENT_TEAM'] = team_id
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  config.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.1'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
end

target.add_file_references([bundle_swift, live_swift])
remove_copy_files_embed(runner)
ensure_embed_script_phase(runner, ios_dir, embed_script)
runner.add_dependency(target)

project.save
puts "[embed_ios_live_activity] added #{widget_name} (#{extension_bundle_id})"
puts "[embed_ios_live_activity] App Group: #{app_group}"
puts '[embed_ios_live_activity] Run: bash tool/provision_ios_app_group.sh (or enable App Groups in Xcode for Runner + extension)'
