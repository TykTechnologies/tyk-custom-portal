# Dependencies: gem install sinatra excon --no-ri
# Run like this: TYK_PORTAL_PORT=8080 TYK_API_KEY=<your-api-key-here> ruby portal.rb

require 'excon'
require 'sinatra'
require 'bcrypt'

# ==== Sinatra configuration ====
enable :sessions

if ENV['TYK_PORTAL_PORT'] != ""
    set :port, ENV['TYK_PORTAL_PORT']
end

# ==== TYK API configuration ====
if ENV['TYK_API_KEY'] == ""
    puts "TYK_API_KEY environment variable not set"
    exit(1)
end

dashboardURL = ENV['TYK_DASHBOARD_URL'] || 'https://admin.cloud.tyk.io/'

Tyk = Excon.new(dashboardURL, :persistent => true, :headers => { "authorization": ENV['TYK_API_KEY']})

### ==== Configure global variables and auth logic
before do
    if session[:developer]
        resp = Tyk.get(path: "/api/portal/developers/email/#{session[:developer]}")

        if resp.status == 200
            @developer = JSON.parse(resp.body)
        else
            session.delete(:developer)
        end
    end

    @apis_catalogue = JSON.parse(Tyk.get(path: "/api/portal/catalogue").body)
    @portal_config = JSON.parse(Tyk.get(path: "/api/portal/configuration").body)
end

set(:auth) do |*roles|   # <- notice the splat here
  condition do
    if roles.include?(:logged) && @developer.nil?
      redirect "/", 303
    end
  end
end

template :layout do
    <<-HTML
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/bulma/0.5.1/css/bulma.min.css">

    <div class="container content">
        <br/>
        <% if @developer.nil? %>
            <span class="title is-2">Welcome to the developer portal</span>
            <a href="/login" class="is-pulled-right is-size-4">Login</a>
            <a href="/register" class="is-pulled-right is-size-4" style="margin-right: 2em">Signup</a>
        <% else %>
            <span class="title is-2">Hello <%=@developer['fields']['Name']%>!</span>
            <a href="/logout" class="is-pulled-right is-size-4">Logout</a>
        <% end %>
        <hr/>

        <% if @error %>
        <h3 style="color: red"><%=@error%></h3>
        <% end %>

        <%=yield%>
    </div>
    HTML
end

### ==== Basic templates used for rendering portal ====
template :dashboard do
    <<-HTML
    <h3>Analytics</h3>
    For the last 30 days you made: <span class="is-size-4"><%=@totals['hits']%></span> requests


    <h3>APIs:</h3>
    <% @apis_catalogue['apis'].each do |api| %>
    <h2 class="header"><%=api['name']%></h2>
    <h3 class="subheader"><%=api['short_description'] %></h3>
    <p><%=api['long_description'] %></p>

    <% if @developer['subscriptions'][api['policy_id']] %>
    <h4>Already subscribed<h4>
    <% else %>
    <a href="/request/<%=api['policy_id']%>">Request access</a>
    <% end %>
    <hr>
    <% end %>
    HTML
end

template :home do
    <<-HTML
    <h3>You can subscribe to the following APIs:</h3>
    <% @apis_catalogue['apis'].each do |api| %>
    <h2 class="header"><%=api['name']%></h2>
    <h3 class="subheader"><%=api['short_description'] %></h3>
    <p><%=api['long_description'] %></p>
    <hr>
    <% end %>

    HTML
end

### ==== Dashboard and home page ====
get '/' do
    if @developer
        redirect "/dashboard"
        return
    end

    erb :home
end

get '/dashboard', auth: :logged do
    keys = @developer['subscriptions'].values.join(',') + ','
    from = (Date.today - 30).strftime("%d/%m/%Y")
    to = Date.today.strftime("%d/%m/%Y")

    resp = Tyk.get(path: "/api/activity/keys/aggregate/#{keys}/#{from}/#{to}?p=-1&res=day")
    @analytics = JSON.parse(resp.body)
    @totals = @analytics['data'].reduce({"hits" => 0, "success" => 0, "error" => 0}) do |total, row|
        total['hits'] += row['hits'].to_i
        total['success'] += row['success'].to_i
        total['error'] += row['error'].to_i

        total
    end

    erb :dashboard
end

### ==== Key request ===
template :request_access do
    <<-HTML
    <h1>Requesting access to '<%=@api['name']%>' API</h1>
    <form target="/request/<%=params[:policy_id]%>" method="POST" class="column is-half">
        <input class="input" placeholder="Use case" name="usecase" /><br/><br/>
        <input class="input"  placeholder="Planned amount of monthly requests" name="traffic" /><br/><br/>
        <input class="button is-primary" type="submit" />
    </form>
    HTML
end

before '/request/:policy_id' do
    @api = @apis_catalogue['apis'].detect{|api| api['policy_id'] == params[:policy_id] }
end

get '/request/:policy_id', auth: :logged do
    erb :request_access
end

post '/request/:policy_id', :auth => :logged do
    key_request = {
        "by_user" => @developer['id'],
        "fields" => {
            "usecase" => params[:usecase],
            "traffic" => params[:traffic],
        },
        'date_created' => Time.now.iso8601,
        "version" => "v2",
        "for_plan" => params[:policy_id]
    }

    resp = Tyk.post(path: "/api/portal/requests", body: key_request.to_json)
    if resp.status != 200
        @error = resp.body
        return erb :request_access
    end

    unless @portal_config['require_key_approval']
        puts resp.body
        reqID = JSON.parse(resp.body)["Message"]
        Tyk.put(path: "/api/portal/requests/approve/#{reqID}")
    end

    redirect "/"
end

### ==== User registration ====
template :register do
    <<-HTML
    <form target="/register" method="POST" class="column is-half">
        <h1>Sign Up</h1>
        <input class="input" placeholder="Email" name="email"/><br/><br/>
        <input class="input" placeholder="Password" name="password" type="password"/><br/><br/>
        <input class="input" placeholder="Name" name="name"/><br/><br/>
        <input class="input" placeholder="Location" name="location"/><br/><br/>
        <input class="button is-primary" type=submit />
    </form>
    HTML
end

get '/register' do
    erb :register
end

post '/register' do
    developer = {
        "email": params[:email],
        "password": params[:password],
        "inactive": false, # Use this field to add additional developer check
        "fields": {
            "Name": params[:name],
            "Location": params[:location]
        }
    }
    resp = Tyk.post(path: "/api/portal/developers", body: developer.to_json)

    if resp.status != 200
        @error = resp.body
        erb :register
    else
        session[:developer] = params[:email]
        redirect "/"
    end
end

#### === User authentification logic ====
template :login do
    <<-HTML
    <form target="/login" method="POST" class="column is-half">
        <h1>Login</h1>
        <input class="input" placeholder="Email" name="email"/><br/><br/>
        <input class="input" placeholder="Password" name="password" type="password"/><br/><br/>
        <input class="button is-primary" type=submit />
    </form>
    HTML
end

get '/login' do
    erb :login
end

post '/login' do
    resp = Tyk.post(path: "/api/portal/developers/verify_credentials", body: { username: params[:email], password: params[:password] }.to_json)
    if false
        @error = "Password not match"
        return erb :login
    end

    session[:developer] = params[:email]
    redirect "/"
end

get '/logout' do
    session.delete(:developer)
    redirect "/"
end
