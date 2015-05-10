require 'uri'

module Gitlab
  module Markdown
    # HTML filter that "fixes" relative links to files in a repository.
    #
    # Context options:
    #   :commit
    #   :project
    #   :project_wiki
    #   :requested_path
    #   :ref
    class RelativeLinkFilter < HTML::Pipeline::Filter

      def call
        if !project_wiki && repository.try(:exists?) && !repository.empty?
          doc.search('a').each do |el|
            process_link_attr el.attribute('href')
          end

          doc.search('img').each do |el|
            process_link_attr el.attribute('src')
          end
        end

        doc
      end

      protected

      def process_link_attr(html_attr)
        return if html_attr.blank?

        uri = URI(html_attr.value)
        if uri.relative? && uri.path.present?
          html_attr.value = rebuild_relative_uri(uri).to_s
        end
      end

      def rebuild_relative_uri(uri)
        file_path = relative_file_path(uri.path)

        uri.path = [
          relative_url_root,
          project.path_with_namespace,
          path_type(file_path),
          ref || 'master',  # assume that if no ref exists we can point to master
          file_path
        ].compact.join('/').squeeze('/').chomp('/')

        uri
      end

      def relative_file_path(path)
        nested_path = build_nested_path(path, requested_path)
        file_exists?(nested_path) ? nested_path : path
      end

      # Covering a special case, when the link is referencing file in the same
      # directory.
      # If we are at doc/api/README.md and the README.md contains relative
      # links like [Users](users.md), this takes the request
      # path(doc/api/README.md) and replaces the README.md with users.md so the
      # path looks like doc/api/users.md.
      # If we are at doc/api and the README.md shown in below the tree view
      # this takes the request path(doc/api) and adds users.md so the path
      # looks like doc/api/users.md
      def build_nested_path(path, request_path)
        return request_path if path.empty?
        return path unless request_path

        parts = request_path.split('/')
        parts.pop if path_type(request_path) != 'tree'
        parts.push(path).join('/')
      end

      def file_exists?(path)
        return false if path.nil?
        repository.blob_at(current_sha, path).present? ||
          repository.tree(current_sha, path).entries.any?
      end

      # Check if the path is pointing to a directory(tree) or a file(blob)
      # eg. doc/api is directory and doc/README.md is file.
      def path_type(path)
        return 'tree' if repository.tree(current_sha, path).entries.any?
        return 'raw' if repository.blob_at(current_sha, path).try(:image?)
        'blob'
      end

      def current_sha
        if commit
          commit.id
        elsif ref
          repository.commit(ref).try(:sha)
        else
          repository.head_commit.sha
        end
      end

      def relative_url_root
        Gitlab.config.gitlab.relative_url_root.presence || '/'
      end

      [:commit, :project, :project_wiki, :requested_path, :ref].each do |name|
        define_method(name) do
          context[name]
        end
      end

      def repository
        return if project.nil?
        project.repository
      end
    end
  end
end
