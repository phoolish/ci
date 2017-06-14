require 'berkshelf'
require 'chef'
require 'octokit'

metadata = Chef::Cookbook::Metadata.new
metadata.from_file("#{ENV['REPO_PATH']}/metadata.rb")

Berkshelf.set_format :null # minimize output
berks = Berkshelf::Berksfile.from_file("#{ENV['REPO_PATH']}/Berksfile")

berks.install if ENV['UPDATE_COOKBOOKS']

repo = ENV['GITHUB_REPO']
gh_client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
prs = gh_client.pull_requests(repo, state: 'open')
base_ref = 'heads/develop'
base_commit_sha = gh_client.ref(repo, base_ref).object.sha

berks.outdated do |cookbook_name, cookbook_data|
  pr_number = nil
  pr_branch = nil
  pr_body = nil

  if metadata.dependencies.include? cookbook_name
    # Only set remote version if we know the end source version
    # otherwise move on because this is probably more complicated then
    # expected
    next unless cookbook_data['remote'].length == 1

    new_cookbook_version = cookbook_data['remote'].values.first.to_s

    if ENV['UPDATE_COOKBOOKS']
      # Check if cookbook PR exists
      prs.each do |pr|
        next unless pr.title == "Update #{cookbook_name} cookbook"

        pr_number = pr.number
        pr_branch = pr.head.label
        pr_body = pr.body
        break
      end

      if pr_number
        new_pr_body = "Update to version #{new_cookbook_version}"
        # Only update when necessary
        unless new_pr_body == pr_body
          branch = gh_client.branch(repo, pr_branch)
          branch_commit_sha = branch.object.sha
          base_tree_sha = gh_client.commit(repo, branch_commit_sha).commit.tree.sha

          puts "Updating #{cookbook_name} to #{new_cookbook_version}"
          berks.update(cookbook_name)

          blob_sha = gh_client.create_blob(repo, Base64.encode64(File.read('Berksfile.lock')), 'base64')
          branch_new_tree = gh_client.create_tree(
            repo,
            [{
              path: 'Berksfile.lock',
              mode: '100644',
              type: 'blob',
              sha: blob_sha
            }],
            base_tree: base_tree_sha
          )

          message = "Update #{cookbook_name} cookbook to #{new_cookbook_version}"

          new_commit = gh_client.create_commit(repo, message, branch_new_tree.sha, branch_commit_sha)

          gh_client.update_ref(repo, branch_ref, new_commit.sha)

          gh_client.update_pull_request(
            repo,
            pr_number,
            body: new_pr_body
          )
        end
      else
        branch = gh_client.create_ref(repo, "heads/#{pr_branch}", base_commit_sha)
        branch_commit_sha = branch.object.sha
        base_tree_sha = gh_client.commit(repo, branch_commit_sha).commit.tree.sha

        puts "Updating #{cookbook_name} to #{new_cookbook_version}"
        berks.update(cookbook_name)

        blob_sha = gh_client.create_blob(repo, Base64.encode64(File.read('Berksfile.lock')), 'base64')
        branch_new_tree = gh_client.create_tree(
          repo,
          [{
            path: 'Berksfile.lock',
            mode: '100644',
            type: 'blob',
            sha: blob_sha
          }],
          base_tree: base_tree_sha
        )

        message = "Update #{cookbook_name} cookbook to #{new_cookbook_version}"

        new_commit = gh_client.create_commit(repo, message, branch_new_tree.sha, branch_commit_sha)

        gh_client.update_ref(repo, branch_ref, new_commit.sha)

        gh_client.create_pull_request(
          repo,
          'develop',
          pr_branch,
          "Update #{cookbook_name} cookbook",
          "Update to version #{new_cookbook_version}"
        )
      end
    else
      puts "#{cookbook_name} needs updating"
    end
  end
end
