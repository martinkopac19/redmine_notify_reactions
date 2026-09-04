# frozen_string_literal: true

# Redmine Notify Reactions (Previo)
#
# Redmine 6 vie lajkovať (palec hore) úlohy, komentáre, príspevky vo fóre
# a novinky. Autorovi o tom ale nepošle nič — lajk uvidí len ten, kto sa
# na stránku náhodou vráti. Plugin pošle autorovi krátky mail.
#
# Žiadne migrácie, žiadny zásah do jadra: `include` nad Reaction a nad Mailer.
require_relative 'lib/notify_reactions/reaction_patch'
require_relative 'lib/notify_reactions/mailer_patch'

Redmine::Plugin.register :redmine_notify_reactions do
  name 'Notify reactions (Previo)'
  author 'Martin Kopáč'
  description 'Emails the author when somebody likes their issue, comment, forum post or news.'
  version '0.1.0'
  requires_redmine version_or_higher: '6.0'
  settings default: { 'enabled' => '1' }, partial: 'settings/notify_reactions'
end

# Patch je zámerne tu a nie v `to_prepare` — ten sa v production nespúšťa
# v správnom čase a patch by ticho nikdy nezabral (rovnaký vzor ako
# redmine_notify_field_users a redmine_done_on_close).
Reaction.include(NotifyReactions::ReactionPatch) unless Reaction.include?(NotifyReactions::ReactionPatch)
Mailer.include(NotifyReactions::MailerPatch) unless Mailer.include?(NotifyReactions::MailerPatch)
