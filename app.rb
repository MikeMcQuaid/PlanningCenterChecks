require "sinatra"
require "oauth"
require "json"
require "date"
require "awesome_print" if ENV["RACK_ENV"] == "development"

PCO_KEY = ENV["PCO_KEY"]
PCO_SECRET = ENV["PCO_SECRET"]
SESSION_SECRET = ENV["SESSION_SECRET"]

PCO_URL = "https://services.planningcenteronline.com"

set :sessions, secret: SESSION_SECRET

def oauth
  @oauth ||= OAuth::Consumer.new PCO_KEY, PCO_SECRET, site: PCO_URL
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
  song_title_author = "#{song["title"]}"
  song_title_author += " - #{song["author"]}" unless song["author"].empty?
  song_title_author
end

def song_link song
  href = "#{PCO_URL}/songs/#{song["id"]}"
  "<a href='#{href}'>#{song_title_author(song)}</a>"
end

def song_current_new? song
  !!song["properties"].to_a.find do |property|
    if property["field"] == "Type"
      (property["option"] == "#Current") || (property["option"] == "#New")
    end
  end
end

def bootstrap_html(html)
  text = markdown(html)
  text.gsub!("<ul>", "<ul class='list-group'>")
  text.gsub!("<li>", "<li class='list-group-item'>")
  text
end

def render_layout
  if @markdown.is_a? StringIO
    markdown_text = @markdown.string
    @markdown.close
    @markdown = markdown_text
  end
  @text = bootstrap_html(markdown(@markdown))

  erb :full
end

before do
  @title = nil
  @markdown = StringIO.new
end

get "/songs" do
  @title = "Songs without attachments"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    next unless song_current_new?(song)
    next if song_and_arrangement_attachments(song).any?
    @markdown.puts "* #{song_link(song)}"
  end

  render_layout
end

get "/no_media" do
  @title = "Songs without Spotify/YouTube media"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    next unless song_current_new? song
    attachments = song_and_arrangement_attachments(song)
    next if attachments.find {|a| a["type"] =~ /Youtube|Spotify/ }
    @markdown.puts "* #{song_link(song)}"
  end

  render_layout
end

get "/docs" do
  @title = "Songs with .doc(x) attachments"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    next unless song_current_new? song
    attachments = song_and_arrangement_attachments(song)
    next if attachments.empty?
    attachments.each do |attachment|
      filename = attachment["filename"]
      next unless filename =~ /\.docx?$/i
      @markdown.puts "* #{song_link(song)}: #{filename}"
    end
  end

  render_layout
end

def songs_without_type_attachments(type)
  @title = "Songs without .#{type} attachments"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    next unless song_current_new? song
    attachments = song_and_arrangement_attachments(song)
    next if attachments.find {|a| a["filename"] =~ /\.#{type}$/i }
    @markdown.puts "* #{song_link(song)}"
  end

  render_layout
end

get "/no_pdf" do
  songs_without_type_attachments(:pdf)
end

get "/no_onsong" do
  songs_without_type_attachments(:onsong)
end

get "/outdated" do
  @title = "Songs not used in 60 days"

  songs = api_hash(:songs)
  songs.each do |song|
    next unless song_current_new? song
    if (last_song_date = song["last_scheduled_dates"])
      last_song_date = Date.parse(last_song_date)
      two_months_ago = Date.today - 60
      next if last_song_date > two_months_ago
    end
    @markdown.puts "* #{song_link(song)}"
  end

  render_layout
end

get "/default_arrangements" do
  @title = "Arrangements named 'Default Arrangement'"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    next unless song_current_new? song
    song["arrangements"].to_a.each do |arrangement|
      next unless arrangement["name"] =~ /^default arrangement$/i
      link = "#{PCO_URL}/arrangements/#{arrangement["id"]}"
      @markdown.puts "* [#{song_title_author(song)}](#{link})"
    end
  end

  render_layout
end

def person_link person
  id = person["person_id"] || person["id"]
  name = person["person_name"] || person["name"]
  position = person["position"]

  name_position = "#{name}"
  name_position += " (#{position})" if position
  link = "#{PCO_URL}/people/#{id}"
  "<a href='#{link}'>#{name_position}</a>"
end

def stream_header(out, title)
  @title = title
  out << erb(:header) << "<ul>"
end

def stream_footer(out)
  out << "</ul>" << erb(:footer)
end

def plan_responses(out, type)
  stream_header(out, "#{type} plan responses")

  organization = api_hash(:organization)
  service_types = organization["service_types"]
  service_types.each do |service_type|
    plans = api_hash("service_types/#{service_type["id"]}/plans")
    plans.each do |plan|
      next unless plan["service_type_name"] =~ /^(7|11).00/
      plan_detail = api_hash("plans/#{plan["id"]}")
      plan_people = plan_detail["plan_people"]
      plan_people.each do |plan_person|
        next unless plan_person["category_name"] == "Band"
        next unless plan_person["status"] == type[0]
        plan_href = "#{PCO_URL}/plans/#{plan["id"]}"
        plan_time = Time.parse(plan_detail["service_times"].first["starts_at"])
        plan_date_time = plan_time.strftime("%d %b %H:%M")
        out << bootstrap_html("<li><a href='#{plan_href}'>#{plan_date_time}</a>: #{person_link(plan_person)}</li>")
      end
    end
  end

  stream_footer(out)
end

get "/unconfirmed" do
  stream {|out| plan_responses(out, "Unconfirmed") }
end

get "/declined" do
  stream {|out| plan_responses(out, "Declined") }
end

get "/no_birthday" do
  stream do |out|
    stream_header(out, "Team members without birthdays")

    people = api_hash(:people)
    people.each do |person|
      person_detail = api_hash("people/#{person["id"]}")
      next unless person_detail["properties"].to_a.find do |property|
        property["field"] == "Musical Role"
      end
      next if person_detail["birthdate"]
      out << bootstrap_html("<li>#{person_link(person)}</li>")
    end

    stream_footer(out)
  end
end

get "/" do
  organization = api_hash(:organization)
  @title = "#{organization["name"]} Planning Center Checks"
  @markdown.puts <<-EOS
* [Songs without attachment](/songs)
* [Songs without Spotify/YouTube media](/no_media)
* [Songs with .doc(x) attachments](/docs)
* [Songs without .pdf attachments](/no_pdf)
* [Songs without .onsong attachments](/no_onsong)
* [Songs not used in 60 days](/outdated)
* [Arrangements named 'Default Arrangement'](/default_arrangements)
* [Unconfirmed plan responses](/unconfirmed)
* [Declined plan responses](/declined)
* [Team members without birthdays](/no_birthday)
EOS
  render_layout
end
