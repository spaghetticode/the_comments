module TheComments
  COMMENTS_COOKIES_TOKEN = 'JustTheCommentsCookies'

  # Cookies and View token for spam protection
  # include TheComments::ViewToken
  module ViewToken
    extend ActiveSupport::Concern

    included { before_action :set_the_comments_cookies }

    def comments_view_token
      cookies[:comments_view_token]
    end

    private

    def set_the_comments_cookies
      cookies[:the_comment_cookies] = { value: TheComments::COMMENTS_COOKIES_TOKEN, expires: 1.year.from_now }
      cookies[:comments_view_token] = { value: SecureRandom.hex, expires: 7.days.from_now } unless cookies[:comments_view_token]
    end
  end

  module Controller
    extend ActiveSupport::Concern

    included do
      include TheComments::ViewToken

      # Attention! We should not set TheComments cookie before create
      skip_before_action :set_the_comments_cookies, only: [:create]

      # Spam protection
      before_action -> { @errors = [] }, only: [:create]

      before_action :ajax_requests_required,  only: [:create]
      before_action :cookies_required,        only: [:create]

      before_action :empty_trap_required,     only: [:create], if: -> { TheComments.config.empty_trap_protection }
      before_action :tolerance_time_required, only: [:create], if: -> { TheComments.config.tolerance_time_protection }

      # preparation
      before_action :define_commentable, only: [:create]

      # raise an errors
      before_action -> { return render(json: { errors: @errors }) unless @errors.blank? }, only: [:create]
    end

    # TODO integrare nel profilo utente
    # def my_comments
    #   @comments = current_user.my_comments.active.recent.page(params[:page])
    #   render comment_template(:my_comments)
    # end

    def delete_request
      find_comment
      if @comment.to_delete_requested
        render text: I18n.t('the_comments.delete_request_accepted')
      else
        render text: I18n.t('the_comments.delete_request_refused')
      end
    end

    # via ajax, to render the form
    def edit
      find_comment
      render partial: comment_partial(:comment_edit), locals: { comment: @comment }
    end

    def create
      @comment = @commentable.comments.new comment_params
      @comment.user = current_user
      if @comment.valid?
        @comment.save
        render layout: false, partial: comment_partial(:comment), locals: { tree: @comment }
      else
        render json: { errors: @comment.errors.full_messages }
      end
    end

    private

    def comment_template template
      { template: "the_comments/#{TheComments.config.template_engine}/#{template}" }
    end

    def comment_partial partial
      "the_comments/#{TheComments.config.template_engine}/#{partial}"
    end

    def denormalized_fields
      @commentable ? { commentable_url: @commentable.commentable_url } : {}
    end

    def request_data_for_comment
      r = request
      { ip: r.ip, referer: CGI::unescape(r.referer  || 'direct_visit'), user_agent: r.user_agent }
    end

    def define_commentable
      commentable_klass = params[:comment][:commentable_type].constantize
      commentable_id    = params[:comment][:commentable_id]

      @commentable = commentable_klass.find(commentable_id)
      return render(json: { errors: [t('the_comments.undefined_commentable')] }) unless @commentable
    end

    def comment_params
      params
        .require(:comment)
        .permit(:title, :contacts, :raw_content, :parent_id, :commentable_type, :commentable_id)
        .merge(denormalized_fields)
        .merge(request_data_for_comment)
        .merge(tolerance_time: params[:tolerance_time].to_i)
        .merge(user: current_user, view_token: comments_view_token)
    end

    def patch_comment_params
      params
        .require(:comment)
        .permit(:title, :contacts, :raw_content, :parent_id)
    end

    # Protection hooks
    def ajax_requests_required
      unless request.xhr?
        return render(text: t('the_comments.ajax_requests_required'))
      end
    end

    def cookies_required
      if cookies[:the_comment_cookies] != TheComments::COMMENTS_COOKIES_TOKEN
        @errors << [t('the_comments.cookies'), t('the_comments.cookies_required')].join(': ')
      end
    end

    # TODO:
    # 1) inject ?
    # 2) fields can be removed on client side
    def empty_trap_required
      is_human = true
      params.slice(*TheComments.config.empty_inputs).values.each{|v| is_human = (is_human && v.blank?) }

      if !is_human
        @errors << [t('the_comments.trap'), t('the_comments.trap_message')].join(': ')
      end
    end

    def tolerance_time_required
      this_time = params[:tolerance_time].to_i
      min_time  = TheComments.config.tolerance_time.to_i

      if this_time < min_time
        tdiff   = min_time - this_time
        @errors << [t('the_comments.tolerance_time'), t('the_comments.tolerance_time_message', time: tdiff )].join(': ')
      end
    end

    def find_comment
      @comment = current_user.comments.find(params[:id])
    end
  end
end