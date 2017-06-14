require 'octokit'

client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])

prs = client.pull_requests(ENV['GITHUB_REPO'], state: 'open')
pr_number = nil

# Check if Release PR exists
prs.each do |pr|
  next unless pr.title == "RELEASE #{ENV['NEW_VERSION']}"

  pr_number = pr.number
  break
end

changelog = File.read(File.join(ENV['REPO_PATH'], '/unreleased.md'))

if pr_number
  client.update_pull_request(ENV['GITHUB_REPO'], pr_number, body: changelog)
else
  client.create_pull_request(ENV['GITHUB_REPO'], 'master', 'develop', "RELEASE #{ENV['NEW_VERSION']}", changelog)
end
