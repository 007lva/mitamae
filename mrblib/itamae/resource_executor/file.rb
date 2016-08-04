module Itamae
  module ResourceExecutor
    # XXX: It's just copied and changed without deep consideration.
    # We must care about temporary file more carefully.
    class File < Base
      def action_create
        # if !current.exist && !@temppath
        #   run_command(["touch", attributes.path])
        # end

        change_target = attributes.modified ? @temppath : attributes.path

        if attributes.mode
          run_specinfra(:change_file_mode, change_target, attributes.mode)
        end

        if attributes.owner || attributes.group
          run_specinfra(:change_file_owner, change_target, attributes.owner, attributes.group)
        end

        if attributes.modified
          run_specinfra(:copy_file, @temppath, attributes.path) # XXX: use move_file
        end
      end

      def action_delete
        if run_specinfra(:check_file_is_file, attributes.path)
          run_specinfra(:remove_file, attributes.path)
        end
      end

      def action_edit
        change_target = attributes.modified ? @temppath : attributes.path

        if attributes.mode || attributes.modified
          mode = attributes.mode || run_specinfra(:get_file_mode, attributes.path).stdout.chomp
          run_specinfra(:change_file_mode, change_target, mode)
        end

        if attributes.owner || attributes.group || attributes.modified
          owner = attributes.owner || run_specinfra(:get_file_owner_user, attributes.path).stdout.chomp
          group = attributes.group || run_specinfra(:get_file_owner_group, attributes.path).stdout.chomp
          run_specinfra(:change_file_owner, change_target, owner, group)
        end

        if attributes.modified
          run_specinfra(:copy_file, @temppath, attributes.path) # XXX: use move_file
        end
      end

      private

      def set_current_attributes(current, action)
        current.modified = false
        current.exist = @existed
        if current.exist
          current.mode = run_specinfra(:get_file_mode, attributes.path).stdout.chomp
          current.owner = run_specinfra(:get_file_owner_user, attributes.path).stdout.chomp
          current.group = run_specinfra(:get_file_owner_group, attributes.path).stdout.chomp
        else
          current.mode = nil
          current.owner = nil
          current.group = nil
        end
      end

      def set_desired_attributes(desired, action)
        # https://github.com/itamae-kitchen/itamae/blob/v1.9.9/lib/itamae/resource/file.rb#L15
        @existed = run_specinfra(:check_file_is_file, attributes.path)

        case action
        when :create
          desired.exist = true
        when :delete
          desired.exist = false
        when :edit
          desired.exist = true

          # FIXME: not supported now
          # if !runner.dry_run? || @existed
          #   content = backend.receive_file(attributes.path)
          #   attributes.block.call(content)
          #   attributes.content = content
          # end
        end

        send_tempfile
        compare_file
      end

      def justify_mode(mode)
        sprintf("%4s", mode).gsub(/ /, '0')
      end

      def show_differences(current, desired)
        current.mode    = justify_mode(current.mode) if current.mode
        attributes.mode = justify_mode(attributes.mode) if attributes.mode

        super

        if @temppath && desired.exist
          show_content_diff
        end
      end

      def compare_to
        if @existed
          attributes.path
        else
          '/dev/null'
        end
      end

      def compare_file
        attributes.modified = false
        unless @temppath
          return
        end

        case run_command(["diff", "-q", compare_to, @temppath], error: false).exit_status
        when 1
          # diff found
          attributes.modified = true
        when 2
          # error
          raise Itamae::Backend::CommandExecutionError, "diff command exited with 2"
        end
      end

      def show_content_diff
        if attributes.modified
          Itamae.logger.info "diff:"
          diff = run_command(["diff", "-u", compare_to, @temppath], error: false)
          diff.stdout.each_line do |line|
            color = if line.start_with?('+')
                      :green
                    elsif line.start_with?('-')
                      :red
                    else
                      :clear
                    end
            Itamae.logger.color(color) do
              Itamae.logger.info line.chomp
            end
          end
        else
          # no change
          Itamae.logger.debug "file content will not change"
        end
      end

      # will be overridden
      def content_file
        nil
      end

      def send_tempfile
        if !attributes.content && !content_file
          @temppath = nil
          return
        end

        src = if content_file
                content_file
              else
                f = Tempfile.open('itamae')
                f.write(attributes.content)
                f.close
                f.path
              end

        # XXX: `runner.tmpdir` is changed to '/tmp'
        @temppath = ::File.join('/tmp', Time.now.to_f.to_s)

        run_command(["touch", @temppath])
        run_specinfra(:change_file_mode, @temppath, '0600')
        run_command(['cp', src, @temppath])

        run_specinfra(:change_file_mode, @temppath, '0600')
      end
    end
  end
end