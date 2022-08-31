# frozen_string_literal: true

require 'clamp'
require 'mclone'

include Mclone

begin

Clamp do

  using Refinements

  self.default_subcommand = 'info'

  option ['-f', '--force'], :flag, 'Insist on potentially dangerous actions', default: false
  option ['-n', '--dry-run'], :flag, 'Simulation mode with no on-disk modifications', default: false
  option ['-v', '--verbose'], :flag, 'Verbose operation', default: false

  option ['-V', '--version'], :flag, 'Show version' do
    puts VERSION
    exit(true)
  end

  def session
    session = Mclone::Session.new
    session.force = force?
    session.simulate = dry_run?
    session.verbose = verbose?
    session.restore_volumes!
    session
  end

  def resolve_mode(mode)
    case (m = Task::MODES.resolve(mode)).size
    when 0 then raise(Task::Error, %(no modes matching pattern "#{mode}"))
    when 1 then m.first
    else raise(Task::Error, %(ambiguous mode pattern "#{mode}"))
    end
  end

  subcommand 'info', 'Output information on volumes & tasks' do
    def execute
      s = session
      $stdout.puts "# Mclone version #{Mclone::VERSION}"
      $stdout.puts
      $stdout.puts '## Volumes'
      $stdout.puts
      s.volumes.each { |volume| $stdout.puts "* [#{volume.id}] :: (#{volume.root})" }
      stales = []
      intacts = []
      intact_tasks = s.intact_tasks
      s.tasks.each do |task|
        ts = (t = intact_tasks[task]).nil? ? "<#{task.id}>" : "[#{task.id}]"
        svs = s.volumes.volume(task.source_id).nil? ? "<#{task.source_id}>" : "[#{task.source_id}]"
        dvs = s.volumes.volume(task.destination_id).nil? ? "<#{task.destination_id}>" : "[#{task.destination_id}]"
        crypter_mode = task.crypter_mode.nil? ? nil : "#{task.crypter_mode}+"
        xs = ["* #{ts} :: #{crypter_mode}#{task.mode} #{svs}(#{task.source_root}) -> #{dvs}(#{task.destination_root})"]
        xs << "include #{task.include}" unless task.include.nil? || task.include.empty?
        xs << "exclude #{task.exclude}" unless task.exclude.nil? || task.exclude.empty?
        (t.nil? ? stales : intacts) << xs.join(' :: ')
      end
      unless intacts.empty?
        $stdout.puts
        $stdout.puts '## Intact tasks'
        $stdout.puts
        intacts.each { |x| $stdout.puts x }
      end
      unless stales.empty?
        $stdout.puts
        $stdout.puts '## Stale tasks'
        $stdout.puts
        stales.each { |x| $stdout.puts x }
      end
    end
  end

  subcommand 'volume', 'Volume operations' do

    subcommand ['new', 'create'], 'Create new volume' do
      parameter 'DIRECTORY', 'Directory to become a Mclone volume'
      def execute
        session.format_volume!(directory)
      end
    end

    subcommand 'delete', 'Delete existing volume' do
      parameter 'VOLUME', 'Volume ID pattern'
      def execute
        session.delete_volume!(volume).commit!
      end
    end

  end

  subcommand 'task', 'Task operations' do

    def self.set_task_opts
      modes = Task::MODES.collect(&:to_s).join(' | ')
      option ['-m', '--mode'], 'MODE', "Operation mode (#{modes})", default: Task::MODES.first.to_s
      option ['-i', '--include'], 'PATTERN', 'Include paths pattern'
      option ['-x', '--exclude'], 'PATTERN', 'Exclude paths pattern'
    end

    subcommand ['new', 'create'], 'Create new SOURCE -> DESTINATION task' do
      set_task_opts
      option ['-d', '--decrypt'], :flag, 'Decrypt source'
      option ['-e', '--encrypt'], :flag, 'Encrypt destination'
      option ['-p', '--password'], 'PASSWORD', 'Plain text password'
      option ['-t', '--token'], 'TOKEN', 'Rclone crypt token (obscured password)'
      parameter 'SOURCE', 'Source path'
      parameter 'DESTINATION', 'Destination path'
      def execute
        crypter_mode = nil
        signal_usage_error 'choose either encryption or decryption mode, not both' if decrypt? && encrypt?
        signal_usage_error 'specify either plain text password or Rclone crypt token, not both' if !password.nil? && !token.nil?
        crypter_mode = :encrypt if encrypt?
        crypter_mode = :decrypt if decrypt?
        session.create_task!(
          resolve_mode(mode),
          source,
          destination,
  include: include, exclude: exclude, crypter_mode: crypter_mode, crypter_password: password, crypter_token: token
        ).commit!
      end
    end

    subcommand 'modify', 'Modify existing task' do
      set_task_opts
      parameter 'TASK', 'Task ID pattern'
      def execute
        session.modify_task!(task, mode: resolve_mode(mode), include: include, exclude: exclude).commit!
      end
    end

    subcommand 'delete', 'Delete existing task' do
      parameter 'TASK', 'Task ID pattern'
      def execute
        session.delete_task!(task).commit!
      end
    end

    subcommand 'process', 'Process specified tasks' do
      parameter '[TASK] ...', 'Task ID pattern(s)', attribute_name: :tasks
      def execute
        session.process_tasks!(*tasks)
      end
    end

  end

end

rescue Mclone::Error
  $stderr.puts "ERROR: #{$!.message}"
  exit(false)
end