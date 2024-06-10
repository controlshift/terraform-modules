require 'net/http'

# This is the main function that will be invoked from the outside, receiving a message from the event bridge.
# Documentation of event format: https://docs.aws.amazon.com/AmazonECR/latest/userguide/ecr-eventbridge.html#ecr-eventbridge-bus
def handler(event:, context:)
  # Log the input
  puts event

  # Extract some information from the event
  message_time = event['time']
  account_id = event['account']
  region = event['region']
  ecr_repo_name = event['detail']['repository-name']
  image_digest = event['detail']['image-digest']
  image_tags = event['detail']['image-tags']
  finding_counts_by_severity = event['detail']['finding-severity-counts']

  image_description = "the #{ecr_repo_name} image tagged #{image_tags.join(', ')}"

  if finding_counts_by_severity.empty?
    # Good news! There were no vulnerabilities found. Spread the word.
    if post_to_slack_when_no_vulnerabilities?
      message = ":white_check_mark: ECR scan found no vulnerabilities in #{image_description}"
      post_simple_message_to_slack(message)
    else
      puts "No vulnerabilities found. Skipping Slack message due to configuration."
    end
  else
    # Uh-oh, there were some vulnerabilities found. Notify the team.
    message = ":warning: ECR scan found vulnerabilities in #{image_description}"

    scan_results_url = "https://#{region}.console.aws.amazon.com/ecr/repositories/private/#{account_id}/"\
                       "#{ecr_repo_name}/_/image/#{image_digest}/details?region=#{region}"

    attachment = {
      fallback: message,
      pretext: "ECR Scan completed at #{message_time}",
      title: message,
      title_link: scan_results_url,
      fields: [
        {title: 'Severity', value: finding_counts_by_severity.keys.join(', '), short: true}
      ]
    }

    slack_message = {
      channel: ENV['SLACK_CHANNEL'],
      text: '',
      attachments: [attachment],
      username: 'ECR Scan'
    }

    post_message_to_slack(slack_message)
  end
end

def post_to_slack_when_no_vulnerabilities?
  # If SUPPRESS_MESSAGES_WITH_NO_VULNERABILITIES is not set, treat it as false
  suppress = if ENV['SUPPRESS_MESSAGES_WITH_NO_VULNERABILITIES'].nil?
               false
             else
               JSON.parse(ENV['SUPPRESS_MESSAGES_WITH_NO_VULNERABILITIES'])
             end

  # If we should suppress, we should not post, and vice versa
  !suppress
end

def post_simple_message_to_slack(message_text)
  slack_message = {
    channel: ENV['SLACK_CHANNEL'],
    text: message_text,
    username: 'ECR Scan'
  }

  post_message_to_slack(slack_message)
end

def post_message_to_slack(slack_message)
  slack_webhook_url = ENV['SLACK_WEBHOOK_URL']

  puts "POSTing to Slack: #{slack_message.to_json}"

  response = Net::HTTP.post(URI(slack_webhook_url), slack_message.to_json, 'Content-Type' => 'application/json')

  case response
  when Net::HTTPSuccess
    puts 'post succeeded'
  else
    puts "#{response.code}: #{response.body}"
    raise 'POST to Slack failed'
  end
end
