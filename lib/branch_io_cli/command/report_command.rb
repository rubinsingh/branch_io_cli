require "shellwords"

module BranchIOCLI
  module Command
    class ReportCommand < Command
      def self.available_options
        [
          Configuration::Option.new(
            name: :workspace,
            description: "Path to an Xcode workspace",
            type: String,
            example: "MyProject.xcworkspace"
          ),
          Configuration::Option.new(
            name: :xcodeproj,
            description: "Path to an Xcode project",
            type: String,
            example: "MyProject.xcodeproj"
          ),
          Configuration::Option.new(
            name: :scheme,
            description: "A scheme from the project or workspace to build",
            type: String,
            example: "MyProjectScheme"
          ),
          Configuration::Option.new(
            name: :target,
            description: "A target to build",
            type: String,
            example: "MyProjectTarget"
          ),
          Configuration::Option.new(
            name: :configuration,
            description: "The build configuration to use (default: Scheme-dependent)",
            type: String,
            example: "Debug|Release|CustomConfigName"
          ),
          Configuration::Option.new(
            name: :sdk,
            description: "Passed as -sdk to xcodebuild",
            type: String,
            example: "iphoneos",
            default_value: "iphonesimulator"
          ),
          Configuration::Option.new(
            name: :podfile,
            description: "Path to the Podfile for the project",
            type: String,
            example: "/path/to/Podfile"
          ),
          Configuration::Option.new(
            name: :cartfile,
            description: "Path to the Cartfile for the project",
            type: String,
            example: "/path/to/Cartfile"
          ),
          Configuration::Option.new(
            name: :clean,
            description: "Clean before attempting to build",
            default_value: true
          ),
          Configuration::Option.new(
            name: :header_only,
            description: "Write a report header to standard output and exit",
            default_value: false,
            aliases: "-H"
          ),
          Configuration::Option.new(
            name: :pod_repo_update,
            description: "Update the local podspec repo before installing",
            default_value: true
          ),
          Configuration::Option.new(
            name: :out,
            description: "Report output path",
            default_value: "./report.txt",
            aliases: "-o",
            example: "./report.txt",
            type: String
          )
        ]
      end

      def run!
        say "\n"

        say "Loading settings from Xcode"
        # In case running in a non-CLI context (e.g., Rake or Fastlane) be sure
        # to reset Xcode settings each time, since project, target and
        # configurations will change.
        Configuration::XcodeSettings.reset
        if Configuration::XcodeSettings.all_valid?
          say "Done ✅"
        else
          say "Failed to load settings from Xcode. Some information may be missing.\n"
        end

        if config.header_only
          say report_helper.report_header
          return
        end

        if config.report_path == "stdout"
          write_report STDOUT
        else
          File.open(config.report_path, "w") { |f| write_report f }
          say "Report generated in #{config.report_path}"
        end
      end

      def write_report(report)
        report.write "Branch.io Xcode build report v #{VERSION} #{DateTime.now}\n\n"
        report.write "#{config.report_configuration}\n"
        report.write "#{report_helper.report_header}\n"

        report_helper.pod_install_if_required report

        # run xcodebuild -list
        report.log_command "#{report_helper.base_xcodebuild_cmd} -list"

        # If using a workspace, -list all the projects as well
        if config.workspace_path
          config.workspace.file_references.map(&:path).each do |project_path|
            path = File.join File.dirname(config.workspace_path), project_path
            report.log_command ["xcodebuild", "-list", "-project", path]
          end
        end

        # xcodebuild -showBuildSettings
        config.configurations.each do |configuration|
          Configuration::XcodeSettings[configuration].log_xcodebuild_showbuildsettings report
        end

        base_cmd = report_helper.base_xcodebuild_cmd
        # Add more options for the rest of the commands
        base_cmd += " -scheme #{Shellwords.escape config.scheme}"
        base_cmd += " -configuration #{Shellwords.escape(config.configuration || config.configurations_from_scheme.first)}"
        base_cmd += " -sdk #{Shellwords.escape config.sdk}"

        if config.clean
          say "Cleaning"
          if report.log_command("#{base_cmd} clean").success?
            say "Done ✅"
          else
            say "Clean failed."
          end
        end

        say "Building"
        if report.log_command("#{base_cmd} -verbose").success?
          say "Done ✅"
        else
          say "Build failed."
        end
      end

      def report_helper
        Helper::ReportHelper
      end
    end
  end
end
