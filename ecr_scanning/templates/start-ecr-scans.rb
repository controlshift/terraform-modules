require 'aws-sdk-ecr'
require 'json'

# This is the main function that will be invoked from the outside, receiving a message from the event bridge.
def handler(event:, context:)
  repository_names = JSON.parse(ENV['REPOSITORIES'])
  tags_to_scan = JSON.parse(ENV['TAGS_TO_SCAN'])

  repository_names.each do |repository_name|
    puts "Scanning #{repository_name} images"

    images_to_scan = {}

    # Look up images that match the tags we're looking for. It's possible multiple tags
    # are on a single image, so we stick them in a hash by image digest to de-dup.
    tags_to_scan.each do |tag|
      # Look up the image with the tag
      begin
        matching_images = client.describe_images({
          repository_name: repository_name,
          image_ids: [{image_tag: tag}]
        }).image_details
      rescue Aws::ECR::Errors::ImageNotFoundException
        matching_images = []
      end

      if matching_images.empty?
        puts "No image found with tag #{tag}"
      else
        image = matching_images.first
        images_to_scan[image.image_digest] = image
      end
    end

    # For each image we identified, kick off a scan.
    images_to_scan.each do |digest, image|
      puts "Starting scan for image #{digest}, tagged with #{image.image_tags.join(', ')}"
      scan_image(image)
    end
  end
end

def scan_image(image_detail)
  begin
    response = client.start_image_scan({
      repository_name: image_detail.repository_name,
      image_id: {
        image_digest: image_detail.image_digest
      }
    })
  rescue Aws::ECR::Errors::LimitExceededException
    puts "Could not start scan due to rate limit"
    return
  end

  scan_status = response.image_scan_status
  puts "#{scan_status.status}: #{scan_status.description}"
end

def client
  @_client ||= Aws::ECR::Client.new
end
