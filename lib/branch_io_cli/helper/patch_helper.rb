require "pattern_patch"

module BranchIOCLI
  module Helper
    class PatchHelper
      class << self
        def load_patch(name)
          path = File.expand_path(File.join('..', '..', '..', 'assets', 'patches', "#{name}.yml"), __FILE__)
          PatternPatch::Patch.from_yaml path
        end

        def config
          Configuration::Configuration.current
        end

        def helper
          BranchHelper
        end

        def add_change(change)
          helper.add_change change
        end

        def bridging_header_required?
          # If there is a Podfile and use_frameworks! is not present for this
          # target, we need a bridging header.
          return true if config.podfile && !config.uses_frameworks?
          !config.modules_enabled?
        end

        def patch_app_delegate_swift(project)
          return false unless config.swift_version

          app_delegate_swift = project.files.find { |f| f.path =~ /AppDelegate.swift$/ }
          return false if app_delegate_swift.nil?

          app_delegate_swift_path = app_delegate_swift.real_path.to_s

          app_delegate = File.read app_delegate_swift_path

          if bridging_header_required?
            unless config.bridging_header_path
              say "Modules not available and bridging header not found. Cannot import Branch."
              say "Please add use_frameworks! to your Podfile and/or enable modules in your project or use --no-patch-source."
              exit(-1)
              return false if app_delegate =~ %r{^\s+#import\s+<Branch/Branch.h>|^\s+@import\s+Branch\s*;}
            end

            say "Patching #{config.bridging_header_path}"

            load_patch(:objc_import).apply config.bridging_header_path
            helper.add_change config.bridging_header_path
          else
            return false if app_delegate =~ /^\s*import\s+Branch/
            load_patch(:swift_import).apply app_delegate_swift_path
          end

          say "Patching #{app_delegate_swift_path}"

          patch_did_finish_launching_method_swift app_delegate_swift_path
          patch_continue_user_activity_method_swift app_delegate_swift_path
          patch_open_url_method_swift app_delegate_swift_path

          add_change app_delegate_swift_path
          true
        end

        def patch_app_delegate_objc(project)
          app_delegate_objc = project.files.find { |f| f.path =~ /AppDelegate.m$/ }
          return false if app_delegate_objc.nil?

          app_delegate_objc_path = app_delegate_objc.real_path.to_s

          app_delegate = File.read app_delegate_objc_path
          return false if app_delegate =~ %r{^\s+#import\s+<Branch/Branch.h>|^\s+@import\s+Branch\s*;}

          say "Patching #{app_delegate_objc_path}"

          load_patch(:objc_import).apply app_delegate_objc_path

          patch_did_finish_launching_method_objc app_delegate_objc_path
          patch_continue_user_activity_method_objc app_delegate_objc_path
          patch_open_url_method_objc app_delegate_objc_path

          add_change app_delegate_objc_path
          true
        end

        def patch_did_finish_launching_method_swift(app_delegate_swift_path)
          app_delegate_swift = File.read app_delegate_swift_path

          patch_name = "did_finish_launching_"
          if app_delegate_swift =~ /didFinishLaunching[^\n]+?\{/m
            # method already present
            patch_name += "test_" unless config.keys.count <= 1 || has_multiple_info_plists?
            patch_name += "swift"
            patch = load_patch patch_name
            patch.regexp = /didFinishLaunchingWithOptions.*?\{[^\n]*\n/m
          else
            # method not present. add entire method
            patch_name += "new_"
            patch_name += "test_" unless config.keys.count <= 1 || has_multiple_info_plists?
            patch_name += "swift"
            patch = load_patch patch_name
            patch.regexp = /var\s+window\s?:\s?UIWindow\?.*?\n/m
          end
          patch.apply app_delegate_swift_path
        end

        def patch_did_finish_launching_method_objc(app_delegate_objc_path)
          app_delegate_objc = File.read app_delegate_objc_path

          patch_name = "did_finish_launching_"
          if app_delegate_objc =~ /didFinishLaunchingWithOptions/m
            # method exists. patch it.
            patch_name += "test_" unless config.keys.count <= 1 || has_multiple_info_plists?
            patch_name += "objc"
            patch = load_patch patch_name
            patch.regexp = /didFinishLaunchingWithOptions.*?\{[^\n]*\n/m
          else
            # method does not exist. add it.
            patch_name += "new_"
            patch_name += "test_" unless config.keys.count <= 1 || has_multiple_info_plists?
            patch_name += "objc"
            patch = load_patch patch_name
            patch.regexp = /^@implementation.*?\n/m
          end
          patch.apply app_delegate_objc_path
        end

        def patch_open_url_method_swift(app_delegate_swift_path)
          app_delegate_swift = File.read app_delegate_swift_path
          patch_name = "open_url_"
          if app_delegate_swift =~ /application.*open\s+url.*options/
            # Has application:openURL:options:
            patch_name += "swift"
            patch = load_patch patch_name
            patch.regexp = /application.*open\s+url.*options:.*?\{.*?\n/m
          elsif app_delegate_swift =~ /application.*open\s+url.*sourceApplication/
            # Has application:openURL:sourceApplication:annotation:
            # TODO: This method is deprecated.
            patch_name += "source_application_swift"
            patch = load_patch patch_name
            patch.regexp = /application.*open\s+url.*sourceApplication:.*?\{.*?\n/m
          else
            # Has neither
            patch_name += "new_swift"
            patch = load_patch patch_name
            patch.regexp = /\n\s*\}[^{}]*\Z/m
          end
          patch.apply app_delegate_swift_path
        end

        def patch_continue_user_activity_method_swift(app_delegate_swift_path)
          app_delegate = File.read app_delegate_swift_path
          patch_name = "continue_user_activity_"
          if app_delegate =~ /application:.*continue userActivity:.*restorationHandler:/
            # Add something to the top of the method
            patch_name += "swift"
            patch = load_patch patch_name
            patch.regexp = /application:.*continue userActivity:.*restorationHandler:.*?\{.*?\n/m
          else
            # Add the application:continueUserActivity:restorationHandler method if it does not exist
            patch_name += "new_swift"
            patch = load_patch patch_name
            patch.regexp = /\n\s*\}[^{}]*\Z/m
          end
          patch.apply app_delegate_swift_path
        end

        def patch_open_url_method_objc(app_delegate_objc_path)
          app_delegate_objc = File.read app_delegate_objc_path
          patch_name = "open_url_"
          if app_delegate_objc =~ /application:.*openURL:.*options/
            # Has application:openURL:options:
            patch_name += "objc"
            patch = load_patch patch_name
            patch.regexp = /application:.*openURL:.*options:.*?\{.*?\n/m
          elsif app_delegate_objc =~ /application:.*openURL:.*sourceApplication/
            # Has application:openURL:sourceApplication:annotation:
            patch_name += "source_application_objc"
            patch = load_patch patch_name
            patch.regexp = /application:.*openURL:.*sourceApplication:.*?\{.*?\n/m
          else
            # Has neither
            patch_name += "new_objc"
            patch = load_patch patch_name
            patch.regexp = /\n\s*@end[^@]*\Z/m
          end
          patch.apply app_delegate_objc_path
        end

        def patch_continue_user_activity_method_objc(app_delegate_objc_path)
          app_delegate = File.read app_delegate_objc_path
          patch_name = "continue_user_activity_"
          if app_delegate =~ /application:.*continueUserActivity:.*restorationHandler:/
            patch_name += "objc"
            patch = load_patch patch_name
            patch.regexp = /application:.*continueUserActivity:.*restorationHandler:.*?\{.*?\n/m
          else
            # Add the application:continueUserActivity:restorationHandler method if it does not exist
            patch_name += "new_objc"
            patch = load_patch patch_name
            patch.regexp = /\n\s*@end[^@]*\Z/m
          end
          patch.apply app_delegate_objc_path
        end

        def patch_podfile(podfile_path)
          podfile = File.read podfile_path

          # Podfile already contains the Branch pod
          # TODO: Allow for adding to multiple targets in the Podfile
          return false if podfile =~ /pod\s+('Branch'|"Branch")/

          say "Adding pod \"Branch\" to #{podfile_path}"

          if podfile =~ /target\s+(["'])#{config.target.name}\1\s+do.*?\n/m
            # if there is a target block for this target:
            patch = PatternPatch::Patch.new(
              regexp: /\n(\s*)target\s+(["'])#{config.target.name}\2\s+do.*?\n/m,
              text: "\\1  pod \"Branch\"\n",
              mode: :append
            )
          else
            # add to the abstract_target for this target
            patch = PatternPatch::Patch.new(
              regexp: /^(\s*)target\s+["']#{config.target.name}/,
              text: "\\1pod \"Branch\"\n",
              mode: :prepend
            )
          end
          patch.apply podfile_path

          true
        end

        def patch_cartfile(cartfile_path)
          cartfile = File.read cartfile_path

          # Cartfile already contains the Branch framework
          return false if cartfile =~ /git.+Branch/

          say "Adding \"Branch\" to #{cartfile_path}"

          load_patch(:cartfile).apply cartfile_path

          true
        end

        def patch_source(xcodeproj)
          patch_app_delegate_swift(xcodeproj) || patch_app_delegate_objc(xcodeproj)
        end
      end
    end
  end
end
