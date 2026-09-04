# frozen_string_literal: true

# Regresný self-test pluginu redmine_notify_reactions.
#
# Spustenie (POZOR na `--user redmine`, inak zostanú v tmp/cache súbory patriace
# rootovi a aplikácia ich potom nedokáže prepísať):
#   docker compose exec -T --user redmine -e SECRET_KEY_BASE=<key> redmine \
#     bin/rails runner -e production plugins/redmine_notify_reactions/extra/selftest.rb
#
# Test NEMÔŽE bežať v transakcii ako selftest pluginu notify_field_users: plugin
# visí na `after_create_commit`, ktorý sa pri rollbacku nikdy nespustí. Preto
# vytvára skutočné riadky v tabuľke `reactions` a v `ensure` bloku ich zmaže.
# Nič iné v databáze nemení — existujúce úlohy a komentáre sa len čítajú.
# Maily idú do :test kolektora, takže nikomu nič neodíde ani cez Mailpit.

OK = []
BAD = []

def check(label, got, want)
  ok = got == want
  (ok ? OK : BAD) << label
  puts format('  %-58s %s', label, ok ? 'OK' : "!! ZLE (#{got.inspect}, cakalo sa #{want.inspect})")
end

def body_of(mail)
  part = mail.text_part || mail
  part.decoded.to_s
end

# Tabulka `reactions` ma unique index na (reactable_type, reactable_id, user_id),
# takze ten isty clovek nemoze mat na tej istej veci dva lajky. Test tu istu vec
# lajkuje viackrat, preto sa predchadzajuci lajk najprv zahodi.
def like(reactable, user, created_ids)
  Reaction.where(reactable: reactable, user: user).delete_all
  ActionMailer::Base.deliveries.clear
  reaction = Reaction.create!(reactable: reactable, user: user)
  created_ids << reaction.id
  reaction
end

puts '=' * 78
puts '  notify_reactions selftest'
puts '=' * 78

created_ids = []
original_delivery = ActionMailer::Base.delivery_method
original_adapter = ActiveJob::Base.queue_adapter
original_setting = Setting.plugin_redmine_notify_reactions
original_job_logger = ActiveJob::Base.logger
original_mail_logger = ActionMailer::Base.logger

begin
  # Bez tohto zahlti kazdy odoslany mail vypis testu piatimi riadkami ActiveJobu.
  quiet = ActiveSupport::Logger.new(IO::NULL)
  ActiveJob::Base.logger = quiet
  ActionMailer::Base.logger = quiet
  ActionMailer::Base.delivery_method = :test
  ActiveJob::Base.queue_adapter = :inline
  ActionMailer::Base.deliveries.clear

  reactor = User.active.where(admin: true).first
  abort '  Ziadny aktivny admin — nie je kto by lajkoval.' if reactor.nil?

  good_author = lambda do |user, object|
    user && user.active? && user.mails.any? && user.mail_notification.to_s != 'none' &&
      user.id != reactor.id && object.visible?(user)
  end

  issue = Issue.order(id: :desc).limit(300).detect { |i| good_author.call(i.author, i) }
  journal = Journal.where(journalized_type: 'Issue').where.not(notes: [nil, ''])
                   .order(id: :desc).limit(300)
                   .detect { |j| j.journalized && good_author.call(j.user, j) }

  abort '  Nenasla sa vhodna uloha.' if issue.nil?
  abort '  Nenasiel sa vhodny komentar.' if journal.nil?

  puts ''
  puts '[1] Prostredie'
  puts "  lajkuje                   : #{reactor.name} (id #{reactor.id})"
  puts "  testovana uloha           : ##{issue.id}, autor #{issue.author.name}"
  puts "  testovany komentar        : journal #{journal.id} k ulohe ##{journal.journalized_id}, autor #{journal.user.name}"
  puts "  plugin zapnuty            : #{NotifyReactions.enabled?}"
  puts "  reakcie zapnute v Redmine : #{Setting.reactions_enabled?}"

  # --- 2. lajk na ulohu -> autor ulohy ---------------------------------------
  puts ''
  puts '[2] Lajk na ulohu'
  like(issue, reactor, created_ids)
  mails = ActionMailer::Base.deliveries
  check('odisiel prave jeden mail', mails.size, 1)
  if mails.size == 1
    m = mails.first
    check('ide autorovi ulohy', (m.to & issue.author.mails).any?, true)
    check('predmet obsahuje meno lajkujuceho', m.subject.include?(reactor.name), true)
    check('predmet obsahuje cislo ulohy', m.subject.include?("##{issue.id}"), true)
    check('telo obsahuje odkaz na ulohu', body_of(m).include?("/issues/#{issue.id}"), true)
  end

  # --- 3. lajk na komentar -> autor komentara --------------------------------
  puts ''
  puts '[3] Lajk na komentar'
  like(journal, reactor, created_ids)
  mails = ActionMailer::Base.deliveries
  check('odisiel prave jeden mail', mails.size, 1)
  if mails.size == 1
    m = mails.first
    check('ide autorovi komentara', (m.to & journal.user.mails).any?, true)
    check('odkaz mieri na konkretny komentar', body_of(m).include?("change-#{journal.id}"), true)
    check('telo obsahuje kusok komentara', body_of(m).include?(journal.notes.to_s.strip[0, 20]), true)
  end

  # --- 4. lajk sam sebe ------------------------------------------------------
  puts ''
  puts '[4] Lajk sam sebe'
  like(issue, issue.author, created_ids)
  check('neposiela sa nic', ActionMailer::Base.deliveries.size, 0)

  # --- 5. respektovanie "ziadne e-maily" -------------------------------------
  puts ''
  puts '[5] Pouzivatel s nastavenim ziadne e-maily'
  none_user = User.active.where(mail_notification: 'none').first
  if none_user
    check('nedostane nic', NotifyReactions.notifiable?(none_user, issue), false)
  else
    puts '  (preskocene — nikto taky v tejto instancii nie je)'
  end
  check('bezny autor ho dostat moze', NotifyReactions.notifiable?(issue.author, issue), true)

  # --- 6. vypinac ------------------------------------------------------------
  puts ''
  puts '[6] Vypnuty plugin'
  Setting.plugin_redmine_notify_reactions = original_setting.merge('enabled' => '0')
  check('plugin sa hlasi ako vypnuty', NotifyReactions.enabled?, false)
  like(journal, reactor, created_ids)
  check('neposiela sa nic', ActionMailer::Base.deliveries.size, 0)
  Setting.plugin_redmine_notify_reactions = original_setting

  # --- 7. zrusenie lajku a opakovany lajk ------------------------------------
  puts ''
  puts '[7] Zrusenie lajku a opakovany lajk'
  reaction = Reaction.where(reactable: issue, user: reactor).first
  ActionMailer::Base.deliveries.clear
  reaction&.destroy
  check('zrusenie lajku neposle nic', ActionMailer::Base.deliveries.size, 0)
  like(issue, reactor, created_ids)
  check('opakovany lajk posle mail znova', ActionMailer::Base.deliveries.size, 1)
ensure
  Reaction.where(id: created_ids).delete_all if created_ids.any?
  Setting.plugin_redmine_notify_reactions = original_setting
  ActionMailer::Base.deliveries.clear
  ActionMailer::Base.delivery_method = original_delivery
  ActiveJob::Base.queue_adapter = original_adapter
  ActiveJob::Base.logger = original_job_logger
  ActionMailer::Base.logger = original_mail_logger
end

puts ''
puts '=' * 78
puts "  OK: #{OK.size}   CHYBA: #{BAD.size}"
puts "  zostalo v DB: #{Reaction.where(id: created_ids).count} testovacich lajkov (ma byt 0)"
puts '=' * 78
