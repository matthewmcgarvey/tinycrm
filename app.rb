# app.rb

class App < Roda
  plugin :public
  plugin :render, engine: "mab"
  plugin :sessions, secret: ENV.fetch("SESSION_SECRET", SecureRandom.urlsafe_base64(64)), key: "id"
  plugin :route_csrf
  plugin :symbol_views
  plugin :slash_path_empty
  plugin :not_found do
    view "404"
  end

  plugin :default_headers,
    "Content-Type"=>"text/html",
    "Strict-Transport-Security"=>"max-age=16070400;",
    "X-Content-Type-Options"=>"nosniff",
    "X-Frame-Options"=>"deny",
    "X-XSS-Protection"=>"1; mode=block"

  plugin :content_security_policy do |csp|
    csp.default_src :none
    csp.style_src :self
    csp.script_src :self
    csp.connect_src :self
    csp.img_src :self
    csp.font_src :self
    csp.form_action :self
    csp.base_uri :none
    csp.frame_ancestors :none
    csp.block_all_mixed_content
  end

  route do |r|
    r.public
    check_csrf!
    @current_user = User.first(id: r.session['user_id'])
    @current_team = @current_user&.team

    r.root do
      view "root"
    end

    r.get "gotmail" do
      :gotmail
    end

    # AUTH
    r.is "signup" do
      # SIGNUP GET
      r.get do
        :signup
      end

      # SIGNUP POST
      r.post do
        email = r.params["email"]

        if email&.include?("@")
          token = SecureRandom.hex(16)
          token_expires_at = Time.now.to_i + 600

          user = User.find_or_create(email: email)
          user.token = token
          user.token_expires_at = token_expires_at
          user.save

          team = user.team || Team.create(name: "My team")

          if user.team.nil?
            user.team = team
            user.save
          end

          %w[follow-up qualified demo negotiation won lost unqualified].each do |name|
            Stage.find_or_create(team: team, name: name)
          end

          r.redirect "gotmail"
        else
          response.status == 422
          @error = "That's not an email! Try to include an @ symbol ;)"
          :signup
        end
      end
    end

    # LOGIN GET
    r.get "login" do
      :login
    end

    r.get "login", String do |token|
      user = User.first Sequel.lit("token = ? and token_expires_at > ?", token, Time.now.to_i)

      if user
        user.update token: nil, token_expires_at: nil
        r.session["user_id"] = user[:id]
        r.redirect "/deals"
      else
        response.status = 404
        r.halt
      end
    end

    unless @current_user
      response.status = 404
      r.halt
    end

    # LOGOUT
    r.post "logout" do
      r.session.delete("user_id")
      r.redirect "/"
    end

    # DEALS
    r.on "deals" do
      r.is do
        r.get do
          # DEALS /
          @deals = Deal.where(team: @current_team)
          :deals
        end
      end

      r.is "new" do
        @companies = Company.where(team: @current_team)
        @assignees = User.where(team: @current_team)
        @stages = Stage.where(team: @current_team)

        # DEALS /NEW
        r.get do
          :deals_new
        end

        # DEALS /POST
        r.post do
          if r.params["company"] && r.params["company"]["name"]
            company = Company.find_or_create(team_id: @current_team.id, name: r.params["company"]["name"])
            company_params = r.params["company"].slice("notes", "url", "linkedin")
            company.update(company_params)
          end

          contact = @current_team.contacts_dataset.with_hashid(r.params["contact_id"]) if r.params["contact_id"]
          user = @current_team.users_dataset.with_hashid(r.params["user_id"]) if r.params["user_id"]
          stage = @current_team.stages_dataset.with_hashid(r.params["stage_id"]) if r.params["stage_id"]

          deal_params = r.params["deal"].slice("notes", "value")

          @deal = Deal.new(deal_params)
          @deal.team = @current_team
          @deal.company = company
          @deal.user = user
          @deal.contact = contact

          if @deal.save
            @deal.add_stage(stage) if stage
            r.redirect "/deals"
          else
            :deals_new
          end
        end
      end
    end

    # STAGES
    r.on "stages" do
      r.is "new" do
        r.get do
          # STAGES NEW
          @stage = Stage.new
          :stages_new
        end

        r.post do
          # STAGES NEW POST
          params = r.params["stage"].slice("name")
          @stage = Stage.new(params)
          @stage.team = @current_team

          if @stage.valid?
            @stage.save
            r.redirect "/deals/new"
          else
            :stages_new
          end
        end
      end
    end

    # TEAM MEMBERS
    # USERS
    r.on "users" do
      r.is "new" do
        r.get do
          # USERS NEW GET
          @user = User.new
          :users_new
        end

        r.post do
          # USERS NEW POST
          params = r.params["user"].slice("email")
          @user = User.new(params)
          @user.team = @current_team

          # TODO email user invite email

          if @user.valid?
            @user.save
            r.redirect "/deals/new"
          else
            :users_new
          end
        end
      end
    end

    # COMPANIES
    r.on "companies" do
      # GET /companies
      r.is do
        @companies = @current_team.companies
        :companies
      end

      r.on String do |id|
        @company = Company.where(team: @current_team).with_hashid(id)

        # GET /companies/:hashid
        r.is do
          :company
        end

        r.is "edit" do
          # GET /companies/:hashid/edit
          r.get do
            :companies_edit
          end

          # POST /companies/:hashid/edit
          r.post do
            params = r.params["company"].slice("name", "linkedin", "url", "notes")
            @company.set(params)

            if @company.valid?
              @company.save
              r.redirect "/companies/#{@company.hashid}"
            else
              :companies_edit
            end
          end
        end
      end
    end
  end
end
