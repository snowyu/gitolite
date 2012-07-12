require 'tempfile'
require 'pathname'

require File.join(File.dirname(__FILE__), 'config', 'repo')
require File.join(File.dirname(__FILE__), 'config', 'group')

module Gitolite
  class Config
    attr_accessor :repos, :groups, :filename, :subconfs, :file, :parent, :includes

    def initialize(config='gitolite.conf', parent=nil)
      @repos = {}
      @groups = {}
      @subconfs = {}
      @includes = {}
      @file = config
      @parent = parent
      @root_config = nil
      @filename = File.basename(config)
    end

    def self.init(filename = "gitolite.conf")
      self.new(filename)
    end

    # Create the subconf instance.
    # the parent must be set.
    def self.new_subconf(filename, parent)
      conf = self.new(filename)
      parent.add_subconf(conf)
      conf
    end

    def self.new_inc(filename, parent)
      conf = self.new(filename)
      parent.add_inc(conf)
      conf
    end

    # Create the subconf instance and load this subconf into the instance.
    # the parent must be set.
    def self.load_subconf(filename, parent)
      conf = new_subconf(filename, parent)
      conf.load_from(filename)
      conf
    end

    def self.load_inc(filename, parent)
      conf = self.new_inc(filename, parent)
      conf.load_from(filename)
      conf
    end


    def self.load_from(filename, parent=nil)
      conf = self.new(filename, parent)
      conf.load_from(filename)
      conf
    end

    def load_from(filename=@file)
      process_config(filename)
    end

    def name
      @file
    end

    # the Config instance just is a container of the subconfs if true
    def is_container?(name = @filename)
      name =~ /\*|\?/
    end

    def root_config
      return @root_config if @root_config
      root = self
      parent = @parent
      while parent do
        root = parent
        parent = parent.parent
      end
      @root_config = root
      root
    end

    def parent=(conf)
      raise ArgumentError, "Config must be of type Gitolite::Config!" unless conf.instance_of? Gitolite::Config
      if has_subconf?(conf, 99) || has_inc?(conf, 99)
        raise ConfigDependencyError
      else
        @parent = conf
      end
    end

    # get the config file path base on the @file
    def get_file_path(file)
      path = Pathname.new(file)
      basedirname = File.dirname(@file)
      basedir = Pathname.new basedirname
      if path.relative?
        if basedirname != '.' && basedir.relative?
          File.join(basedir, file)
        else
          file
        end
      else
        result = path.relative_path_from(basedir)
        result.to_s
      end
    rescue
      file
    end

    def get_relative_path(file)
      path = Pathname.new(file)
      if path.relative?
        file
      else
        basedir = Pathname.new File.dirname(@file)
        result = path.relative_path_from(basedir)
        result.to_s
      end
    rescue
      file
    end

    # add a include config
    def add_inc(conf)
      add_subconf(conf, @includes)
    end

    # has a include config
    def has_inc?(aFile, level = 1)
      has_subconf?(aFile, level, @includes)
    end

    # get the include config
    def get_inc(file, level = 1)
      get_subconf(file, level, @includes)
    end

    # rm a include config
    def rm_inc(file)
      rm_subconf(file, @includes)
    end

    def add_subconf(conf, container = @subconfs)
      raise ArgumentError, "Config must be of type Gitolite::Config!" unless conf.instance_of? Gitolite::Config
      conf.parent = self if conf.parent != self
      key = get_relative_path(conf.file)
      container[key] = conf
    end

    def has_subconf?(aFile, level = 1, container = @subconfs)
      file = get_relative_path(normalize_config_name(aFile))
      result = container.has_key?(file)
      if !result and (level > 1)
        level -= 1
        container.each do |k, v|
          result = v.has_subconf?(file, level, container)
          break if result 
        end
      end
      result
    end

    def get_subconf(file, level = 1, container = @subconfs)
      file = get_relative_path(normalize_config_name(file))

      result = container[file]
      if !result and (level > 1)
        level -= 1
        container.each do |k,v|
          result = v.get_subconf(file, level, container)
        end
      end
      result
    end

    def rm_subconf(file, container = @subconfs)
      file = normalize_config_name(file)
      container.delete(get_relative_path(file))
    end

    #TODO: merge repo unless overwrite = true
    def add_repo(repo, overwrite = false)
      raise ArgumentError, "Repo must be of type Gitolite::Config::Repo!" unless repo.instance_of? Gitolite::Config::Repo
      @repos[repo.name] = repo
    end

    def rm_repo(repo)
      name = normalize_repo_name(repo)
      @repos.delete(name)
    end

    def has_repo?(repo)
      name = normalize_repo_name(repo)
      @repos.has_key?(name)
    end

    def get_repo(repo)
      name = normalize_repo_name(repo)
      @repos[name]
    end

    def add_group(group, overwrite = false)
      raise ArgumentError, "Group must be of type Gitolite::Config::Group!" unless group.instance_of? Gitolite::Config::Group
      @groups[group.name] = group
    end

    def rm_group(group)
      name = normalize_group_name(group)
      @groups.delete(name)
    end

    def has_group?(group)
      name = normalize_group_name(group)
      @groups.has_key?(name)
    end

    def get_group(group)
      name = normalize_group_name(group)
      @groups[name]
    end

    # it will return the file name if only one config file saved
    # Or it will return the saved file name list
    def to_file(path=".", filename=@filename, force_dir=false)
      filename=@filename if !filename || filename == ''
      new_conf = File.join(path, filename)
      saved_files = []
      path = File.dirname(new_conf)

      if force_dir
        vPath = Pathname.new File.dirname(new_conf)
        vPath.mkpath unless vPath.exist?
      else
        raise ArgumentError, "Path contains a filename or does not exist" unless File.directory?(path)
      end

      if is_container?
        @subconfs.each do |k ,v|
            k= get_relative_path k
            saved_files << v.to_file(path, k, force_dir)
        end
        @includes.each do |k ,v|
            k= get_relative_path k
            saved_files << v.to_file(path, k, force_dir)
        end
      else
        File.open(new_conf, "w") do |f|
          #Output groups
          dep_order = build_groups_depgraph
          dep_order.each {|group| f.write group.to_s }

          gitweb_descs = []
          @repos.each do |k, v|
            f.write v.to_s

            gwd = v.gitweb_description
            gitweb_descs.push(gwd) unless gwd.nil?
          end

          f.write gitweb_descs.join("\n")

          # write subconfs into file
          gitweb_descs = []
          @subconfs.each do |k ,v|
            k= get_relative_path k
            gitweb_descs.push("subconf    \"#{k}\"")
            saved_files << v.to_file(path, k, force_dir)
          end
          f.write gitweb_descs.join("\n")

          # write includes into file
          gitweb_descs = []
          @includes.each do |k ,v|
            k= get_relative_path k
            gitweb_descs.push("include    \"#{k}\"")
            saved_files << v.to_file(path, k, force_dir)
          end
          f.write gitweb_descs.join("\n")
        end
      end

      if saved_files.length > 0
        saved_files << new_conf unless is_container?
        saved_files.flatten
      else
        new_conf
      end
    end

    private
      #Based on
      #https://github.com/sitaramc/gitolite/blob/pu/src/gl-compile-conf#cleanup_conf_line
      def cleanup_config_line(line)
        #remove comments, even those that happen inline
        line.gsub!(/^((".*?"|[^#"])*)#.*/) {|m| m=$1}

        #fix whitespace
        line.gsub!('=', ' = ')
        line.gsub!(/\s+/, ' ')
        line.strip
      end

      def process_config(config)
        context = [] #will store our context for permissions or config declarations

        #Read each line of our config
        File.open(config, 'r').each do |l|

          line = cleanup_config_line(l)
          next if line.empty? #lines are empty if we killed a comment

          case line
            #found a repo definition
            when /^repo (.*)/
              #Empty our current context
              context = []

              repos = $1.split
              repos.each do |r|
                context << r

                @repos[r] = Repo.new(r) unless has_repo?(r)
              end
            #repo permissions
            when /^(-|C|R|RW\+?(?:C?D?|D?C?)M?) (.* )?= (.+)/
              perm = $1
              refex = $2 || ""
              users = $3.split

              context.each do |c|
                @repos[c].add_permission(perm, refex, users)
              end
            #repo git config
            when /^config (.+) = ?(.*)/
              key = $1
              value = $2

              context.each do |c|
                @repos[c].set_git_config(key, value)
              end
            #group definition
            when /^#{Group::PREPEND_CHAR}(\S+) = ?(.*)/
              group = $1
              users = $2.split

              @groups[group] = Group.new(group) unless has_group?(group)
              @groups[group].add_users(users)
            #gitweb definition
            when /^(\S+)(?: "(.*?)")? = "(.*)"$/
              repo = $1
              owner = $2
              description = $3

              #Check for missing description
              raise ParseError, "Missing Gitweb description for repo: #{repo}" if description.nil?

              #Check for groups
              raise ParseError, "Gitweb descriptions cannot be set for groups" if repo =~ /@.+/

              if has_repo? repo
                r = @repos[repo]
              else
                r = Repo.new(repo)
                add_repo(r)
              end

              r.owner = owner
              r.description = description
            when /^include\s+(['"])([\S]+)\1/
              #TODO: check includes GroupDependencyError
              file = $2
              sub_conf_name = file
              dir = File.dirname(@file)
              path = Pathname.new file
              file = File.join(dir, file) unless path.absolute?
              if is_container?(file) # it should be a container for matched files.
                 container = Gitolite::Config.new_inc(file, self)
                 Dir[file].each do |f|
                   Gitolite::Config.load_inc(f, container)
                 end
              else
                path = Pathname.new file
                raise ParseError, "'#{line}' '#{file}' not exits!" unless path.file?
                if !root_config.has_inc?(sub_conf_name, 99)
                  Gitolite::Config.load_inc(file, self)
                else
                  raise ConfigDependencyError, "'#{line}' recursive reference!"
                end
              end
            when /^subconf(?:\s+(['"]?)(\S+)\1)?\s+(['"])([\S]+)\3/
              file = $4
              sub_conf_name = $2
              sub_conf_name = file unless sub_conf_name
              dir = File.dirname(@file)
              path = Pathname.new file
              file = File.join(dir, file) unless path.absolute?
              if is_container?(file) # it should be a container for matched files.
                 container = Gitolite::Config.new_subconf(file, self)
                 Dir[file].each do |f|
                   Gitolite::Config.load_subconf(f, container)
                 end
              else
                path = Pathname.new file
                raise ParseError, "'#{line}' '#{file}' not exits!" unless path.file?
                subconf = root_config.get_subconf(sub_conf_name, 99)
                if !subconf || !subconf.has_subconf?(self, 99)
                  Gitolite::Config.load_subconf(file, self)
                else
                  raise ConfigDependencyError, "'#{line}' recursive reference!"
                end
              end
            else
              raise ParseError, "'#{line}' cannot be processed"
          end
        end
      end

      # Normalizes the various different input objects to Strings
      def normalize_name(context, constant = nil)
        case context
          when constant
            context.name
          when Symbol
            context.to_s
          else
            context
        end
      end

      def method_missing(meth, *args, &block)
        if meth.to_s =~ /normalize_(\w+)_name/
          #Could use Object.const_get to figure out the constant here
          #but for only two cases, this is more readable
          case $1
            when "repo"
              normalize_name(args[0], Gitolite::Config::Repo)
            when "group"
              normalize_name(args[0], Gitolite::Config::Group)
            when 'config'
              normalize_name(args[0], Gitolite::Config)
          end
        else
          super
        end
      end

      # Builds a dependency tree from the groups in order to ensure all groups
      # are defined before they are used
      def build_groups_depgraph
        dp = ::Plexus::Digraph.new

        # Add each group to the graph
        @groups.each_value do |group|
          dp.add_vertex! group

          # Select group names from the users
          subgroups = group.users.select {|u| u =~ /^#{Group::PREPEND_CHAR}.*$/}
                                 .map{|g| get_group g.gsub(Group::PREPEND_CHAR, '') }

          subgroups.each do |subgroup|
            dp.add_edge! subgroup, group
          end
        end

        # Figure out if we have a good depedency graph
        dep_order = dp.topsort

        if dep_order.empty?
          raise GroupDependencyError unless @groups.empty?
        end

        dep_order
      end

      #Raised when something in a config fails to parse properly
      class ParseError < RuntimeError
      end

      # Raised when group dependencies cannot be suitably resolved for output
      class GroupDependencyError < RuntimeError
      end

      # Raised when config dependencies cannot be suitably resolved for output
      class ConfigDependencyError < RuntimeError
      end
  end
end
