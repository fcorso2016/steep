module Steep
  module Server
    module ChangeBuffer
      attr_reader :mutex
      attr_reader :buffered_changes

      def push_buffer
        @mutex.synchronize do
          yield buffered_changes
        end
      end

      def pop_buffer
        changes = {}
        @mutex.synchronize do
          changes.merge!(buffered_changes)
          buffered_changes.clear
        end
        if block_given?
          yield changes
        else
          changes
        end
      end

      def load_files(project:, commandline_args:)
        push_buffer do |changes|
          loader = Services::FileLoader.new(base_dir: project.base_dir)

          project.targets.each do |target|
            loader.load_changes(target.source_pattern, commandline_args, changes: changes)
            loader.load_changes(target.signature_pattern, changes: changes)
          end
        end
      end

      def collect_changes(request)
        push_buffer do |changes|
          path = project.relative_path(Pathname(URI.parse(request[:params][:textDocument][:uri]).path))
          version = request[:params][:textDocument][:version]
          Steep.logger.info { "Updating source: path=#{path}, version=#{version}..." }

          changes[path] ||= []
          request[:params][:contentChanges].each do |change|
            changes[path] << Services::ContentChange.new(
              range: change[:range]&.yield_self {|range|
                [
                  range[:start].yield_self {|pos| Services::ContentChange::Position.new(line: pos[:line] + 1, column: pos[:character]) },
                  range[:end].yield_self {|pos| Services::ContentChange::Position.new(line: pos[:line] + 1, column: pos[:character]) }
                ]
              },
              text: change[:text]
            )
          end
        end
      end
    end
  end
end