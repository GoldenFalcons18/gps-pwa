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
TEST_LOCALE = "ja"
TEST_NOTES = <<~NOTES.freeze
  【今回のテスト内容】
  ・GPS：現在地・受信精度表示、進路／方位表示
  ・地図：現在地追従、ウェイポイント名の表示・追加・編集、地点タップと目標選択
  ・地点管理：グループ選択と移動
  ・航跡：記録開始、一時停止／再開、停止
  ・セーリング：速度・方位・目標距離表示、画面サイズに応じた文字サイズ
  ・スタートタイマー：設定時間表示、開始・一時停止・再開、「0秒合わせ」
  ・シグナル：旗操作と音響
  ・Apple Watch：記録操作とiPhoneとの連携
  不具合はTestFlightの「フィードバックを送信」から、再現手順と画面を添えて報告してください。
NOTES
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
    [integer.value.to_i.to_s(16).rjust(64, "0")[-64, 64]].pack("H*")
  end.join
  "#{signing_input}.#{b64url(raw_signature)}"
end

def request(method, path, body = nil, allow_not_found: false)
  uri = URI("#{API_ROOT}#{path}")
  klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PATCH" => Net::HTTP::Patch }.fetch(method)
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
  return nil if allow_not_found && response.code == "404"
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


localizations_query = query("limit" => "200", "fields[betaBuildLocalizations]" => "locale,whatsNew")
localizations = request(
  "GET",
  "/builds/#{URI.encode_www_form_component(build.fetch("id"))}/betaBuildLocalizations?#{localizations_query}"
)["data"] || []
japanese_localizations = localizations.select { |item| item.dig("attributes", "locale") == TEST_LOCALE }
abort("Multiple Japanese TestFlight localizations found for build #{build_number}; refusing to choose.") if japanese_localizations.length > 1

if japanese_localizations.empty?
  request(
    "POST",
    "/betaBuildLocalizations",
    {
      data: {
        type: "betaBuildLocalizations",
        attributes: { locale: TEST_LOCALE, whatsNew: TEST_NOTES },
        relationships: { build: { data: { type: "builds", id: build.fetch("id") } } }
      }
    }
  )
  puts "Created Japanese TestFlight test notes for build #{build_number}."
else
  localization = japanese_localizations.first
  if localization.dig("attributes", "whatsNew") == TEST_NOTES
    puts "Japanese TestFlight test notes are already current for build #{build_number}."
  else
    request(
      "PATCH",
      "/betaBuildLocalizations/#{URI.encode_www_form_component(localization.fetch("id"))}",
      {
        data: {
          type: "betaBuildLocalizations",
          id: localization.fetch("id"),
          attributes: { whatsNew: TEST_NOTES }
        }
      }
    )
    puts "Updated Japanese TestFlight test notes for build #{build_number}."
  end
end

verified_localizations = request(
  "GET",
  "/builds/#{URI.encode_www_form_component(build.fetch("id"))}/betaBuildLocalizations?#{localizations_query}"
)["data"] || []
verified = verified_localizations.select do |item|
  item.dig("attributes", "locale") == TEST_LOCALE && item.dig("attributes", "whatsNew") == TEST_NOTES
end
abort("Japanese TestFlight test notes verification failed for build #{build_number}.") unless verified.length == 1

relationship_query = query("limit" => "200")
existing = request("GET", "/betaGroups/#{URI.encode_www_form_component(group_id)}/relationships/builds?#{relationship_query}")["data"] || []
if existing.any? { |item| item["id"] == build.fetch("id") }
  puts "Build #{build_number} is already assigned to the TestFlight group #{GROUP_NAME}."
else
  request(
    "POST",
    "/betaGroups/#{URI.encode_www_form_component(group_id)}/relationships/builds",
    { data: [{ type: "builds", id: build.fetch("id") }] }
  )
  puts "Assigned processed build #{build_number} to the TestFlight group #{GROUP_NAME}."
end

submission_path = "/builds/#{URI.encode_www_form_component(build.fetch("id"))}/betaAppReviewSubmission?#{query("fields[betaAppReviewSubmissions]" => "betaReviewState,submittedDate")}"
submission = request("GET", submission_path, nil, allow_not_found: true)
state = submission&.dig("data", "attributes", "betaReviewState")
case state
when "WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"
  puts "Build #{build_number} already has a Beta App Review state of #{state}."
when "REJECTED"
  abort("Build #{build_number} was rejected by Beta App Review; a new build is required.")
else
  puts "Build #{build_number} has no active Beta App Review state; submitting it now."
  result = request(
    "POST",
    "/betaAppReviewSubmissions",
    {
      data: {
        type: "betaAppReviewSubmissions",
        relationships: { build: { data: { type: "builds", id: build.fetch("id") } } }
      }
    }
  )
  state = result.dig("data", "attributes", "betaReviewState")
  puts "Submitted build #{build_number} for Beta App Review (#{state || "submitted"})."
end
