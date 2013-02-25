module TheCommentModels
  module Commentable
    extend ActiveSupport::Concern

    included do
      has_many :comments, as: :commentable

      def comments_sum
        published_comments_count + draft_comments_count
      end

      def recalculate_comments_counters
        self.draft_comments_count     = comments.with_state(:draft).count
        self.published_comments_count = comments.with_state(:published).count
        self.deleted_comments_count   = comments.with_state(:deleted).count
        save
      end
    end
  end

  module User
    extend ActiveSupport::Concern
    
    included do
      has_many :comments
      has_many :comcoms, class_name: :Comment, foreign_key: :holder_id

      def recalculate_comments_counters
        [:comments, :comcoms].each do |name|
          send "draft_#{name}_count=",     send(name).with_state(:draft).count
          send "published_#{name}_count=", send(name).with_state(:published).count
          send "deleted_#{name}_count=",   send(name).with_state(:deleted).count
        end
        save
      end

      def comments_sum
        published_comments_count + draft_comments_count
      end

      def comcoms_sum
        published_comcoms_count + draft_comcoms_count
      end
    end    
  end

  module Comment
    extend ActiveSupport::Concern

    included do
      # Nested Set
      attr_accessible :parent_id
      acts_as_nested_set scope: [:commentable_type, :commentable_id]

      # Comments State Machine
      include TheCommentsStates

      # TheSortableTree
      include TheSortableTree::Scopes

      attr_accessible :user, :title, :contacts, :raw_content, :view_token, :state
      attr_accessible :ip, :referer, :user_agent, :tolerance_time

      # validates :title, presence: true
      validates :raw_content, presence: true

      # relations
      belongs_to :user
      belongs_to :holder, class_name: :User
      belongs_to :commentable, polymorphic: true

      # callbacks
      before_create :define_holder, :define_anchor, :prepare_content
      after_create  :update_cache_counters

      def avatar_url
        src = id.to_s
        src = title unless title.blank?
        src = contacts if !contacts.blank? && /@/ =~ contacts
        hash = Digest::MD5.hexdigest(src)
        "http://www.gravatar.com/avatar/#{hash}?s=40&d=identicon"
      end

      private

      def define_anchor
        self.anchor = SecureRandom.hex[0..5]
      end

      def define_holder
        self.holder = self.commentable.user
      end

      def prepare_content
        self.content = self.raw_content
      end

      def update_cache_counters
        self.user.try        :increment!, :draft_comments_count
        self.holder.try      :increment!, :draft_comcoms_count
        self.commentable.try :increment!, :draft_comments_count
      end
    end
  end

  module BlackIp
    extend ActiveSupport::Concern
    
    included do
      attr_accessible :ip

      validates :ip, presence:   true
      validates :ip, uniqueness: true
    end
  end

  module BlackUserAgent
    extend ActiveSupport::Concern

    included do
      attr_accessible :user_agent

      validates :user_agent, presence:   true
      validates :user_agent, uniqueness: true
    end
  end
end