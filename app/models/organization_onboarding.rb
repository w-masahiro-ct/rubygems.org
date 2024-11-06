class OrganizationOnboarding < ApplicationRecord
  enum :name_type, { gem: "gem", user: "user" }, prefix: true, default: "gem"
  enum :status, { pending: "pending", completed: "completed", failed: "failed" }, default: "pending"

  has_many :invites, class_name: "OrganizationOnboardingInvite", inverse_of: :organization_onboarding, dependent: :destroy
  belongs_to :organization, optional: true, foreign_key: :onboarded_organization_id, inverse_of: :organization_onboarding
  belongs_to :created_by, class_name: "User", inverse_of: :organization_onboardings

  validate :created_by_gem_ownerships

  validates :organization_name, :organization_handle, :name_type, presence: true

  with_options if: :completed? do
    validates :onboarded_at, presence: true
  end

  with_options if: :failed? do
    validates :error, presence: true
  end

  with_options if: :name_type_user? do
    before_validation :set_user_handle
  end

  with_options if: :name_type_gem? do
    validate :organization_handle_matches_rubygem_name
  end

  def onboard!
    raise StandardError, "onboard has already been completed" if completed?

    transaction do
      onboarded_organization = create_organization!

      onboard_rubygems!(onboarded_organization)

      update!(
        onboarded_at: Time.zone.now,
        status: :completed,
        onboarded_organization_id: onboarded_organization.id
      )
    end
  rescue ActiveRecord::ActiveRecordError => e
    update!(
      error: e.message,
      status: :failed
    )
  end

  def available_rubygems
    @available_rubygems ||= created_by.rubygems
  end

  def user_invites
    users_for_selected_gems.map do |user|
      OrganizationOnboardingInvite.new(user: user)
    end
  end

  private

  def users_for_selected_gems
    User # TODO: Move this to a scope, verify performance
      .joins(:ownerships)
      .where(ownerships: { rubygem_id: available_rubygems.pluck(:id) })
      .where.not(ownerships: { user_id: created_by })
      .order(Arel.sql("COUNT (ownerships.id) DESC"))
      .group(users: [:id])
  end

  def create_organization!
    memberships = invites.map(&:to_membership)
    memberships << build_owner

    Organization.create!(
      name: organization_name,
      handle: organization_handle,
      memberships: memberships,
      teams: [build_team]
    )
  end

  def onboard_rubygems!(onboarded_organization)
    onboarding_gems = Rubygem.where(id: rubygems).all
    onboarding_gems.each do |rubygem|
      rubygem.update!(organization_id: onboarded_organization.id)
    end
  end

  def build_membership(invite)
    Membership.build(
      user_id: invite.user_id,
      role: invite.role
    )
  end

  def build_owner
    Membership.build(
      user: created_by,
      role: :owner,
      confirmed_at: Time.zone.now
    )
  end

  def build_team
    Team.build(
      name: "Default",
      handle: "default",
      team_members: build_team_members
    )
  end

  def build_team_members
    users = invites.map(&:user).append(created_by)
    users.map do |user|
      TeamMember.build(
        user_id: user.id
      )
    end
  end

  def set_user_handle
    return if created_by.blank?
    self.organization_handle = created_by.handle
  end

  def organization_handle_matches_rubygem_name
    return if organization_handle.blank?
    rubygem = available_rubygems.find_by(name: organization_handle)
    return if rubygem.present?

    errors.add(:organization_handle, "must match a rubygem you own")
  end

  def created_by_gem_ownerships
    return if created_by.blank? || rubygems.blank?

    ownerships = Ownership.where(user: created_by, rubygem: rubygems).index_by(&:rubygem_id)
    selected_rubygems = Rubygem.where(id: rubygems)

    selected_rubygems.each do |rubygem|
      ownership = ownerships[rubygem.id]
      next if ownership.present? && ownership.owner?

      errors.add(:created_by, "must be an owner of the #{rubygem.name} gem")
    end
  end
end
