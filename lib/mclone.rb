# frozen_string_literal: true


require 'date'
require 'json'
require 'fileutils'
require 'securerandom'


#
module Mclone


  VERSION = '0.2.0'


  #
  class Error < StandardError; end

  #
  module Refinements

    refine ::Hash do
      # Same as #dig but raises KeyError exception on any non-existent key
      def extract(*args)
        case args.size
        when 0 then raise(KeyError, 'non-empty key sequence expected')
        when 1 then fetch(args.first)
        else fetch(args.shift).extract(*args)
        end
      end
    end

    refine ::Array do
      # Return a list of items which fully or partially match the specified pattern
      def resolve(partial)
        rx = Regexp.new(partial)
        collect { |item| rx.match?(item.to_s) ? item : nil }.compact
      end
    end

  end


  using Refinements


  # Two-way mapping between an object and its ID
  class ObjectSet

    include Enumerable

    #
    def each_id(&code)
      @ids.each_key(&code)
    end

    #
    def each(&code)
      @objects.each_value(&code)
    end

    #
    def empty?
      @objects.empty?
    end

    #
    def size
      @objects.size
    end

    def initialize
      @ids = {} # { id => object }
      @objects = {} # { object => object }
      @modified = false
    end

    # Return ID of the object considered equal to the specified obj or nil
    def id(obj)
      @objects[obj]&.id
    end

    # Return object with specified ID or nil
    def object(id)
      @ids[id]
    end

    # Return object considered equal to obj or nil
    def [](obj)
      @objects[obj]
    end

    #
    def modified?
      @modified
    end

    def commit!
      @modified = false
      self
    end

    # Unregister an object considered equal to the specified obj and return true if object has been actually removed
    private def forget(obj)
      !@ids.delete(@objects.delete(obj)&.id).nil?
    end

    # Return a list of registered IDs (fully or partially) matching the specified pattern
    def resolve(pattern)
      each_id.to_a.resolve(pattern)
    end

    # Either add brand new object or replace existing one equal to the specified object
    def <<(obj)
      forget(obj)
      @objects[obj] = @ids[obj.id] = obj
      @modified = true
      obj
    end

    # Remove object considered equal to the specified obj
    def >>(obj)
      @modified = true if (status = forget(obj))
      status
    end

    # Add all tasks from enumerable
    def merge!(objs)
      objs.each { |x| self << x }
      self
    end

  end


  #
  class Task

    #
    class Error < Mclone::Error
    end

    #
    attr_reader :id

    #
    attr_reader :source_id, :destination_id

    #
    attr_reader :source_root, :destination_root

    #
    attr_reader :mtime

    #
    attr_reader :mode

    #
    attr_reader :include, :exclude

    #
    attr_reader :crypter_mode

    def hash
      @hash ||= source_id.hash ^ destination_id.hash ^ source_root.hash ^ destination_root.hash
    end

    def eql?(other)
      equal?(other) || (
        source_id == other.source_id &&
        destination_id == other.destination_id &&
        source_root == other.source_root &&
        destination_root == other.destination_root
      )
    end

    alias == eql?

    #
    def initialize(mode, source_id, source_root, destination_id, destination_root, include: nil, exclude: nil, crypter_mode: nil, crypter_token: nil, crypter_password: nil)
      @touch = false # Indicates that the time stamp should be updated whenever state of self is altered
      @id = SecureRandom.hex(4)
      @source_id = source_id
      @destination_id = destination_id
      @source_root = source_root
      @destination_root = destination_root
      self.mode = mode
      self.include = include
      self.exclude = exclude
      set_crypter_mode crypter_mode
      unless crypter_mode.nil?
        raise(Task::Error, %(either Rclone crypt token or plain text password is expected, not both)) if !crypter_token.nil? && !crypter_password.nil?
        @assigned_token = register_crypter_token crypter_token
        @assigned_password = crypter_password
      end
    ensure
      @touch = true
      touch!
    end

    CRYPTER_MODES = %i[encrypt decrypt].freeze

    @@crypter_tokens = {}

    private def set_crypter_mode(mode)
      @crypter_mode = mode.nil? ? nil : (CRYPTER_MODES.include?(mode = mode.intern) ? mode : raise(Task::Error, %(unknown crypt mode "#{mode}")))
    end

    private def register_crypter_token(token)
      unless token.nil?
        @@crypter_tokens[id] = @@crypter_tokens[id].nil? ? token : raise(Task::Error, %(attempt to re-register token for task "#{id}"))
      end
      token
    end

    # Lazily determine the crypt token from either assigned values or the token repository
    def crypter_token
      # Locally assigned token takes precedence over the repository's
      unless @assigned_token.nil?
        @@crypter_tokens[id] = @assigned_token unless @@crypter_tokens[id].nil? # Assign repository entry with this local token if not yet assigned
        @assigned_token
      else
        unless @@crypter_tokens[id].nil?
          @@crypter_tokens[id]
        else
          # If token is neither locally assigned nor in repository, try to construct it from the password
          @@crypter_tokens[id] =
            if @assigned_password.nil?
              %x('#{Mclone.rclone}' obscure '#{SecureRandom.alphanumeric(16)}').strip # Create Rclone token from randomly generated password
            else
              %x('#{Mclone.rclone}' obscure '#{@assigned_password}').strip # Create Rclone token from locally assigned plain text password
            end
        end
      end
    end

    #
    MODES = %i[update synchronize copy move].freeze

    #
    def mode=(mode)
      @mode = MODES.include?(mode = mode.intern) ? mode : raise(Task::Error, %(unknown mode "#{mode}"))
      touch!
      mode
    end

    #
    def include=(mask)
      @include = mask.nil? || mask == '-' ? nil : mask # TODO: verify mask
      touch!
      mask
    end

    #
    def exclude=(mask)
      @exclude = mask.nil? || mask == '-' ? nil : mask # TODO: verify mask
      touch!
      mask
    end

    #
    def self.restore(hash)
      obj = allocate
      obj.send(:from_h, hash)
      obj
    end

    #
    private def from_h(hash)
      @touch = false
      @id = hash.extract(:task)
      @mtime = DateTime.parse(hash.extract(:mtime)) rescue DateTime.now # Deleting mtime entry from json can be used to modify data out of mclone
      @source_id = hash.extract(:source, :volume)
      @destination_id = hash.extract(:destination, :volume)
      @source_root = hash.dig(:source, :root)
      @destination_root = hash.dig(:destination, :root)
      self.mode = hash.extract(:mode)
      self.include = hash.dig(:include)
      self.exclude = hash.dig(:exclude)
      set_crypter_mode hash.dig(:crypter, :mode)
      @assigned_token = register_crypter_token(hash.dig(:crypter, :token)) unless crypter_mode.nil?
    ensure
      @touch = true
    end

    #
    def to_h(volume)
      hash = {
        task: id,
        mode: mode,
        mtime: mtime,
        source: { volume: source_id },
        destination: { volume: destination_id }
      }
      hash[:source][:root] = source_root unless source_root.nil? || source_root.empty?
      hash[:destination][:root] = destination_root unless destination_root.nil? || destination_root.empty?
      hash[:include] = include unless include.nil?
      hash[:exclude] = exclude unless exclude.nil?
      unless crypter_mode.nil?
        crypter = hash[:crypter] = { mode: crypter_mode }
        # Make sure the token won't get into the encrypted volume's task
        crypter[:token] = crypter_token if (crypter_mode == :encrypt && source_id == volume.id) || (crypter_mode == :decrypt && destination_id == volume.id)
      end
      hash
    end

    #
    def touch!
      @mtime = DateTime.now if @touch
      self
    end
  end


  #
  class TaskSet < ObjectSet

    alias task object

    # Add new task or replace existing one with outdated timestamp
    def <<(task)
      t = self[task]
      super if t.nil? || (!t.nil? && t.mtime < task.mtime)
      task
    end

    #
    def resolve(id)
      case (ids = super).size
      when 0 then raise(Task::Error, %(no task matching "#{id}" pattern found))
      when 1 then ids.first
      else raise(Task::Error, %(ambiguous "#{id}" pattern: two or more tasks match))
      end
    end

  end


  #
  class Volume

    #
    class Error < Mclone::Error

    end

    #
    VERSION = 0

    #
    FILE = '.mclone'

    #
    attr_reader :id

    #
    attr_reader :file


    #
    def root
      @root ||= File.realpath(File.dirname(file))
    end

    #
    attr_reader :session

    #
    def initialize(session, file)
      @id = SecureRandom.hex(4)
      @session = session
      @file = file
    end

    #
    def self.restore(session, file)
      obj = allocate
      obj.send(:from_file, session, file)
      obj
    end

    #
    private def from_file(session, file)
      hash = JSON.parse(IO.read(file), symbolize_names: true)
      @id = hash.extract(:volume)
      @session = session
      @file = file
      raise(Volume::Error, %(unsupported Mclone volume format version "#{version}")) unless hash.extract(:mclone) == VERSION
      hash.dig(:tasks)&.each { |t| session.tasks << Task.restore(t) }
      self
    end

    #
    def hash
      id.hash
    end

    #
    def eql?(other)
      equal?(other) || id == other.id
    end

    #
    def commit!(force = false)
      if force || tasks.modified?
        open(file, 'w') do |stream|
          stream << JSON.pretty_generate(to_h)
          tasks.commit!
        end
      end
    end

    #
    def tasks
      TaskSet.new(self).merge!(session.tasks)
    end

    #
    def to_h
      { mclone: VERSION, volume: id, tasks: tasks.collect { |task| task.to_h(self) } }
    end

    # Volume-bound set of tasks belonging to the specific volume
    class TaskSet < Mclone::TaskSet

      def initialize(volume)
        @volume = volume
        super()
      end

      # Accept only the tasks referencing the volume as either source or destination
      def <<(task)
        task.source_id == @volume.id || task.destination_id == @volume.id ? super : task
      end

    end
  end


  #
  class VolumeSet < ObjectSet

    alias volume object

    #
    def resolve(id)
      case (ids = super).size
      when 0 then raise(Volume::Error, %(no volume matching "#{id}" pattern found))
      when 1 then ids.first
      else raise(Volume::Error, %(ambiguous "#{id}" pattern: two or more volumes match))
      end
    end

  end


  #
  class Session

    #
    class Error < Mclone::Error

    end

    #
    attr_reader :volumes

    #
    def simulate?
      @simulate == true
    end

    #
    def verbose?
      @verbose == true
    end

    #
    def force?
      @force == true
    end

    #
    attr_writer :simulate, :verbose, :force

    #
    attr_reader :tasks

    #
    def initialize
      @volumes = VolumeSet.new
      @tasks = SessionTaskSet.new(self)
    end

    #
    def format_volume!(dir)
      mclone = File.join(dir, Volume::FILE)
      raise(Session::Error, %(refuse to overwrite existing Mclone volume file "#{mclone}")) if File.exist?(mclone) && !force?
      volumes << (volume = Volume.new(self, mclone))
      volume.commit!(true) unless simulate? # Force creation of a new (empty) volume
      self
    end

    #
    def restore_volume!(dir)
      volumes << Volume.restore(self, File.join(dir, Volume::FILE))
      self
    end

    #
    def restore_volumes!
      (Mclone.environment_mounts + Mclone.system_mounts + [ENV['HOME']]).each { |dir| restore_volume!(dir) rescue Errno::ENOENT }
      self
    end

    #
    def delete_volume!(id)
      volume = volumes.volume(id = volumes.resolve(id))
      raise(Session::Error, %(refuse to delete non-empty Mclone volume file "#{volume.file}")) unless volume.tasks.empty? || force?
      volumes >> volume
      FileUtils.rm_f(volume.file) unless simulate?
      self
    end

    #
    def create_task!(mode, source, destination, **kws)
      task = Task.new(mode, *locate(source), *locate(destination), **kws)
      _task = tasks[task]
      raise(Session::Error, %(refuse to overwrite existing task "#{_task.id}")) unless _task.nil? || force?
      tasks << task
      self
    end

    #
    def modify_task!(id, mode: nil, include: nil, exclude: nil)
      ts = tasks
      task = ts.task(ts.resolve(id)).clone
      task.mode = mode unless mode.nil?
      task.include = include unless include.nil?
      task.exclude = exclude unless exclude.nil?
      tasks << task
      self
    end

    #
    def delete_task!(id)
      tasks >> tasks.task(tasks.resolve(id))
      self
    end

    #
    def process_tasks!(*ids)
      ts = intact_tasks
      ids = ts.collect(&:id) if ids.empty?
      ids.collect { |id| ts.task(ts.resolve(id)) }.each do |task|
        args = [Mclone.rclone]
        opts = [
          simulate? ? '--dry-run' : nil,
          verbose? ? '--verbose' : nil
        ].compact
        case task.mode
        when :update
          args.push('copy', '--update')
        when :synchronize
          args << 'sync'
        when :copy
          args << 'copy'
        when :move
          args << 'move'
        end
        opts.append('--filter', "- /#{Volume::FILE}")
        opts.append('--filter', "- #{task.exclude}") unless task.exclude.nil? || task.exclude.empty?
        opts.append('--filter', "+ #{task.include}") unless task.include.nil? || task.include.empty?
        args.concat(opts)
        args.append(
          File.join(volumes.volume(task.source_id).root, task.source_root.nil? ? EMPTY_STRING : task.source_root),
          File.join(volumes.volume(task.destination_id).root, task.destination_root.nil? ? EMPTY_STRING : task.destination_root)
        )
        case system(*args)
        when nil then raise(Session::Error, %(failed to execute "#{args.first}"))
        when false then exit($?)
        end
      end
    end

    EMPTY_STRING = ''

    # Collect all tasks from all loaded volumes which are ready to be executed
    def intact_tasks
      IntactTaskSet.new(self).merge!(tasks)
    end

    #
    private def locate(path)
      path = File.realpath(path)
      x = volumes.each.collect { |v| Regexp.new(%!^#{v.root}/?(.*)!, Mclone.windows? ? Regexp::IGNORECASE : nil) =~ path ? [v.root, v.id, $1] : nil }.compact
      if x.empty?
        raise(Session::Error, %(path "#{path}" does not belong to a loaded Mclone volume))
      else
        root, volume, path = x.sort { |a,b| a.first.size <=> b.first.size}.last
        [volume, path]
      end
    end

    #
    def commit!
      volumes.each { |v| v.commit!(force?) } unless simulate?
      self
    end

    #
    class SessionTaskSet < Mclone::TaskSet

      def initialize(session)
        @session = session
        super()
      end

    end

    # Session-bound set of intact tasks for which both source and destination volumes are loaded
    class IntactTaskSet < SessionTaskSet

      # Accept only intact tasks for which both source and destination volumes are loaded
      def <<(task)
        @session.volumes.volume(task.source_id).nil? || @session.volumes.volume(task.destination_id).nil? ? task : super
      end

    end

  end

  #
  def self.rclone
    @@rclone ||= (rclone = ENV['RCLONE']).nil? ? 'rclone' : rclone
  end

  # Return true if run in the real Windows environment (e.g. not in real *NIX or various emulation layers such as MSYS, Cygwin etc.)
  def self.windows?
    @@windows ||= /^(mingw)/.match?(RbConfig::CONFIG['target_os']) # RubyInstaller's MRI, other MinGW-build MRI
  end

  # Match OS-specific system mount points (/dev /proc etc.) which normally should be omitted when scanning for Mclone voulmes
  UNIX_SYSTEM_MOUNTS = %r!^/(dev|sys|proc|run)!

  # TODO handle Windows variants
  # Specify OS-specific path name list separator (such as in the $PATH environment variable)
  PATH_LIST_SEPARATOR = windows? ? ';' : ':'

  # Return list of live user-provided mounts (mount points on *NIX and disk drives on Windows) which may contain Mclone volumes
  # Look for the $MCLONE_PATH environment variable
  def self.environment_mounts
    ENV['MCLONE_PATH'].split(PATH_LIST_SEPARATOR).collect { |path| File.directory?(path) ? path : nil }.compact rescue []
  end
  # Return list of live system-managed mounts (mount points on *NIX and disk drives on Windows) which may contain Mclone volumes
  case RbConfig::CONFIG['target_os']
  when 'linux'
    # Linux OS
    def self.system_mounts
      # Query on /proc for currently mounted file systems
      IO.readlines('/proc/self/mountstats').collect do |line|
        mount = line.split[4]
        UNIX_SYSTEM_MOUNTS.match?(mount) || !File.directory?(mount) ? nil : mount
      end.compact
    end
    # TODO handle Windows variants
  when /^mingw/ # RubyInstaller's MRI
	module Kernel32
		require 'fiddle'
		require 'fiddle/types'
		require 'fiddle/import'
		extend Fiddle::Importer
		dlload('kernel32')
		include Fiddle::Win32Types
		extern 'DWORD WINAPI GetLogicalDrives()'
	end  
    def self.system_mounts
      mounts = []
      mask = Kernel32.GetLogicalDrives
      ('A'..'Z').each do |x|
        mounts << "#{x}:" if mask & 1 == 1
        mask >>= 1
      end
      mounts
    end
  else
    # Generic *NIX-like OS, including Cygwin & MSYS(2)
    def self.system_mounts
      # Use $(mount) system utility to obtain currently mounted file systems
      %x(mount).split("\n").collect do |line|
        mount = line.split[2]
        UNIX_SYSTEM_MOUNTS.match?(mount) || !File.directory?(mount) ? nil : mount
      end.compact
    end
  end
end