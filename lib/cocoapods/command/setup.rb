require 'fileutils'

module Pod
  class Command
    class Setup < Command
      self.summary = 'Setup the CocoaPods environment'

      self.description = <<-DESC
        Creates a directory at `~/.cocoapods/repos` which will hold your spec-repos.
        This is where it will create a clone of the public `master` spec-repo from:

            https://github.com/CocoaPods/Specs

        If the clone already exists, it will ensure that it is up-to-date.
      DESC

      def self.options
        [
          ['--no-shallow', 'Clone full history so push will work'],
          ['--push', 'Use this option to enable push access once granted'],
        ].concat(super)
      end

      extend Executable
      executable :git

      def initialize(argv)
        @push_option = argv.flag?('push')
        @shallow     = argv.flag?('shallow', !@push_option)
        super
      end

      def run
        UI.section 'Setting up CocoaPods master repo' do
          if master_repo_dir.exist?
            set_master_repo_url
            set_master_repo_branch
            update_master_repo
          elsif old_master_repo_dir.exist?
            migrate_repos
          else
            add_master_repo
          end
        end

        access_type = push? ? 'push' : 'read-only'
        UI.puts "Setup completed (#{access_type} access)".green
      end

      #--------------------------------------#

      # @!group Setup steps

      # Migrates any repos from the old directory structure to the new
      # directory structure.
      #
      # @todo: Remove by 1.0
      #
      def migrate_repos
        config.repos_dir.mkpath
        Dir.foreach old_master_repo_dir.parent do |repo_dir|
          source_repo_dir = old_master_repo_dir.parent + repo_dir
          target_repo_dir = config.repos_dir + repo_dir
          if repo_dir !~ /\.+/ && source_repo_dir != config.repos_dir
            FileUtils.mv source_repo_dir, target_repo_dir
          end
        end
      end

      # Sets the url of the master repo according to whether it is push.
      #
      # @return [void]
      #
      def set_master_repo_url
        Dir.chdir(master_repo_dir) do
          git("remote set-url origin '#{url}'")
        end
      end

      # Adds the master repo from the remote.
      #
      # @return [void]
      #
      def add_master_repo
        cmd = ['master', url, 'master']
        cmd << '--shallow' if @shallow
        Repo::Add.parse(cmd).run
      end

      # Updates the master repo against the remote.
      #
      # @return [void]
      #
      def update_master_repo
        SourcesManager.update('master', true)
      end

      # Sets the repo to the master branch.
      #
      # @note   This is not needed anymore as it was used for CocoaPods 0.6
      #         release candidates.
      #
      # @return [void]
      #
      def set_master_repo_branch
        Dir.chdir(master_repo_dir) do
          git('checkout master')
        end
      end

      #--------------------------------------#

      # @!group Private helpers

      # @return [String] the url to use according to whether push mode should
      #         be enabled.
      #
      def url
        push? ? self.class.read_write_url : self.class.read_only_url
      end

      # @return [String] the read only url of the master repo.
      #
      def self.read_only_url
        'https://github.com/CocoaPods/Specs.git'
      end

      # @return [String] the read-write url of the master repo.
      #
      def self.read_write_url
        'git@github.com:CocoaPods/Specs.git'
      end

      # Checks if the user asked to setup the master repo in push mode or if
      # the repo was already in push mode.
      #
      # @return [String] whether the master repo should be set up in push mode.
      #
      def push?
        @push ||= (@push_option || master_repo_is_push?)
      end

      # @return [Bool] if the master repo is already configured in push mode.
      #
      def master_repo_is_push?
        return false unless master_repo_dir.exist?
        Dir.chdir(master_repo_dir) do
          url = git('config --get remote.origin.url')
          url.chomp == self.class.read_write_url
        end
      end

      # @return [Pathname] the directory of the master repo.
      #
      def master_repo_dir
        SourcesManager.master_repo_dir
      end

      # @return [Pathname] the directory of the old master repo.
      #
      def old_master_repo_dir
        Pathname.new('~/.cocoapods/master').expand_path
      end
    end
  end
end
