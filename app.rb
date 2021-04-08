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

    r.on "login" do
      # GET /login
      r.is do
        :login
      end

      # GET /login/:token
      r.on String do |token|
        r.is do
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
        # DEALS /
        @deals = @current_team.deals
        :deals
      end

      r.on String do |id|
        @companies = @current_team.companies
        @users = @current_team.users
        @stages = @current_team.stages
        @contacts = @current_team.contacts

        if id == "new"
          # DEALS /NEW
          r.get do
            :deals_new
          end

          # DEALS /POST
          r.post do
            company = @current_team.companies.with_hashid(r.params["company_id"]) if r.params["company_id"]
            contact = @current_team.contacts.with_hashid(r.params["contact_id"]) if r.params["contact_id"]
            user = @current_team.users.with_hashid(r.params["user_id"]) if r.params["user_id"]
            stage = @current_team.stages.with_hashid(r.params["stage_id"]) if r.params["stage_id"]

            deal_params = r.params["deal"].slice("notes", "value")

            @deal = Deal.new(deal_params)
            @deal.team = @current_team
            @deal.company = company
            @deal.user = user
            @deal.contact = contact

            if @deal.valid?
              @deal.save
              @deal.add_stage(stage) if stage
              r.redirect "/deals"
            else
              :deals_new
            end
          end
        end

        r.is "edit" do
          # DEALS EDIT
          @deal = @current_team.deals.with_hashid(id)
          @contacts = @deal.company.contacts
          @stage = @deal.latest_stage

          r.get do
            :deals_edit
          end

          r.post do
            contact = @current_team.contacts.with_hashid(r.params["contact_id"]) if r.params["contact_id"]
            user = @current_team.users.with_hashid(r.params["user_id"]) if r.params["user_id"]
            stage = @current_team.stages.with_hashid(r.params["stage_id"]) if r.params["stage_id"]

            params = r.params["deal"].slice("value", "notes")
            @deal.set(params)
            @deal.contact = contact
            @deal.user = user

            if r.params["deal"]["status"] == "closed"
              @deal.closed_at = Time.now.to_i
            else
              @deal.closed_at = nil
            end

            if @deal.valid?
              @deal.save
              @deal.add_stage(stage) if stage
              r.redirect "/deals"
            else
              :deals_edit
            end
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
      def params(r)
        r.params["user"].slice("email", "name")
      end

      r.is do
        @users = @current_team.users
        :users
      end

      r.is "new" do
        # GET /users/new
        r.get do
          @user = User.new
          :users_new
        end

        r.post do
          # USERS NEW POST
          @user = User.new params(r)
          @user.team = @current_team

          # TODO email user invite email ?

          if @user.valid?
            @user.save
            r.redirect "/deals/new"
          else
            :users_new
          end
        end
      end

      r.on String do |id|
        r.is "edit" do
          @user = @current_team.users.with_hashid(id)

          r.get do
            :users_edit
          end

          r.post do
            @user.set(params(r))

            if @user.valid?
              @user.save
              r.redirect "/users"
            else
              :users_edit
            end
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
        def params(r)
          r.params["company"].slice("name", "linked_in", "url", "notes")
        end

        if id == "new"
          r.get do
            @company = Company.new
            :companies_new
          end

          r.post do
            @company = Company.new params(r)
            @company.team = @current_team

            if @company.valid?
              @company.save
              r.redirect "/companies"
            else
              :companies_new
            end
          end
        end

        @company = @current_team.companies.with_hashid(id)

        # GET /companies/:hashid
        # COMPANIES SHOW
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
            @company.set params(r)

            if @company.valid?
              @company.save
              r.redirect "/companies"
            else
              :companies_edit
            end
          end
        end
      end
    end

    # CONTACTS
    r.on "contacts" do
      def params(r)
        r.params["contact"].slice("name", "email", "address", "phone", "linkedin", "notes")
      end

      # GET /contacts
      r.is do
        @contacts = @current_team.contacts
        :contacts
      end

      r.on "new" do
        @companies = @current_team.companies

        # CONTACTS NEW
        # GET /contacts/new
        r.get do
          @contact = Contact.new
          :contacts_new
        end

        # CONTACTS CREATE
        # POST /contacts/new
        r.post do
          @contact = Contact.new params(r)
          @contact.team = @current_team
          company_id = r.params.dig("company", "id")
          @contact.company = @current_team.companies.with_hashid(company_id) if company_id

          if @contact.valid?
            @contact.save
            r.redirect "/contacts"
          else
            :contacts_new
          end
        end
      end

      r.on String do |id|
        @contact = @current_team.contacts.with_hashid(id)

        if @contact.nil?
          response.status = 404
          r.halt
        end

        # CONTACTS EDIT
        r.is "edit" do
          # GET /contacts/:id/edit
          r.get do
            :contacts_edit
          end

          # POST /contacts/:id/edit
          r.post do
            if @contact.update params(r)
              r.redirect "/contacts"
            else
              :contacts_edit
            end
          end
        end

        # CONTACTS DELETE
        # POST /contacts/:id/delete
        r.post "delete" do
          @contact.delete
          r.redirect "/contacts"
        end
      end
    end
  end
end
