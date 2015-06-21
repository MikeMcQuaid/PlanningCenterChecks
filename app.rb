require "sinatra"
require "oauth"
require "json"
require "date"
require "awesome_print" if ENV["RACK_ENV"] == "development"

PCO_KEY = ENV["PCO_KEY"]
PCO_SECRET = ENV["PCO_SECRET"]
SESSION_SECRET = ENV["SESSION_SECRET"]

URL_ROOT = "https://services.planningcenteronline.com"

set :sessions, secret: SESSION_SECRET

def oauth
  @oauth ||= OAuth::Consumer.new PCO_KEY, PCO_SECRET, site: "https://planningcenteronline.com"
end

before %r{^(?!/callback)} do
  if session[:access_token]
    @access_token = OAuth::AccessToken.from_hash oauth, session[:access_token]
    next if @access_token
  end

  request_token = oauth.get_request_token oauth_callback: "#{request.base_url}/callback"
  session[:request_token] = token_to_hash request_token

  redirect to request_token.authorize_url
end

get "/callback" do
  request_token = OAuth::RequestToken.from_hash oauth, session[:request_token]

  @access_token = request_token.get_access_token oauth_verifier: params[:oauth_verifier]
  session[:access_token] = token_to_hash @access_token

  redirect to "/"
end

def token_to_hash token
  token.params.select {|key,_| key.is_a? Symbol }
end

def api_hash object, parameters={}
  endpoint = "/#{object}.json"
  parameters.each do |key, value|
    start = parameters.keys.first == key ? "?" : "&"
    endpoint += "#{start}#{key}=#{value}"
  end
  response = @access_token.get endpoint
  body = JSON.parse response.body
  subbody = body[object.to_s] if body.is_a? Hash
  body = subbody if subbody
  body
end

def song_and_arrangement_attachments song
  attachments = song["attachments"]

  song["arrangements"].to_a.each do |arrangement|
    attachments += arrangement["attachments"]
  end

  attachments
end

def song_title_author song
  "#{song["title"]} - #{song["author"]}"
end

def song_link song
  href = "#{URL_ROOT}/songs/#{song["id"]}"
  "<a href='#{href}'>#{song_title_author(song)}</a>"
end

get "/songs" do
  songs_without_attachments = "<h1>Songs without attachments</h1>"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    next if song_and_arrangement_attachments(song).empty?
    songs_without_attachments += "<li>#{song_link(song)}</li>"
  end

  songs_without_attachments
end

get "/no_media" do
  songs_without_media = "<h1>Songs without Spotify/YouTube media</h1>"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    attachments = song_and_arrangement_attachments(song)
    next if attachments.find {|a| a["type"] =~ /Youtube|Spotify/ }
    songs_without_media += "<li>#{song_link(song)}</li>"
  end

  songs_without_media
end

get "/docs" do
  songs_doc_attachments = "<h1>Songs with .doc(x) attachments</h1>"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    attachments = song_and_arrangement_attachments(song)
    next if attachments.empty?
    attachments.each do |attachment|
      filename = attachment["filename"]
      next unless filename =~ /\.docx?$/i
      songs_doc_attachments += "<li>#{song_link(song)}: #{filename}</li>"
    end
  end

  songs_doc_attachments
end

def songs_without_type_attachments(type)
  songs_without_type_attachments = "<h1>Songs without .#{type} attachments</h1>"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    attachments = song_and_arrangement_attachments(song)
    next if attachments.find {|a| a["filename"] =~ /\.#{type}$/i }
    songs_without_type_attachments += "<li>#{song_link(song)}</li>"
  end

  songs_without_type_attachments
end

get "/no_pdf" do
  songs_without_type_attachments(:pdf)
end

get "/no_onsong" do
  songs_without_type_attachments(:onsong)
end

get "/outdated" do
  outdated_songs = "<h1>Songs not used in 60 days</h1>"

  songs = api_hash(:songs)
  songs.each do |song|
    if (last_song_date = song["last_scheduled_dates"])
      ap last_song_date
      last_song_date = Date.parse(last_song_date)
      two_months_ago = Date.today - 60
      next if last_song_date > two_months_ago
    end
    outdated_songs += "<li>#{song_link(song)}</li>"
  end

  outdated_songs
end

get "/default_arrangements" do
  default_arrangements = "<h1>Arrangements named 'Default Arrangement'</h1>"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    song["arrangements"].to_a.each do |arrangement|
      next unless arrangement["name"] =~ /^default arrangement$/i
      href = "#{URL_ROOT}/arrangements/#{arrangement["id"]}"
      default_arrangements += "<li><a href='#{href}'>#{song_title_author(song)}</a></li>"
    end
  end

  default_arrangements
end

def person_link person
  id = person["person_id"] || person["id"]
  name = person["person_name"] || person["name"]
  position = person["position"]

  name_position = "#{name}"
  name_position += " (#{position})" if position
  href = "#{URL_ROOT}/people/#{id}"
  "<a href='#{href}'>#{name_position}</a>"
end

def plan_responses(out, type)
  out << "<h1>#{type} plan responses</h1>"

  organisation = api_hash(:organization)
  service_types = organisation["service_types"]
  service_types.each do |service_type|
    plans = api_hash("service_types/#{service_type["id"]}/plans")
    plans.each do |plan|
      plan_detail = api_hash("plans/#{plan["id"]}")
      plan_people = plan_detail["plan_people"]
      plan_people.each do |plan_person|
        next unless plan_person["status"] == type[0]
        plan_href = "#{URL_ROOT}/plans/#{plan["id"]}"
        plan_time = Time.parse(plan_detail["service_times"].first["starts_at"])
        plan_date_time = plan_time.strftime("%d %b %H:%M")
        out << "<li><a href='#{plan_href}'>#{plan_date_time}</a>: #{person_link(plan_person)}</li>"
      end
    end
  end
end

get "/unconfirmed" do
  stream {|out| plan_responses(out, "Unconfirmed") }
end

get "/declined" do
  stream {|out| plan_responses(out, "Declined") }
end

get "/no_birthday" do
  stream do |out|
    out << "<h1>Team members without birthdays</h1>"

    people = api_hash(:people)
    people.each do |person|
      person_detail = api_hash("people/#{person["id"]}")
      next if person_detail["birthdate"]
      out << "<li>#{person_link(person)}</li>"
    end
  end
end

get "/" do
<<-EOS
<li><a href='/songs'>Songs without attachments</a></li>
<li><a href='/no_media'>Songs without Spotify/YouTube media</a></li>
<li><a href='/docs'>Songs with .doc(x) attachments</a></li>
<li><a href='/no_pdf'>Songs without .pdf attachments</a></li>
<li><a href='/no_onsong'>Songs without .onsong attachments</a></li>
<li><a href='/outdated'>Songs not used in 60 days</a></li>
<li><a href='/default_arrangements'>Arrangements named 'Default Arrangement'</a></li>
<li><a href='/unconfirmed'>Unconfirmed plan responses</a></li>
<li><a href='/declined'>Declined plan responses</a></li>
<li><a href='/no_birthday'>Team members without birthdays</a></li>
EOS
end
