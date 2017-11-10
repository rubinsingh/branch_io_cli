module BranchIOCLI
  module Configuration
    class ReportConfiguration < Configuration
      attr_reader :clean
      attr_reader :header_only
      attr_reader :scheme
      attr_reader :configuration
      attr_reader :report_path
      attr_reader :sdk

      def validate_options
        @clean = options.clean
        @header_only = options.header_only
        @scheme = options.scheme
        @target = options.target
        @report_path = options.out
        @sdk = options.sdk
        @pod_repo_update = options.pod_repo_update

        validate_xcodeproj_and_workspace options
        validate_scheme options
        validate_target options
        validate_configuration options

        # If neither --podfile nor --cartfile is present, arbitrarily look for a Podfile
        # first.

        # If --cartfile is present, don't look for a Podfile. Just validate that
        # Cartfile.
        validate_buildfile_path(options.podfile, "Podfile") if options.cartfile.nil?

        # If --podfile is present or a Podfile was found, don't look for a Cartfile.
        validate_buildfile_path(options.cartfile, "Cartfile") if sdk_integration_mode.nil?
      end

      def log
        super
        say <<EOF
<%= color('Xcode workspace:', BOLD) %> #{workspace_path || '(none)'}
<%= color('Xcode project:', BOLD) %> #{xcodeproj_path || '(none)'}
<%= color('Scheme:', BOLD) %> #{scheme || '(none)'}
<%= color('Target:', BOLD) %> #{target || '(none)'}
<%= color('Configuration:', BOLD) %> #{configuration}
<%= color('SDK:', BOLD) %> #{sdk}
<%= color('Podfile:', BOLD) %> #{podfile_path || '(none)'}
<%= color('Cartfile:', BOLD) %> #{cartfile_path || '(none)'}
<%= color('Pod repo update:', BOLD) %> #{pod_repo_update.inspect}
<%= color('Clean:', BOLD) %> #{clean.inspect}
<%= color('Report path:', BOLD) %> #{report_path}
EOF
      end

      # rubocop: disable Metrics/PerceivedComplexity
      def validate_xcodeproj_and_workspace(options)
        # 1. What was passed in?
        begin
          if options.workspace
            path = options.workspace
            @workspace = Xcodeproj::Workspace.new_from_xcworkspace options.workspace
            @workspace_path = options.workspace
          end
          if options.xcodeproj
            path = options.xcodeproj
            @xcodeproj = Xcodeproj::Project.open options.xcodeproj
            @xcodeproj_path = options.xcodeproj
          else
            # Pass --workspace and --xcodeproj to override this inference.
            if workspace && workspace.file_references.count > 0 && workspace.file_references.first.path =~ /\.xcodeproj$/
              @xcodeproj_path = File.expand_path "../#{@workspace.file_references.first.path}", workspace_path
              @xcodeproj = Xcodeproj::Project.open xcodeproj_path
            end
          end
          return if @workspace || @xcodeproj
        rescue StandardError => e
          say e.message
        end

        # Try to find first a workspace, then a project
        all_workspace_paths = Dir[File.expand_path(File.join(".", "**/*.xcworkspace"))]
                              .reject { |w| w =~ %r{/project.xcworkspace$} }
                              .select do |p|
          valid = true
          Pathname.new(p).each_filename do |f|
            valid = false && break if f == "Carthage" || f == "Pods"
          end
          valid
        end

        if all_workspace_paths.count == 1
          path = all_workspace_paths.first
        elsif all_workspace_paths.count == 0
          all_xcodeproj_paths = Dir[File.expand_path(File.join(".", "**/*.xcodeproj"))]
          xcodeproj_paths = all_xcodeproj_paths.select do |p|
            valid = true
            Pathname.new(p).each_filename do |f|
              valid = false && break if f == "Carthage" || f == "Pods"
            end
            valid
          end

          path = xcodeproj_paths.first if xcodeproj_paths.count == 1
        end
        # If more than one workspace. Don't try to find a project. Just prompt.

        loop do
          path = ask "Please enter a path to your Xcode project or workspace: " if path.nil?
          begin
            if path =~ /\.xcworkspace$/
              @workspace = Xcodeproj::Workspace.new_from_xcworkspace path
              @workspace_path = path

              # Pass --workspace and --xcodeproj to override this inference.
              if workspace.file_references.count > 0 && workspace.file_references.first.path =~ /\.xcodeproj$/
                @xcodeproj_path = File.expand_path "../#{workspace.file_references.first.path}", workspace_path
                @xcodeproj = Xcodeproj::Project.open xcodeproj_path
              end

              return
            elsif path =~ /\.xcodeproj$/
              @xcodeproj = Xcodeproj::Project.open path
              @xcodeproj_path = path
              return
            else
              say "Path must end with .xcworkspace or .xcodeproj"
            end
          rescue StandardError => e
            say e.message
          end
        end
      end
      # rubocop: enable Metrics/PerceivedComplexity

      def validate_scheme(options)
        schemes = all_schemes

        if options.scheme && schemes.include?(options.scheme)
          @scheme = options.scheme
        elsif schemes.count == 1
          @scheme = schemes.first
          say "Scheme #{options.scheme} not found. Using #{@scheme}." if options.scheme
        elsif !schemes.empty?
          # By default, take a scheme with the same name as the project name.
          return if !options.scheme && (@scheme = schemes.find { |s| s == File.basename(xcodeproj_path, '.xcodeproj') })

          @scheme = choose do |menu|
            menu.header = "Schemes from project"
            schemes.each { |s| menu.choice s }
            menu.prompt = "Please choose one of the schemes above. "
          end
        else
          say "No scheme defined in project."
          exit(-1)
        end

        return if options.target || xcscheme.nil?

        # Find the target used when running the scheme if the user didn't specify one.
        # This will be picked up in #validate_target
        entry = xcscheme.build_action.entries.select(&:build_for_running?).first
        options.target = entry.buildable_references.first.target_name
      end

      def all_schemes
        if workspace_path
          workspace.schemes.keys.reject { |scheme| scheme == "Pods" }
        else
          Xcodeproj::Project.schemes xcodeproj_path
        end
      end

      def xcscheme
        return @xcscheme if @xcscheme_checked
        # This may not exist. If it comes back nil once, don't keep checking.
        @xcscheme_checked = true
        @xcscheme = scheme_with_name @scheme
        @xcscheme
      end

      def scheme_with_name(scheme_name)
        if workspace_path
          project_path = workspace.schemes[@scheme]
        else
          project_path = xcodeproj_path
        end

        # Look for a shared scheme.
        xcshareddata_path = File.join project_path, "xcshareddata", "xcschemes", "#{@scheme}.xcscheme"
        scheme_path = xcshareddata_path if File.exist?(xcshareddata_path)

        unless scheme_path
          # Look for a local scheme
          user = @xcode_settings["USER"] if @xcode_settings
          user ||= ENV["USER"] || ENV["LOGNAME"]
          xcuserdata_path = File.join project_path, "xcuserdata", "#{user}.xcuserdatad", "xcschemes", "#{@scheme}.xcscheme"
          scheme_path = xcuserdata_path if File.exist?(xcuserdata_path)
        end

        return nil unless scheme_path

        Xcodeproj::XCScheme.new(scheme_path)
      end

      def validate_configuration(options)
        all_configs = xcodeproj.build_configurations.map(&:name)

        if options.configuration && all_configs.include?(options.configuration)
          @configuration = options.configuration
        elsif options.configuration
          say "Configuration #{options.configuration} not found."
          @configuration = choose do |menu|
            menu.header = "Configurations from project"
            all_configs.each { |c| menu.choice c }
            menu.prompt = "Please choose one of the above. "
          end
        end

        return if @configuration

        @configuration = "Debug" # Usual default for the launch action

        return unless xcscheme

        @configuration = xcscheme.launch_action.build_configuration
      end
    end
  end
end
