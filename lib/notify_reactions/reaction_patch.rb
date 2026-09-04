# frozen_string_literal: true

module NotifyReactions
  module_function

  def enabled?
    Setting.plugin_redmine_notify_reactions.presence&.[]('enabled').to_s != '0'
  end

  # Autor lajknutej veci. Komentár k úlohe (Journal) drží autora v `user`,
  # všetko ostatné (úloha, príspevok vo fóre, novinka, komentár k novinke)
  # v `author`.
  def author_of(reactable)
    reactable.is_a?(Journal) ? reactable.user : reactable.author
  end

  # Smie tomuto človeku prísť mail o tomto lajku?
  #
  # Rešpektuje sa „žiadne e-maily" (mail_notification 'none') a zamknuté účty.
  # Ostatné voľby sa neriešia zámerne: lajk je vždy o tvojej vlastnej veci,
  # takže voľby typu „len úlohy, kde som riešiteľ" sem nedávajú zmysel.
  def notifiable?(user, reactable)
    user.is_a?(User) && user.active? &&
      user.mail_notification.to_s != 'none' &&
      reactable.visible?(user)
  end

  def deliver(reaction)
    return unless enabled?
    return unless Setting.reactions_enabled?

    reactable = reaction.reactable
    return if reactable.nil?

    author = author_of(reactable)
    return if author.nil?
    # Lajk sám sebe nie je správa, ktorú treba posielať mailom.
    return if author == reaction.user
    return unless notifiable?(author, reactable)

    Mailer.deliver_reaction_added(reaction, author)
  end

  module ReactionPatch
    extend ActiveSupport::Concern

    included do
      # `after_create_commit`, nie `after_create`: mail sa nesmie odoslať za
      # záznam, ktorý sa nakoniec neuloží. Rovnaký vzor má Comment v jadre.
      after_create_commit :notify_reaction_author
    end

    private

    def notify_reaction_author
      NotifyReactions.deliver(self)
    rescue StandardError => e
      # Lajk je drobnosť. Keby na ňom spadol request, bolo by to horšie
      # než neodoslaný mail.
      Rails.logger&.error("[notify_reactions] reaction #{id}: #{e.class}: #{e.message}")
    end
  end
end
