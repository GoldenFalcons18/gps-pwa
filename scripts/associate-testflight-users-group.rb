#!/usr/bin/env ruby
# Associate the newly processed iOS build with the existing external "使用者" group.
require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

required = %w[APPSTORE_KEY_ID APPSTORE_ISSUER_ID APPSTORE_PRIVATE_KEY_BASE64 BUILD_NUMBER]
missing = required.select { |name| ENV[name].to_s.empty? }
abort("Missing required environment variables: #{missing.join(', ')}") unless missing.empty?

APP_BUNDLE_ID = "com.goldenfalcons.sailinggps"
GROUP_NAME = "使用者"
API_ROOT = "https://api.appstoreconnect.apple.com/v1"

def b64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

def token
  key_id = ENV.fetch("APPSTORE_KEY_ID")
  issuer = ENV.fetch("APPSTORE_ISSUER_ID")
  pem = Base64.decode64(ENV.fetch("APPSTORE_PRIVATE_KEY_BASE64"))
  key = OpenSSL::PKey.read(pem)
  now = Time.now.to_i
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = { iss: issuer, iat: now, exp: now + 900, aud: "appstoreconnect-v1" }
  signing_input = [header, payload].map { |part| b64url(JSON.generate(part)) }.join(".")
  der_signature = key.sign("SHA256", signing_input)
  sequence = OpenSSL::ASN1.decode(der_signature)
  raw_signature = sequence.value.map do |integer|
    integer.value.to_s(2).rjust(32, "\0")[-32, 32]
  end.join
  "#{signing_input}.#{b64url(raw_signature)}"
end

def request(method, path, body = nil)
  uri = URI("#{API_ROOT}#{path}")
  klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post }.fetch(method)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Accept"] = "application/json"
  if body
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 45) do |http|
    http.request(req)
  end
  unless response.is_a?(Net::HTTPSuccess) || response.code == "204"
    detail = begin
      parsed = JSON.parse(response.body)
      Array(parsed["errors"]).map { |error| "#{error["status"]} #{error["code"]}: #{error["detail"]}" }.join("; ")
    rescue JSON::ParserError
      response.body.to_s[0, 500]
    end
    abort("App Store Connect API #{method} #{path} failed (HTTP #{response.code}): #{detail}")
  end
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

def query(params)
  URI.encode_www_form(params)
end

app_query = query("filter[bundleId]" => APP_BUNDLE_ID, "limit" => "200")
apps = request("GET", "/apps?#{app_query}")["data"] || []
app_matches = apps.select { |item| item.dig("attributes", "bundleId") == APP_BUNDLE_ID }
abort("Expected exactly one App Store Connect app for #{APP_BUNDLE_ID}; found #{app_matches.length}.") unless app_matches.length == 1
app_id = app_matches.first.fetch("id")

group_query = query(
  "filter[app]" => app_id,
  "filter[name]" => GROUP_NAME,
  "filter[isInternalGroup]" => "false",
  "limit" => "200"
)
groups = request("GET", "/betaGroups?#{group_query}")["data"] || []
group_matches = groups.select do |item|
  attributes = item["attributes"] || {}
  attributes["name"] == GROUP_NAME && attributes["isInternalGroup"] == false
end
abort("Expected exactly one external TestFlight group named #{GROUP_NAME.inspect}; found #{group_matches.length}.") unless group_matches.length == 1
group_id = group_matches.first.fetch("id")

build_number = ENV.fetch("BUILD_NUMBER")
build_query = query("limit" => "200", "fields[builds]" => "version,processingState")
deadline = Time.now + 30 * 60
build = nil
loop do
  builds = request("GET", "/apps/#{URI.encode_www_form_component(app_id)}/builds?#{build_query}")["data"] || []
  matches = builds.select { |item| item.dig("attributes", "version") == build_number }
  abort("Multiple builds matched build number #{build_number}; refusing to choose.") if matches.length > 1
  if matches.length == 1
    candidate = matches.first
    state = candidate.dig("attributes", "processingState")
    case state
    when "VALID"
      build = candidate
      break
    when "FAILED", "INVALID"
      abort("Apple processing failed for build #{build_number} (#{state}).")
    else
      puts "Build #{build_number} is still processing (#{state || "unknown"}); checking again in 60 seconds."
    end
  else
    puts "Build #{build_number} is not visible in App Store Connect yet; checking again in 60 seconds."
  end
  abort("Timed out waiting for Apple to process build #{build_number}. Rerun this workflow to finish group assignment.") if Time.now >= deadline
  sleep 60
end

relationship_query = query("limit" => "200")
existing = request("GET", "/betaGroups/#{URI.encode_www_form_component(group_id)}/relationships/builds?#{relationship_query}")["data"] || []
if existing.any? { |item| item["id"] == build.fetch("id") }
  puts "Build #{build_number} is already assigned to the TestFlight group #{GROUP_NAME}."
else
  request(
    "POST",
    "/betaGroups/#{URI.encode_www_form_component(group_id)}/relationships/builds",
    data: [{ type: "builds", id: build.fetch("id") }]
  )
  puts "Assigned processed build #{build_number} to the TestFlight group #{GROUP_NAME}."
end
