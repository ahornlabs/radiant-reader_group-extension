class Group < ActiveRecord::Base

  has_site if respond_to? :has_site
  default_scope :order => 'name'

  belongs_to :created_by, :class_name => 'User'
  belongs_to :updated_by, :class_name => 'User'
  belongs_to :homepage, :class_name => 'Page'

  has_many :messages
  has_many :permissions
  has_many :pages, :through => :permissions
  has_many :memberships
  has_many :readers, :through => :memberships
  
  validates_presence_of :name
  validates_uniqueness_of :name
  
  named_scope :with_home_page, { :conditions => "homepage_id IS NOT NULL", :include => :homepage }
  named_scope :subscribable, { :conditions => "public = 1" }
  named_scope :unsubscribable, { :conditions => "public = 0" }

  named_scope :attached_to, lambda { |objects|
    conditions = objects.map{|o| "(pp.permitted_type = ? AND pp.permitted_id = ?)" }.join(" OR ")
    binds = objects.map{|o| [o.class.to_s, o.id]}.flatten
    {
      :select => "groups.*, count(pp.group_id) AS pcount",
      :joins => "INNER JOIN permissions as pp on pp.group_id = groups.id", 
      :conditions => [conditions, *binds],
      :having => "pcount > 0",    # otherwise attached_to([]) returns all groups
      :group => column_names.map { |n| self.table_name + '.' + n }.join(','),
      :readonly => false
    }
  }

  def url
    homepage.url if homepage
  end
  
  def send_welcome_to(reader)
    if reader.activated?                                        # welcomes will be triggered again on activation
      message = messages.for_function('group_welcome').first    # only if a group_welcome message exists *belonging to this group*
      message.deliver_to(reader) if message                     # (the belonging also allows us to mention the group in the message)
    end
  end

  def admit(reader)
    self.readers << reader
  end

  def permission_for(object)
    self.permissions.for(object).first
  end

  def membership_for(reader)
    self.memberships.for(reader).first
  end
  
  # we can't has_many through the polymorphic permission relationship, so this is called from has_groups
  # and for eg. Page, it defines:
  # Permission.for_pages named_scope
  # Group.page_permissions  => set of permission objects
  # Group.pages             => set of page objects
  
  def self.define_retrieval_methods(classname)
    type_scope = "for_#{classname.downcase.pluralize}".intern
    Permission.send :named_scope, type_scope, :conditions => { :permitted_type => classname }
    define_method("#{classname.downcase}_permissions") { self.permissions.send type_scope }
    define_method("#{classname.downcase.pluralize}") { self.send("#{classname.to_s.downcase}_permissions".intern).map(&:permitted) }
  end
  
  

end

