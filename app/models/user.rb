class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :omniauthable, omniauth_providers: [:facebook, :google_oauth2], :authentication_keys => [:login]
  # Virtual attribute for authenticating by either username or email
  # This is in addition to a real persisted field like 'username'
  #attr_accessor :login

  has_many :identity, dependent: :delete_all
  has_many :orders
  has_many :followings
  has_many :chefs, through: :followings

  has_and_belongs_to_many :allergies, join_table: :user_allergies
  has_many :dish_evaluations

  has_many :favorite_dishes#ADD AL
  has_many :dishes, through: :favorite_dishes#ADD AL
  #has_and_belongs_to_many :dishes, join_table: :favorite_dishes #ADD AL

  has_many :addresses
  has_many :notifications, foreign_key: :recipient_id

  #if you want email to be case insensitive, you should add
  # Validamos que el identificador tenga entre 8 a 12 caracteres
  # Validamos que el email sea unico
  #Validar que nombre de usuario no contenga @
  validates :username , presence: true , confirmation: true
  validates :username, length: { in: 4..100 ,message: "muy corto"}
  validates :username, uniqueness: {case_sensitive: false ,message: "ya esta registrado"}
  validates_format_of :username, with: /^[a-zA-Z0-9]*$/, :multiline => true ,message: "No debe contener caracteres especiales"
  #validates :phone , presence: false, confirmation: false

  def to_param
    username
  end

  def self.types
    %w(Diner Chef Admin)
  end

  def login=(login)
    @login = login
  end

  def login
    @login || self.username || self.email
  end

  def self.find_for_database_authentication(warden_conditions)
      conditions = warden_conditions.dup
      if login = conditions.delete(:login)
        where(conditions.to_h).where(["lower(username) = :value OR lower(email) = :value", { :value => login.downcase }]).first
      elsif conditions.has_key?(:username) || conditions.has_key?(:email)
        where(conditions.to_h).first
      end
    end

  #Login with facebook
  def self.find_for_oauth(auth, signed_in_resource = nil)
    identity = Identity.find_for_oauth(auth)
    user = signed_in_resource ? signed_in_resource : identity.user

    if user.nil?
      email = auth.info.email
      user = User.find_by(email: email) if email
      username = auth.info.email.split("@")[0]
      username = username.split(".")[0]
      if User.find_by_username(username) != nil
        username = "#{auth.uid}"
      end
      # Create the user if it's a new registration
      if user.nil?
         password = Devise.friendly_token[0,20]
        if auth.provider == 'facebook'
          user = User.new(
            email: email ? email : "#{auth.uid}@change-me.com",
            username: username ? username : "#{auth.uid}",
            picture: auth.info.image + "?type=large",
            name: auth.info.name,
            lastname: auth.info.last_name,
            password: password,
            birthday: auth.info.birthday,
            password_confirmation: password,
            oauth_token: auth.credentials.token
          )
        elsif auth.provider == 'google_oauth2'
          user = User.new(
            email: email ? email : "#{auth.uid}@change-me.com",
            username: username ? username : "#{auth.uid}",
            picture: auth.info.image,
            name: auth.info.first_name,
            lastname: auth.info.last_name,
            birthday: auth[:extra][:raw_info][:birthday],
            password: password,
            password_confirmation: password
          )
        end
      end
      user.save!
    end

    if identity.user != user
      identity.user = user
      identity.save!
    end
    user
  end

  def self.connect_to_google(auth)
     data = auth.info
     where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
       user.email = data["email"]
       user.password = Devise.friendly_token[0,20]
       user.first_name = data["first_name"]
       user.last_name = data["last_name"]
       user.avatar = process_uri(data["image"])
     end
  end

  def email_verified?
    if self.email
      if self.email.split('@')[1] == 'change-me.com'
        return false
      else
        return true
      end
    else
      return false
    end
  end

  def facebook
    @facebook ||= Koala::Facebook::API.new(oauth_token)
     block_given? ? yield(@facebook) : @facebook
  rescue Koala::Facebook::APIError => e
      logger.info e.to_s
      nil
  end
  def friends
    @friends = facebook { |fb| fb.get_connection("me","friends?fields=id,name,picture.type(large)") }
  end

  def shareDish(names,ids,descriptions)
  facebook { |fb| fb.put_wall_post("GourNet", {
      "name" => names,
      "link" => "https://gournet.herokuapp.com/dishes/",
      "caption" => "https://gournet.herokuapp.com/",
      "description" => descriptions,
      "picture" => "http://www.example.com/thumbnail.jpg"
    })}
  end

  attr_accessor :user_picture

  private

  after_create :upload_image, if: :user_picture

  def upload_image
    image = StorageBucket.files.new(
                                   key: "user_pictures/#{email}/#{user_picture.original_filename}",
                                   body: user_picture.read,
                                   public: true
    )

    image.save

    update_columns picture: image.public_url
  end

  before_destroy :delete_image, if: :picture

  def delete_image
    bucket_name = StorageBucket.key
    image_uri   = URI.parse picture

    if image_uri.host == "#{bucket_name}.storage.googleapis.com"
      # Remove leading forward slash from image path
      # The result will be the image key, eg. "cover_images/:id/:filename"
      image_key = image_uri.path.sub("/", "")
      image     = StorageBucket.files.new key: image_key

      image.destroy
    end
  end
  # [END delete]

  # [START update]
  after_update :update_image, if: :user_picture

  def update_image
    print picture
    delete_image if picture?
    upload_image
  end
end
