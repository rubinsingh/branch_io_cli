require "pattern_patch"

module BranchIOCLI
  module Helper
    class PatchHelper
      # Adds patch_dir class attr and patch class method
      extend PatternPatch::Methods

      # Set the patch_dir for PatternPatch
      self.patch_dir = File.expand_path(File.join('..', '..', '..', 'assets', 'patches'), __FILE__)
      self.trim_mode = "<>"

      class << self
        def config
          Configuration::Configuration.current
        end

        def helper
          BranchHelper
        end

        def add_change(change)
          helper.add_change change
        end

        def use_conditional_test_key?
          config.keys.count > 1 && config.setting.nil? && !helper.has_multiple_info_plists?
        end

        def swift_file_includes_branch?(path)
          # Can't just check for the import here, since there may be a bridging header.
          # This may match branch.initSession (if the Branch instance is stored) or
          # Branch.getInstance().initSession, etc.
          /branch.*initsession|^\s*import\s+branch/i.match_file? path
        end

        def patch_bridging_header
          unless config.bridging_header_path
            say "Modules not available and bridging header not found. Cannot import Branch."
            say "Please add use_frameworks! to your Podfile and/or enable modules in your project or use --no-patch-source."
            exit(-1)
          end

          begin
            bridging_header = File.read config.bridging_header_path
            return false if bridging_header =~ %r{^\s+#import\s+<Branch/Branch.h>|^\s+@import\s+Branch\s*;}
          rescue RuntimeError => e
            say e.message
            say "Cannot read #{config.bridging_header_path}."
            say "Please correct this setting or use --no-patch-source."
            exit(-1)
          end

          say "Patching #{config.bridging_header_path}"

          if /^\s*(#import|#include|@import)/.match_file? config.bridging_header_path
            # Add among other imports
            patch(:objc_import).apply config.bridging_header_path
          elsif /\n\s*#ifndef\s+(\w+).*\n\s*#define\s+\1.*?\n/m.match_file? config.bridging_header_path
            # Has an include guard. Add inside.
            patch(:objc_import_include_guard).apply config.bridging_header_path
          else
            # No imports, no include guard. Add at the end.
            patch(:objc_import_at_end).apply config.bridging_header_path
          end
          helper.add_change config.bridging_header_path
        end

        def patch_app_delegate_swift(project)
          return false unless config.patch_source
          app_delegate_swift_path = config.app_delegate_swift_path

          return false if app_delegate_swift_path.nil? ||
                          swift_file_includes_branch?(app_delegate_swift_path)

          say "Patching #{app_delegate_swift_path}"

          unless config.bridging_header_required?
            patch(:swift_import).apply app_delegate_swift_path
          end

          patch_did_finish_launching_method_swift app_delegate_swift_path
          patch_continue_user_activity_method_swift app_delegate_swift_path
          patch_open_url_method_swift app_delegate_swift_path

          add_change app_delegate_swift_path
          true
        end

        def patch_app_delegate_objc(project)
          return false unless config.patch_source
          app_delegate_objc_path = config.app_delegate_objc_path

          return false unless app_delegate_objc_path

          app_delegate = File.read app_delegate_objc_path
          return false if app_delegate =~ %r{^\s+#import\s+<Branch/Branch.h>|^\s+@import\s+Branch\s*;}

          say "Patching #{app_delegate_objc_path}"

          patch(:objc_import).apply app_delegate_objc_path

          patch_did_finish_launching_method_objc app_delegate_objc_path
          patch_continue_user_activity_method_objc app_delegate_objc_path
          patch_open_url_method_objc app_delegate_objc_path

          add_change app_delegate_objc_path
          true
        end

        def patch_did_finish_launching_method_swift(app_delegate_swift_path)
          app_delegate_swift = File.read app_delegate_swift_path

          is_new_method = app_delegate_swift !~ /didFinishLaunching[^\n]+?\{/m
          if is_new_method
            patch_name = :did_finish_launching_new_swift
          else
            patch_name = :did_finish_launching_swift
          end
          patch(patch_name).apply app_delegate_swift_path, binding: binding
        end

        def patch_did_finish_launching_method_objc(app_delegate_objc_path)
          app_delegate_objc = File.read app_delegate_objc_path

          is_new_method = app_delegate_objc !~ /didFinishLaunchingWithOptions/m
          if is_new_method
            patch_name = :did_finish_launching_new_objc
          else
            patch_name = :did_finish_launching_objc
          end
          patch(patch_name).apply app_delegate_objc_path, binding: binding
        end

        def patch_open_url_method_swift(app_delegate_swift_path)
          app_delegate_swift = File.read app_delegate_swift_path

          if app_delegate_swift =~ /application.*open\s+url.*options/
            # Has application:openURL:options:
            patch_name = :open_url_swift
          elsif app_delegate_swift =~ /application.*open\s+url.*sourceApplication/
            # Has application:openURL:sourceApplication:annotation:
            # TODO: This method is deprecated.
            patch_name = :open_url_source_application_swift
          else
            # Has neither
            patch_name = :open_url_new_swift
          end
          patch(patch_name).apply app_delegate_swift_path
        end

        def patch_continue_user_activity_method_swift(app_delegate_swift_path)
          app_delegate_swift = File.read app_delegate_swift_path

          if app_delegate_swift =~ /application:.*continue userActivity:.*restorationHandler:/
            patch_name = :continue_user_activity_swift
          else
            patch_name = :continue_user_activity_new_swift
          end
          patch(patch_name).apply app_delegate_swift_path
        end

        def patch_open_url_method_objc(app_delegate_objc_path)
          app_delegate_objc = File.read app_delegate_objc_path

          if app_delegate_objc =~ /application:.*openURL:.*options/
            # Has application:openURL:options:
            patch_name = :open_url_objc
          elsif app_delegate_objc =~ /application:.*openURL:.*sourceApplication/
            # Has application:openURL:sourceApplication:annotation:
            patch_name = :open_url_source_annotation_objc
            # TODO: This method is deprecated.
          else
            # Has neither
            patch_name = :open_url_new_objc
          end
          patch(patch_name).apply app_delegate_objc_path
        end

        def patch_continue_user_activity_method_objc(app_delegate_objc_path)
          app_delegate_swift = File.read app_delegate_objc_path

          if app_delegate_swift =~ /application:.*continueUserActivity:.*restorationHandler:/
            patch_name = :continue_user_activity_objc
          else
            patch_name = :continue_user_activity_new_objc
          end
          patch(patch_name).apply app_delegate_objc_path
        end

        def patch_messages_view_controller
          path = config.messages_view_controller_path

          patch_name = "messages_did_become_active_"
          case path
          when nil
            return false
          when /\.swift$/
            return false if swift_file_includes_branch?(path)

            unless config.bridging_header_required?
              patch(:swift_import).apply path
            end

            is_new_method = !/didBecomeActive\(with.*?\{[^\n]*\n/m.match_file?(path)
            patch_name += "#{is_new_method ? 'new_' : ''}swift"
          else
            return false if %r{^\s+#import\s+<Branch/Branch.h>|^\s+@import\s+Branch\s*;}.match_file?(path)

            patch(:objc_import).apply path

            is_new_method = !/didBecomeActiveWithConversation.*?\{[^\n]*\n/m.match_file?(path)
            patch_name += "#{is_new_method ? 'new_' : ''}objc"
          end

          say "Patching #{path}"

          patch(patch_name).apply path, binding: binding

          helper.add_change(path)
          true
        end

        def patch_podfile(podfile_path)
          target_definition = config.podfile.target_definitions[config.target.name]
          raise "Target #{config.target.name} not found in Podfile" unless target_definition

          # Podfile already contains the Branch pod, possibly just a subspec
          return false if target_definition.dependencies.any? { |d| d.name =~ %r{^(Branch|Branch-SDK)(/.*)?$} }

          say "Adding pod \"Branch\" to #{podfile_path}"

          # It may not be clear from the Pod::Podfile whether the target has a do block.
          # It doesn't seem to be possible to update the Podfile object and write it out.
          # So we patch.
          podfile = File.read config.podfile_path

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

          patch(:cartfile).apply cartfile_path

          true
        end

        def patch_source(xcodeproj)
          # Patch the bridging header any time Swift imports are not available,
          # to make Branch available throughout the app, whether the AppDelegate
          # is in Swift or Objective-C.
          patch_bridging_header if config.bridging_header_required?
          patch_app_delegate_swift(xcodeproj) || patch_app_delegate_objc(xcodeproj)
          patch_messages_view_controller
        end
      end
    end
  end
end
